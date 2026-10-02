"""
Асинхронный движок пинга с поддержкой TCP Connect, Raw ICMP и Subprocess ICMP.
"""
import asyncio
import ipaddress
import itertools
import math
import os
import platform
import re
import shutil
import socket
import struct
import threading
import time
from contextlib import suppress
from datetime import datetime
from typing import AsyncIterator, Dict, List, Optional, Tuple

from config.settings import GATEWAY_PLACEHOLDER, HostTarget, PingMode
from metrics.models import PingResult

PingOutcome = Tuple[bool, Optional[float], Optional[str]]

# Счётчик для уникальных identifier/sequence ICMP-пакетов: raw-сокет получает ВСЕ ICMP-ответы
# хоста, поэтому ответы разных параллельных проверок нужно различать по (источник, id, seq).
_icmp_counter = itertools.count(1)
_icmp_lock = threading.Lock()

# «время=12мс», «time=12.3 ms», «Zeit=12ms», «temps=12 ms», «time<1ms» — достаточно «=/<» + число + ms/мс
_LATENCY_RE = re.compile(r"[=<]\s*(\d+(?:[.,]\d+)?)\s*(?:ms|мс)", re.IGNORECASE)
_HOST_RE = re.compile(r"^[A-Za-z0-9._:\-\[\]%]+$")


def _next_icmp_ident() -> Tuple[int, int]:
    with _icmp_lock:
        n = next(_icmp_counter)
    return (os.getpid() + n) & 0xFFFF, n & 0xFFFF


def _icmp_checksum(data: bytes) -> int:
    """Контрольная сумма Internet (RFC 1071) с полной свёрткой переноса."""
    if len(data) % 2:
        data += b"\x00"
    total = sum(struct.unpack("!%dH" % (len(data) // 2), data))
    while total >> 16:
        total = (total & 0xFFFF) + (total >> 16)
    return ~total & 0xFFFF


def _is_safe_host(host: str) -> bool:
    """Хост не должен начинаться с '-' (иначе он станет опцией утилиты ping) и содержать мусор."""
    return bool(host) and not host.startswith("-") and bool(_HOST_RE.match(host))


def _sync_raw_ping(host: str, timeout: float) -> PingOutcome:
    """
    Один ICMP Echo через raw-сокет (blocking; вызывается в пуле потоков).

    Ответ засчитывается ТОЛЬКО если он пришёл от адреса назначения и совпадают
    identifier и sequence нашего запроса; общий дедлайн не продлевается чужим ICMP-трафиком.
    """
    try:
        dest_ip = socket.gethostbyname(host)
    except OSError as ex:
        return False, None, f"DNS: {ex}"

    ident, seq = _next_icmp_ident()
    payload = b"NetPulsePing" + struct.pack("!d", time.time())
    header = struct.pack("!BBHHH", 8, 0, 0, ident, seq)
    checksum = _icmp_checksum(header + payload)
    packet = struct.pack("!BBHHH", 8, 0, checksum, ident, seq) + payload

    sock: Optional[socket.socket] = None
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP)
        deadline = time.monotonic() + timeout
        start = time.perf_counter()
        sock.sendto(packet, (dest_ip, 0))

        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return False, None, "ICMP socket timeout"
            sock.settimeout(remaining)
            try:
                data, addr = sock.recvfrom(1024)
            except socket.timeout:
                return False, None, "ICMP socket timeout"
            rtt = (time.perf_counter() - start) * 1000.0

            if len(data) < 20:
                continue
            ihl = (data[0] & 0x0F) * 4          # длина IP-заголовка (может быть > 20 при опциях)
            if len(data) < ihl + 8:
                continue
            ic_type, ic_code, _, ic_id, ic_seq = struct.unpack("!BBHHH", data[ihl:ihl + 8])

            if ic_type == 0 and ic_id == ident and ic_seq == seq and addr[0] == dest_ip:
                return True, round(rtt, 2), None

            if ic_type in (3, 11):
                # ICMP-ошибка: во вложении — IP-заголовок и 8 байт нашего исходного пакета
                inner = data[ihl + 8:]
                if len(inner) >= 28:
                    inner_ihl = (inner[0] & 0x0F) * 4
                    if len(inner) >= inner_ihl + 8:
                        _, _, _, in_id, in_seq = struct.unpack("!BBHHH", inner[inner_ihl:inner_ihl + 8])
                        if in_id == ident and in_seq == seq:
                            return False, None, f"ICMP ошибка: type={ic_type} code={ic_code} от {addr[0]}"
    except PermissionError:
        return False, None, "Нет прав на raw-сокет (нужен root / CAP_NET_RAW)"
    except OSError as ex:
        return False, None, str(ex)
    finally:
        if sock is not None:
            sock.close()


class AsyncPingEngine:
    """Асинхронный многопротокольный движок проверки доступности хостов."""

    DNS_CACHE_TTL = 300.0  # секунд

    def __init__(self, mode: PingMode = PingMode.AUTO, timeout: float = 2.0):
        self.mode = mode
        self.timeout = timeout
        self.system = platform.system().lower()
        self._raw_socket_available = self._check_raw_socket_permission()
        self._ping_binary = shutil.which("ping")
        self._dns_cache: Dict[str, Tuple[str, float]] = {}

    def _check_raw_socket_permission(self) -> bool:
        """Проверка наличия прав для создания сырых ICMP сокетов (root / Admin / CAP_NET_RAW)."""
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP)
            s.close()
            return True
        except (PermissionError, OSError):
            return False

    async def _resolve_ip(self, host: str, port: int, timeout: float) -> str:
        """
        Разрешение имени ОТДЕЛЬНО от замера: иначе в «RTT» входило бы время DNS-запроса,
        а каждый всплеск DNS выглядел бы как скачок задержки до узла.
        """
        try:
            ipaddress.ip_address(host)
            return host
        except ValueError:
            pass

        now = time.monotonic()
        cached = self._dns_cache.get(host)
        if cached and cached[1] > now:
            return cached[0]

        loop = asyncio.get_running_loop()
        infos = await asyncio.wait_for(
            loop.getaddrinfo(host, port, type=socket.SOCK_STREAM), timeout=timeout
        )
        ip = infos[0][4][0]
        self._dns_cache[host] = (ip, now + self.DNS_CACHE_TTL)
        return ip

    async def tcp_ping(self, host: str, port: int = 443, timeout: Optional[float] = None) -> PingOutcome:
        """
        Проверка доступности хоста через открытие TCP сокета.
        Работает без прав суперпользователя на любых ОС. Время DNS в замер не входит.
        """
        t_out = self.timeout if timeout is None else timeout
        try:
            ip = await self._resolve_ip(host, port, t_out)
        except asyncio.TimeoutError:
            return False, None, "DNS timeout"
        except (OSError, ValueError) as e:
            return False, None, f"DNS: {e}"

        start = time.perf_counter()
        try:
            _, writer = await asyncio.wait_for(asyncio.open_connection(ip, port), timeout=t_out)
            elapsed_ms = (time.perf_counter() - start) * 1000.0
            writer.close()
            with suppress(Exception):
                await writer.wait_closed()
            return True, round(elapsed_ms, 2), None
        except asyncio.TimeoutError:
            self._dns_cache.pop(host, None)  # адрес мог смениться — в следующий раз разрешим заново
            return False, None, "Connection timed out"
        except ConnectionRefusedError:
            # Порт закрыт, но хост ответил RST — хост ЖИВ, задержка валидна.
            elapsed_ms = (time.perf_counter() - start) * 1000.0
            return True, round(elapsed_ms, 2), None
        except OSError as e:
            self._dns_cache.pop(host, None)
            return False, None, str(e)

    def _ping_command(self, host: str, t_out: float) -> List[str]:
        if self.system == "windows":
            return ["ping", "-n", "1", "-w", str(max(1, int(t_out * 1000))), host]
        if self.system == "darwin":
            # BSD/macOS: -W задаётся в МИЛЛИСЕКУНДАХ (в Linux — в секундах)
            return ["ping", "-c", "1", "-W", str(max(1, int(t_out * 1000))), "--", host]
        # Linux: целые секунды, минимум 1 (int(0.5) == 0 означало бы «не ждать»)
        return ["ping", "-c", "1", "-W", str(max(1, math.ceil(t_out))), "--", host]

    async def subprocess_icmp_ping(self, host: str, timeout: Optional[float] = None) -> PingOutcome:
        """
        ICMP пинг через вызов системной утилиты ping в неблокирующем подпроцессе.
        """
        t_out = self.timeout if timeout is None else timeout
        if not self._ping_binary:
            return False, None, "Утилита ping не найдена в системе"
        if not _is_safe_host(host):
            return False, None, "Некорректное имя хоста"

        cmd = self._ping_command(host, t_out)
        proc = None
        try:
            start = time.perf_counter()
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )
            try:
                stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=t_out + 1.0)
            except asyncio.TimeoutError:
                return False, None, "ICMP ping timeout"
            elapsed_total = (time.perf_counter() - start) * 1000.0

            if proc.returncode == 0:
                encoding = "oem" if self.system == "windows" else "utf-8"
                out_text = stdout.decode(encoding, errors="ignore")
                match = _LATENCY_RE.search(out_text)
                if match:
                    latency = float(match.group(1).replace(",", "."))
                    return True, round(latency, 2), None
                return True, round(elapsed_total, 2), None
            return False, None, f"Ping exit code {proc.returncode}"
        except FileNotFoundError:
            return False, None, "Утилита ping не найдена в системе"
        except Exception as e:
            return False, None, str(e)
        finally:
            # Не оставляем «осиротевших» процессов ping (таймаут, отмена задачи)
            if proc is not None and proc.returncode is None:
                with suppress(ProcessLookupError):
                    proc.kill()
                with suppress(Exception):
                    await proc.wait()

    async def raw_icmp_ping(self, host: str, timeout: Optional[float] = None) -> PingOutcome:
        """
        Низкоуровневый ICMP Echo пинг через сырой сокет (требует прав root / Admin).
        """
        if not self._raw_socket_available:
            return await self.subprocess_icmp_ping(host, timeout)

        t_out = self.timeout if timeout is None else timeout
        loop = asyncio.get_running_loop()
        try:
            return await loop.run_in_executor(None, _sync_raw_ping, host, t_out)
        except Exception as e:
            return False, None, str(e)

    async def ping_target(self, target: HostTarget) -> PingResult:
        """
        Проверка одного хоста в соответствии с выбранным режимом и авто-фолбеком.
        """
        now = datetime.now()
        host = target.address

        if host == GATEWAY_PLACEHOLDER or not host:
            return PingResult(
                host=host,
                target_name=target.name,
                timestamp=now,
                is_success=False,
                error_message="Шлюз пока не определен",
                protocol="unknown",
            )

        success = False
        latency = None
        error = None
        used_protocol = "tcp"

        if self.mode == PingMode.TCP:
            port = target.tcp_port or 443
            success, latency, error = await self.tcp_ping(host, port)
            used_protocol = f"tcp:{port}"
        elif self.mode == PingMode.ICMP:
            success, latency, error = await self.raw_icmp_ping(host)
            used_protocol = "icmp"
        elif self.mode == PingMode.SUBPROCESS:
            success, latency, error = await self.subprocess_icmp_ping(host)
            used_protocol = "icmp-subproc"
        else:  # AUTO mode: TCP ping first (fastest/non-privileged), fallback to subprocess ping
            port = target.tcp_port or 443
            success, latency, error = await self.tcp_ping(host, port)
            used_protocol = f"tcp:{port}"

            # Если TCP не прошел (например, узел закрыл порты 443/53), пробуем ICMP
            if not success:
                ic_ok, ic_lat, ic_err = await self.subprocess_icmp_ping(host)
                if ic_ok:
                    success = True
                    latency = ic_lat
                    error = None
                    used_protocol = "icmp"
                elif error is None:
                    error = ic_err

        return PingResult(
            host=host,
            target_name=target.name,
            timestamp=now,
            is_success=success,
            latency_ms=latency,
            error_message=error,
            protocol=used_protocol,
        )

    async def _safe_ping_target(self, target: HostTarget) -> PingResult:
        """Проверка, которая никогда не бросает исключение (сбой одного хоста не должен ронять цикл)."""
        try:
            return await self.ping_target(target)
        except asyncio.CancelledError:
            raise
        except Exception as e:
            return PingResult(
                host=target.address,
                target_name=target.name,
                timestamp=datetime.now(),
                is_success=False,
                error_message=str(e),
                protocol="error",
            )

    @staticmethod
    def _active_targets(targets: List[HostTarget]) -> List[HostTarget]:
        # Заглушку шлюза не опрашиваем: пока адрес не определён, проверять нечего
        return [t for t in targets if t.enabled and t.address and t.address != GATEWAY_PLACEHOLDER]

    async def ping_stream(self, targets: List[HostTarget]) -> AsyncIterator[PingResult]:
        """
        Параллельный опрос; результаты отдаются по мере готовности.
        Быстрые хосты не ждут самый медленный (раньше один «мёртвый» узел задерживал запись всех).
        """
        tasks = [asyncio.ensure_future(self._safe_ping_target(t)) for t in self._active_targets(targets)]
        try:
            for fut in asyncio.as_completed(tasks):
                yield await fut
        finally:
            for t in tasks:
                if not t.done():
                    t.cancel()

    async def ping_all(self, targets: List[HostTarget]) -> List[PingResult]:
        """Параллельный опрос всех зарегистрированных хостов (результаты в порядке целей)."""
        active_targets = self._active_targets(targets)
        return list(await asyncio.gather(*(self._safe_ping_target(t) for t in active_targets)))
