"""
Модуль сбора и агрегации сетевых метрик в реальном времени.
"""
from collections import deque
from datetime import datetime
from typing import Callable, Deque, Dict, List, Optional
from config.settings import AlertThresholds
from metrics.analyzer import MetricsAnalyzer
from metrics.models import HostStats, NetworkAlert, PingResult, SystemNetworkInfo


class MetricsCollector:
    """Агрегатор и диспетчер метрик реального времени."""

    def __init__(
        self,
        thresholds: AlertThresholds,
        window_size: int = 120,
        on_alert_callback: Optional[Callable[[NetworkAlert], None]] = None,
    ):
        self.thresholds = thresholds
        self.window_size = window_size
        self.on_alert_callback = on_alert_callback
        
        # Данные по хостам: address -> deque of PingResult
        self._history: Dict[str, Deque[PingResult]] = {}
        # Текущая агрегированная статистика по хостам: address -> HostStats
        self._stats: Dict[str, HostStats] = {}
        # Журнал последних алертов
        self._alerts_log: Deque[NetworkAlert] = deque(maxlen=100)
        # Системная информация
        self.system_info: SystemNetworkInfo = SystemNetworkInfo()
        # Предыдущее значение задержки для расчета RFC 3550 джиттера: address -> float
        self._prev_latencies: Dict[str, Optional[float]] = {}

    def register_host(self, name: str, address: str, is_gateway: bool = False) -> None:
        """Регистрация целевого хоста для мониторинга."""
        if address not in self._stats:
            self._stats[address] = HostStats(
                name=name,
                address=address,
                is_gateway=is_gateway,
                last_updated=datetime.now(),
            )
            self._history[address] = deque(maxlen=self.window_size)
            self._prev_latencies[address] = None

    def update_gateway_address(self, new_gateway_ip: str) -> None:
        """Обновление IP адреса шлюза при его динамическом определении."""
        if "gateway" in self._stats and new_gateway_ip:
            old_stats = self._stats.pop("gateway")
            old_history = self._history.pop("gateway", deque(maxlen=self.window_size))
            old_prev = self._prev_latencies.pop("gateway", None)
            
            old_stats.address = new_gateway_ip
            self._stats[new_gateway_ip] = old_stats
            self._history[new_gateway_ip] = old_history
            self._prev_latencies[new_gateway_ip] = old_prev

    def record_result(self, result: PingResult) -> HostStats:
        """Запись нового результата проверки хоста и пересчет агрегированной статистики."""
        address = result.host
        if address not in self._stats:
            self.register_host(result.target_name, address)

        history = self._history[address]
        history.append(result)
        stats = self._stats[address]

        # Обновление счетчиков
        stats.sent_count += 1
        stats.last_updated = result.timestamp

        if result.is_success and result.latency_ms is not None:
            stats.received_count += 1
            curr_lat = result.latency_ms
            stats.last_latency_ms = curr_lat
            
            # Расчет Jitter по RFC 3550
            prev_lat = self._prev_latencies.get(address)
            stats.jitter_ms = MetricsAnalyzer.calculate_rfc3550_jitter(
                prev_jitter=stats.jitter_ms,
                prev_latency=prev_lat,
                curr_latency=curr_lat,
            )
            self._prev_latencies[address] = curr_lat
        else:
            stats.lost_count += 1
            stats.last_latency_ms = None

        # Общий процент потерь
        if stats.sent_count > 0:
            stats.loss_rate_pct = round((stats.lost_count / stats.sent_count) * 100.0, 1)

        # Анализ метрик по скользящему окну истории
        window_results = list(history)
        window_lost = sum(1 for r in window_results if not r.is_success)
        stats.loss_window_pct = round((window_lost / len(window_results)) * 100.0, 1)

        success_latencies = [r.latency_ms for r in window_results if r.is_success and r.latency_ms is not None]
        if success_latencies:
            stats.min_latency_ms = round(min(success_latencies), 1)
            stats.max_latency_ms = round(max(success_latencies), 1)
            stats.avg_latency_ms = round(sum(success_latencies) / len(success_latencies), 1)
            p50, p95, p99 = MetricsAnalyzer.calculate_percentiles(success_latencies)
            stats.p95_latency_ms = p95
            stats.p99_latency_ms = p99
        else:
            stats.min_latency_ms = None
            stats.max_latency_ms = None
            stats.avg_latency_ms = None
            stats.p95_latency_ms = None
            stats.p99_latency_ms = None

        # Формирование Sparkline
        latencies_for_spark: Deque[Optional[float]] = deque(
            (r.latency_ms if r.is_success else None for r in history),
            maxlen=self.window_size
        )
        stats.sparkline = MetricsAnalyzer.generate_sparkline(latencies_for_spark, length=14)

        # Оценка здоровья хоста и генерация алертов
        new_status, alerts = MetricsAnalyzer.evaluate_health(stats, self.thresholds)
        stats.status = new_status

        for alert in alerts:
            self._alerts_log.append(alert)
            if self.on_alert_callback:
                try:
                    self.on_alert_callback(alert)
                except Exception:
                    pass

        return stats

    def get_all_stats(self) -> List[HostStats]:
        """Получить список статистики по всем целевым хостам."""
        return list(self._stats.values())

    def get_recent_alerts(self, limit: int = 10) -> List[NetworkAlert]:
        """Получить последние события и аномалии."""
        return list(self._alerts_log)[-limit:]

    def get_host_history(self, address: str) -> List[PingResult]:
        """Получить временной ряд измерений для заданного хоста."""
        return list(self._history.get(address, []))
