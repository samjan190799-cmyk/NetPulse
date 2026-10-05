"""Терминальный интерфейс: безопасный вывод динамического текста, индикатор связи, звук, панель трассировки."""
import io
import time
from datetime import datetime

import pytest
from rich.console import Console

import ui.tui as tui_module
from config.settings import AlertThresholds, AppConfig
from metrics.collector import MetricsCollector
from metrics.models import AlertSeverity, NetworkAlert, PingResult, TracerouteHop
from ui.tui import TerminalUI


def make_console(terminal: bool = False) -> Console:
    return Console(file=io.StringIO(), width=170, force_terminal=terminal, color_system=None)


@pytest.fixture
def collector():
    return MetricsCollector(AlertThresholds())


@pytest.fixture
def ui(collector):
    return TerminalUI(AppConfig(), collector, console=make_console())


def feed(collector, host, name, ok=True, latency=10.0, count=3):
    if host not in {s.address for s in collector.get_all_stats()}:
        collector.register_host(name, host)
    for _ in range(count):
        collector.record_result(PingResult(host=host, target_name=name, timestamp=datetime.now(),
                                           is_success=ok, latency_ms=latency if ok else None))


def rendered(ui) -> str:
    ui.console.print(ui.render())
    return ui.console.file.getvalue()


def test_empty_dashboard_renders(ui):
    assert "NetPulse" in rendered(ui)


def test_dynamic_text_with_markup_is_shown_literally(ui, collector):
    """Регрессия: имя узла вида «[red]x[/]» (из командной строки/DNS) интерпретировалось как разметка."""
    feed(collector, "10.0.0.1", "[bold red]evil[/bold red] [/oops] [link=http://x]")
    ui.last_export_message = "ошибка: [/unclosed] [bold"
    ui.web_error = None
    out = rendered(ui)
    assert "[bold red]evil[/bold red]" in out and "[/oops]" in out
    assert "ошибка: [/unclosed] [bold" in out


def test_traceroute_target_and_error_are_escaped(ui):
    ui.traceroute_target = "[red]host"
    ui.traceroute_error = "Ошибка: [/x] [bold"
    ui.traceroute_hops = [TracerouteHop(hop_num=1, ip_address="[b]1.2.3.4", host_name=None, latency_ms=1.0, loss_pct=0.0)]
    ui.traceroute_finished_at = time.monotonic()
    out = rendered(ui)
    assert "[red]host" in out and "[/x] [bold" in out and "[b]1.2.3.4" in out


def test_web_error_is_shown_in_footer(ui):
    ui.web_error = "Веб-интерфейс не запущен: порт занят"
    assert "порт занят" in rendered(ui)


# ---- индикатор связи --------------------------------------------------------------------------------

def test_connectivity_initializing_then_online_then_offline(ui, collector):
    """Регрессия: «ONLINE» показывался по таймеру, даже когда ни один узел не отвечал."""
    assert "INITIALIZING" in ui._connectivity_markup(5)
    feed(collector, "1.1.1.1", "ok", ok=True)
    assert "ONLINE" in ui._connectivity_markup(5)
    collector.record_result(PingResult(host="1.1.1.1", target_name="ok", timestamp=datetime.now(), is_success=False))
    assert "OFFLINE" in ui._connectivity_markup(5)


def test_unresolved_gateway_does_not_count_as_data(ui, collector):
    collector.register_host("gw", "gateway", is_gateway=True)
    assert "INITIALIZING" in ui._connectivity_markup(5)


# ---- звук --------------------------------------------------------------------------------------------

def test_sound_alert_writes_bel_through_the_live_console(collector):
    """
    Регрессия: звук писался в sys.stdout, который Rich Live перехватывает и отбрасывает управляющий BEL —
    сигнал не звучал никогда. Теперь BEL идёт через консоль дисплея.
    """
    console = make_console(terminal=True)
    ui = TerminalUI(AppConfig(sound_alerts=True), collector, console=console)
    ui.trigger_sound_alert()
    assert "\x07" in console.file.getvalue()


def test_sound_is_silent_when_disabled(collector):
    console = make_console(terminal=True)
    TerminalUI(AppConfig(sound_alerts=False), collector, console=console).trigger_sound_alert()
    assert "\x07" not in console.file.getvalue()


def test_sound_failure_is_swallowed(collector, monkeypatch):
    ui = TerminalUI(AppConfig(sound_alerts=True), collector, console=make_console(terminal=True))
    monkeypatch.setattr(ui.console, "bell", lambda: (_ for _ in ()).throw(OSError("no tty")))
    ui.trigger_sound_alert()                              # не бросает


# ---- панель трассировки ------------------------------------------------------------------------------

def test_trace_panel_replaces_alert_log_only_temporarily(ui, monkeypatch):
    """Регрессия: после первой трассировки журнал алертов навсегда пропадал из интерфейса."""
    ui.traceroute_hops = [TracerouteHop(hop_num=1, ip_address="192.168.1.1", host_name=None, latency_ms=1.0, loss_pct=0.0)]
    ui.traceroute_finished_at = time.monotonic()
    assert ui._trace_panel_visible()
    monkeypatch.setattr(tui_module.time, "monotonic", lambda: ui.traceroute_finished_at + tui_module.TRACE_PANEL_TTL_S + 1)
    assert not ui._trace_panel_visible()


def test_running_trace_is_always_visible(ui):
    ui.traceroute_running = True
    assert ui._trace_panel_visible()


def test_failed_trace_shows_reason_not_endless_spinner(ui):
    ui.traceroute_error = "Утилита traceroute не найдена"
    ui.traceroute_finished_at = time.monotonic()
    out = rendered(ui)
    assert "Не выполнена" in out and "Утилита traceroute не найдена" in out and "в процессе" not in out


# ---- алерты в журнале ----------------------------------------------------------------------------------

def test_alert_log_lists_all_severities(ui, collector):
    feed(collector, "10.0.0.1", "h")
    for sev, text in ((AlertSeverity.WARNING, "warn-text"), (AlertSeverity.CRITICAL, "crit-text"),
                      (AlertSeverity.INFO, "info-text")):
        collector._dispatch(NetworkAlert(timestamp=datetime.now(), host="10.0.0.1", target_name="h", severity=sev,
                                         message=text, metric_name="x", current_value=0, threshold_value=0))
    out = rendered(ui)
    assert all(word in out for word in ("warn-text", "crit-text", "info-text"))
