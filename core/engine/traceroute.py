"""
Асинхронный движок трассировки сетевого маршрута (Traceroute / MTR).
"""
import asyncio
import math
import platform
import re
import shutil
from contextlib import suppress
from typing import Callable, List, Optional
from metrics.models import TracerouteHop

# Номер хопа: 1–3 цифры, за которыми сразу ПРОБЕЛ. Строка вида «72.14.238.99  12.7 ms»
# (продолжение хопа при ECMP-балансировке) под правило не подпадает: после «72» идёт точка.
_HOP_RE = re.compile(r"^\s*(\d{1,3})(?=\s)")
_IP_RE = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
# «0.512 ms», «<1 ms», «12мс», «5,3 ms»
_LATENCY_RE = re.compile(r"<?\s*(\d+(?:[.,]\d+)?)\s*(?:ms|мс)", re.IGNORECASE)
_HOST_RE = re.compile(r"^[A-Za-z0-9._:\-\[\]%]+$")


class AsyncTracerouteEngine:
    """Движок трассировки пакетов для локализации сетевых узких мест."""

    def __init__(self, max_hops: int = 15, timeout_ms: int = 600, total_timeout: float = 90.0):
        self.max_hops = max_hops
        self.timeout_ms = timeout_ms
        self.total_timeout = total_timeout
        self.system = platform.system().lower()
        # Причина, по которой последняя трассировка не дала результата (None — всё в порядке)
        self.last_error: Optional[str] = None

    @property
    def binary_name(self) -> str:
        return "tracert" if self.system == "windows" else "traceroute"

    def is_available(self) -> bool:
        return shutil.which(self.binary_name) is not None

    def _build_command(self, target_host: str) -> List[str]:
        if self.system == "windows":
            return ["tracert", "-d", "-h", str(self.max_hops), "-w", str(self.timeout_ms), target_host]
        # -w в traceroute — целые секунды, минимум 1
        wait_s = max(1, math.ceil(self.timeout_ms / 1000))
        return ["traceroute", "-n", "-m", str(self.max_hops), "-w", str(wait_s), target_host]

    async def trace(
        self,
        target_host: str,
        on_hop_callback: Optional[Callable[[TracerouteHop], None]] = None
    ) -> List[TracerouteHop]:
        """
        Выполнение трассировки маршрута до указанного хоста.

        Результат — список хопов; если трассировка невозможна (нет утилиты, неверный хост,
        таймаут), список пуст/неполон, а причина записывается в `last_error`.
        """
        hops: List[TracerouteHop] = []
        self.last_error = None

        if not target_host or target_host.startswith("-") or not _HOST_RE.match(target_host):
            self.last_error = f"Недопустимый адрес для трассировки: {target_host!r}"
            return hops
        if not self.is_available():
            self.last_error = (
                f"Утилита {self.binary_name} не найдена. "
                + ("" if self.system == "windows" else "Установите пакет traceroute (apt install traceroute).")
            ).strip()
            return hops

        cmd = self._build_command(target_host)
        proc = None
        try:
            # stderr не читаем -> направляем в DEVNULL, иначе переполнение pipe могло бы заблокировать процесс
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )

            encoding = "oem" if self.system == "windows" else "utf-8"
            async with asyncio.timeout(self.total_timeout):
                while True:
                    line_bytes = await proc.stdout.readline()
                    if not line_bytes:
                        break
                    line = line_bytes.decode(encoding, errors="ignore").strip()
                    if not line:
                        continue

                    hop = self._parse_hop_line(line)
                    if hop:
                        hops.append(hop)
                        if on_hop_callback:
                            try:
                                on_hop_callback(hop)
                            except Exception:
                                pass
                await proc.wait()
        except TimeoutError:
            self.last_error = f"Трассировка прервана: превышено {self.total_timeout:.0f} с"
        except FileNotFoundError:
            self.last_error = f"Утилита {self.binary_name} не найдена"
        except Exception as e:
            self.last_error = f"Ошибка трассировки: {e}"
        finally:
            # Процесс не должен пережить трассировку (таймаут, отмена задачи, закрытие приложения)
            if proc is not None and proc.returncode is None:
                with suppress(ProcessLookupError):
                    proc.kill()
                with suppress(Exception):
                    await proc.wait()

        if not hops and self.last_error is None:
            self.last_error = "Утилита трассировки не вернула ни одного хопа (хост недоступен или ICMP фильтруется)"
        return hops

    def _parse_hop_line(self, line: str) -> Optional[TracerouteHop]:
        """Парсинг строки вывода traceroute / tracert."""
        # Windows: "  1    <1 ms    <1 ms    <1 ms  192.168.1.1"
        # Windows: "  2     *        *        *     Превышен интервал ожидания для запроса."
        # Linux: " 1  192.168.1.1  0.512 ms  0.480 ms  0.420 ms"

        match_hop_num = _HOP_RE.match(line)
        if not match_hop_num:
            return None

        hop_num = int(match_hop_num.group(1))
        rest = line[match_hop_num.end():]

        ip_match = _IP_RE.search(rest)
        ip_address = ip_match.group(0) if ip_match else None

        latencies = [float(v.replace(",", ".")) for v in _LATENCY_RE.findall(rest)]
        avg_latency = round(sum(latencies) / len(latencies), 1) if latencies else None

        # Потери на хопе: доля проб без ответа среди всех проб этой строки
        asterisks = rest.count("*")
        probes = len(latencies) + asterisks
        loss_pct = round((asterisks / probes) * 100.0, 1) if probes > 0 else 0.0

        return TracerouteHop(
            hop_num=hop_num,
            ip_address=ip_address or ("*" if asterisks > 0 and not latencies else "Unknown"),
            host_name=None,
            latency_ms=avg_latency,
            loss_pct=loss_pct,
        )
