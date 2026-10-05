"""Оркестратор (main.py): аргументы командной строки, алерты → трассировка, speedtest, клавиши, цикл опроса, завершение."""
import argparse
import asyncio
import io
import socket
import sqlite3
from datetime import datetime

import pytest
from rich.console import Console

from config.settings import GATEWAY_PLACEHOLDER, AppConfig, HostTarget, PingMode
from main import NetPulseApplication, parse_arguments, parse_host_spec
from metrics.models import AlertSeverity, NetworkAlert, SpeedtestResult


# ---- командная строка -------------------------------------------------------------------------------

def test_parse_host_spec_variants():
    assert (parse_host_spec("1.1.1.1").address, parse_host_spec("1.1.1.1").tcp_port) == ("1.1.1.1", 443)
    t = parse_host_spec("8.8.8.8:53")
    assert (t.address, t.tcp_port, t.name) == ("8.8.8.8", 53, "8.8.8.8:53")
    t = parse_host_spec("[::1]:8080")
    assert (t.address, t.tcp_port) == ("::1", 8080)
    t = parse_host_spec("2001:db8::1")                       # IPv6 без скобок — адрес целиком, порт по умолчанию
    assert (t.address, t.tcp_port) == ("2001:db8::1", 443)
    assert parse_host_spec("  example.com  ").address == "example.com"


@pytest.mark.parametrize("spec", ["host:abc", "host:0", "host:70000", "[::1]:99999"])
def test_parse_host_spec_rejects_bad_ports(spec):
    with pytest.raises(argparse.ArgumentTypeError):
        parse_host_spec(spec)


@pytest.mark.parametrize("argv", [
    ["-i", "0"], ["-i", "-1"], ["-i", "nan"], ["-i", "inf"], ["-i", "abc"],
    ["-t", "0"], ["-t", "-5"],
    ["-p", "0"], ["-p", "70000"], ["-p", "abc"],
    ["-m", "bogus"],
    ["-H", "host:abc"], ["-H", "host:70000"],
])
def test_invalid_arguments_are_usage_errors(argv, capsys):
    """Регрессия: `--interval 0` давал busy-loop на 100 % CPU, `--interval -1` и нечисловые значения — трейсбек."""
    with pytest.raises(SystemExit) as exc:
        parse_arguments(argv)
    assert exc.value.code == 2
    assert "Traceback" not in capsys.readouterr().err


def test_defaults():
    cfg = parse_arguments([])
    assert (cfg.ping_interval, cfg.ping_timeout, cfg.ping_mode) == (1.0, 2.0, PingMode.AUTO)
    assert (cfg.web.enabled, cfg.web.port, cfg.sound_alerts) == (False, 8080, False)
    assert any(t.is_gateway for t in cfg.targets)


def test_hosts_option_replaces_defaults_and_skips_blank_items():
    cfg = parse_arguments(["-H", "1.1.1.1, ,8.8.8.8:53,", "-m", "tcp", "-i", "0.5", "-t", "1", "-w", "-p", "9090", "-s"])
    assert [(t.address, t.tcp_port) for t in cfg.targets] == [("1.1.1.1", 443), ("8.8.8.8", 53)]
    assert (cfg.ping_mode, cfg.ping_interval, cfg.ping_timeout) == (PingMode.TCP, 0.5, 1.0)
    assert (cfg.web.enabled, cfg.web.port, cfg.sound_alerts) == (True, 9090, True)


# ---- приложение -------------------------------------------------------------------------------------

def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def make_app(tmp_path, monkeypatch, targets=None) -> NetPulseApplication:
    monkeypatch.chdir(tmp_path)
    cfg = AppConfig()
    cfg.db_path = tmp_path / "app.db"
    cfg.ping_mode = PingMode.TCP
    cfg.ping_interval = 0.1
    cfg.ping_timeout = 0.5
    cfg.targets = targets if targets is not None else [
        HostTarget("Шлюз", GATEWAY_PLACEHOLDER, is_gateway=True),
        HostTarget("DNS", "1.1.1.1"),
    ]
    app = NetPulseApplication(cfg)
    app.storage.export_dir = tmp_path / "exports"
    app.console = Console(file=io.StringIO(), width=140, color_system=None)
    return app


@pytest.fixture
def app(tmp_path, monkeypatch):
    return make_app(tmp_path, monkeypatch)


def alert(host="1.1.1.1", severity=AlertSeverity.CRITICAL) -> NetworkAlert:
    return NetworkAlert(timestamp=datetime.now(), host=host, target_name=host, severity=severity, message="m",
                        metric_name="availability", current_value=3.0, threshold_value=3.0)


def db_count(app, table) -> int:
    with sqlite3.connect(app.storage.db_path) as conn:
        return conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]


def result(status="SUCCESS", dl=90.0, ul=20.0) -> SpeedtestResult:
    return SpeedtestResult(timestamp=datetime.now(), download_mbps=dl, upload_mbps=ul, duration_s=2.0, status=status)


# ---- алерты и автотрассировка -----------------------------------------------------------------------

@pytest.fixture
def traces(app, monkeypatch):
    """Подменяет движок трассировки: фиксирует запуски и держит их, пока не вызван release()."""
    class Traces:
        started = []
        sounds = []
        gate = asyncio.Event()

    t = Traces()
    t.started, t.sounds, t.gate = [], [], asyncio.Event()

    async def fake_trace(host, on_hop_callback=None):
        t.started.append(host)
        await t.gate.wait()
        return []

    monkeypatch.setattr(app.traceroute_engine, "trace", fake_trace)
    monkeypatch.setattr(app.ui, "trigger_sound_alert", lambda: t.sounds.append(1))
    return t


async def test_burst_of_critical_alerts_starts_a_single_traceroute(app, traces):
    """Регрессия: каждый алерт из одного батча запускал свою трассировку (десятки процессов traceroute)."""
    for _ in range(5):
        app._handle_alert(alert("1.1.1.1"))
    for _ in range(5):
        app._handle_alert(alert("8.8.8.8"))            # другой узел, пока трассировка ещё идёт
    await asyncio.sleep(0.05)
    assert traces.started == ["1.1.1.1"]
    assert len(traces.sounds) == 10 and app.auto_trace_in_progress

    traces.gate.set()
    await asyncio.sleep(0.05)
    assert not app.auto_trace_in_progress and not app.ui.traceroute_running


async def test_traceroute_cooldown_is_per_host(app, traces):
    traces.gate.set()
    app._handle_alert(alert("1.1.1.1"))
    await asyncio.sleep(0.05)
    app._handle_alert(alert("1.1.1.1"))                 # тот же узел в пределах cooldown — нет
    await asyncio.sleep(0.05)
    assert traces.started == ["1.1.1.1"]
    app._handle_alert(alert("8.8.8.8"))                 # другой узел — да
    await asyncio.sleep(0.05)
    assert traces.started == ["1.1.1.1", "8.8.8.8"]


async def test_traceroute_repeats_after_cooldown(app, traces):
    traces.gate.set()
    app.config.auto_traceroute_cooldown_s = 0.0
    app._handle_alert(alert("1.1.1.1"))
    await asyncio.sleep(0.05)
    app._handle_alert(alert("1.1.1.1"))
    await asyncio.sleep(0.05)
    assert traces.started == ["1.1.1.1", "1.1.1.1"]


async def test_info_and_warning_alerts_do_not_trace(app, traces):
    app._handle_alert(alert(severity=AlertSeverity.INFO))
    assert traces.sounds == []                          # «узел восстановлен» — не повод для звука
    app._handle_alert(alert(severity=AlertSeverity.WARNING))
    assert traces.sounds == [1]
    await asyncio.sleep(0.05)
    assert traces.started == []


async def test_no_traceroute_for_unresolved_gateway_or_when_disabled(app, traces):
    app._handle_alert(alert(GATEWAY_PLACEHOLDER))
    app.config.auto_traceroute_on_alert = False
    app._handle_alert(alert("1.1.1.1"))
    await asyncio.sleep(0.05)
    assert traces.started == []


async def test_all_alerts_are_queued_for_storage(app, traces):
    for sev in AlertSeverity:
        app._handle_alert(alert(severity=sev))
    assert len(app._pending_alerts) == 3


async def test_traceroute_engine_failure_is_shown_and_state_reset(app, monkeypatch):
    async def boom(host, on_hop_callback=None):
        raise RuntimeError("sandbox forbids exec")

    monkeypatch.setattr(app.traceroute_engine, "trace", boom)
    app._start_traceroute("1.1.1.1")
    await asyncio.sleep(0.05)
    assert "sandbox forbids exec" in app.ui.traceroute_error
    assert not app.ui.traceroute_running and not app.auto_trace_in_progress
    assert app.ui.traceroute_finished_at is not None


async def test_missing_traceroute_utility_reason_reaches_the_ui(app, monkeypatch):
    """Регрессия: без утилиты traceroute панель вечно показывала «Анализ…» без объяснения."""
    async def fake_trace(host, on_hop_callback=None):
        app.traceroute_engine.last_error = "Утилита traceroute не найдена"
        return []

    monkeypatch.setattr(app.traceroute_engine, "trace", fake_trace)
    app._start_traceroute("1.1.1.1")
    await asyncio.sleep(0.05)
    assert app.ui.traceroute_error == "Утилита traceroute не найдена"


# ---- speedtest ---------------------------------------------------------------------------------------

async def test_speedtest_while_busy_returns_busy_and_keeps_flag(app):
    app.ui.speedtest_running = True
    assert (await app.run_manual_speedtest()).status == "BUSY"
    assert app.ui.speedtest_running is True             # флаг ЧУЖОГО замера не сбрасывается


async def test_concurrent_speedtests_run_only_once(app, monkeypatch):
    """Регрессия: гонка проверка-флага/запуск — два замера одновременно и стирание статуса друг друга."""
    calls, gate = [], asyncio.Event()

    async def slow(progress_cb=None):
        calls.append(1)
        await gate.wait()
        return result()

    monkeypatch.setattr(app.speedtest_engine, "run_full_speedtest", slow)
    first = asyncio.create_task(app.run_manual_speedtest())
    await asyncio.sleep(0)
    second = await app.run_manual_speedtest()
    gate.set()
    assert second.status == "BUSY" and (await first).status == "SUCCESS" and calls == [1]
    assert not app.ui.speedtest_running


async def test_speedtest_engine_exception_becomes_failed_result(app, monkeypatch):
    async def boom(progress_cb=None):
        raise RuntimeError("network down")

    monkeypatch.setattr(app.speedtest_engine, "run_full_speedtest", boom)
    res = await app.run_manual_speedtest()
    assert res.status == "FAILED" and not app.ui.speedtest_running
    assert "network down" in app.ui.speedtest_status_text


async def test_failed_speedtest_does_not_overwrite_last_good_result(app, monkeypatch):
    good = result()
    app.ui.last_speedtest = good

    async def failed(progress_cb=None):
        return result("FAILED", 0.0, 0.0)

    monkeypatch.setattr(app.speedtest_engine, "run_full_speedtest", failed)
    await app.run_manual_speedtest()
    assert app.ui.last_speedtest is good


async def test_successful_speedtest_is_shown_and_stored(app, monkeypatch):
    fresh = result(dl=93.4, ul=21.7)

    async def ok(progress_cb=None):
        progress_cb("download", 50.0)
        return fresh

    monkeypatch.setattr(app.speedtest_engine, "run_full_speedtest", ok)
    res = await app.run_manual_speedtest()
    assert res is fresh and app.ui.last_speedtest is fresh
    assert "93.4" in app.ui.speedtest_status_text and db_count(app, "speedtests") == 1


async def test_partial_speedtest_is_labelled_honestly(app, monkeypatch):
    async def partial(progress_cb=None):
        return result("PARTIAL", 55.0, 0.0)

    monkeypatch.setattr(app.speedtest_engine, "run_full_speedtest", partial)
    await app.run_manual_speedtest()
    assert "отдачу измерить не удалось" in app.ui.speedtest_status_text


async def test_error_text_with_markup_cannot_break_the_ui(app, monkeypatch):
    async def boom(progress_cb=None):
        raise RuntimeError("[bold red]oops[/")

    monkeypatch.setattr(app.speedtest_engine, "run_full_speedtest", boom)
    await app.run_manual_speedtest()
    app.console.print(app.ui.render())                  # не должно бросать MarkupError


# ---- клавиши ------------------------------------------------------------------------------------------

async def test_q_requests_shutdown(app):
    await app._safe_process_key("q")
    assert app.shutdown_event.is_set()


async def test_unknown_key_is_ignored(app):
    await app._safe_process_key("z")
    assert not app.shutdown_event.is_set()


async def test_handler_error_does_not_kill_key_listener(app, monkeypatch):
    """Регрессия: исключение в обработчике 'e' (read-only диск) завершало слушатель — 'q' переставал работать."""
    async def boom(key):
        raise RuntimeError("disk is read-only")

    monkeypatch.setattr(app, "_process_key", boom)
    await app._safe_process_key("e")                    # не бросает
    assert "disk is read-only" in app.ui.last_export_message


async def test_export_key_writes_reports_and_reports_failures(app, monkeypatch):
    await app._process_key("e")
    assert sorted(p.suffix for p in app.storage.export_dir.iterdir()) == [".csv", ".json"]
    assert "Отчеты сохранены" in app.ui.last_export_message

    def deny(*_a, **_k):
        raise PermissionError("read-only filesystem")

    monkeypatch.setattr(app.storage, "export_json", deny)
    await app._process_key("e")
    assert "Экспорт не удался" in app.ui.last_export_message


async def test_manual_traceroute_key_runs_once_at_a_time(app, traces):
    await app._process_key("t")
    await app._process_key("t")                         # повторное нажатие во время трассировки игнорируется
    await asyncio.sleep(0.05)
    assert traces.started == ["1.1.1.1"]               # шлюз не определён → запасная цель
    traces.gate.set()
    await asyncio.sleep(0.05)


async def test_speedtest_key_while_running_does_nothing(app, monkeypatch):
    calls = []

    async def fake(progress_cb=None):
        calls.append(1)
        return result()

    monkeypatch.setattr(app.speedtest_engine, "run_full_speedtest", fake)
    app.ui.speedtest_running = True
    await app._process_key("s")
    await asyncio.sleep(0.05)
    assert calls == []


# ---- шлюз ----------------------------------------------------------------------------------------------

def test_apply_gateway_updates_target_and_collector(app):
    app._apply_gateway("192.168.1.1")
    gateway = next(t for t in app.config.targets if t.is_gateway)
    assert gateway.address == "192.168.1.1" and gateway.enabled
    assert {s.address for s in app.collector.get_all_stats()} == {"192.168.1.1", "1.1.1.1"}


@pytest.mark.parametrize("value", [None, "", "127.0.0.1"])
def test_apply_gateway_ignores_unusable_values(app, value):
    app._apply_gateway(value)
    assert next(t for t in app.config.targets if t.is_gateway).address == GATEWAY_PLACEHOLDER


def test_gateway_equal_to_explicit_host_is_not_pinged_twice(tmp_path, monkeypatch):
    app = make_app(tmp_path, monkeypatch, targets=[
        HostTarget("Шлюз", GATEWAY_PLACEHOLDER, is_gateway=True),
        HostTarget("Router", "192.168.1.1"),
    ])
    app._apply_gateway("192.168.1.1")
    active = [t for t in app.config.targets if t.enabled]
    assert [t.name for t in active] == ["Router"]


# ---- веб-порт ------------------------------------------------------------------------------------------

def test_web_port_check(app):
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        app.config.web.port = probe.getsockname()[1]
    assert app._check_web_port() is None                # порт освободился

    with socket.socket() as busy:
        busy.bind(("127.0.0.1", 0))
        busy.listen(1)
        app.config.web.port = busy.getsockname()[1]
        message = app._check_web_port()
    assert message and str(app.config.web.port) in message


# ---- цикл опроса и завершение --------------------------------------------------------------------------

async def run_loop_for(app, seconds):
    task = asyncio.create_task(app._ping_loop())
    await asyncio.sleep(seconds)
    app.shutdown_event.set()
    await asyncio.wait_for(task, 3)


async def test_ping_loop_collects_and_persists(tmp_path, monkeypatch):
    server = await asyncio.start_server(lambda r, w: w.close(), "127.0.0.1", 0)
    port = server.sockets[0].getsockname()[1]
    app = make_app(tmp_path, monkeypatch, targets=[HostTarget("local", "127.0.0.1", tcp_port=port)])
    app._handle_alert(alert("127.0.0.1", AlertSeverity.INFO))
    try:
        await run_loop_for(app, 0.7)
    finally:
        server.close()
        await server.wait_closed()
    stats = app.collector.get_all_stats()[0]
    assert stats.sent_count >= 3 and stats.status == "OK"
    assert db_count(app, "ping_records") == stats.sent_count
    assert db_count(app, "alerts") == 1 and app._pending_alerts == []


async def test_storage_failure_neither_kills_loop_nor_loses_alerts(tmp_path, monkeypatch):
    server = await asyncio.start_server(lambda r, w: w.close(), "127.0.0.1", 0)
    port = server.sockets[0].getsockname()[1]
    app = make_app(tmp_path, monkeypatch, targets=[HostTarget("local", "127.0.0.1", tcp_port=port)])
    app._handle_alert(alert("127.0.0.1", AlertSeverity.INFO))
    original, failures = app.storage.record_batch, []

    def flaky(pings, alerts):
        if not failures:
            failures.append(1)
            raise sqlite3.OperationalError("database is locked")
        return original(pings, alerts)

    monkeypatch.setattr(app.storage, "record_batch", flaky)
    try:
        await run_loop_for(app, 0.8)
    finally:
        server.close()
        await server.wait_closed()
    assert failures == [1]
    assert db_count(app, "alerts") == 1                 # алерт пережил сбой записи и сохранён со следующей итерацией
    assert app.collector.get_all_stats()[0].sent_count >= 3


async def test_graceful_shutdown_cancels_tasks_and_writes_reports(app):
    background = app._spawn(asyncio.sleep(30), name="dummy")
    app._handle_alert(alert("1.1.1.1", AlertSeverity.WARNING))
    await app._graceful_shutdown(None)
    assert background.cancelled()
    assert sorted(p.suffix for p in app.storage.export_dir.iterdir()) == [".csv", ".json"]
    assert db_count(app, "alerts") == 1                 # алерт, не успевший в БД, дописан при выходе
    with sqlite3.connect(app.storage.db_path) as conn:
        assert conn.execute("SELECT end_time FROM sessions WHERE session_id = ?",
                            (app.storage.session_id,)).fetchone()[0] is not None
    assert "успешно завершена" in app.console.file.getvalue()


async def test_shutdown_continues_when_a_step_fails(app, monkeypatch):
    def deny(*_a, **_k):
        raise PermissionError("read-only filesystem")

    monkeypatch.setattr(app.storage, "export_json", deny)
    await app._graceful_shutdown(None)                  # не бросает
    out = app.console.file.getvalue()
    assert "Не удалось" in out and "успешно завершена" in out


async def test_background_task_error_is_reported_not_lost(app):
    async def boom():
        raise RuntimeError("task exploded")

    task = app._spawn(boom(), name="boomer")
    await asyncio.sleep(0.05)
    assert task.done() and task not in app._tasks
    assert "boomer" in app.ui.last_export_message and "task exploded" in app.ui.last_export_message
