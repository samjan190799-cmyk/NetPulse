"""Движок пинга: TCP, ICMP (raw и через утилиту), DNS-кэш, разбор ответов, конкурентность."""
import asyncio
import os
import socket
import stat
import struct
import sys
import time

import pytest

import engine.ping as ping_module
from config.settings import GATEWAY_PLACEHOLDER, HostTarget, PingMode
from engine.ping import (
    AsyncPingEngine,
    _icmp_checksum,
    _is_safe_host,
    _LATENCY_RE,
    _next_icmp_ident,
    _sync_raw_ping,
)

posix_only = pytest.mark.skipif(sys.platform == "win32", reason="POSIX-скрипты и сигналы")


# ---- вспомогательные --------------------------------------------------------------------------

@pytest.fixture
async def tcp_server():
    """Локальный TCP-сервер на свободном порту loopback."""
    async def handler(reader, writer):
        writer.close()

    server = await asyncio.start_server(handler, "127.0.0.1", 0)
    port = server.sockets[0].getsockname()[1]
    yield port
    server.close()
    await server.wait_closed()


def free_closed_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


# ---- TCP --------------------------------------------------------------------------------------

async def test_tcp_ping_open_port(tcp_server):
    ok, latency, error = await AsyncPingEngine(PingMode.TCP).tcp_ping("127.0.0.1", tcp_server)
    assert ok and error is None and 0 < latency < 1000


async def test_tcp_ping_closed_port_means_host_is_alive():
    """RST в ответ на SYN — хост отвечает, значит жив; задержка валидна."""
    ok, latency, error = await AsyncPingEngine(PingMode.TCP).tcp_ping("127.0.0.1", free_closed_port())
    assert ok and latency is not None and error is None


async def test_tcp_ping_unresolvable_host_fails_with_dns_error():
    ok, latency, error = await AsyncPingEngine(PingMode.TCP).tcp_ping("no-such-host.invalid", 443, timeout=2.0)
    assert not ok and latency is None and error.startswith("DNS")


async def test_tcp_ping_timeout(monkeypatch):
    async def never(*_a, **_k):
        await asyncio.sleep(30)

    monkeypatch.setattr(asyncio, "open_connection", never)
    t0 = time.monotonic()
    ok, latency, error = await AsyncPingEngine(PingMode.TCP).tcp_ping("127.0.0.1", 9, timeout=0.2)
    assert (ok, latency, error) == (False, None, "Connection timed out")
    assert time.monotonic() - t0 < 2


async def test_dns_is_resolved_once_and_cached(monkeypatch):
    loop = asyncio.get_running_loop()
    calls = []

    async def fake_getaddrinfo(host, port, **_kw):
        calls.append(host)
        return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("192.0.2.10", port))]

    monkeypatch.setattr(loop, "getaddrinfo", fake_getaddrinfo)
    engine = AsyncPingEngine(PingMode.TCP)
    assert await engine._resolve_ip("example.test", 443, 1.0) == "192.0.2.10"
    assert await engine._resolve_ip("example.test", 443, 1.0) == "192.0.2.10"
    assert calls == ["example.test"]


async def test_ip_literal_skips_dns(monkeypatch):
    loop = asyncio.get_running_loop()

    async def fail(*_a, **_k):
        raise AssertionError("DNS не должен вызываться для IP-адреса")

    monkeypatch.setattr(loop, "getaddrinfo", fail)
    assert await AsyncPingEngine(PingMode.TCP)._resolve_ip("127.0.0.1", 443, 1.0) == "127.0.0.1"


async def test_rtt_does_not_include_dns_time(monkeypatch, tcp_server):
    """Регрессия: в «RTT» входило время DNS-запроса — каждый всплеск DNS выглядел как скачок задержки."""
    loop = asyncio.get_running_loop()

    async def slow_getaddrinfo(host, port, **_kw):
        await asyncio.sleep(0.4)
        return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("127.0.0.1", port))]

    monkeypatch.setattr(loop, "getaddrinfo", slow_getaddrinfo)
    ok, latency, _ = await AsyncPingEngine(PingMode.TCP).tcp_ping("slow-dns.test", tcp_server, timeout=3.0)
    assert ok and latency < 100


# ---- разбор ответа утилиты ping и безопасность аргументов ------------------------------------------

@pytest.mark.parametrize(
    "line, expected",
    [
        ("64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=12.3 ms", 12.3),
        ("Reply from 1.1.1.1: bytes=32 time<1ms TTL=57", 1.0),
        ("Reply from 1.1.1.1: bytes=32 time=15ms TTL=57", 15.0),
        ("Ответ от 1.1.1.1: число байт=32 время=15мс TTL=57", 15.0),
        ("Antwort von 1.1.1.1: Bytes=32 Zeit=8ms TTL=57", 8.0),
        ("64 bytes from ::1: icmp_seq=1 ttl=64 time=0,512 ms", 0.512),
    ],
)
def test_latency_is_parsed_in_any_locale(line, expected):
    """Регрессия: регулярка требовала английское «time=» — на локализованной ОС RTT подменялся временем процесса."""
    match = _LATENCY_RE.search(line)
    assert match and float(match.group(1).replace(",", ".")) == expected


@pytest.mark.parametrize("host", ["example.com", "1.1.1.1", "::1", "fe80::1%eth0", "[::1]", "my-host_1.local"])
def test_safe_hosts(host):
    assert _is_safe_host(host)


@pytest.mark.parametrize("host", ["", "-oProxyCommand=evil", "-c 100", "a b", "a;b", "$(id)", "`id`", "a\nb"])
def test_unsafe_hosts_are_rejected(host):
    """Имя хоста, начинающееся с «-», стало бы опцией утилиты ping (инъекция аргументов)."""
    assert not _is_safe_host(host)


@pytest.mark.parametrize(
    "system, timeout, expected",
    [
        ("linux", 0.5, ["ping", "-c", "1", "-W", "1", "--", "h"]),    # int(0.5) == 0 означало бы «не ждать»
        ("linux", 2.0, ["ping", "-c", "1", "-W", "2", "--", "h"]),
        ("linux", 2.1, ["ping", "-c", "1", "-W", "3", "--", "h"]),
        ("darwin", 2.0, ["ping", "-c", "1", "-W", "2000", "--", "h"]),  # на macOS -W в миллисекундах
        ("windows", 2.0, ["ping", "-n", "1", "-w", "2000", "h"]),
    ],
)
def test_ping_command_per_platform(system, timeout, expected):
    engine = AsyncPingEngine(PingMode.SUBPROCESS)
    engine.system = system
    assert engine._ping_command("h", timeout) == expected


@pytest.fixture
def fake_ping(tmp_path, monkeypatch):
    """Подставляет в PATH поддельную утилиту ping с заданным телом (sh)."""
    def install(body: str) -> None:
        script = tmp_path / "ping"
        script.write_text("#!/bin/sh\n" + body + "\n")
        script.chmod(script.stat().st_mode | stat.S_IEXEC)
        monkeypatch.setenv("PATH", f"{tmp_path}{os.pathsep}{os.environ['PATH']}")
    return install


def make_engine_with_ping() -> AsyncPingEngine:
    engine = AsyncPingEngine(PingMode.SUBPROCESS, timeout=1.0)
    engine.system = "linux"
    engine._ping_binary = "ping"
    return engine


@posix_only
async def test_subprocess_ping_success(fake_ping):
    fake_ping('echo "64 bytes from x: icmp_seq=1 ttl=57 time=12.3 ms"')
    assert await make_engine_with_ping().subprocess_icmp_ping("example.com") == (True, 12.3, None)


@posix_only
async def test_subprocess_ping_failure_exit_code(fake_ping):
    fake_ping("exit 1")
    ok, latency, error = await make_engine_with_ping().subprocess_icmp_ping("example.com")
    assert (ok, latency) == (False, None) and "1" in error


@posix_only
async def test_subprocess_ping_rejects_option_like_host(fake_ping, tmp_path):
    marker = tmp_path / "ran"
    fake_ping(f"touch {marker}")
    result = await make_engine_with_ping().subprocess_icmp_ping("-oProxyCommand=evil")
    assert result[0] is False
    assert not marker.exists()                       # процесс даже не запускался


@posix_only
async def test_subprocess_ping_timeout_kills_the_process(fake_ping, tmp_path):
    """Регрессия: по таймауту утилита ping оставалась жить («осиротевшие» процессы)."""
    pidfile = tmp_path / "pid"
    fake_ping(f"echo $$ > {pidfile}\nexec sleep 30")
    ok, _, error = await make_engine_with_ping().subprocess_icmp_ping("example.com", timeout=0.2)
    assert not ok and "timeout" in error.lower()
    pid = int(pidfile.read_text())
    with pytest.raises(ProcessLookupError):
        os.kill(pid, 0)


async def test_subprocess_ping_without_binary():
    engine = AsyncPingEngine(PingMode.SUBPROCESS)
    engine._ping_binary = None
    ok, _, error = await engine.subprocess_icmp_ping("example.com")
    assert not ok and error


# ---- ICMP: контрольная сумма и разбор пакетов ------------------------------------------------------

def test_icmp_checksum_rfc1071_example():
    assert _icmp_checksum(bytes.fromhex("0001f203f4f5f6f7")) == 0x220D


def test_icmp_checksum_of_valid_packet_is_zero():
    header = struct.pack("!BBHHH", 8, 0, 0, 1, 1)
    payload = b"abc"                                       # нечётная длина: проверяем добивку нулём
    packet = struct.pack("!BBHHH", 8, 0, _icmp_checksum(header + payload), 1, 1) + payload
    assert _icmp_checksum(packet) == 0


def test_icmp_checksum_handles_carry_overflow():
    assert _icmp_checksum(b"\xff\xff" * 1000) == 0


def test_icmp_identifiers_are_unique():
    pairs = {_next_icmp_ident() for _ in range(2000)}
    assert len(pairs) == 2000


DEST = "198.51.100.5"
IDENT, SEQ = 0x1234, 7


def ip_header(src: str, ihl_words: int = 5) -> bytes:
    header = struct.pack("!BBHHHBBH4s4s", 0x40 | ihl_words, 0, 0, 0, 0, 64, 1, 0,
                         socket.inet_aton(src), socket.inet_aton("127.0.0.1"))
    return header + b"\x00" * ((ihl_words - 5) * 4)


def echo_reply(src: str, ident: int = IDENT, seq: int = SEQ, ihl_words: int = 5) -> tuple:
    data = ip_header(src, ihl_words) + struct.pack("!BBHHH", 0, 0, 0, ident, seq) + b"NetPulsePing"
    return data, (src, 0)


def dest_unreachable(src: str, ident: int = IDENT, seq: int = SEQ) -> tuple:
    inner = ip_header("127.0.0.1") + struct.pack("!BBHHH", 8, 0, 0, ident, seq)
    data = ip_header(src) + struct.pack("!BBHHH", 3, 1, 0, 0, 0) + inner
    return data, (src, 0)


class FakeRawSocket:
    def __init__(self, packets, fail_send=None):
        self.packets = list(packets)
        self.fail_send = fail_send
        self.sent = []
        self.closed = False

    def sendto(self, packet, addr):
        if self.fail_send:
            raise self.fail_send
        self.sent.append((packet, addr))

    def settimeout(self, _t):
        pass

    def recvfrom(self, _n):
        if not self.packets:
            raise socket.timeout()
        return self.packets.pop(0)

    def close(self):
        self.closed = True


class SocketShim:
    """Подмена модуля socket ТОЛЬКО внутри engine.ping (глобальный socket.socket трогать нельзя)."""

    def __init__(self, fake):
        self._fake = fake

    def socket(self, *_a, **_k):
        return self._fake

    def gethostbyname(self, _host):
        return DEST

    def __getattr__(self, name):
        return getattr(socket, name)


@pytest.fixture
def raw(monkeypatch):
    def run(packets, fail_send=None):
        fake = FakeRawSocket(packets, fail_send)
        monkeypatch.setattr(ping_module, "socket", SocketShim(fake))
        monkeypatch.setattr(ping_module, "_next_icmp_ident", lambda: (IDENT, SEQ))
        return _sync_raw_ping("dest.test", 0.5), fake
    return run


def test_raw_matching_reply_is_success(raw):
    (ok, latency, error), fake = raw([echo_reply(DEST)])
    assert ok and latency >= 0 and error is None
    assert fake.closed and fake.sent[0][1] == (DEST, 0)


def test_raw_reply_from_another_host_is_not_accepted(raw):
    """Регрессия: ответ ЖИВОГО хоста засчитывался «мёртвому» (проверялись только id и seq, не источник)."""
    (ok, _, error), _ = raw([echo_reply("203.0.113.9")])
    assert not ok and "timeout" in error.lower()


def test_raw_reply_with_wrong_identifier_or_sequence_is_ignored(raw):
    assert not raw([echo_reply(DEST, ident=IDENT + 1)])[0][0]
    assert not raw([echo_reply(DEST, seq=SEQ + 1)])[0][0]


def test_raw_foreign_packets_do_not_abort_the_wait(raw):
    (ok, _, _), _ = raw([echo_reply("203.0.113.9"), echo_reply(DEST, ident=1), echo_reply(DEST)])
    assert ok


def test_raw_reply_with_ip_options_is_parsed(raw):
    """Длина IP-заголовка берётся из IHL, а не равна 20 байтам."""
    (ok, _, _), _ = raw([echo_reply(DEST, ihl_words=6)])
    assert ok


def test_raw_destination_unreachable_for_our_packet_is_reported(raw):
    (ok, latency, error), _ = raw([dest_unreachable("192.0.2.1")])
    assert (ok, latency) == (False, None) and "type=3" in error


def test_raw_destination_unreachable_for_someone_else_is_ignored(raw):
    (ok, _, error), _ = raw([dest_unreachable("192.0.2.1", ident=IDENT + 5)])
    assert not ok and "timeout" in error.lower()


def test_raw_socket_closed_even_when_send_fails(raw):
    (ok, _, error), fake = raw([], fail_send=OSError("Network is unreachable"))
    assert not ok and "unreachable" in error and fake.closed


def test_raw_permission_error_has_clear_message(raw):
    (ok, _, error), fake = raw([], fail_send=PermissionError())
    assert not ok and "root" in error and fake.closed


# ---- ping_target / ping_stream ---------------------------------------------------------------------

async def test_gateway_placeholder_is_not_pinged():
    result = await AsyncPingEngine(PingMode.TCP).ping_target(HostTarget("Шлюз", GATEWAY_PLACEHOLDER, is_gateway=True))
    assert not result.is_success and result.protocol == "unknown"


async def test_ping_target_tcp_reports_port_in_protocol(tcp_server):
    result = await AsyncPingEngine(PingMode.TCP).ping_target(HostTarget("local", "127.0.0.1", tcp_port=tcp_server))
    assert result.is_success and result.protocol == f"tcp:{tcp_server}" and result.latency_ms > 0


async def test_auto_mode_falls_back_to_icmp(monkeypatch):
    engine = AsyncPingEngine(PingMode.AUTO)

    async def tcp_fail(*_a, **_k):
        return False, None, "refused by firewall"

    async def icmp_ok(*_a, **_k):
        return True, 5.0, None

    monkeypatch.setattr(engine, "tcp_ping", tcp_fail)
    monkeypatch.setattr(engine, "subprocess_icmp_ping", icmp_ok)
    result = await engine.ping_target(HostTarget("h", "192.0.2.1"))
    assert result.is_success and result.protocol == "icmp" and result.latency_ms == 5.0 and result.error_message is None


async def test_auto_mode_keeps_first_error_when_everything_fails(monkeypatch):
    engine = AsyncPingEngine(PingMode.AUTO)

    async def tcp_fail(*_a, **_k):
        return False, None, "Connection timed out"

    async def icmp_fail(*_a, **_k):
        return False, None, "Ping exit code 1"

    monkeypatch.setattr(engine, "tcp_ping", tcp_fail)
    monkeypatch.setattr(engine, "subprocess_icmp_ping", icmp_fail)
    result = await engine.ping_target(HostTarget("h", "192.0.2.1"))
    assert not result.is_success and result.error_message == "Connection timed out"


def test_inactive_targets_are_skipped():
    targets = [
        HostTarget("ok", "1.1.1.1"),
        HostTarget("placeholder", GATEWAY_PLACEHOLDER, is_gateway=True),
        HostTarget("off", "8.8.8.8", enabled=False),
        HostTarget("empty", ""),
    ]
    assert [t.name for t in AsyncPingEngine._active_targets(targets)] == ["ok"]


async def test_ping_stream_does_not_wait_for_the_slowest_host(monkeypatch):
    """Регрессия: gather ждал самый медленный узел — запись быстрых задерживалась до его таймаута."""
    engine = AsyncPingEngine(PingMode.TCP)

    async def fake(target):
        await asyncio.sleep(0.6 if target.name == "slow" else 0.0)
        return ping_module.PingResult(host=target.address, target_name=target.name,
                                      timestamp=ping_module.datetime.now(), is_success=True, latency_ms=1.0)

    monkeypatch.setattr(engine, "ping_target", fake)
    t0 = time.monotonic()
    arrivals = []
    async for res in engine.ping_stream([HostTarget("slow", "10.0.0.1"), HostTarget("fast", "10.0.0.2")]):
        arrivals.append((res.target_name, time.monotonic() - t0))
    assert [name for name, _ in arrivals] == ["fast", "slow"]
    assert arrivals[0][1] < 0.3


async def test_one_failing_check_does_not_break_the_cycle(monkeypatch):
    engine = AsyncPingEngine(PingMode.TCP)
    original = engine.ping_target

    async def flaky(target):
        if target.name == "bad":
            raise RuntimeError("boom")
        return await original(target)

    monkeypatch.setattr(engine, "ping_target", flaky)
    results = await engine.ping_all([HostTarget("bad", "127.0.0.1", tcp_port=free_closed_port()),
                                     HostTarget("good", "127.0.0.1", tcp_port=free_closed_port())])
    assert [r.target_name for r in results] == ["bad", "good"]            # порядок целей сохранён
    assert not results[0].is_success and "boom" in results[0].error_message
    assert results[1].is_success


async def test_cancelling_stream_cancels_pending_checks(monkeypatch):
    engine = AsyncPingEngine(PingMode.TCP)
    cancelled = []

    async def hang(target):
        try:
            await asyncio.sleep(30)
        except asyncio.CancelledError:
            cancelled.append(target.name)
            raise

    monkeypatch.setattr(engine, "ping_target", hang)
    stream = engine.ping_stream([HostTarget("a", "10.0.0.1"), HostTarget("b", "10.0.0.2")])
    task = asyncio.ensure_future(stream.__anext__())
    await asyncio.sleep(0.05)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    await stream.aclose()
    await asyncio.sleep(0.05)
    assert sorted(cancelled) == ["a", "b"]


# ---- настоящий raw-ICMP (только при наличии прав) --------------------------------------------------------

def test_real_raw_icmp_on_loopback():
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP)
        probe.close()
    except (PermissionError, OSError):
        pytest.skip("нет прав на raw-сокет")
    ok, latency, error = _sync_raw_ping("127.0.0.1", 2.0)
    assert ok and latency is not None and error is None
