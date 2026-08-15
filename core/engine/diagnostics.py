"""
Модуль сетевой диагностики: определение локального IP, шлюза, DNS-серверов и внешнего IP с ISP.
Поддерживает работу со стандартной библиотекой Python (urllib) и aiohttp.
"""
import asyncio
import json
import platform
import re
import socket
import urllib.request
from typing import List, Optional
from metrics.models import SystemNetworkInfo


class NetworkDiagnostics:
    """Анализатор сетевых параметров операционной системы и интернет-провайдера."""

    @staticmethod
    def get_local_ip() -> str:
        """Определение активного локального IP-адреса хоста."""
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            # Фиктивное подключение не отправляет трафик, но позволяет ОС выбрать нужный интерфейс
            s.connect(("1.1.1.1", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except Exception:
            return "127.0.0.1"

    @staticmethod
    async def get_default_gateway() -> Optional[str]:
        """Определение IP адреса основного шлюза (Default Gateway)."""
        sys_name = platform.system().lower()
        try:
            if sys_name == "windows":
                proc = await asyncio.create_subprocess_shell(
                    "route print 0.0.0.0",
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=3.0)
                out = stdout.decode("cp866", errors="ignore")
                
                # Ищем строку с сетевым назначением 0.0.0.0
                for line in out.splitlines():
                    line = line.strip()
                    if line.startswith("0.0.0.0"):
                        parts = line.split()
                        if len(parts) >= 3:
                            gw = parts[2]
                            if re.match(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$", gw):
                                return gw
            else:
                proc = await asyncio.create_subprocess_shell(
                    "ip route show default",
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=3.0)
                out = stdout.decode("utf-8", errors="ignore")
                match = re.search(r"default via ([\d\.]+)", out)
                if match:
                    return match.group(1)
        except Exception:
            pass
        return None

    @staticmethod
    async def get_dns_servers() -> List[str]:
        """Получение списка активных DNS-серверов."""
        dns_list: List[str] = []
        sys_name = platform.system().lower()
        try:
            if sys_name == "windows":
                proc = await asyncio.create_subprocess_shell(
                    "netsh interface ipv4 show dnsservers",
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=3.0)
                out = stdout.decode("cp866", errors="ignore")
                for match in re.finditer(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", out):
                    ip = match.group(0)
                    if ip not in dns_list and not ip.startswith("0.") and not ip.startswith("255."):
                        dns_list.append(ip)
            else:
                with open("/etc/resolv.conf", "r", encoding="utf-8") as f:
                    for line in f:
                        if line.startswith("nameserver"):
                            parts = line.split()
                            if len(parts) >= 2:
                                dns_list.append(parts[1])
        except Exception:
            pass
        
        return dns_list or ["Auto (DHCP)"]

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
                        return {
                            "public_ip": data.get("ip"),
                            "isp": data.get("org") or data.get("asn"),
                            "country": data.get("country_name"),
                            "city": data.get("city"),
                        }
                    elif mode == "trace":
                        ip_match = re.search(r"ip=([\d\.\:a-fA-F]+)", raw_data)
                        loc_match = re.search(r"loc=([A-Z]+)", raw_data)
                        return {
                            "public_ip": ip_match.group(1) if ip_match else None,
                            "isp": "Cloudflare Edge",
                            "country": loc_match.group(1) if loc_match else None,
                            "city": None,
                        }
                    elif mode == "ipify":
                        data = json.loads(raw_data)
                        return {
                            "public_ip": data.get("ip"),
                            "isp": "ISP Network",
                            "country": None,
                            "city": None,
                        }
            except Exception:
                continue

        return {"public_ip": "Недоступен", "isp": "Unknown", "country": "", "city": ""}

    @classmethod
    async def fetch_public_info(cls) -> dict:
        """Асинхронный запрос публичного IP адреса и информации о провайдере."""
        return await asyncio.to_thread(cls._fetch_sync_public_info)

    @classmethod
    async def collect_full_info(cls) -> SystemNetworkInfo:
        """Сбор всех сетевых параметров хоста."""
        local_ip = cls.get_local_ip()
        gateway_task = cls.get_default_gateway()
        dns_task = cls.get_dns_servers()
        public_task = cls.fetch_public_info()

        gateway, dns, public = await asyncio.gather(
            gateway_task,
            dns_task,
            public_task,
            return_exceptions=True
        )

        gw_ip = gateway if isinstance(gateway, str) else None
        dns_srv = dns if isinstance(dns, list) else ["1.1.1.1", "8.8.8.8"]
        pub_dict = public if isinstance(public, dict) else {}

        return SystemNetworkInfo(
            local_ip=local_ip,
            gateway_ip=gw_ip or "192.168.1.1",
            interface_name="Active Interface",
            dns_servers=dns_srv,
            public_ip=pub_dict.get("public_ip", "N/A"),
            isp_name=pub_dict.get("isp", "N/A"),
            country=pub_dict.get("country"),
            city=pub_dict.get("city"),
        )
