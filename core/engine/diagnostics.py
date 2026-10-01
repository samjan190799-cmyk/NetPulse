"""
Модуль сетевой диагностики: определение локального IP, шлюза, DNS-серверов и внешнего IP с ISP.
Работает на стандартной библиотеке Python (urllib + asyncio).

Принцип: если значение определить не удалось — возвращается None / пустой список, а не «правдоподобная
выдумка» (раньше при неудаче подставлялись шлюз 192.168.1.1 и DNS 1.1.1.1/8.8.8.8).
"""
import asyncio
import json
import platform
import re
import socket
import struct
import urllib.request
from contextlib import suppress
from pathlib import Path
from typing import List, Optional, Tuple
from metrics.models import SystemNetworkInfo

_IPV4_RE = re.compile(r"^\d{1,3}(?:\.\d{1,3}){3}$")


class NetworkDiagnostics:
    """Анализатор сетевых параметров операционной системы и интернет-провайдера."""

    @staticmethod
    def get_local_ip() -> str:
        """Определение активного локального IP-адреса хоста."""
        try:
            # Фиктивное подключение не отправляет трафик, но позволяет ОС выбрать нужный интерфейс
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.connect(("1.1.1.1", 80))
                return s.getsockname()[0]
        except Exception:
            return "127.0.0.1"

    # ---- запуск внешних утилит ------------------------------------------------

    @staticmethod
    async def _run(cmd: List[str], timeout: float = 3.0) -> str:
        """Запуск утилиты БЕЗ shell, с убийством процесса по таймауту. Пустая строка при любой ошибке."""
        proc = None
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
            encoding = "oem" if platform.system().lower() == "windows" else "utf-8"
            return stdout.decode(encoding, errors="ignore")
        except Exception:
            return ""
        finally:
            if proc is not None and proc.returncode is None:
                with suppress(ProcessLookupError):
                    proc.kill()
                with suppress(Exception):
                    await proc.wait()

    # ---- шлюз ---------------------------------------------------------------

    @staticmethod
    def parse_proc_net_route(text: str) -> Tuple[Optional[str], Optional[str]]:
        """Разбор /proc/net/route (Linux): (IP шлюза по умолчанию, интерфейс) с наименьшей метрикой."""
        best: Optional[Tuple[int, str, str]] = None
        for line in text.splitlines()[1:]:
            parts = line.split()
            if len(parts) < 8 or parts[1] != "00000000":
                continue
            try:
                if not int(parts[3], 16) & 0x2:      # RTF_GATEWAY
                    continue
                metric = int(parts[6])
                gw_ip = socket.inet_ntoa(struct.pack("<L", int(parts[2], 16)))
            except (ValueError, struct.error, OSError):
                continue
            if gw_ip == "0.0.0.0":
                continue
            if best is None or metric < best[0]:
                best = (metric, gw_ip, parts[0])
        return (best[1], best[2]) if best else (None, None)

    @staticmethod
    def parse_route_n_get_default(text: str) -> Tuple[Optional[str], Optional[str]]:
        """Разбор вывода `route -n get default` (macOS/BSD)."""
        gw = re.search(r"gateway:\s*(\d{1,3}(?:\.\d{1,3}){3})", text)
        iface = re.search(r"interface:\s*(\S+)", text)
        return (gw.group(1) if gw else None, iface.group(1) if iface else None)

    @staticmethod
    def parse_windows_route_print(text: str) -> Tuple[Optional[str], Optional[str]]:
        """Разбор `route print 0.0.0.0` (Windows): шлюз с наименьшей метрикой."""
        best: Optional[Tuple[int, str, Optional[str]]] = None
        for line in text.splitlines():
            parts = line.split()
            if len(parts) >= 5 and parts[0] == "0.0.0.0" and _IPV4_RE.match(parts[2]):
                try:
                    metric = int(parts[4])
                except ValueError:
                    metric = 9999
                iface_ip = parts[3] if _IPV4_RE.match(parts[3]) else None
                if best is None or metric < best[0]:
                    best = (metric, parts[2], iface_ip)
        return (best[1], best[2]) if best else (None, None)

    @staticmethod
    async def get_gateway_and_interface() -> Tuple[Optional[str], Optional[str]]:
        """IP основного шлюза и имя интерфейса. (None, None), если определить не удалось."""
        sys_name = platform.system().lower()
        try:
            if sys_name == "windows":
                out = await NetworkDiagnostics._run(["route", "print", "0.0.0.0"])
                return NetworkDiagnostics.parse_windows_route_print(out)

            if sys_name == "darwin":
                out = await NetworkDiagnostics._run(["route", "-n", "get", "default"])
                return NetworkDiagnostics.parse_route_n_get_default(out)

            # Linux: сначала /proc (не нужны никакие утилиты), затем `ip`
            proc_route = Path("/proc/net/route")
            if proc_route.exists():
                text = await asyncio.to_thread(proc_route.read_text, "utf-8", "ignore")
                gw, iface = NetworkDiagnostics.parse_proc_net_route(text)
                if gw:
                    return gw, iface
            out = await NetworkDiagnostics._run(["ip", "-4", "route", "show", "default"])
            match = re.search(r"default via (\d{1,3}(?:\.\d{1,3}){3})(?:.*?dev (\S+))?", out)
            if match:
                return match.group(1), match.group(2)
        except Exception:
            pass
        return None, None

    @staticmethod
    async def get_default_gateway() -> Optional[str]:
        """Определение IP адреса основного шлюза (Default Gateway)."""
        gw, _ = await NetworkDiagnostics.get_gateway_and_interface()
        return gw

    # ---- DNS ----------------------------------------------------------------

    @staticmethod
    def parse_resolv_conf(text: str) -> List[str]:
        servers: List[str] = []
        for line in text.splitlines():
            line = line.strip()
            if line.startswith("nameserver"):
                parts = line.split()
                if len(parts) >= 2 and parts[1] not in servers:
                    servers.append(parts[1])
        return servers

    @staticmethod
    async def get_dns_servers() -> List[str]:
        """Получение списка активных DNS-серверов. Пустой список, если определить не удалось."""
        sys_name = platform.system().lower()
        dns_list: List[str] = []
        try:
            if sys_name == "windows":
                out = await NetworkDiagnostics._run(["netsh", "interface", "ipv4", "show", "dnsservers"])
                for match in re.finditer(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", out):
                    ip = match.group(0)
                    if ip not in dns_list and not ip.startswith("0.") and not ip.startswith("255."):
                        dns_list.append(ip)
            elif sys_name == "darwin":
                out = await NetworkDiagnostics._run(["scutil", "--dns"])
                for match in re.finditer(r"nameserver\[\d+\]\s*:\s*(\S+)", out):
                    if match.group(1) not in dns_list:
                        dns_list.append(match.group(1))
            if not dns_list and sys_name != "windows":
                candidates = ["/etc/resolv.conf"]
                for path in candidates:
                    p = Path(path)
                    if p.exists():
                        servers = NetworkDiagnostics.parse_resolv_conf(
                            await asyncio.to_thread(p.read_text, "utf-8", "ignore"))
                        # systemd-resolved: в /etc/resolv.conf только заглушка 127.0.0.53 —
                        # настоящие серверы лежат в /run/systemd/resolve/resolv.conf
                        if servers and all(s.startswith("127.") for s in servers):
                            real = Path("/run/systemd/resolve/resolv.conf")
                            if real.exists():
                                real_servers = NetworkDiagnostics.parse_resolv_conf(
                                    await asyncio.to_thread(real.read_text, "utf-8", "ignore"))
                                if real_servers:
                                    servers = real_servers
                        dns_list = servers
        except Exception:
            pass
        return dns_list

    # ---- публичный IP -------------------------------------------------------

    @staticmethod
    def _fetch_sync_public_info() -> dict:
        """Синхронный запрос к IP эндпоинтам через urllib с таймаутом."""
        endpoints = [
            ("https://ipapi.co/json/", "json"),
            ("https://1.1.1.1/cdn-cgi/trace", "trace"),
            ("https://api.ipify.org?format=json", "ipify"),
        ]

        for url, mode in endpoints:
            try:
                req = urllib.request.Request(
                    url,
                    headers={"User-Agent": "NetPulse/1.0 (Network Quality Monitor)"}
                )
                with urllib.request.urlopen(req, timeout=3.0) as response:
                    raw_data = response.read().decode("utf-8", errors="ignore")

                if mode == "json":
                    data = json.loads(raw_data)
                    # Ответ-ошибка (rate limit и т.п.) без поля ip — пробуем следующий эндпоинт
                    if data.get("error") or not data.get("ip"):
                        continue
                    return {
                        "public_ip": data.get("ip"),
                        "isp": data.get("org") or data.get("asn"),
                        "country": data.get("country_name"),
                        "city": data.get("city"),
                    }
                elif mode == "trace":
                    ip_match = re.search(r"ip=([\d\.\:a-fA-F]+)", raw_data)
                    if not ip_match:
                        continue
                    loc_match = re.search(r"loc=([A-Z]+)", raw_data)
                    return {
                        "public_ip": ip_match.group(1),
                        "isp": "Cloudflare Edge",
                        "country": loc_match.group(1) if loc_match else None,
                        "city": None,
                    }
                elif mode == "ipify":
                    data = json.loads(raw_data)
                    if not data.get("ip"):
                        continue
                    return {
                        "public_ip": data.get("ip"),
                        "isp": None,
                        "country": None,
                        "city": None,
                    }
            except Exception:
                continue

        return {"public_ip": None, "isp": None, "country": None, "city": None}

    @classmethod
    async def fetch_public_info(cls) -> dict:
        """Асинхронный запрос публичного IP адреса и информации о провайдере."""
        return await asyncio.to_thread(cls._fetch_sync_public_info)

    @classmethod
    async def collect_full_info(cls) -> SystemNetworkInfo:
        """Сбор всех сетевых параметров хоста."""
        local_ip = cls.get_local_ip()

        gateway_res, dns, public = await asyncio.gather(
            cls.get_gateway_and_interface(),
            cls.get_dns_servers(),
            cls.fetch_public_info(),
            return_exceptions=True
        )

        gw_ip: Optional[str] = None
        iface: Optional[str] = None
        if isinstance(gateway_res, tuple):
            gw_ip, iface = gateway_res

        dns_srv = dns if isinstance(dns, list) else []
        pub_dict = public if isinstance(public, dict) else {}

        return SystemNetworkInfo(
            local_ip=local_ip,
            gateway_ip=gw_ip,                     # None, если не определён (никаких «192.168.1.1 по умолчанию»)
            interface_name=iface or "unknown",
            dns_servers=dns_srv,                  # [] , если не определены
            public_ip=pub_dict.get("public_ip") or "Недоступен",
            isp_name=pub_dict.get("isp"),
            country=pub_dict.get("country"),
            city=pub_dict.get("city"),
        )
