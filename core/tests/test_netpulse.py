"""
Модульные тесты для NetPulse (на базе стандартного unittest).
"""
import os
import shutil
import tempfile
import unittest
from collections import deque
from datetime import datetime
from pathlib import Path

from config.settings import AlertThresholds
from metrics.analyzer import MetricsAnalyzer
from metrics.collector import MetricsCollector
from metrics.models import PingResult, SystemNetworkInfo
from metrics.storage import StorageManager


class TestNetPulse(unittest.TestCase):
    """Набор тестов для алгоритмов и хранилища NetPulse."""

    def test_rfc3550_jitter_calculation(self):
        """Тестирование расчета джиттера по стандарту RFC 3550."""
        # Первый пакет: джиттер 0.0
        j0 = MetricsAnalyzer.calculate_rfc3550_jitter(
            prev_jitter=0.0,
            prev_latency=None,
            curr_latency=20.0
        )
        self.assertEqual(j0, 0.0)

        # Второй пакет с разницей 16 мс:
        # D = |36 - 20| = 16
        # J = 0 + (16 - 0)/16 = 1.0
        j1 = MetricsAnalyzer.calculate_rfc3550_jitter(
            prev_jitter=0.0,
            prev_latency=20.0,
            curr_latency=36.0
        )
        self.assertEqual(j1, 1.0)

        # Третий пакет с разницей 32 мс:
        # D = |68 - 36| = 32
        # J = 1.0 + (32 - 1.0)/16 = 1.0 + 31/16 = 1.0 + 1.9375 = 2.94
        j2 = MetricsAnalyzer.calculate_rfc3550_jitter(
            prev_jitter=j1,
            prev_latency=36.0,
            curr_latency=68.0
        )
        self.assertEqual(j2, 2.94)

    def test_percentile_calculation(self):
        """Тестирование расчета перцентилей задержки."""
        values = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 100.0]
        p50, p95, p99 = MetricsAnalyzer.calculate_percentiles(values)
        
        self.assertEqual(p50, 55.0)  # медиана
        self.assertGreater(p95, 90.0)
        self.assertGreater(p99, 95.0)

    def test_sparkline_generation(self):
        """Тестирование генерации sparkline-графиков."""
        history = deque([10.0, 20.0, 30.0, None, 50.0], maxlen=10)
        spark = MetricsAnalyzer.generate_sparkline(history, length=5)
        
        self.assertEqual(len(spark), 5)
        self.assertIn("✕", spark)  # маркер потери пакета

    def test_metrics_collector_aggregation(self):
        """Тестирование агрегации метрик в реальном времени."""
        thresholds = AlertThresholds(latency_warn_ms=100.0, latency_crit_ms=150.0)
        collector = MetricsCollector(thresholds=thresholds, window_size=10)
        collector.register_host("Google DNS", "8.8.8.8")

        # 1. Успешный пинг
        r1 = PingResult(
            host="8.8.8.8",
            target_name="Google DNS",
            timestamp=datetime.now(),
            is_success=True,
            latency_ms=15.0,
            protocol="tcp",
        )
        s1 = collector.record_result(r1)
        self.assertEqual(s1.sent_count, 1)
        self.assertEqual(s1.received_count, 1)
        self.assertEqual(s1.loss_rate_pct, 0.0)
        self.assertEqual(s1.last_latency_ms, 15.0)
        self.assertEqual(s1.status, "OK")

        # 2. Потеря пакета
        r2 = PingResult(
            host="8.8.8.8",
            target_name="Google DNS",
            timestamp=datetime.now(),
            is_success=False,
            latency_ms=None,
            protocol="tcp",
        )
        s2 = collector.record_result(r2)
        self.assertEqual(s2.sent_count, 2)
        self.assertEqual(s2.lost_count, 1)
        self.assertEqual(s2.loss_rate_pct, 50.0)

    def test_sqlite_storage_and_export(self):
        """Тестирование SQLite хранилища и экспорта отчетов в JSON и CSV."""
        temp_dir = Path(tempfile.mkdtemp())
        try:
            db_file = temp_dir / "test_netpulse.db"
            storage = StorageManager(db_path=db_file)
            
            # Регистрация сессии
            sys_info = SystemNetworkInfo(local_ip="192.168.1.50", gateway_ip="192.168.1.1", public_ip="1.2.3.4")
            storage.start_session(sys_info)

            # Запись пинга
            r = PingResult(
                host="1.1.1.1",
                target_name="Cloudflare DNS",
                timestamp=datetime.now(),
                is_success=True,
                latency_ms=12.4,
                protocol="tcp",
            )
            storage.record_ping(r)

            # Экспорт
            json_path = storage.export_json(temp_dir / "report.json")
            csv_path = storage.export_csv(temp_dir / "report.csv")

            self.assertTrue(json_path.exists())
            self.assertTrue(csv_path.exists())
            self.assertGreater(json_path.stat().st_size, 0)
            self.assertGreater(csv_path.stat().st_size, 0)
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
