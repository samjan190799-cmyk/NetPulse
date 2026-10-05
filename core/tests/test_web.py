"""
Веб-интерфейс: оба сервера (FastAPI/uvicorn и резервный http.server) проходят ОДНИ И ТЕ ЖЕ проверки
по настоящему HTTP — маршруты, защита от CSRF/DNS-rebinding, path traversal, экспорт, speedtest.
"""
import asyncio
import json
import re
import socket
import tempfile
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

import pytest

from config.settings import AppConfig
from metrics.collector import MetricsCollector
from metrics.models import PingResult, SpeedtestResult
from metrics.storage import StorageManager
from ui import web
from ui.web import StandaloneWebServer, allowed_hosts_for, request_allowed

UI_DIR = Path(web.__file__).parent


# ---- чистая логика проверки запросов ---------------------------------------------------------------

def cfg(host="127.0.0.1") -> AppConfig:
    c = AppConfig()
    c.web.host = host
    return c


def test_allowed_hosts_for_loopback_binding():
    assert {"127.0.0.1", "localhost", "[::1]"} <= allowed_hosts_for(cfg())


def test_checks_are_disabled_only_when_bound_to_all_interfaces():
    assert allowed_hosts_for(cfg("0.0.0.0")) is None
    assert allowed_hosts_for(cfg("::")) is None
    assert "192.168.1.5" in allowed_hosts_for(cfg("192.168.1.5"))


@pytest.mark.parametrize(
    "headers, expected",
    [
        ({"host": "127.0.0.1:8080"}, True),
        ({"host": "localhost:8080"}, True),
        ({"host": "[::1]:8080"}, True),
        ({"host": "evil.example"}, False),                                       # DNS-rebinding
        ({"host": "evil.example:8080"}, False),
        ({"host": "127.0.0.1:8080", "origin": "http://127.0.0.1:8080"}, True),
        ({"host": "127.0.0.1:8080", "origin": "http://localhost:8080"}, True),
        ({"host": "127.0.0.1:8080", "origin": "http://evil.example"}, False),    # CSRF с чужого сайта
        ({"host": "127.0.0.1:8080", "origin": "null"}, False),                   # sandbox-iframe / file://
        ({"host": "127.0.0.1:8080", "sec-fetch-site": "cross-site"}, False),
        ({"host": "127.0.0.1:8080", "sec-fetch-site": "same-origin"}, True),
        ({"host": "127.0.0.1:8080", "sec-fetch-site": "none"}, True),            # ввод адреса вручную
        ({}, True),                                                              # curl без заголовков
    ],
)
def test_request_allowed(headers, expected):
    assert request_allowed(headers, allowed_hosts_for(cfg())) is expected


def test_everything_allowed_when_checks_are_disabled():
    assert request_allowed({"host": "anything", "origin": "http://evil.example"}, None)


# ---- запуск серверов -------------------------------------------------------------------------------

def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_port(port: int, timeout: float = 5.0) -> None:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        with socket.socket() as s:
            s.settimeout(0.2)
            if s.connect_ex(("127.0.0.1", port)) == 0:
                return
        time.sleep(0.05)
    raise RuntimeError(f"сервер не поднялся на порту {port}")


class State:
    """Общее состояние для тестов: коллектор с данными, хранилище и управляемый speedtest."""

    def __init__(self, tmp_path: Path):
        self.config = AppConfig()
        self.config.web.port = free_port()
        self.collector = MetricsCollector(self.config.thresholds)
        self.collector.register_host("Cloudflare", "1.1.1.1")
        self.collector.register_host("Evil <b>name</b>", "10.0.0.1")
        for host, name in (("1.1.1.1", "Cloudflare"), ("10.0.0.1", "Evil <b>name</b>")):
            for latency in (10.0, 12.0, 11.0):
                self.collector.record_result(PingResult(host=host, target_name=name, timestamp=datetime.now(),
                                                        is_success=True, latency_ms=latency))
        self.storage = StorageManager(db_path=tmp_path / "t.db")
        self.storage.record_batch([PingResult(host="1.1.1.1", target_name="Cloudflare", timestamp=datetime.now(),
                                              is_success=True, latency_ms=11.0, protocol="tcp:443")], [])
        self.speed_calls = 0
        self.speed_delay = 0.0
        self.speed_result = SpeedtestResult(timestamp=datetime.now(), download_mbps=93.4, upload_mbps=21.7,
                                            duration_s=3.4, server_name="Cloudflare CDN Edge", status="SUCCESS")

    async def speedtest(self):
        self.speed_calls += 1
        await asyncio.sleep(self.speed_delay)
        return self.speed_result


@pytest.fixture(params=["fastapi", "standalone"])
def server(request, tmp_path):
    state = State(tmp_path)
    port = state.config.web.port
    stop = None

    if request.param == "fastapi":
        if not web.FASTAPI_AVAILABLE:
            pytest.skip("FastAPI не установлен")
        import uvicorn
        app = web.create_web_app(state.config, state.collector, state.storage, state.speedtest)
        srv = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=port, log_level="critical"))
        thread = threading.Thread(target=srv.run, daemon=True)
        thread.start()

        def stop():
            srv.should_exit = True
            thread.join(5)
    else:
        loop = asyncio.new_event_loop()
        loop_thread = threading.Thread(target=loop.run_forever, daemon=True)
        loop_thread.start()
        srv = StandaloneWebServer(state.config, state.collector, state.storage, state.speedtest, loop=loop)
        thread = threading.Thread(target=srv.start_sync, daemon=True)
        thread.start()

        def stop():
            srv.shutdown()
            loop.call_soon_threadsafe(loop.stop)
            loop_thread.join(5)

    wait_port(port)
    state.base = f"http://127.0.0.1:{port}"
    state.kind = request.param
    yield state
    stop()


OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))      # без системного прокси


def http(method: str, url: str, headers=None, timeout: float = 15.0):
    """Возвращает (status, заголовки с именами в нижнем регистре, тело): uvicorn и http.server пишут их по-разному."""
    req = urllib.request.Request(url, method=method, headers=headers or {}, data=b"" if method == "POST" else None)
    try:
        with OPENER.open(req, timeout=timeout) as resp:
            return resp.status, {k.lower(): v for k, v in resp.headers.items()}, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, {k.lower(): v for k, v in e.headers.items()}, e.read()


def get_json(state, path, **kw):
    status, headers, body = http("GET", state.base + path, **kw)
    return status, json.loads(body)


# ---- маршруты ---------------------------------------------------------------------------------------

def test_dashboard_page_is_served(server):
    status, headers, body = http("GET", server.base + "/")
    assert status == 200 and "text/html" in headers["content-type"]
    assert "NetPulse" in body.decode("utf-8")


def test_index_html_alias_and_query_string_do_not_break_routing(server):
    assert http("GET", server.base + "/index.html")[0] == 200
    assert http("GET", server.base + "/api/stats?nocache=1")[0] == 200


def test_stats_payload(server):
    status, data = get_json(server, "/api/stats")
    assert status == 200 and {s["address"] for s in data} == {"1.1.1.1", "10.0.0.1"}
    first = next(s for s in data if s["address"] == "1.1.1.1")
    for key in ("name", "status", "last_latency_ms", "p50_latency_ms", "p95_latency_ms", "jitter_ms",
                "loss_window_pct", "loss_rate_pct", "loss_recent_pct", "sent_count", "sparkline"):
        assert key in first
    assert first["sent_count"] == 3 and first["status"] == "OK"


def test_system_and_alerts_payload(server):
    assert get_json(server, "/api/system")[0] == 200
    status, alerts = get_json(server, "/api/alerts")
    assert status == 200 and alerts == []


def test_api_responses_are_not_cacheable(server):
    _, headers, _ = http("GET", server.base + "/api/stats")
    assert "no-store" in headers.get("cache-control", "")


def test_unknown_routes(server):
    assert http("GET", server.base + "/nope")[0] == 404
    assert http("POST", server.base + "/api/stats")[0] in (404, 405)


def test_standalone_server_starts_without_reverse_dns(monkeypatch, tmp_path):
    """На macOS socket.getfqdn висит секундами, а сервер всё это время не слушает порт: имя ему не нужно."""
    def no_dns(*args, **kwargs):
        raise AssertionError("запуск сервера не должен спрашивать у DNS имя хоста")

    monkeypatch.setattr(socket, "getfqdn", no_dns)
    state = State(tmp_path)
    port = state.config.web.port
    loop = asyncio.new_event_loop()
    loop_thread = threading.Thread(target=loop.run_forever, daemon=True)
    loop_thread.start()
    srv = StandaloneWebServer(state.config, state.collector, state.storage, state.speedtest, loop=loop)
    thread = threading.Thread(target=srv.start_sync, daemon=True)
    thread.start()
    try:
        wait_port(port)
        assert http("GET", f"http://127.0.0.1:{port}/")[0] == 200
        assert srv.start_error is None
    finally:
        srv.shutdown()
        loop.call_soon_threadsafe(loop.stop)
        loop_thread.join(5)


# ---- защита ---------------------------------------------------------------------------------------

def test_foreign_host_header_is_rejected(server):
    """DNS-rebinding: чужое имя, резолвящееся в 127.0.0.1, не должно читать данные."""
    assert http("GET", server.base + "/api/stats", headers={"Host": "evil.example"})[0] == 403


@pytest.mark.parametrize("headers", [
    {"Origin": "http://evil.example"},
    {"Origin": "null"},
    {"Sec-Fetch-Site": "cross-site"},
])
def test_cross_site_post_does_not_start_speedtest(server, headers):
    """CSRF: чужая страница не может запустить замер (нагрузка на канал) через POST на localhost."""
    status, _, _ = http("POST", server.base + "/api/speedtest", headers=headers)
    assert status == 403 and server.speed_calls == 0


def test_same_origin_post_is_allowed(server):
    port = server.config.web.port
    status, _, _ = http("POST", server.base + "/api/speedtest", headers={"Origin": f"http://127.0.0.1:{port}"})
    assert status == 200 and server.speed_calls == 1


@pytest.mark.parametrize("path", [
    "/static/../main.py",
    "/static/%2e%2e/main.py",
    "/static/..%2fmain.py",
    "/static/%2e%2e%2f%2e%2e%2fmain.py",
    "/static//etc/passwd",
])
def test_static_path_traversal_is_blocked(server, path):
    status, _, body = http("GET", server.base + path)
    assert status in (400, 403, 404)
    assert b"NetPulseApplication" not in body and b"root:" not in body


# ---- статические файлы -----------------------------------------------------------------------------

@pytest.mark.parametrize("path, mime, min_size", [
    ("/static/dashboard.js", "javascript", 1000),
    ("/static/dashboard.css", "text/css", 1000),
    ("/static/vendor/chart.umd.min.js", "javascript", 100_000),
    ("/static/favicon.png", "image/png", 100),
])
def test_static_files(server, path, mime, min_size):
    status, headers, body = http("GET", server.base + path)
    assert status == 200 and mime in headers["content-type"] and len(body) >= min_size


# ---- speedtest --------------------------------------------------------------------------------------

def test_speedtest_success_payload(server):
    status, _, body = http("POST", server.base + "/api/speedtest")
    data = json.loads(body)
    assert status == 200
    assert (data["status"], data["download_mbps"], data["upload_mbps"], data["server"]) == (
        "SUCCESS", 93.4, 21.7, "Cloudflare CDN Edge")


def test_busy_speedtest_maps_to_409(server):
    """Регрессия: при уже идущем замере возвращался устаревший прошлый результат с кодом 200."""
    server.speed_result = SpeedtestResult(timestamp=datetime.now(), download_mbps=0, upload_mbps=0, status="BUSY")
    assert http("POST", server.base + "/api/speedtest")[0] == 409


def test_dashboard_stays_responsive_during_speedtest(server):
    """Регрессия: замер выполнялся в обработчике и блокировал весь сервер на 20+ секунд."""
    server.speed_delay = 1.5
    results = {}
    t = threading.Thread(target=lambda: results.setdefault("r", http("POST", server.base + "/api/speedtest")))
    t.start()
    time.sleep(0.3)
    t0 = time.monotonic()
    assert http("GET", server.base + "/api/stats")[0] == 200
    assert time.monotonic() - t0 < 1.0
    t.join(10)
    assert results["r"][0] == 200


# ---- экспорт ---------------------------------------------------------------------------------------

def leftover_export_dirs():
    return {p.name for p in Path(tempfile.gettempdir()).glob("netpulse_export_*")}


def wait_cleanup(before, timeout=3.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if leftover_export_dirs() <= before:
            return True
        time.sleep(0.05)
    return False


def test_json_export_download(server):
    before = leftover_export_dirs()
    status, headers, body = http("GET", server.base + "/api/export/json")
    assert status == 200 and "attachment" in headers["content-disposition"]
    data = json.loads(body)
    assert data["summary"]["total_pings"] == 1 and data["ping_records"][0]["host"] == "1.1.1.1"
    assert wait_cleanup(before)


def test_csv_export_download(server):
    before = leftover_export_dirs()
    status, headers, body = http("GET", server.base + "/api/export/csv")
    assert status == 200 and "text/csv" in headers["content-type"]
    assert body.decode("utf-8").splitlines()[0].startswith("Timestamp,TargetName")
    assert wait_cleanup(before)


def test_export_through_web_does_not_litter_working_directory(server, tmp_path, monkeypatch):
    """Регрессия: каждое нажатие «Экспорт» оставляло файл отчёта в каталоге запуска."""
    monkeypatch.chdir(tmp_path)
    http("GET", server.base + "/api/export/json")
    http("GET", server.base + "/api/export/csv")
    assert list(tmp_path.glob("netpulse_*")) == []


# ---- резервный сервер: особенности ------------------------------------------------------------------

def test_standalone_reports_busy_port(tmp_path):
    state = State(tmp_path)
    with socket.socket() as busy:
        busy.bind(("127.0.0.1", 0))
        busy.listen(1)
        state.config.web.port = busy.getsockname()[1]
        srv = StandaloneWebServer(state.config, state.collector, state.storage)
        with pytest.raises(OSError):
            srv.start_sync()
        assert srv.start_error


def test_standalone_shutdown_before_start_is_safe(tmp_path):
    state = State(tmp_path)
    StandaloneWebServer(state.config, state.collector, state.storage).shutdown()


def test_standalone_without_speedtest_callback_returns_501(tmp_path):
    state = State(tmp_path)
    srv = StandaloneWebServer(state.config, state.collector, state.storage)
    thread = threading.Thread(target=srv.start_sync, daemon=True)
    thread.start()
    wait_port(state.config.web.port)
    try:
        assert http("POST", f"http://127.0.0.1:{state.config.web.port}/api/speedtest")[0] == 501
    finally:
        srv.shutdown()


# ---- гигиена шаблона (строгая CSP, работа без CDN) ----------------------------------------------------

def test_dashboard_has_no_external_dependencies_or_inline_code():
    html = (UI_DIR / "templates" / "index.html").read_text(encoding="utf-8")
    js = (UI_DIR / "static" / "dashboard.js").read_text(encoding="utf-8")
    css = (UI_DIR / "static" / "dashboard.css").read_text(encoding="utf-8")

    assert not re.search(r"""(?:src|href)\s*=\s*["']https?://""", html), "внешние ресурсы в HTML"
    assert "@import" not in css and "url(http" not in css
    assert "Content-Security-Policy" in html
    scripts = re.findall(r"<script\b[^>]*>", html)
    assert scripts and all("src=" in s for s in scripts), "inline-скрипт нарушает CSP"
    assert not re.search(r"\son\w+\s*=", html), "inline-обработчик событий (onclick=…) нарушает CSP"
    assert not re.search(r"\sstyle\s*=", html), "inline-стили нарушают CSP"
    assert (UI_DIR / "static" / "vendor" / "chart.umd.min.js").exists(), "Chart.js должен лежать локально"
    assert ".innerHTML" not in js and "insertAdjacentHTML" not in js and "document.write" not in js
    assert "eval(" not in js
