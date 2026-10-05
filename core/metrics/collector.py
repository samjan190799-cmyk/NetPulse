"""
Модуль сбора и агрегации сетевых метрик в реальном времени.
"""
from collections import deque
from datetime import datetime
from typing import Callable, Deque, Dict, List, Optional, Tuple
from config.settings import GATEWAY_PLACEHOLDER, AlertThresholds
from metrics.analyzer import MetricsAnalyzer
from metrics.models import AlertSeverity, HostStats, NetworkAlert, PingResult, SystemNetworkInfo

_SEVERITY_RANK = {AlertSeverity.INFO: 0, AlertSeverity.WARNING: 1, AlertSeverity.CRITICAL: 2}


class MetricsCollector:
    """Агрегатор и диспетчер метрик реального времени."""

    def __init__(
        self,
        thresholds: AlertThresholds,
        window_size: int = 120,
        on_alert_callback: Optional[Callable[[NetworkAlert], None]] = None,
        alert_cooldown_s: float = 60.0,
        status_window: int = 20,
    ):
        self.thresholds = thresholds
        self.window_size = window_size
        self.on_alert_callback = on_alert_callback
        self.alert_cooldown_s = alert_cooldown_s
        self.status_window = max(1, status_window)

        # Данные по хостам: address -> deque of PingResult
        self._history: Dict[str, Deque[PingResult]] = {}
        # Текущая агрегированная статистика по хостам: address -> HostStats
        self._stats: Dict[str, HostStats] = {}
        # Журнал последних алертов (только реально выпущенные, без повторов)
        self._alerts_log: Deque[NetworkAlert] = deque(maxlen=100)
        # Системная информация
        self.system_info: SystemNetworkInfo = SystemNetworkInfo()
        # Предыдущее значение задержки для расчета RFC 3550 джиттера: address -> float
        self._prev_latencies: Dict[str, Optional[float]] = {}
        # Состояние фильтра джиттера БЕЗ округления: address -> float
        self._jitter_state: Dict[str, float] = {}
        # Подавление повторов: (address, metric) -> (severity, время последнего выпуска)
        self._alert_state: Dict[Tuple[str, str], Tuple[AlertSeverity, datetime]] = {}
        # Хосты, которые уже были неисправны, — чтобы выпустить «восстановлен»
        self._was_unhealthy: Dict[str, bool] = {}
        # «Эпизод сбоя»: от перехода в DOWN до возврата в OK. Пока он идёт, потери пакетов
        # (следствие того же сбоя) отдельно не объявляются, а состояние подавления не сбрасывается.
        self._outage_episode: Dict[str, bool] = {}
        # Псевдонимы адресов: «gateway» -> реальный IP шлюза
        self._aliases: Dict[str, str] = {}
        self._gateway_address: Optional[str] = None

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
            self._jitter_state[address] = 0.0

    def _drop_host_state(self, address: str) -> None:
        for key in [k for k in self._alert_state if k[0] == address]:
            del self._alert_state[key]
        self._was_unhealthy.pop(address, None)
        self._outage_episode.pop(address, None)

    def update_gateway_address(self, new_gateway_ip: str) -> None:
        """
        Подстановка реального IP шлюза вместо заглушки (и перенос при смене сети).

        * Заглушка не опрашивалась, поэтому её «чистая» запись просто переименовывается.
        * Запоздавшие результаты со старым адресом «gateway» перенаправляются через псевдоним —
          «призрачная» строка не создаётся.
        * Если шлюз уже был определён и сменился (другая сеть) — прежняя статистика к новому
          шлюзу не относится: строка начинается с нуля.
        """
        if not new_gateway_ip or new_gateway_ip == GATEWAY_PLACEHOLDER:
            return

        current = self._gateway_address
        self._aliases[GATEWAY_PLACEHOLDER] = new_gateway_ip
        if current == new_gateway_ip:
            return
        self._gateway_address = new_gateway_ip

        if GATEWAY_PLACEHOLDER in self._stats:
            source_key: Optional[str] = GATEWAY_PLACEHOLDER
        elif current is not None and current in self._stats:
            source_key = current
        else:
            return

        old_stats = self._stats.pop(source_key)
        old_history = self._history.pop(source_key, deque(maxlen=self.window_size))
        old_prev = self._prev_latencies.pop(source_key, None)
        old_jitter = self._jitter_state.pop(source_key, 0.0)
        self._drop_host_state(source_key)

        if new_gateway_ip in self._stats:
            # Адрес шлюза совпал с уже отслеживаемым хостом — не затираем его статистику,
            # а помечаем существующий как шлюз (дубль строки удаляется).
            self._stats[new_gateway_ip].is_gateway = True
            return

        if source_key == GATEWAY_PLACEHOLDER:
            old_stats.address = new_gateway_ip
            self._stats[new_gateway_ip] = old_stats
            self._history[new_gateway_ip] = old_history
            self._prev_latencies[new_gateway_ip] = old_prev
            self._jitter_state[new_gateway_ip] = old_jitter
        else:
            self._stats[new_gateway_ip] = HostStats(
                name=old_stats.name,
                address=new_gateway_ip,
                is_gateway=True,
                last_updated=datetime.now(),
            )
            self._history[new_gateway_ip] = deque(maxlen=self.window_size)
            self._prev_latencies[new_gateway_ip] = None
            self._jitter_state[new_gateway_ip] = 0.0

    def record_result(self, result: PingResult) -> Optional[HostStats]:
        """
        Запись нового результата проверки хоста и пересчет агрегированной статистики.

        Результаты для неразрешённой заглушки шлюза игнорируются: это не измерения, а
        «нечего опрашивать» (иначе шлюз получил бы 100 % потерь и CRITICAL-алерт до
        завершения диагностики).
        """
        address = self._aliases.get(result.host, result.host)
        if address == GATEWAY_PLACEHOLDER:
            return self._stats.get(address)

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
            stats.consecutive_failures = 0
            curr_lat = result.latency_ms
            stats.last_latency_ms = curr_lat

            # Расчет Jitter по RFC 3550: состояние хранится без округления
            prev_lat = self._prev_latencies.get(address)
            state = MetricsAnalyzer.calculate_rfc3550_jitter(
                prev_jitter=self._jitter_state.get(address, 0.0),
                prev_latency=prev_lat,
                curr_latency=curr_lat,
                precise=True,
            )
            self._jitter_state[address] = state
            stats.jitter_ms = round(state, 2)
            self._prev_latencies[address] = curr_lat
        else:
            stats.lost_count += 1
            stats.consecutive_failures += 1
            stats.last_latency_ms = None

        # Общий процент потерь
        if stats.sent_count > 0:
            stats.loss_rate_pct = round((stats.lost_count / stats.sent_count) * 100.0, 1)

        # Потери по скользящему окну истории (для отображения) и по «недавнему» (для статуса)
        window_results = list(history)
        window_lost = sum(1 for r in window_results if not r.is_success)
        stats.loss_window_pct = round((window_lost / len(window_results)) * 100.0, 1)

        recent = window_results[-self.status_window:]
        stats.recent_count = len(recent)
        recent_lost = sum(1 for r in recent if not r.is_success)
        stats.loss_recent_pct = round((recent_lost / len(recent)) * 100.0, 1)

        success_latencies = [r.latency_ms for r in window_results if r.is_success and r.latency_ms is not None]
        if success_latencies:
            stats.min_latency_ms = round(min(success_latencies), 1)
            stats.max_latency_ms = round(max(success_latencies), 1)
            stats.avg_latency_ms = round(sum(success_latencies) / len(success_latencies), 1)
            p50, p95, p99 = MetricsAnalyzer.calculate_percentiles(success_latencies)
            stats.p50_latency_ms = p50
            stats.p95_latency_ms = p95
            stats.p99_latency_ms = p99
        else:
            stats.min_latency_ms = None
            stats.max_latency_ms = None
            stats.avg_latency_ms = None
            stats.p50_latency_ms = None
            stats.p95_latency_ms = None
            stats.p99_latency_ms = None

        # Формирование Sparkline
        latencies_for_spark: Deque[Optional[float]] = deque(
            (r.latency_ms if r.is_success else None for r in history),
            maxlen=self.window_size
        )
        stats.sparkline = MetricsAnalyzer.generate_sparkline(latencies_for_spark, length=14)

        # Оценка здоровья хоста и выпуск алертов (только изменения состояния)
        new_status, conditions = MetricsAnalyzer.evaluate_health(stats, self.thresholds)
        stats.status = new_status
        self._emit_alerts(stats, conditions, result.timestamp)

        return stats

    # ---- подавление повторов ------------------------------------------------

    def _emit_alerts(self, stats: HostStats, conditions: List[NetworkAlert], now: datetime) -> None:
        """
        Edge-trigger: алерт выпускается, когда условие ПОЯВИЛОСЬ, усилилось (WARNING → CRITICAL)
        или держится дольше cooldown. Пока условие стабильно — повторов нет.
        При возврате в норму выпускается INFO-событие «восстановлен».

        Эпизод сбоя (DOWN → … → OK): потери в окне после обрыва — «хвост» того же события,
        поэтому отдельный алерт по потерям в этот период не выпускается (иначе в момент, когда связь
        уже вернулась, прозвучал бы новый CRITICAL), а состояние подавления сохраняется до полного
        возврата в OK (мерцающий канал не порождает алерт на каждый обрыв).
        """
        address = stats.address
        active_keys = set()

        if stats.status == "DOWN":
            self._outage_episode[address] = True
        elif stats.status == "OK":
            self._outage_episode.pop(address, None)   # полностью восстановился — эпизод окончен
        in_episode = self._outage_episode.get(address, False)

        for alert in conditions:
            if in_episode and alert.metric_name == "packet_loss":
                continue
            key = (address, alert.metric_name)
            active_keys.add(key)
            prev = self._alert_state.get(key)
            should_emit = (
                prev is None
                or _SEVERITY_RANK[alert.severity] > _SEVERITY_RANK[prev[0]]
                or (now - prev[1]).total_seconds() >= self.alert_cooldown_s
            )
            if should_emit:
                self._alert_state[key] = (alert.severity, now)
                self._dispatch(alert)

        # Условия, которые перестали выполняться, — сбрасываем (повтор снова вызовет алерт).
        # Во время эпизода сбоя состояние не трогаем (см. docstring).
        if not in_episode:
            for key in [k for k in self._alert_state if k[0] == address and k not in active_keys]:
                del self._alert_state[key]

        unhealthy = stats.status in ("DOWN", "CRIT", "WARN")
        if self._was_unhealthy.get(address) and stats.status == "OK":
            self._dispatch(
                NetworkAlert(
                    timestamp=now,
                    host=address,
                    target_name=stats.name,
                    severity=AlertSeverity.INFO,
                    message=f"Узел {stats.name} ({address}) снова в норме",
                    metric_name="recovery",
                    current_value=0.0,
                    threshold_value=0.0,
                )
            )
        self._was_unhealthy[address] = unhealthy

    def _dispatch(self, alert: NetworkAlert) -> None:
        self._alerts_log.append(alert)
        if self.on_alert_callback:
            try:
                self.on_alert_callback(alert)
            except Exception:
                # Ошибка обработчика не должна ломать сбор метрик
                pass

    def get_all_stats(self) -> List[HostStats]:
        """Получить список статистики по всем целевым хостам."""
        return list(self._stats.values())

    def get_recent_alerts(self, limit: int = 10) -> List[NetworkAlert]:
        """Получить последние события и аномалии."""
        return list(self._alerts_log)[-limit:]

    def get_host_history(self, address: str) -> List[PingResult]:
        """Получить временной ряд измерений для заданного хоста."""
        address = self._aliases.get(address, address)
        return list(self._history.get(address, []))
