"""Диагностика сети: разбор таблиц маршрутов/DNS, отсутствие «выдуманных» значений."""
import io
import json
import urllib.request

import pytest

from engine.diagnostics import NetworkDiagnostics

parse_route = NetworkDiagnostics.parse_proc_net_route


# ---- Linux: /proc/net/route -------------------------------------------------------------------

PROC_ROUTE = """Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT
eth0\t00000000\t0101A8C0\t0003\t0\t0\t100\t00000000\t0\t0\t0
eth0\t0001A8C0\t00000000\t0001\t0\t0\t100\t00FFFFFF\t0\t0\t0
wlan0\t00000000\t0100000A\t0003\t0\t0\t600\t00000000\t0\t0\t0
"""


def test_proc_net_route_picks_lowest_metric_default_route():
    assert parse_route(PROC_ROUTE) == ("192.168.1.1", "eth0")


def test_proc_net_route_second_interface_when_first_is_absent():
    only_wlan = "\n".join(PROC_ROUTE.splitlines()[:1] + PROC_ROUTE.splitlines()[3:])
    assert parse_route(only_wlan) == ("10.0.0.1", "wlan0")


def test_proc_net_route_without_default_route():
    on_link_only = "\n".join(PROC_ROUTE.splitlines()[:1] + PROC_ROUTE.splitlines()[2:3])
    assert parse_route(on_link_only) == (None, None)


def test_proc_net_route_ignores_routes_without_gateway_flag_and_garbage():
    text = (
        "Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask\tMTU\tWindow\tIRTT\n"
        "eth0\t00000000\t0101A8C0\t0001\t0\t0\t100\t00000000\t0\t0\t0\n"      # нет RTF_GATEWAY
        "eth0\t00000000\t00000000\t0003\t0\t0\t100\t00000000\t0\t0\t0\n"      # шлюз 0.0.0.0
        "garbage line\n"
        "eth0\t00000000\tZZZZZZZZ\t0003\t0\t0\t100\t00000000\t0\t0\t0\n"      # не hex
    )
    assert parse_route(text) == (None, None)


def test_proc_net_route_empty_input():
    assert parse_route("") == (None, None)


# ---- macOS ------------------------------------------------------------------------------------

def test_macos_route_get_default():
    text = (
        "   route to: default\ndestination: default\n       mask: default\n"
        "    gateway: 192.168.0.1\n  interface: en0\n      flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>\n"
    )
    assert NetworkDiagnostics.parse_route_n_get_default(text) == ("192.168.0.1", "en0")


def test_macos_route_get_without_gateway():
    assert NetworkDiagnostics.parse_route_n_get_default("route: writing to routing socket: not in table") == (None, None)


# ---- Windows ----------------------------------------------------------------------------------

WIN_ROUTE = """IPv4 Route Table
===========================================================================
Active Routes:
Network Destination        Netmask          Gateway       Interface  Metric
          0.0.0.0          0.0.0.0      192.168.1.1    192.168.1.100     25
          0.0.0.0          0.0.0.0         10.0.0.1       10.0.0.50      5
          0.0.0.0          0.0.0.0         On-link       172.16.0.9      1
        127.0.0.0        255.0.0.0         On-link         127.0.0.1    331
==========================================================================="""


def test_windows_route_print_picks_lowest_metric_numeric_gateway():
    assert NetworkDiagnostics.parse_windows_route_print(WIN_ROUTE) == ("10.0.0.1", "10.0.0.50")


def test_windows_route_print_without_default():
    assert NetworkDiagnostics.parse_windows_route_print("Network Destination  Netmask\n") == (None, None)


# ---- DNS --------------------------------------------------------------------------------------

def test_resolv_conf_parsing():
    text = "# comment\nnameserver 192.168.1.1\nnameserver 192.168.1.1\nsearch lan\nnameserver 2001:4860:4860::8888\n  nameserver 1.1.1.1  \nnameserver\n"
    assert NetworkDiagnostics.parse_resolv_conf(text) == ["192.168.1.1", "2001:4860:4860::8888", "1.1.1.1"]


def test_resolv_conf_without_servers():
    assert NetworkDiagnostics.parse_resolv_conf("search lan\n") == []


# ---- сбор сведений: никаких «правдоподобных выдумок» ---------------------------------------------------

async def test_unknown_values_stay_unknown(monkeypatch):
    """Регрессия: при неудаче подставлялись шлюз 192.168.1.1 и DNS 1.1.1.1/8.8.8.8 — будто это реальные данные."""
    async def no_gateway():
        return None, None

    async def no_dns():
        return []

    async def no_public():
        return {}

    monkeypatch.setattr(NetworkDiagnostics, "get_gateway_and_interface", staticmethod(no_gateway))
    monkeypatch.setattr(NetworkDiagnostics, "get_dns_servers", staticmethod(no_dns))
    monkeypatch.setattr(NetworkDiagnostics, "fetch_public_info", classmethod(lambda cls: no_public()))
    info = await NetworkDiagnostics.collect_full_info()
    assert info.gateway_ip is None
    assert info.dns_servers == []
    assert info.interface_name == "unknown"
    assert info.public_ip == "Недоступен" and info.isp_name is None


async def test_collect_survives_failing_subtasks(monkeypatch):
    async def boom(*_a, **_k):
        raise RuntimeError("subsystem down")

    monkeypatch.setattr(NetworkDiagnostics, "get_gateway_and_interface", staticmethod(boom))
    monkeypatch.setattr(NetworkDiagnostics, "get_dns_servers", staticmethod(boom))
    monkeypatch.setattr(NetworkDiagnostics, "fetch_public_info", classmethod(lambda cls: boom()))
    info = await NetworkDiagnostics.collect_full_info()
    assert info.gateway_ip is None and info.dns_servers == []


async def test_collect_uses_detected_values(monkeypatch):
    async def gateway():
        return "192.168.50.1", "eth7"

    async def dns():
        return ["192.168.50.1"]

    async def public():
        return {"public_ip": "203.0.113.5", "isp": "ExampleNet", "country": "NL", "city": "Amsterdam"}

    monkeypatch.setattr(NetworkDiagnostics, "get_gateway_and_interface", staticmethod(gateway))
    monkeypatch.setattr(NetworkDiagnostics, "get_dns_servers", staticmethod(dns))
    monkeypatch.setattr(NetworkDiagnostics, "fetch_public_info", classmethod(lambda cls: public()))
    info = await NetworkDiagnostics.collect_full_info()
    assert (info.gateway_ip, info.interface_name, info.dns_servers) == ("192.168.50.1", "eth7", ["192.168.50.1"])
    assert (info.public_ip, info.isp_name, info.city) == ("203.0.113.5", "ExampleNet", "Amsterdam")


# ---- публичный IP: переход к следующему источнику -------------------------------------------------------

class FakeResponse(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


def fake_urlopen(responses):
    """responses: список (подстрока URL, тело | Exception)."""
    def opener(req, timeout=None):
        for needle, body in responses:
            if needle in req.full_url:
                if isinstance(body, Exception):
                    raise body
                return FakeResponse(body.encode() if isinstance(body, str) else body)
        raise OSError("no route")
    return opener


def test_public_info_skips_error_json_and_uses_next_source(monkeypatch):
    """Регрессия: ответ-ошибка первого сервиса (rate limit) прерывал поиск — IP не определялся вовсе."""
    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen([
        ("ipapi.co", json.dumps({"error": True, "reason": "RateLimited"})),
        ("cdn-cgi/trace", "fl=1\nip=203.0.113.9\nloc=DE\n"),
    ]))
    info = NetworkDiagnostics._fetch_sync_public_info()
    assert info["public_ip"] == "203.0.113.9" and info["country"] == "DE"


def test_public_info_when_nothing_is_reachable(monkeypatch):
    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen([]))
    assert NetworkDiagnostics._fetch_sync_public_info() == {
        "public_ip": None, "isp": None, "country": None, "city": None}


def test_public_info_from_primary_source(monkeypatch):
    body = json.dumps({"ip": "198.51.100.7", "org": "AS64500 Example", "country_name": "France", "city": "Paris"})
    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen([("ipapi.co", body)]))
    assert NetworkDiagnostics._fetch_sync_public_info() == {
        "public_ip": "198.51.100.7", "isp": "AS64500 Example", "country": "France", "city": "Paris"}


@pytest.mark.skipif(not hasattr(NetworkDiagnostics, "get_local_ip"), reason="n/a")
def test_local_ip_is_a_string():
    ip = NetworkDiagnostics.get_local_ip()
    assert isinstance(ip, str) and ip
