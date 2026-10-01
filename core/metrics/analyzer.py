"""
Модуль математического и статистического анализа сетевых параметров.
Реализует стандарт расчета джиттера RFC 3550 и перцентили задержки.
"""
import math
from typing import List, Optional, Sequence, Tuple
from config.settings import AlertThresholds
from metrics.models import AlertSeverity, HostStats, NetworkAlert

# Минимум проверок в «недавнем» окне, чтобы оценивать потери в процентах:
# при 1–2 замерах один сбой дал бы «50–100 % потерь» и ложную тревогу.
MIN_SAMPLES_FOR_LOSS_PCT = 10


class MetricsAnalyzer:
    """Статистический анализатор метрик сетевого соединения."""

    # Символы для построения графиков sparkline в терминале (8 уровней; нижний — тоже видимый)
    SPARK_CHARS = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    LOSS_CHAR = "✕"   # потеря пакета
    PAD_CHAR = " "    # «ещё нет данных» (заполнитель слева)

    @staticmethod
    def calculate_rfc3550_jitter(
        prev_jitter: float,
        prev_latency: Optional[float],
        curr_latency: float,
        precise: bool = False,
    ) -> float:
        """
        Расчет межпакетного джиттера в соответствии с RFC 3550 (раздел 6.4.1).

        Формула:
            D(i-1, i) = |Transit(i) - Transit(i-1)|
            J(i) = J(i-1) + (|D(i-1, i)| - J(i-1)) / 16

        precise=False — результат округляется до 0.01 (для отображения).
        precise=True  — без округления: именно так нужно хранить СОСТОЯНИЕ фильтра,
        иначе округление «залипает» (джиттер не затухает ниже ~0.07 мс).
        """
        if prev_latency is None:
            return 0.0

        transit_diff = abs(curr_latency - prev_latency)
        new_jitter = max(0.0, prev_jitter + (transit_diff - prev_jitter) / 16.0)
        return new_jitter if precise else round(new_jitter, 2)

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
    def generate_sparkline(cls, history: Sequence[Optional[float]], length: int = 15) -> str:
        """
        Генерация компактного графика Sparkline из последних значений задержки.

        * потеря пакета (None) — «✕»;
        * недостающие слева позиции (данных пока меньше, чем length) — пробелы, а не «потери»;
        * плоский ряд (все значения равны) — средний уровень, а не невидимые пробелы.
        """
        items = list(history)[-length:] if history else []
        pad = " " * (length - len(items)) if len(items) < length else ""

        valid_nums = [v for v in items if v is not None]
        if not valid_nums:
            return pad + cls.LOSS_CHAR * len(items)

        min_v = min(valid_nums)
        max_v = max(valid_nums)
        span = max_v - min_v
        top = len(cls.SPARK_CHARS) - 1

        chars: List[str] = []
        for val in items:
            if val is None:
                chars.append(cls.LOSS_CHAR)
            elif span <= 0:
                chars.append(cls.SPARK_CHARS[top // 2])
            else:
                idx = int(round((val - min_v) / span * top))
                chars.append(cls.SPARK_CHARS[max(0, min(top, idx))])

        return pad + "".join(chars)

    @staticmethod
    def evaluate_health(
        stats: HostStats,
        thresholds: AlertThresholds
    ) -> Tuple[str, List[NetworkAlert]]:
        """
        Оценка состояния хоста и перечень условий, которые выполняются ПРЯМО СЕЙЧАС.

        Функция «без памяти»: она возвращает все актуальные условия на каждый замер.
        Подавление повторов (edge-trigger + cooldown) выполняет MetricsCollector.

        Статус DOWN — только если подряд неудачны N последних проверок; потери в процентах
        считаются по «недавнему» окну (последние ~20 проверок), а не по всей истории,
        иначе после обрыва статус залипал бы на минуты.
        """
        alerts: List[NetworkAlert] = []
        now = stats.last_updated

        if stats.sent_count == 0:
            return "UNKNOWN", alerts

        def add(severity: AlertSeverity, message: str, metric: str, value: float, threshold: float) -> None:
            if now:
                alerts.append(
                    NetworkAlert(
                        timestamp=now,
                        host=stats.address,
                        target_name=stats.name,
                        severity=severity,
                        message=message,
                        metric_name=metric,
                        current_value=value,
                        threshold_value=threshold,
                    )
                )

        # Полная недоступность: N проверок подряд неудачны
        down_after = max(1, int(thresholds.down_after_failures))
        if stats.consecutive_failures >= down_after:
            add(
                AlertSeverity.CRITICAL,
                f"Узел {stats.name} ({stats.address}) недоступен (неудачных проверок подряд: {stats.consecutive_failures})",
                "availability",
                float(stats.consecutive_failures),
                float(down_after),
            )
            return "DOWN", alerts

        is_crit = False
        is_warn = False

        # Потери пакетов — по недавнему окну и только при достаточном числе замеров
        if stats.recent_count >= MIN_SAMPLES_FOR_LOSS_PCT:
            if stats.loss_recent_pct >= thresholds.loss_crit_pct:
                is_crit = True
                add(
                    AlertSeverity.CRITICAL,
                    f"Критические потери пакетов: {stats.loss_recent_pct:.1f}% (порог {thresholds.loss_crit_pct}%)",
                    "packet_loss", stats.loss_recent_pct, thresholds.loss_crit_pct,
                )
            elif stats.loss_recent_pct >= thresholds.loss_warn_pct:
                is_warn = True
                add(
                    AlertSeverity.WARNING,
                    f"Повышенные потери пакетов: {stats.loss_recent_pct:.1f}% (порог {thresholds.loss_warn_pct}%)",
                    "packet_loss", stats.loss_recent_pct, thresholds.loss_warn_pct,
                )
        elif stats.consecutive_failures > 0:
            # Мало данных, но последний замер неудачен — не тревога, а предупреждение
            is_warn = True

        # Проверка задержки RTT
        if stats.last_latency_ms is not None:
            if stats.last_latency_ms >= thresholds.latency_crit_ms:
                is_crit = True
                add(
                    AlertSeverity.CRITICAL,
                    f"Критический скачок задержки: {stats.last_latency_ms:.1f} мс (порог {thresholds.latency_crit_ms} мс)",
                    "latency", stats.last_latency_ms, thresholds.latency_crit_ms,
                )
            elif stats.last_latency_ms >= thresholds.latency_warn_ms:
                is_warn = True
                add(
                    AlertSeverity.WARNING,
                    f"Повышенная задержка: {stats.last_latency_ms:.1f} мс (порог {thresholds.latency_warn_ms} мс)",
                    "latency", stats.last_latency_ms, thresholds.latency_warn_ms,
                )

        # Проверка джиттера
        if stats.jitter_ms >= thresholds.jitter_crit_ms:
            is_crit = True
            add(
                AlertSeverity.CRITICAL,
                f"Критический джиттер: {stats.jitter_ms:.1f} мс (порог {thresholds.jitter_crit_ms} мс)",
                "jitter", stats.jitter_ms, thresholds.jitter_crit_ms,
            )
        elif stats.jitter_ms >= thresholds.jitter_warn_ms:
            is_warn = True
            add(
                AlertSeverity.WARNING,
                f"Повышенный джиттер: {stats.jitter_ms:.1f} мс (порог {thresholds.jitter_warn_ms} мс)",
                "jitter", stats.jitter_ms, thresholds.jitter_warn_ms,
            )

        if is_crit:
            return "CRIT", alerts
        if is_warn:
            return "WARN", alerts
        return "OK", alerts
