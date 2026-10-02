"""
Настройки и параметры конфигурации системы NetPulse.
Использует стандартные датаклассы Python для максимальной автономности и скорости.
"""
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import List, Optional

# Адрес-заглушка локального шлюза: подставляется, пока шлюз не определён диагностикой.
# Пока заглушка не заменена реальным IP, цель НЕ опрашивается и в статистику не попадает.
GATEWAY_PLACEHOLDER = "gateway"


class PingMode(str, Enum):
    AUTO = "auto"
    TCP = "tcp"
    ICMP = "icmp"
    SUBPROCESS = "subprocess"


@dataclass
class HostTarget:
    name: str
    address: str
    tcp_port: Optional[int] = 443
    enabled: bool = True
    is_gateway: bool = False


@dataclass
class AlertThresholds:
    latency_warn_ms: float = 100.0   # Порог предупреждения по задержке (мс)
    latency_crit_ms: float = 180.0   # Критический порог по задержке (мс)
    jitter_warn_ms: float = 20.0     # Порог предупреждения по джиттеру (мс)
    jitter_crit_ms: float = 40.0     # Критический порог по джиттеру (мс)
    loss_warn_pct: float = 3.0       # Порог предупреждения по потерям пакетов (%)
    loss_crit_pct: float = 8.0       # Критический порог по потерям пакетов (%)
    down_after_failures: int = 3     # Сколько неудачных проверок ПОДРЯД считать недоступностью (DOWN)


@dataclass
class WebConfig:
    enabled: bool = False
    host: str = "127.0.0.1"
    port: int = 8080


@dataclass
class AppConfig:
    # Основные параметры пинга
    ping_interval: float = 1.0       # Интервал между проверками в секундах
    ping_timeout: float = 2.0        # Таймаут одного пинга в секундах
    ping_mode: PingMode = PingMode.AUTO  # Режим пинга (auto, tcp, icmp, subprocess)

    # Целевые хосты по умолчанию
    targets: List[HostTarget] = field(
        default_factory=lambda: [
            HostTarget(name="Локальный шлюз", address=GATEWAY_PLACEHOLDER, is_gateway=True),
            HostTarget(name="Cloudflare DNS", address="1.1.1.1", tcp_port=443),
            HostTarget(name="Google DNS", address="8.8.8.8", tcp_port=53),
            HostTarget(name="Yandex DNS", address="77.88.8.8", tcp_port=53),
            HostTarget(name="Quad9 DNS", address="9.9.9.9", tcp_port=53),
        ]
    )

    # Пороги алертов
    thresholds: AlertThresholds = field(default_factory=AlertThresholds)

    # Реакция на аномалии
    auto_traceroute_on_alert: bool = True   # Авто-запуск MTR при критическом сбое
    auto_traceroute_cooldown_s: float = 120.0  # Не чаще одной авто-трассировки на хост за этот интервал
    sound_alerts: bool = False             # Звуковое оповещение при сбоях
    alert_cooldown_s: float = 60.0         # Повтор алерта о ТОМ ЖЕ состоянии не чаще этого интервала

    # Буфер и хранилище
    history_window_size: int = 120          # Размер скользящего окна метрик для графиков
    status_window_size: int = 20            # Окно (последние N проверок) для статуса и алертов по потерям
    db_path: Path = Path("netpulse_history.db")  # Путь к файлу базы SQLite
    retention_days: int = 30                # Сколько дней хранить историю в SQLite (0 — не чистить)

    # Веб-интерфейс
    web: WebConfig = field(default_factory=WebConfig)


def load_config() -> AppConfig:
    """Загрузка конфигурации приложения по умолчанию."""
    return AppConfig()
