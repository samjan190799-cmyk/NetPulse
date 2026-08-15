"""
Веб-интерфейс NetPulse.
Поддерживает FastAPI/Uvicorn (при наличии) и встроенный http.server стандартной библиотеки Python.
"""
import asyncio
import json
import os
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from typing import Any, Callable, Optional

from config.settings import AppConfig
from metrics.collector import MetricsCollector
from metrics.storage import StorageManager

try:
    from fastapi import FastAPI, HTTPException
    from fastapi.responses import FileResponse, HTMLResponse
    from fastapi.staticfiles import StaticFiles
    FASTAPI_AVAILABLE = True
except ImportError:
    FASTAPI_AVAILABLE = False


def create_web_app(
    config: AppConfig,
    collector: MetricsCollector,
    storage: StorageManager,
    speedtest_callback: Optional[Callable] = None,
    traceroute_callback: Optional[Callable] = None,
) -> Any:
    """Создание FastAPI приложения при наличии библиотеки."""
    if not FASTAPI_AVAILABLE:
        return None

    app = FastAPI(title="NetPulse Web Dashboard", version="1.0.0")
    templates_dir = Path(__file__).parent / "templates"
    static_dir = Path(__file__).parent / "static"
    index_html_path = templates_dir / "index.html"

    if static_dir.exists():
        app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

    @app.get("/", response_class=HTMLResponse)
    async def get_dashboard():
        if not index_html_path.exists():
            raise HTTPException(status_code=404, detail="Dashboard template not found")
        with open(index_html_path, "r", encoding="utf-8") as f:
            return f.read()

    @app.get("/api/system")
    async def get_system_info():
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

    @app.get("/api/stats")
    async def get_host_stats():
        stats = collector.get_all_stats()
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
                "p95_latency_ms": s.p95_latency_ms,
                "p99_latency_ms": s.p99_latency_ms,
                "jitter_ms": s.jitter_ms,
                "loss_rate_pct": s.loss_rate_pct,
                "loss_window_pct": s.loss_window_pct,
                "sparkline": s.sparkline,
            }
            for s in stats
        ]

    @app.get("/api/alerts")
    async def get_recent_alerts():
        alerts = collector.get_recent_alerts(limit=20)
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
            for a in alerts
        ]

    @app.post("/api/speedtest")
    async def run_speedtest():
        if speedtest_callback:
            res = await speedtest_callback()
            return {
                "status": res.status,
                "download_mbps": res.download_mbps,
                "upload_mbps": res.upload_mbps,
                "duration_s": res.duration_s,
                "server": res.server_name,
                "timestamp": res.timestamp.isoformat(),
            }
        raise HTTPException(status_code=501, detail="Speedtest callback not configured")

    @app.get("/api/export/json")
    async def export_json():
        file_path = storage.export_json()
        return FileResponse(path=str(file_path), filename=file_path.name, media_type="application/json")

    @app.get("/api/export/csv")
    async def export_csv():
        file_path = storage.export_csv()
        return FileResponse(path=str(file_path), filename=file_path.name, media_type="text/csv")

    return app


class StandaloneWebServer:
    """Встроенный легковесный веб-сервер на базе http.server."""

    def __init__(
        self,
        config: AppConfig,
        collector: MetricsCollector,
        storage: StorageManager,
        speedtest_callback: Optional[Callable] = None,
    ):
        self.config = config
        self.collector = collector
        self.storage = storage
        self.speedtest_callback = speedtest_callback
        self.templates_dir = Path(__file__).parent / "templates"
        self.httpd: Optional[HTTPServer] = None

    def start_sync(self):
        collector = self.collector
        storage = self.storage
        templates_dir = self.templates_dir
        speedtest_cb = self.speedtest_callback

        class RequestHandler(SimpleHTTPRequestHandler):
            def log_message(self, format, *args):
                pass  # Подавляем логирование запросов в консоль

            def do_GET(self):
                if self.path == "/" or self.path == "/index.html":
                    idx_path = templates_dir / "index.html"
                    self.send_response(200)
                    self.send_header("Content-Type", "text/html; charset=utf-8")
                    self.end_headers()
                    with open(idx_path, "rb") as f:
                        self.wfile.write(f.read())
                elif self.path == "/api/system":
                    info = collector.system_info
                    data = {
                        "local_ip": info.local_ip,
                        "gateway_ip": info.gateway_ip,
                        "interface_name": info.interface_name,
                        "dns_servers": info.dns_servers,
                        "public_ip": info.public_ip,
                        "isp_name": info.isp_name,
                        "country": info.country,
                        "city": info.city,
                    }
                    self._send_json(data)
                elif self.path == "/api/stats":
                    stats = collector.get_all_stats()
                    data = [
                        {
                            "name": s.name,
                            "address": s.address,
                            "is_gateway": s.is_gateway,
                            "status": s.status,
                            "last_latency_ms": s.last_latency_ms,
                            "min_latency_ms": s.min_latency_ms,
                            "max_latency_ms": s.max_latency_ms,
                            "avg_latency_ms": s.avg_latency_ms,
                            "p95_latency_ms": s.p95_latency_ms,
                            "p99_latency_ms": s.p99_latency_ms,
                            "jitter_ms": s.jitter_ms,
                            "loss_rate_pct": s.loss_rate_pct,
                            "loss_window_pct": s.loss_window_pct,
                            "sparkline": s.sparkline,
                        }
                        for s in stats
                    ]
                    self._send_json(data)
                elif self.path == "/api/export/json":
                    file_path = storage.export_json()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Disposition", f'attachment; filename="{file_path.name}"')
                    self.end_headers()
                    with open(file_path, "rb") as f:
                        self.wfile.write(f.read())
                elif self.path.startswith("/static/"):
                    static_file = Path(__file__).parent / self.path.lstrip("/")
                    if static_file.exists() and static_file.is_file():
                        content_type = "image/png" if static_file.suffix == ".png" else "image/x-icon" if static_file.suffix == ".ico" else "application/octet-stream"
                        self.send_response(200)
                        self.send_header("Content-Type", content_type)
                        self.end_headers()
                        with open(static_file, "rb") as f:
                            self.wfile.write(f.read())
                    else:
                        self.send_response(404)
                        self.end_headers()
                else:
                    self.send_response(404)
                    self.end_headers()

            def do_POST(self):
                if self.path == "/api/speedtest":
                    if speedtest_cb:
                        # Запуск в текущем контексте
                        loop = asyncio.new_event_loop()
                        res = loop.run_until_complete(speedtest_cb())
                        loop.close()
                        self._send_json({
                            "status": res.status,
                            "download_mbps": res.download_mbps,
                            "upload_mbps": res.upload_mbps,
                            "duration_s": res.duration_s,
                            "server": res.server_name,
                            "timestamp": res.timestamp.isoformat(),
                        })
                    else:
                        self.send_response(501)
                        self.end_headers()
                else:
                    self.send_response(404)
                    self.end_headers()

            def _send_json(self, data: Any):
                body = json.dumps(data, ensure_ascii=False).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        server_address = (self.config.web.host, self.config.web.port)
        self.httpd = HTTPServer(server_address, RequestHandler)
        self.httpd.serve_forever()

    def shutdown(self):
        if self.httpd:
            self.httpd.shutdown()
            self.httpd.server_close()
