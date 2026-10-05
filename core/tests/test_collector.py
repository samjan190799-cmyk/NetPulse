"""MetricsCollector: агрегация, статус, подавление алертов, шлюз-заглушка."""
from collections import Counter

from config.settings import GATEWAY_PLACEHOLDER, AlertThresholds
from metrics.collector import MetricsCollector
from metrics.models import AlertSeverity


def feed(collector, make_result, pattern, host="10.0.0.1", latency=10.0):
    """pattern: строка из 'o' (успех) и 'x' (потеря). Возвращает список статусов после каждой проверки."""
    statuses = []
    for ch in pattern:
        stats = collector.record_result(make_result(host=host, ok=(ch == "o"), latency=latency))
        statuses.append(stats.status)
    return statuses


def kinds(alerts):
    return [(a.severity.value, a.metric_name) for a in alerts]


# ---- агрегация --------------------------------------------------------------------------------

def test_counters_loss_and_latency_stats(collector, make_result):
    collector.record_result(make_result(ok=True, latency=10.0))
    collector.record_result(make_result(ok=True, latency=30.0))
    stats = collector.record_result(make_result(ok=False))
    assert (stats.sent_count, stats.received_count, stats.lost_count) == (3, 2, 1)
    assert stats.loss_rate_pct == 33.3
    assert stats.last_latency_ms is None
    assert (stats.min_latency_ms, stats.avg_latency_ms, stats.max_latency_ms) == (10.0, 20.0, 30.0)
    assert stats.p50_latency_ms == 20.0


def test_history_is_bounded_by_window(make_result):
    c = MetricsCollector(AlertThresholds(), window_size=10)
    c.register_host("h", "10.0.0.1")
    feed(c, make_result, "o" * 50)
    assert len(c.get_host_history("10.0.0.1")) == 10


def test_jitter_returns_to_zero_after_stable_series(collector, make_result):
    collector.record_result(make_result(latency=10.0))
    collector.record_result(make_result(latency=90.0))
    assert collector.get_all_stats()[0].jitter_ms > 4.0
    feed(collector, make_result, "o" * 300, latency=90.0)
    assert collector.get_all_stats()[0].jitter_ms == 0.0


def test_unknown_host_is_registered_on_first_result(collector, make_result):
    collector.record_result(make_result(host="192.0.2.7", name="new"))
    assert {s.address for s in collector.get_all_stats()} == {"10.0.0.1", "192.0.2.7"}


# ---- статус и алерты --------------------------------------------------------------------------

def test_host_goes_down_on_third_consecutive_failure(collector, make_result, alerts):
    """Регрессия: DOWN наступал лишь когда потери по всей истории достигали 100 %."""
    feed(collector, make_result, "o" * 5)
    statuses = feed(collector, make_result, "xxx")
    assert statuses[:2] != ["DOWN", "DOWN"] and "DOWN" not in statuses[:2]
    assert statuses[2] == "DOWN"
    assert ("critical", "availability") in kinds(alerts)


def test_one_alert_per_outage_not_one_per_second(collector, make_result, alerts):
    """Регрессия: каждая проверка во время сбоя порождала новый CRITICAL (звук + трассировка + запись в БД)."""
    feed(collector, make_result, "o" * 15 + "x" * 40)
    availability = [a for a in alerts if a.metric_name == "availability"]
    assert len(availability) == 1


def test_long_outage_repeats_only_after_cooldown(collector, make_result, alerts):
    feed(collector, make_result, "o" * 15 + "x" * 130)
    availability = [a for a in alerts if a.metric_name == "availability"]
    assert len(availability) == 3                       # 3-я проверка, +60 с, +120 с


def test_status_recovers_when_status_window_is_clean(collector, make_result):
    """Регрессия: после обрыва статус оставался красным ~110 проверок (потери считались по всей истории)."""
    feed(collector, make_result, "o" * 30 + "x" * 30)
    statuses = feed(collector, make_result, "o" * 25)
    assert statuses[18] != "OK"
    assert statuses[19] == "OK"                         # окно статуса = 20 проверок
    assert statuses[-1] == "OK"


def test_recovery_is_announced_once(collector, make_result, alerts):
    feed(collector, make_result, "o" * 15 + "x" * 10 + "o" * 40)
    assert kinds(alerts).count(("info", "recovery")) == 1
    assert alerts[-1].severity is AlertSeverity.INFO


def test_no_critical_loss_alert_when_connection_is_back(make_result):
    """
    Регрессия: после сбоя дольше cooldown в момент ВОССТАНОВЛЕНИЯ срабатывал новый CRITICAL
    (по «хвосту» потерь в окне) — со звуком и авто-трассировкой, когда связь уже вернулась.
    """
    for outage in (3, 30, 59, 61, 130, 400):
        alerts = []
        c = MetricsCollector(AlertThresholds(), on_alert_callback=alerts.append)
        c.register_host("h", "10.0.0.1")
        feed(c, make_result, "o" * 15 + "x" * outage)
        before = len(alerts)
        feed(c, make_result, "o" * 40)
        after = alerts[before:]
        assert kinds(after) == [("info", "recovery")], f"outage={outage}: {kinds(after)}"


def test_flapping_connection_does_not_alert_on_every_drop(collector, make_result, alerts):
    feed(collector, make_result, "o" * 15)
    feed(collector, make_result, "xxxo" * 5)            # мерцание: 3 потери подряд, 1 успех
    availability = [a for a in alerts if a.metric_name == "availability"]
    assert len(availability) == 1


def test_warning_escalates_to_critical(make_result, alerts):
    c = MetricsCollector(AlertThresholds(), on_alert_callback=alerts.append)
    c.register_host("h", "10.0.0.1")
    feed(c, make_result, "o" * 19 + "x")                # 1 из 20 → 5 % → WARNING
    feed(c, make_result, "o" * 0)
    assert kinds(alerts) == [("warning", "packet_loss")]
    feed(c, make_result, "ox")                          # 2 из 20 → 10 % → CRITICAL (эскалация)
    assert ("critical", "packet_loss") in kinds(alerts)


def test_stable_warning_is_not_repeated(make_result, alerts):
    c = MetricsCollector(AlertThresholds(), on_alert_callback=alerts.append)
    c.register_host("h", "10.0.0.1")
    feed(c, make_result, "o" * 15 + "x" + "o" * 4)
    n = len(alerts)
    feed(c, make_result, "o" * 10)                      # потеря ещё в окне, но состояние не менялось
    assert len(alerts) == n


def test_high_latency_alert_is_edge_triggered(collector, make_result, alerts):
    feed(collector, make_result, "o" * 5, latency=10.0)
    feed(collector, make_result, "o" * 10, latency=130.0)
    latency_alerts = [a for a in alerts if a.metric_name == "latency"]
    assert len(latency_alerts) == 1
    assert latency_alerts[0].severity is AlertSeverity.WARNING


def test_callback_exception_does_not_break_collection(make_result):
    def boom(_alert):
        raise RuntimeError("handler failed")

    c = MetricsCollector(AlertThresholds(), on_alert_callback=boom)
    c.register_host("h", "10.0.0.1")
    statuses = feed(c, make_result, "o" * 10 + "x" * 5)
    assert statuses[-1] == "DOWN"
    assert len(c.get_recent_alerts()) >= 1              # журнал ведётся и без обработчика


# ---- шлюз-заглушка ----------------------------------------------------------------------------

def make_gateway_collector(alerts):
    c = MetricsCollector(AlertThresholds(), on_alert_callback=alerts.append)
    c.register_host("Шлюз", GATEWAY_PLACEHOLDER, is_gateway=True)
    return c


def test_unresolved_gateway_placeholder_is_not_measured(make_result, alerts):
    """Регрессия: заглушка «gateway» получала 100 % потерь и CRITICAL до окончания диагностики."""
    c = make_gateway_collector(alerts)
    for _ in range(10):
        c.record_result(make_result(host=GATEWAY_PLACEHOLDER, ok=False, name="Шлюз"))
    assert alerts == []
    assert c.get_all_stats()[0].sent_count == 0


def test_gateway_is_renamed_to_real_address_without_ghost_row(make_result, alerts):
    """Регрессия: после определения шлюза в таблице оставалась «призрачная» строка со старым адресом."""
    c = make_gateway_collector(alerts)
    c.update_gateway_address("192.168.1.1")
    c.record_result(make_result(host="192.168.1.1", name="Шлюз"))
    c.record_result(make_result(host=GATEWAY_PLACEHOLDER, name="Шлюз"))        # запоздавший результат
    stats = c.get_all_stats()
    assert [(s.address, s.is_gateway) for s in stats] == [("192.168.1.1", True)]
    assert stats[0].sent_count == 2


def test_gateway_change_starts_fresh_statistics(make_result, alerts):
    c = make_gateway_collector(alerts)
    c.update_gateway_address("192.168.1.1")
    feed(c, make_result, "x" * 5, host="192.168.1.1")
    c.update_gateway_address("10.1.1.1")                                        # другая сеть
    stats = c.get_all_stats()
    assert [s.address for s in stats] == ["10.1.1.1"]
    assert stats[0].sent_count == 0 and stats[0].status == "UNKNOWN"


def test_gateway_equal_to_monitored_host_is_merged(make_result, alerts):
    c = make_gateway_collector(alerts)
    c.register_host("Router", "192.168.1.1")
    c.update_gateway_address("192.168.1.1")
    stats = c.get_all_stats()
    assert len(stats) == 1 and stats[0].is_gateway
    assert Counter(s.address for s in stats)["192.168.1.1"] == 1
