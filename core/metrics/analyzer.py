"""
Модуль математического и статистического анализа сетевых параметров.
Реализует стандарт расчета джиттера RFC 3550 и перцентили задержки.
"""
import math
from typing import Deque, List, Optional, Tuple
from config.settings import AlertThresholds
from metrics.models import AlertSeverity, HostStats, NetworkAlert, PingResult


class MetricsAnalyzer:
    """Статистический анализатор метрик сетевого соединения."""

    # Символы для построения графиков sparkline в терминале
    SPARK_CHARS = [" ", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    @staticmethod
    def calculate_rfc3550_jitter(
        prev_jitter: float,
        prev_latency: Optional[float],
        curr_latency: float
    ) -> float:
        """
        Расчет межпакетного джиттера в соответствии с RFC 3550 (раздел 6.4.1).
        
        Формула:
            D(i-1, i) = |Transit(i) - Transit(i-1)|
            J(i) = J(i-1) + (|D(i-1, i)| - J(i-1)) / 16
        """
        if prev_latency is None:
            return 0.0
        
        transit_diff = abs(curr_latency - prev_latency)
        new_jitter = prev_jitter + (transit_diff - prev_jitter) / 16.0
        return max(0.0, round(new_jitter, 2))

    @staticmethod
    def calculate_percentiles(values: List[float]) -> Tuple[float, float, float]:
        """
        Расчет перцентилей P50 (медиана), P95 и P99.
        """
        if not values:
            return 0.0, 0.0, 0.0
        
        sorted_vals = sorted(values)
        n = len(sorted_vals)
        
        def get_p(p: float) -> float:
            k = (n - 1) * (p / 100.0)
            f = math.floor(k)
            c = math.ceil(k)
            if f == c:
                return sorted_vals[int(k)]
            d0 = sorted_vals[int(f)] * (c - k)
            d1 = sorted_vals[int(c)] * (k - f)
            return d0 + d1

        return (
            round(get_p(50), 2),
            round(get_p(95), 2),
            round(get_p(99), 2),
        )

    @classmethod
    def generate_sparkline(cls, history: Deque[Optional[float]], length: int = 15) -> str:
        """
        Генерация компактного графика Sparkline из последних значений задержки.
        Потери пакетов (None) отображаются специальным символом '·' или красным маркером.
        """
        if not history:
            return " " * length
        
        items = list(history)[-length:]
        # Дополняем пробелами слева, если значений меньше требуемой длины
        if len(items) < length:
            items = [None] * (length - len(items)) + items
        
        valid_nums = [v for v in items if v is not None]
        if not valid_nums:
            return "·" * length
        
        min_v = min(valid_nums)
        max_v = max(valid_nums)
        span = max_v - min_v if max_v != min_v else 1.0

        chars = []
        for val in items:
            if val is None:
                chars.append("✕")  # Потеря пакета
            else:
                norm = (val - min_v) / span
                idx = int(norm * (len(cls.SPARK_CHARS) - 1))
                idx = max(0, min(len(cls.SPARK_CHARS) - 1, idx))
                chars.append(cls.SPARK_CHARS[idx])
        
        return "".join(chars)

    @staticmethod
    def evaluate_health(
        stats: HostStats,
        thresholds: AlertThresholds
    ) -> Tuple[str, List[NetworkAlert]]:
        """
        Оценка состояния хоста и генерация предупреждений при выходе за пороговые значения.
        """
        alerts: List[NetworkAlert] = []
        now = stats.last_updated
        
        if stats.sent_count == 0:
            return "UNKNOWN", alerts

        # Проверка полной недоступности
        if stats.loss_window_pct >= 99.0 and stats.sent_count >= 3:
            status = "DOWN"
            if now:
                alerts.append(
                    NetworkAlert(
                        timestamp=now,
                        host=stats.address,
                        target_name=stats.name,
                        severity=AlertSeverity.CRITICAL,
                        message=f"Узел {stats.name} ({stats.address}) полностью недоступен!",
                        metric_name="packet_loss",
                        current_value=100.0,
                        threshold_value=thresholds.loss_crit_pct,
                    )
                )
            return status, alerts

        # Проверка потерь
        is_crit = False
        is_warn = False

        if stats.loss_window_pct >= thresholds.loss_crit_pct:
            is_crit = True
            if now:
                alerts.append(
                    NetworkAlert(
                        timestamp=now,
                        host=stats.address,
                        target_name=stats.name,
                        severity=AlertSeverity.CRITICAL,
                        message=f"Критические потери пакетов: {stats.loss_window_pct:.1f}% (порог {thresholds.loss_crit_pct}%)",
                        metric_name="packet_loss",
                        current_value=stats.loss_window_pct,
                        threshold_value=thresholds.loss_crit_pct,
                    )
                )
        elif stats.loss_window_pct >= thresholds.loss_warn_pct:
            is_warn = True
            if now:
                alerts.append(
                    NetworkAlert(
                        timestamp=now,
                        host=stats.address,
                        target_name=stats.name,
                        severity=AlertSeverity.WARNING,
                        message=f"Повышенные потери пакетов: {stats.loss_window_pct:.1f}% (порог {thresholds.loss_warn_pct}%)",
                        metric_name="packet_loss",
                        current_value=stats.loss_window_pct,
                        threshold_value=thresholds.loss_warn_pct,
                    )
                )

        # Проверка задержки RTT
        if stats.last_latency_ms is not None:
            if stats.last_latency_ms >= thresholds.latency_crit_ms:
                is_crit = True
                if now:
                    alerts.append(
                        NetworkAlert(
                            timestamp=now,
                            host=stats.address,
                            target_name=stats.name,
                            severity=AlertSeverity.CRITICAL,
                            message=f"Критический скачок задержки: {stats.last_latency_ms:.1f} мс (порог {thresholds.latency_crit_ms} мс)",
                            metric_name="latency",
                            current_value=stats.last_latency_ms,
                            threshold_value=thresholds.latency_crit_ms,
                        )
                    )
            elif stats.last_latency_ms >= thresholds.latency_warn_ms:
                is_warn = True
                if now:
                    alerts.append(
                        NetworkAlert(
                            timestamp=now,
                            host=stats.address,
                            target_name=stats.name,
                            severity=AlertSeverity.WARNING,
                            message=f"Повышенная задержка: {stats.last_latency_ms:.1f} мс (порог {thresholds.latency_warn_ms} мс)",
                            metric_name="latency",
                            current_value=stats.last_latency_ms,
                            threshold_value=thresholds.latency_warn_ms,
                        )
                    )

        # Проверка джиттера
        if stats.jitter_ms >= thresholds.jitter_crit_ms:
            is_crit = True
            if now:
                alerts.append(
                    NetworkAlert(
                        timestamp=now,
                        host=stats.address,
                        target_name=stats.name,
                        severity=AlertSeverity.CRITICAL,
                        message=f"Критический джиттер: {stats.jitter_ms:.1f} мс (порог {thresholds.jitter_crit_ms} мс)",
                        metric_name="jitter",
                        current_value=stats.jitter_ms,
                        threshold_value=thresholds.jitter_crit_ms,
                    )
                )
        elif stats.jitter_ms >= thresholds.jitter_warn_ms:
            is_warn = True
            if now:
                alerts.append(
                    NetworkAlert(
                        timestamp=now,
                        host=stats.address,
                        target_name=stats.name,
                        severity=AlertSeverity.WARNING,
                        message=f"Повышенный джиттер: {stats.jitter_ms:.1f} мс (порог {thresholds.jitter_warn_ms} мс)",
                        metric_name="jitter",
                        current_value=stats.jitter_ms,
                        threshold_value=thresholds.jitter_warn_ms,
                    )
                )

        if is_crit:
            return "CRIT", alerts
        if is_warn:
            return "WARN", alerts
        return "OK", alerts
