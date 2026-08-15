"""
Модели данных для системы NetPulse.
"""
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import List, Optional


class AlertSeverity(str, Enum):
    INFO = "info"
    WARNING = "warning"
    CRITICAL = "critical"


@dataclass
class PingResult:
    """Результат единичной проверки хоста."""
    host: str
    target_name: str
    timestamp: datetime
    is_success: bool
    latency_ms: Optional[float] = None
    error_message: Optional[str] = None
    protocol: str = "tcp"  # icmp, tcp, subprocess


@dataclass
class HostStats:
    """Агрегированная статистика по целевому хосту."""
    name: str
    address: str
    is_gateway: bool = False
    
    # Счетчики
    sent_count: int = 0
    received_count: int = 0
    lost_count: int = 0
    
    # Метрики задержки (мс)
    last_latency_ms: Optional[float] = None
    min_latency_ms: Optional[float] = None
    max_latency_ms: Optional[float] = None
    avg_latency_ms: Optional[float] = None
    p95_latency_ms: Optional[float] = None
    p99_latency_ms: Optional[float] = None
    
    # Джиттер (RFC 3550)
    jitter_ms: float = 0.0
    
    # Потери пакетов
    loss_rate_pct: float = 0.0
    loss_window_pct: float = 0.0  # за последнее скользящее окно
    
    # Статус
    status: str = "UNKNOWN"  # OK, WARN, CRIT, DOWN
    last_updated: Optional[datetime] = None
    sparkline: str = ""


@dataclass
class NetworkAlert:
    """Сетевое оповещение/аномалия."""
    timestamp: datetime
    host: str
    target_name: str
    severity: AlertSeverity
    message: str
    metric_name: str
    current_value: float
    threshold_value: float


@dataclass
class SystemNetworkInfo:
    """Сведения о сетевых интерфейсах и конфигурации ОС."""
    local_ip: str = "127.0.0.1"
    gateway_ip: Optional[str] = None
    interface_name: str = "unknown"
    dns_servers: List[str] = field(default_factory=list)
    public_ip: Optional[str] = None
    isp_name: Optional[str] = None
    country: Optional[str] = None
    city: Optional[str] = None


@dataclass
class SpeedtestResult:
    """Результат замера скорости подключения."""
    timestamp: datetime
    download_mbps: float
    upload_mbps: float
    server_name: str = "Cloudflare CDN"
    duration_s: float = 0.0
    status: str = "SUCCESS"


@dataclass
class TracerouteHop:
    """Узел маршрута при трассировке."""
    hop_num: int
    ip_address: Optional[str]
    host_name: Optional[str]
    latency_ms: Optional[float]
    loss_pct: float = 0.0
