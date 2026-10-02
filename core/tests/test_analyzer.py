"""Математика и оценка здоровья: джиттер RFC 3550, перцентили, sparkline, пороги."""
from datetime import datetime

import pytest

from config.settings import AlertThresholds
from metrics.analyzer import MIN_SAMPLES_FOR_LOSS_PCT, MetricsAnalyzer
from metrics.models import AlertSeverity, HostStats

jitter = MetricsAnalyzer.calculate_rfc3550_jitter


# ---- джиттер ----------------------------------------------------------------------------------

def test_jitter_first_packet_is_zero():
    assert jitter(prev_jitter=0.0, prev_latency=None, curr_latency=20.0) == 0.0


def test_jitter_matches_rfc3550_reference():
    j1 = jitter(prev_jitter=0.0, prev_latency=20.0, curr_latency=36.0)   # D=16 → 16/16
    assert j1 == 1.0
    j2 = jitter(prev_jitter=j1, prev_latency=36.0, curr_latency=68.0)    # D=32 → 1 + 31/16
    assert j2 == 2.94


def test_jitter_state_without_rounding_decays_to_zero():
    """Регрессия: состояние фильтра хранилось округлённым и «залипало» на ~0.07 мс."""
    state = jitter(0.0, 10.0, 90.0, precise=True)              # всплеск на 80 мс
    assert state == pytest.approx(5.0)
    for _ in range(200):                                        # дальше ряд стабилен
        state = jitter(state, 90.0, 90.0, precise=True)
    assert state < 0.001


def test_jitter_with_rounded_state_sticks():
    """Показывает, почему состояние нельзя округлять (поведение, ради которого есть precise=True)."""
    state = 0.07
    for _ in range(200):
        state = jitter(state, 50.0, 50.0)                       # precise=False — округление до 0.01
    assert state > 0.05


# ---- перцентили -------------------------------------------------------------------------------

def test_percentiles_of_empty_list():
    assert MetricsAnalyzer.calculate_percentiles([]) == (0.0, 0.0, 0.0)


def test_percentiles_of_single_value():
    assert MetricsAnalyzer.calculate_percentiles([42.0]) == (42.0, 42.0, 42.0)


def test_percentiles_linear_interpolation():
    values = [float(v) for v in range(10, 101, 10)]
    p50, p95, p99 = MetricsAnalyzer.calculate_percentiles(values)
    assert (p50, p95, p99) == (55.0, 95.5, 99.1)


def test_percentiles_do_not_depend_on_input_order():
    assert MetricsAnalyzer.calculate_percentiles([30.0, 10.0, 20.0]) == MetricsAnalyzer.calculate_percentiles(
        [10.0, 20.0, 30.0]
    )


# ---- sparkline --------------------------------------------------------------------------------

@pytest.mark.parametrize("count", range(0, 21))
def test_sparkline_has_requested_length(count):
    history = [float(i) for i in range(count)]
    assert len(MetricsAnalyzer.generate_sparkline(history, length=8)) == 8


def test_sparkline_marks_lost_packets():
    spark = MetricsAnalyzer.generate_sparkline([10.0, None, 30.0], length=3)
    assert spark[1] == MetricsAnalyzer.LOSS_CHAR
    assert MetricsAnalyzer.LOSS_CHAR not in (spark[0], spark[2])


def test_sparkline_pads_missing_history_with_spaces_not_loss_marks():
    """Регрессия: при короткой истории слева рисовались «потери»."""
    spark = MetricsAnalyzer.generate_sparkline([10.0, 20.0], length=6)
    assert spark[:4] == "    "
    assert MetricsAnalyzer.LOSS_CHAR not in spark


def test_sparkline_flat_series_is_visible():
    """Регрессия: при одинаковых значениях рисовались пробелы (график «пропадал»)."""
    spark = MetricsAnalyzer.generate_sparkline([25.0] * 5, length=5)
    assert len(set(spark)) == 1
    assert spark.strip() != ""


def test_sparkline_minimum_is_not_blank():
    spark = MetricsAnalyzer.generate_sparkline([10.0, 100.0], length=2)
    assert spark[0] == MetricsAnalyzer.SPARK_CHARS[0]
    assert spark[1] == MetricsAnalyzer.SPARK_CHARS[-1]


def test_sparkline_all_lost():
    assert MetricsAnalyzer.generate_sparkline([None, None, None], length=3) == "✕✕✕"


# ---- оценка здоровья --------------------------------------------------------------------------

def make_stats(**kw) -> HostStats:
    base = dict(name="h", address="10.0.0.1", sent_count=30, received_count=30, last_updated=datetime(2026, 1, 1))
    base.update(kw)
    return HostStats(**base)


def metrics_of(alerts):
    return {(a.metric_name, a.severity) for a in alerts}


def test_unknown_until_first_measurement():
    status, alerts = MetricsAnalyzer.evaluate_health(make_stats(sent_count=0), AlertThresholds())
    assert (status, alerts) == ("UNKNOWN", [])


def test_healthy_host_is_ok():
    stats = make_stats(last_latency_ms=15.0, recent_count=20, loss_recent_pct=0.0)
    assert MetricsAnalyzer.evaluate_health(stats, AlertThresholds()) == ("OK", [])


def test_down_only_after_n_consecutive_failures():
    """Регрессия: DOWN объявлялся лишь когда потери по всей истории достигали 100 % (~119-я проверка)."""
    t = AlertThresholds()
    two = make_stats(consecutive_failures=t.down_after_failures - 1, recent_count=3)
    assert MetricsAnalyzer.evaluate_health(two, t)[0] != "DOWN"

    three = make_stats(consecutive_failures=t.down_after_failures, recent_count=3)
    status, alerts = MetricsAnalyzer.evaluate_health(three, t)
    assert status == "DOWN"
    assert metrics_of(alerts) == {("availability", AlertSeverity.CRITICAL)}


def test_loss_percentage_needs_enough_samples():
    """Регрессия: 1 потеря из 2 проверок давала «50 % потерь» и CRITICAL."""
    stats = make_stats(consecutive_failures=1, recent_count=MIN_SAMPLES_FOR_LOSS_PCT - 1, loss_recent_pct=50.0)
    status, alerts = MetricsAnalyzer.evaluate_health(stats, AlertThresholds())
    assert not [a for a in alerts if a.metric_name == "packet_loss"]
    assert status == "WARN"


@pytest.mark.parametrize(
    "loss, expected_status, expected_severity",
    [(2.9, "OK", None), (3.0, "WARN", AlertSeverity.WARNING), (7.9, "WARN", AlertSeverity.WARNING),
     (8.0, "CRIT", AlertSeverity.CRITICAL), (40.0, "CRIT", AlertSeverity.CRITICAL)],
)
def test_loss_thresholds_with_enough_samples(loss, expected_status, expected_severity):
    stats = make_stats(recent_count=20, loss_recent_pct=loss, last_latency_ms=10.0)
    status, alerts = MetricsAnalyzer.evaluate_health(stats, AlertThresholds())
    assert status == expected_status
    found = [a for a in alerts if a.metric_name == "packet_loss"]
    assert (found[0].severity if found else None) == expected_severity


@pytest.mark.parametrize(
    "latency, expected",
    [(99.9, "OK"), (100.0, "WARN"), (179.9, "WARN"), (180.0, "CRIT")],
)
def test_latency_thresholds(latency, expected):
    stats = make_stats(last_latency_ms=latency, recent_count=20)
    assert MetricsAnalyzer.evaluate_health(stats, AlertThresholds())[0] == expected


@pytest.mark.parametrize(
    "jit, expected",
    [(19.9, "OK"), (20.0, "WARN"), (39.9, "WARN"), (40.0, "CRIT")],
)
def test_jitter_thresholds(jit, expected):
    stats = make_stats(last_latency_ms=10.0, jitter_ms=jit, recent_count=20)
    assert MetricsAnalyzer.evaluate_health(stats, AlertThresholds())[0] == expected
