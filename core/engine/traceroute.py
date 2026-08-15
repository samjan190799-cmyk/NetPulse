"""
Асинхронный движок трассировки сетевого маршрута (Traceroute / MTR).
"""
import asyncio
import platform
import re
from typing import Callable, List, Optional
from metrics.models import TracerouteHop


class AsyncTracerouteEngine:
    """Движок трассировки пакетов для локализации сетевых узких мест."""

    def __init__(self, max_hops: int = 15, timeout_ms: int = 600):
        self.max_hops = max_hops
        self.timeout_ms = timeout_ms
        self.system = platform.system().lower()

    async def trace(
        self,
        target_host: str,
        on_hop_callback: Optional[Callable[[TracerouteHop], None]] = None
    ) -> List[TracerouteHop]:
        """
        Выполнение трассировки маршрута до указанного хоста.
        """
        hops: List[TracerouteHop] = []

        if self.system == "windows":
            cmd = ["tracert", "-d", "-h", str(self.max_hops), "-w", str(self.timeout_ms), target_host]
        else:
            cmd = ["traceroute", "-n", "-m", str(self.max_hops), "-w", str(max(1, int(self.timeout_ms / 1000))), target_host]

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )

            # Читаем построчно для оперативного информирования
            encoding = "cp866" if self.system == "windows" else "utf-8"
            
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
        except Exception:
            pass

        return hops

    def _parse_hop_line(self, line: str) -> Optional[TracerouteHop]:
        """Парсинг строки вывода traceroute / tracert."""
        # Windows: "  1    <1 ms    <1 ms    <1 ms  192.168.1.1"
        # Windows: "  2     *        *        *     Превышен интервал ожидания для запроса."
        # Linux: " 1  192.168.1.1  0.512 ms  0.480 ms  0.420 ms"

        # Проверяем, начинается ли строка с номера хопа
        match_hop_num = re.match(r"^\s*(\d+)\b", line)
        if not match_hop_num:
            return None

        hop_num = int(match_hop_num.group(1))

        # Поиск IP-адреса
        ip_match = re.search(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", line)
        ip_address = ip_match.group(0) if ip_match else None

        # Поиск времен ответа
        times = re.findall(r"(?:[<]?(\d+(?:\.\d+)?)\s*ms|\b(\d+(?:\.\d+)?)\s*мс)", line, re.IGNORECASE)
        latencies = []
        for t1, t2 in times:
            val = t1 or t2
            if val:
                latencies.append(float(val))

        avg_latency = round(sum(latencies) / len(latencies), 1) if latencies else None
        
        # Расчет процента потерь на хопе
        asterisks = line.count("*")
        loss_pct = round((asterisks / 3.0) * 100.0, 1) if asterisks > 0 else 0.0

        return TracerouteHop(
            hop_num=hop_num,
            ip_address=ip_address or ("*" if asterisks == 3 else "Unknown"),
            host_name=None,
            latency_ms=avg_latency,
            loss_pct=loss_pct,
        )
