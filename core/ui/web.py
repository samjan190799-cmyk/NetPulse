"""
Веб-интерфейс NetPulse.
Поддерживает FastAPI/Uvicorn (при наличии) и встроенный http.server стандартной библиотеки Python.

Безопасность: API не требует авторизации, поэтому по умолчанию сервер слушает только 127.0.0.1,
а каждый запрос проверяется на Host / Origin / Sec-Fetch-Site. Это закрывает CSRF с чужих сайтов
(запуск speedtest, создание файлов отчёта) и DNS-rebinding (чтение данных чужой страницей).
"""
import asyncio
import json
import mimetypes
import shutil
import socketserver
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable, Dict, List, Mapping, Optional, Set
from urllib.parse import unquote, urlsplit

from config.settings import AppConfig
from metrics.collector import MetricsCollector
from metrics.storage import StorageManager

try:
    from fastapi import FastAPI, HTTPException, Request
    from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
    from fastapi.staticfiles import StaticFiles
    from starlette.background import BackgroundTask
    FASTAPI_AVAILABLE = True
except ImportError:
    FASTAPI_AVAILABLE = False

TEMPLATES_DIR = Path(__file__).parent / "templates"
STATIC_DIR = Path(__file__).parent / "static"


# ---- общие сборщики ответов (одни и те же для FastAPI и standalone-сервера) ------------------

def system_payload(collector: MetricsCollector) -> Dict[str, Any]:
    info = collector.system_info
    return {
        "local_ip": info.local_ip,
        "gateway_ip": info.gateway_ip,
        "interface_name": info.interface_name,
        "dns_servers": info.dns_servers,
        "public_ip": info.public_ip,
        "isp_name": info.isp_name,
        "country": info.country,
        "city": info.city,
    }


def stats_payload(collector: MetricsCollector) -> List[Dict[str, Any]]:
    return [
        {
            "name": s.name,
            "address": s.address,
            "is_gateway": s.is_gateway,
            "status": s.status,
            "last_latency_ms": s.last_latency_ms,
            "min_latency_ms": s.min_latency_ms,
            "max_latency_ms": s.max_latency_ms,
            "avg_latency_ms": s.avg_latency_ms,
            "p50_latency_ms": s.p50_latency_ms,
            "p95_latency_ms": s.p95_latency_ms,
            "p99_latency_ms": s.p99_latency_ms,
            "jitter_ms": s.jitter_ms,
            "sent_count": s.sent_count,
            "lost_count": s.lost_count,
            "loss_rate_pct": s.loss_rate_pct,
            "loss_window_pct": s.loss_window_pct,
            "loss_recent_pct": s.loss_recent_pct,
            "sparkline": s.sparkline,
        }
        for s in collector.get_all_stats()
    ]


def alerts_payload(collector: MetricsCollector, limit: int = 20) -> List[Dict[str, Any]]:
    return [
        {
            "timestamp": a.timestamp.isoformat(),
            "host": a.host,
            "target_name": a.target_name,
            "severity": a.severity.value,
            "message": a.message,
            "metric_name": a.metric_name,
            "current_value": a.current_value,
            "threshold_value": a.threshold_value,
        }
        for a in collector.get_recent_alerts(limit=limit)
    ]


def speedtest_payload(res) -> Dict[str, Any]:
    return {
        "status": res.status,
        "download_mbps": res.download_mbps,
        "upload_mbps": res.upload_mbps,
        "duration_s": res.duration_s,
        "server": res.server_name,
        "timestamp": res.timestamp.isoformat(),
    }


# ---- проверка запросов (CSRF / DNS-rebinding) -------------------------------------------------

def allowed_hosts_for(config: AppConfig) -> Optional[Set[str]]:
    """
    Допустимые значения заголовка Host (без порта). None — проверка отключена
    (сервер намеренно привязан к 0.0.0.0 / ::, т.е. открыт для сети по решению пользователя).
    """
    host = (config.web.host or "").strip()
    if host in ("0.0.0.0", "::", ""):
        return None
    return {"127.0.0.1", "localhost", "::1", "[::1]", host.lower()}


def _strip_port(netloc: str) -> str:
    netloc = netloc.strip().lower()
    if netloc.startswith("["):                       # [::1]:8080
        end = netloc.find("]")
        return netloc[: end + 1] if end != -1 else netloc
    if netloc.count(":") == 1:                       # host:port
        return netloc.split(":", 1)[0]
    return netloc


def request_allowed(headers: Mapping[str, str], allowed_hosts: Optional[Set[str]]) -> bool:
    """True, если запрос выглядит как обращение пользователя к собственному дашборду."""
    if allowed_hosts is None:
        return True
    host = headers.get("host")
    if host and _strip_port(host) not in allowed_hosts:
        return False                                  # DNS-rebinding: чужое имя резолвится в 127.0.0.1
    if headers.get("sec-fetch-site", "").lower() == "cross-site":
        return False                                  # запрос инициирован чужой страницей
    origin = headers.get("origin")
    if origin and origin.lower() != "null":
        if _strip_port(urlsplit(origin).netloc) not in allowed_hosts:
            return False                              # fetch/форма с другого origin
    elif origin and origin.lower() == "null":
        return False
    return True


# ---- FastAPI ---------------------------------------------------------------------------------

def create_web_app(
    config: AppConfig,
    collector: MetricsCollector,
    storage: StorageManager,
    speedtest_callback: Optional[Callable] = None,
) -> Any:
    """Создание FastAPI приложения при наличии библиотеки."""
    if not FASTAPI_AVAILABLE:
        return None

    app = FastAPI(title="NetPulse Web Dashboard", version="1.0.0")
    index_html_path = TEMPLATES_DIR / "index.html"
    allowed = allowed_hosts_for(config)

    @app.middleware("http")
    async def guard_requests(request: Request, call_next):
        if not request_allowed(request.headers, allowed):
            return JSONResponse({"detail": "Forbidden"}, status_code=403)
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        if request.url.path.startswith("/api/"):
            response.headers["Cache-Control"] = "no-store"
        return response

    if STATIC_DIR.exists():
        app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

    @app.get("/", response_class=HTMLResponse)
    @app.get("/index.html", response_class=HTMLResponse, include_in_schema=False)
    async def get_dashboard():
        if not index_html_path.exists():
            raise HTTPException(status_code=404, detail="Dashboard template not found")
        return await asyncio.to_thread(index_html_path.read_text, "utf-8")

    @app.get("/api/system")
    async def get_system_info():
        return system_payload(collector)

    @app.get("/api/stats")
    async def get_host_stats():
        return stats_payload(collector)

    @app.get("/api/alerts")
    async def get_recent_alerts():
        return alerts_payload(collector, limit=20)

    @app.post("/api/speedtest")
    async def run_speedtest():
        if not speedtest_callback:
            raise HTTPException(status_code=501, detail="Speedtest callback not configured")
        res = await speedtest_callback()
        if res.status == "BUSY":
            raise HTTPException(status_code=409, detail="Замер скорости уже выполняется")
        return speedtest_payload(res)

    def _export_response(kind: str):
        """Экспорт — во временный каталог, который удаляется после отправки файла."""
        tmp = Path(tempfile.mkdtemp(prefix="netpulse_export_"))
        try:
            if kind == "json":
                path = storage.export_json(tmp / f"netpulse_report_{storage.session_id}.json")
                media = "application/json"
            else:
                path = storage.export_csv(tmp / f"netpulse_metrics_{storage.session_id}.csv")
                media = "text/csv"
        except Exception:
            shutil.rmtree(tmp, ignore_errors=True)
            raise
        return FileResponse(
            path=str(path),
            filename=path.name,
            media_type=media,
            background=BackgroundTask(shutil.rmtree, tmp, True),
        )

    # Обычные (sync) функции: FastAPI выполняет их в пуле потоков, а не блокирует цикл событий
    @app.get("/api/export/json")
    def export_json():
        return _export_response("json")

    @app.get("/api/export/csv")
    def export_csv():
        return _export_response("csv")

    return app


# ---- резервный сервер без FastAPI ---------------------------------------------------------------

class _QuickBindHTTPServer(ThreadingHTTPServer):
    """ThreadingHTTPServer, который при запуске не спрашивает у DNS имя своего адреса.

    Обычный HTTPServer.server_bind после занятия порта вызывает socket.getfqdn(host). На macOS это обратный
    DNS-запрос, и он может висеть секундами: порт уже занят, но ещё не слушает, и сервер отклоняет подключения.
    Полное имя серверу не нужно (оно годится только для CGI), поэтому берём сам адрес.
    """

    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        host, port = self.server_address[:2]
        self.server_name = str(host)
        self.server_port = port


class StandaloneWebServer:
    """Встроенный легковесный многопоточный веб-сервер на базе http.server."""

    def __init__(
        self,
        config: AppConfig,
        collector: MetricsCollector,
        storage: StorageManager,
        speedtest_callback: Optional[Callable] = None,
        loop: Optional[asyncio.AbstractEventLoop] = None,
    ):
        self.config = config
        self.collector = collector
        self.storage = storage
        self.speedtest_callback = speedtest_callback
        # Цикл событий приложения: speedtest_callback — корутина ЭТОГО цикла
        self.loop = loop
        self.templates_dir = TEMPLATES_DIR
        self.static_dir = STATIC_DIR
        self.httpd: Optional[ThreadingHTTPServer] = None
        self.start_error: Optional[str] = None

    def _build_handler(self):
        server = self
        allowed = allowed_hosts_for(self.config)

        class RequestHandler(BaseHTTPRequestHandler):
            def log_message(self, format, *args):
                pass  # Подавляем логирование запросов в консоль

            # -- вспомогательные --
            def _send_bytes(self, status: int, body: bytes, content_type: str, extra: Optional[Dict[str, str]] = None):
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("X-Content-Type-Options", "nosniff")
                for k, v in (extra or {}).items():
                    self.send_header(k, v)
                self.end_headers()
                self.wfile.write(body)

            def _send_json(self, data: Any, status: int = 200):
                body = json.dumps(data, ensure_ascii=False).encode("utf-8")
                self._send_bytes(status, body, "application/json; charset=utf-8", {"Cache-Control": "no-store"})

            def _send_empty(self, status: int):
                self._send_bytes(status, b"", "text/plain; charset=utf-8")

            def _guard(self) -> bool:
                if not request_allowed(self.headers, allowed):
                    self._send_json({"detail": "Forbidden"}, 403)
                    return False
                return True

            def _send_static(self, rel: str):
                try:
                    root = server.static_dir.resolve()
                    target = (server.static_dir / unquote(rel)).resolve()
                    ok = target.is_relative_to(root) and target.is_file()
                except (OSError, ValueError):
                    ok = False
                if not ok:
                    self._send_empty(404)
                    return
                ctype = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
                self._send_bytes(200, target.read_bytes(), ctype)

            def _send_export(self, kind: str):
                tmp = Path(tempfile.mkdtemp(prefix="netpulse_export_"))
                try:
                    if kind == "json":
                        path = server.storage.export_json(tmp / f"netpulse_report_{server.storage.session_id}.json")
                        ctype = "application/json"
                    else:
                        path = server.storage.export_csv(tmp / f"netpulse_metrics_{server.storage.session_id}.csv")
                        ctype = "text/csv; charset=utf-8"
                    self._send_bytes(
                        200, path.read_bytes(), ctype,
                        {"Content-Disposition": f'attachment; filename="{path.name}"'},
                    )
                finally:
                    shutil.rmtree(tmp, ignore_errors=True)

            # -- маршруты --
            def do_GET(self):
                if not self._guard():
                    return
                path = urlsplit(self.path).path    # query-string («?v=2») не должна ломать маршрут
                try:
                    if path in ("/", "/index.html"):
                        self._send_bytes(200, (server.templates_dir / "index.html").read_bytes(),
                                         "text/html; charset=utf-8")
                    elif path == "/api/system":
                        self._send_json(system_payload(server.collector))
                    elif path == "/api/stats":
                        self._send_json(stats_payload(server.collector))
                    elif path == "/api/alerts":
                        self._send_json(alerts_payload(server.collector, limit=20))
                    elif path == "/api/export/json":
                        self._send_export("json")
                    elif path == "/api/export/csv":
                        self._send_export("csv")
                    elif path.startswith("/static/"):
                        self._send_static(path[len("/static/"):])
                    else:
                        self._send_empty(404)
                except (BrokenPipeError, ConnectionResetError):
                    pass
                except Exception as e:
                    self._send_json({"detail": f"Internal error: {e}"}, 500)

            def do_POST(self):
                if not self._guard():
                    return
                path = urlsplit(self.path).path
                if path != "/api/speedtest":
                    self._send_empty(404)
                    return
                if not server.speedtest_callback:
                    self._send_empty(501)
                    return
                try:
                    if server.loop is not None and server.loop.is_running():
                        fut = asyncio.run_coroutine_threadsafe(server.speedtest_callback(), server.loop)
                        res = fut.result(timeout=180)
                    else:
                        res = asyncio.run(server.speedtest_callback())
                except Exception as e:
                    self._send_json({"detail": f"Speedtest failed: {e}"}, 500)
                    return
                if res.status == "BUSY":
                    self._send_json({"detail": "Замер скорости уже выполняется"}, 409)
                else:
                    self._send_json(speedtest_payload(res))

        return RequestHandler

    def start_sync(self):
        """Блокирующий запуск сервера (вызывается в отдельном потоке)."""
        try:
            self.httpd = _QuickBindHTTPServer((self.config.web.host, self.config.web.port), self._build_handler())
        except OSError as e:
            self.start_error = str(e)
            raise
        self.httpd.daemon_threads = True
        self.httpd.serve_forever(poll_interval=0.25)

    def shutdown(self):
        httpd = self.httpd
        if not httpd:
            return
        # shutdown() блокируется, пока serve_forever не завершится — не вешаем вызывающий поток
        t = threading.Thread(target=httpd.shutdown, daemon=True)
        t.start()
        t.join(2.0)
        httpd.server_close()
