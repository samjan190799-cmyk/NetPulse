"""Движок трассировки: разбор вывода traceroute/tracert, обработка ошибок, безопасность аргументов."""
import os
import stat
import sys

import pytest

import engine.traceroute as traceroute_module
from engine.traceroute import AsyncTracerouteEngine

posix_only = pytest.mark.skipif(sys.platform == "win32", reason="POSIX-скрипты")


@pytest.fixture
def engine():
    return AsyncTracerouteEngine()


# ---- разбор строк -----------------------------------------------------------------------------

def test_linux_line(engine):
    hop = engine._parse_hop_line(" 1  192.168.1.1  0.512 ms  0.480 ms  0.420 ms")
    assert (hop.hop_num, hop.ip_address, hop.latency_ms, hop.loss_pct) == (1, "192.168.1.1", 0.5, 0.0)


def test_windows_line_with_small_values(engine):
    hop = engine._parse_hop_line("  1     1 ms     1 ms     1 ms  192.168.1.1")
    assert (hop.hop_num, hop.ip_address, hop.latency_ms, hop.loss_pct) == (1, "192.168.1.1", 1.0, 0.0)


def test_windows_less_than_one_ms(engine):
    hop = engine._parse_hop_line("  2    <1 ms    <1 ms    <1 ms  10.0.0.1")
    assert hop.hop_num == 2 and hop.latency_ms == 1.0


def test_windows_timeouts_are_full_loss(engine):
    hop = engine._parse_hop_line("  2     *        *        *     Превышен интервал ожидания для запроса.")
    assert (hop.hop_num, hop.loss_pct, hop.latency_ms, hop.ip_address) == (2, 100.0, None, "*")


def test_partial_loss_is_proportional_to_probes(engine):
    """Регрессия: «звёздочки» делились на фиксированные 3 пробы, а не на фактическое их число."""
    hop = engine._parse_hop_line(" 4  10.1.1.1  5.0 ms * 7.0 ms")
    assert hop.loss_pct == pytest.approx(33.3, abs=0.1) and hop.latency_ms == 6.0
    two_probes = engine._parse_hop_line(" 5  10.1.1.2  5.0 ms *")
    assert two_probes.loss_pct == 50.0


def test_localized_milliseconds(engine):
    hop = engine._parse_hop_line("  3    12 мс    14 мс    13 мс  8.8.8.8")
    assert hop.latency_ms == 13.0 and hop.ip_address == "8.8.8.8"


@pytest.mark.parametrize(
    "line",
    [
        "  72.14.238.99  12.7 ms  13.1 ms  12.9 ms",          # продолжение хопа при ECMP-балансировке
        "traceroute to 1.1.1.1 (1.1.1.1), 15 hops max, 60 byte packets",
        "Tracing route to one.one.one.one [1.1.1.1]",
        "over a maximum of 15 hops:",
        "Trace complete.",
        "",
    ],
)
def test_non_hop_lines_are_ignored(engine, line):
    """Регрессия: «72.14.238.99 …» разбиралось как хоп №72, ломая таблицу маршрута."""
    assert engine._parse_hop_line(line) is None


# ---- построение команды -----------------------------------------------------------------------

def test_linux_command_uses_whole_seconds_wait():
    eng = AsyncTracerouteEngine(timeout_ms=600)
    eng.system = "linux"
    cmd = eng._build_command("1.1.1.1")
    assert cmd == ["traceroute", "-n", "-m", "15", "-w", "1", "1.1.1.1"]      # -w в секундах, минимум 1


def test_windows_command_uses_milliseconds():
    eng = AsyncTracerouteEngine(timeout_ms=600)
    eng.system = "windows"
    assert eng._build_command("1.1.1.1") == ["tracert", "-d", "-h", "15", "-w", "600", "1.1.1.1"]


# ---- ошибки -----------------------------------------------------------------------------------

async def test_missing_binary_is_reported(monkeypatch):
    """Регрессия: без утилиты traceroute панель показывала «Анализ…» вечно — причина пропадала молча."""
    monkeypatch.setattr(traceroute_module.shutil, "which", lambda _name: None)
    eng = AsyncTracerouteEngine()
    hops = await eng.trace("1.1.1.1")
    assert hops == [] and eng.last_error and "traceroute" in eng.last_error.lower()


@pytest.mark.parametrize("host", ["-oProxyCommand=evil", "-g 1.2.3.4", "a b", "x;y", "$(id)", ""])
async def test_option_like_or_malformed_hosts_are_rejected(host, monkeypatch):
    called = []

    async def spy(*args, **kwargs):
        called.append(args)
        raise AssertionError("процесс не должен запускаться")

    monkeypatch.setattr(traceroute_module.asyncio, "create_subprocess_exec", spy)
    eng = AsyncTracerouteEngine()
    assert await eng.trace(host) == []
    assert eng.last_error and not called


@pytest.fixture
def fake_traceroute(tmp_path, monkeypatch):
    def install(body: str) -> None:
        script = tmp_path / "traceroute"
        script.write_text("#!/bin/sh\n" + body + "\n")
        script.chmod(script.stat().st_mode | stat.S_IEXEC)
        monkeypatch.setenv("PATH", f"{tmp_path}{os.pathsep}{os.environ['PATH']}")
    return install


@posix_only
async def test_full_trace_with_callback(fake_traceroute):
    fake_traceroute(
        'echo "traceroute to 1.1.1.1 (1.1.1.1), 15 hops max"\n'
        'echo " 1  192.168.1.1  0.5 ms  0.4 ms  0.6 ms"\n'
        'echo " 2  * * *"\n'
        'echo "    72.14.238.99  9.1 ms"\n'
        'echo " 3  1.1.1.1  11.0 ms  11.2 ms  10.8 ms"'
    )
    eng = AsyncTracerouteEngine()
    eng.system = "linux"
    seen = []
    hops = await eng.trace("1.1.1.1", on_hop_callback=seen.append)
    assert [h.hop_num for h in hops] == [1, 2, 3]
    assert [h.hop_num for h in seen] == [1, 2, 3]
    assert hops[1].ip_address == "*" and hops[1].loss_pct == 100.0
    assert eng.last_error is None


@posix_only
async def test_no_hops_sets_explanation(fake_traceroute):
    fake_traceroute("exit 0")
    eng = AsyncTracerouteEngine()
    eng.system = "linux"
    assert await eng.trace("1.1.1.1") == [] and eng.last_error


@posix_only
async def test_total_timeout_kills_the_process(fake_traceroute, tmp_path):
    """Регрессия: «зависший» traceroute не имел общего таймаута и переживал приложение."""
    pidfile = tmp_path / "pid"
    fake_traceroute(f'echo " 1  192.168.1.1  0.5 ms"\necho $$ > {pidfile}\nexec sleep 30')
    eng = AsyncTracerouteEngine(total_timeout=0.5)
    eng.system = "linux"
    hops = await eng.trace("1.1.1.1")
    assert [h.hop_num for h in hops] == [1]                    # то, что успели получить, сохраняется
    assert eng.last_error and "превышено" in eng.last_error
    pid = int(pidfile.read_text())
    with pytest.raises(ProcessLookupError):
        os.kill(pid, 0)
