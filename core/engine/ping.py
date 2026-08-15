"""
Асинхронный движок пинга с поддержкой TCP Connect, Raw ICMP и Subprocess ICMP.
"""
import asyncio
import os
import platform
import re
import socket
import struct
import time
from datetime import datetime
from typing import List, Optional, Tuple

from config.settings import HostTarget, PingMode
from metrics.models import PingResult


class AsyncPingEngine:
    """Асинхронный многопротокольный движок проверки доступности хостов."""

    def __init__(self, mode: PingMode = PingMode.AUTO, timeout: float = 2.0):
        self.mode = mode
        self.timeout = timeout
        self.system = platform.system().lower()
        self._raw_socket_available = self._check_raw_socket_permission()

    def _check_raw_socket_permission(self) -> bool:
        """Проверка наличия прав для создания сырых ICMP сокетов."""
        if self.system == "windows":
            # На Windows сырые сокеты требуют прав Администратора
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP)
                s.close()
                return True
            except (PermissionError, OSError):
                return False
        else:
            return os.geteuid() == 0 if hasattr(os, "geteuid") else False

    async def tcp_ping(self, host: str, port: int = 443, timeout: Optional[float] = None) -> Tuple[bool, Optional[float], Optional[str]]:
        """
        Проверка доступности хоста через открытие TCP сокета.
        Работает без прав суперпользователя на любых ОС.
        """
        t_out = timeout or self.timeout
        start = time.perf_counter()
        try:
            # Асинхронное открытие TCP-соединения
            _, writer = await asyncio.wait_for(
                asyncio.open_connection(host, port),
                timeout=t_out
            )
            elapsed_ms = (time.perf_counter() - start) * 1000.0
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass
            return True, round(elapsed_ms, 2), None
        except asyncio.TimeoutError:
            return False, None, "Connection timed out"
        except ConnectionRefusedError:
            # Если порт закрыт, но хост ответил RST пакетом — хост ЖИВ! Задержка валидна!
            elapsed_ms = (time.perf_counter() - start) * 1000.0
            return True, round(elapsed_ms, 2), None
        except Exception as e:
            return False, None, str(e)

    async def subprocess_icmp_ping(self, host: str, timeout: Optional[float] = None) -> Tuple[bool, Optional[float], Optional[str]]:
        """
        ICMP пинг через вызов системной утилиты ping в неблокирующем подпроцессе.
        """
        t_out = timeout or self.timeout
        t_out_ms = int(t_out * 1000)

        if self.system == "windows":
            cmd = ["ping", "-n", "1", "-w", str(t_out_ms), host]
        else:
            cmd = ["ping", "-c", "1", "-W", str(int(t_out)), host]

        try:
            start = time.perf_counter()
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=t_out + 1.0)
            elapsed_total = (time.perf_counter() - start) * 1000.0

            if proc.returncode == 0:
                out_text = stdout.decode("cp866" if self.system == "windows" else "utf-8", errors="ignore")
                
                # Парсинг времени ответа из вывода ping
                # Windows: "время=12мс" или "time=12ms" или "время<1мс"
                # Linux: "time=12.3 ms"
                match = re.search(r"(?:time|время)[=<]([\d\.]+)\s*(?:ms|мс)?", out_text, re.IGNORECASE)
                if match:
                    latency = float(match.group(1))
                    return True, round(latency, 2), None
                return True, round(elapsed_total, 2), None
            else:
                return False, None, f"Ping exit code {proc.returncode}"
        except asyncio.TimeoutError:
            return False, None, "ICMP ping timeout"
        except Exception as e:
            return False, None, str(e)

    async def raw_icmp_ping(self, host: str, timeout: Optional[float] = None) -> Tuple[bool, Optional[float], Optional[str]]:
        """
        Низкоуровневый ICMP Echo пинг через сырой сокет (требует прав root / Admin).
        """
        if not self._raw_socket_available:
            return await self.subprocess_icmp_ping(host, timeout)

        t_out = timeout or self.timeout
        loop = asyncio.get_running_loop()

        def _sync_raw_ping() -> Tuple[bool, Optional[float], Optional[str]]:
            try:
                dest_ip = socket.gethostbyname(host)
                sock = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP)
                sock.settimeout(t_out)

                # Построение ICMP Echo Request пакета
                pid = os.getpid() & 0xFFFF
                seq = 1
                payload = b"NetPulsePingPayload1234567890"
                # Заголовок: Type(8)=8, Code=0, Checksum=0, ID, Sequence
                header = struct.pack("!BBHHH", 8, 0, 0, pid, seq)
                # Расчет контрольной суммы
                checksum = 0
                packet = header + payload
                if len(packet) % 2 == 1:
                    packet += b"\x00"
                for i in range(0, len(packet), 2):
                    w = (packet[i] << 8) + packet[i + 1]
                    checksum += w
                checksum = (checksum >> 16) + (checksum & 0xFFFF)
                checksum = ~checksum & 0xFFFF
                header = struct.pack("!BBHHH", 8, 0, checksum, pid, seq)
                full_packet = header + payload

                start = time.perf_counter()
                sock.sendto(full_packet, (dest_ip, 0))
                
                while True:
                    data, addr = sock.recvfrom(1024)
                    rtt = (time.perf_counter() - start) * 1000.0
                    # IP заголовок занимает минимум 20 байт
                    icmp_header = data[20:28]
                    ic_type, _, _, ic_id, ic_seq = struct.unpack("!BBHHH", icmp_header)
                    if ic_type == 0 and ic_id == pid:  # ICMP Echo Reply
                        sock.close()
                        return True, round(rtt, 2), None
            except socket.timeout:
                return False, None, "ICMP socket timeout"
            except Exception as ex:
                return False, None, str(ex)

        try:
            return await loop.run_in_executor(None, _sync_raw_ping)
        except Exception as e:
            return False, None, str(e)

    async def ping_target(self, target: HostTarget) -> PingResult:
        """
        Проверка одного хоста в соответствии с выбранным режимом и авто-фолбеком.
        """
        now = datetime.now()
        host = target.address

        if host == "gateway" or not host:
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

    async def ping_all(self, targets: List[HostTarget]) -> List[PingResult]:
        """Параллельный опрос всех зарегистрированных хостов."""
        active_targets = [t for t in targets if t.enabled]
        tasks = [self.ping_target(t) for t in active_targets]
        results = await asyncio.gather(*tasks, return_exceptions=False)
        return results
