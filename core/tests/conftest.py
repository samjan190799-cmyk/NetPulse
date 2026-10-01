"""Общие фикстуры. Все тесты герметичны: интернет не нужен (сеть — только loopback)."""
from datetime import datetime, timedelta
from typing import Callable, List

import pytest

from config.settings import AlertThresholds
from metrics.collector import MetricsCollector
from metrics.models import NetworkAlert, PingResult


@pytest.fixture
def make_result() -> Callable[..., PingResult]:
    """Фабрика PingResult с детерминированным временем: каждый следующий результат — на 1 секунду позже."""
    base = datetime(2026, 1, 1, 12, 0, 0)
    counter = {"n": 0}

    def _make(host: str = "10.0.0.1", ok: bool = True, latency: float = 10.0, name: str = "") -> PingResult:
        counter["n"] += 1
        return PingResult(
            host=host,
            target_name=name or host,
            timestamp=base + timedelta(seconds=counter["n"]),
            is_success=ok,
            latency_ms=latency if ok else None,
            protocol="tcp",
        )

    return _make


@pytest.fixture
def alerts() -> List[NetworkAlert]:
    return []


@pytest.fixture
def collector(alerts: List[NetworkAlert]) -> MetricsCollector:
    """Коллектор с одним узлом 10.0.0.1 и записью всех выпущенных алертов в `alerts`."""
    c = MetricsCollector(AlertThresholds(), on_alert_callback=alerts.append)
    c.register_host("host", "10.0.0.1")
    return c
