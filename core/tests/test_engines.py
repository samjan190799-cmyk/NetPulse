"""
Интеграционные тесты сетевых движков (Ping, Diagnostics, Traceroute parser).
"""
import asyncio
import unittest
from engine.diagnostics import NetworkDiagnostics
from engine.ping import AsyncPingEngine
from engine.traceroute import AsyncTracerouteEngine
from config.settings import HostTarget, PingMode


class TestNetworkEngines(unittest.TestCase):
    """Тестирование сетевых движков NetPulse."""

    def test_local_ip_detection(self):
        """Проверка определения локального IP-адреса."""
        ip = NetworkDiagnostics.get_local_ip()
        self.assertIsInstance(ip, str)
        self.assertNotEqual(ip, "")

    def test_ping_target_tcp(self):
        """Проверка асинхронного TCP пинга к надежному DNS-серверу Cloudflare."""
        async def _run():
            engine = AsyncPingEngine(mode=PingMode.TCP, timeout=2.0)
            target = HostTarget(name="Cloudflare", address="1.1.1.1", tcp_port=443)
            res = await engine.ping_target(target)
            return res

        res = asyncio.run(_run())
        self.assertEqual(res.host, "1.1.1.1")
        self.assertTrue(res.is_success)
        self.assertIsNotNone(res.latency_ms)
        self.assertGreater(res.latency_ms, 0.0)

    def test_traceroute_line_parser(self):
        """Проверка парсинга строк вывода утилиты tracert/traceroute."""
        engine = AsyncTracerouteEngine()
        
        # Строка Windows с успешными ответами
        win_line = "  1     1 ms     1 ms     1 ms  192.168.1.1"
        hop1 = engine._parse_hop_line(win_line)
        self.assertIsNotNone(hop1)
        self.assertEqual(hop1.hop_num, 1)
        self.assertEqual(hop1.ip_address, "192.168.1.1")
        self.assertEqual(hop1.latency_ms, 1.0)
        self.assertEqual(hop1.loss_pct, 0.0)

        # Строка Windows со звездочками (потерями)
        win_loss_line = "  2     *        *        *     Превышен интервал ожидания для запроса."
        hop2 = engine._parse_hop_line(win_loss_line)
        self.assertIsNotNone(hop2)
        self.assertEqual(hop2.hop_num, 2)
        self.assertEqual(hop2.loss_pct, 100.0)


if __name__ == "__main__":
    unittest.main()
