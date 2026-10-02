"""SQLite-хранилище и экспорт JSON/CSV."""
import csv
import json
import sqlite3
from datetime import datetime, timedelta
from pathlib import Path

import pytest

from metrics.models import AlertSeverity, NetworkAlert, PingResult, SpeedtestResult, SystemNetworkInfo
from metrics.storage import StorageManager, _csv_safe


@pytest.fixture
def storage(tmp_path) -> StorageManager:
    return StorageManager(db_path=tmp_path / "t.db", export_dir=tmp_path / "exports")


def ping(host="1.1.1.1", name="Cloudflare", ok=True, latency=12.4, when=None) -> PingResult:
    return PingResult(host=host, target_name=name, timestamp=when or datetime.now(), is_success=ok,
                      latency_ms=latency if ok else None, protocol="tcp:443")


def alert(msg="Узел недоступен") -> NetworkAlert:
    return NetworkAlert(timestamp=datetime.now(), host="1.1.1.1", target_name="Cloudflare",
                        severity=AlertSeverity.CRITICAL, message=msg, metric_name="availability",
                        current_value=3.0, threshold_value=3.0)


def count(db: Path, table: str) -> int:
    with sqlite3.connect(db) as conn:
        return conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]


def test_session_row_exists_immediately(storage):
    """Регрессия: строка сессии появлялась только после диагностики — записи могли «висеть» без сессии."""
    with sqlite3.connect(storage.db_path) as conn:
        row = conn.execute("SELECT session_id FROM sessions").fetchone()
    assert row[0] == storage.session_id


def test_start_session_updates_row_instead_of_replacing(storage):
    storage.record_ping(ping())
    storage.start_session(SystemNetworkInfo(local_ip="192.168.1.5", gateway_ip="192.168.1.1", public_ip="1.2.3.4"))
    with sqlite3.connect(storage.db_path) as conn:
        rows = conn.execute("SELECT local_ip, gateway_ip, public_ip FROM sessions").fetchall()
    assert rows == [("192.168.1.5", "192.168.1.1", "1.2.3.4")]
    assert count(storage.db_path, "ping_records") == 1


def test_record_batch_writes_pings_and_alerts_atomically(storage):
    storage.record_batch([ping(), ping(ok=False)], [alert()])
    assert count(storage.db_path, "ping_records") == 2
    assert count(storage.db_path, "alerts") == 1


def test_failed_batch_is_rolled_back(storage, monkeypatch):
    good = ping()
    bad = alert()
    bad.metric_name = None                                   # NOT NULL → IntegrityError на втором insert
    with pytest.raises(sqlite3.IntegrityError):
        storage.record_batch([good], [bad])
    assert count(storage.db_path, "ping_records") == 0       # откат: половина пачки не сохранилась


def test_connections_are_closed(storage, tmp_path, monkeypatch):
    """Регрессия: `with sqlite3.connect()` не закрывает соединение — дескрипторы копились."""
    opened = []
    real_connect = sqlite3.connect

    def spy(*args, **kwargs):
        conn = real_connect(*args, **kwargs)
        opened.append(conn)
        return conn

    monkeypatch.setattr(sqlite3, "connect", spy)
    storage.record_ping(ping())
    storage.record_batch([ping()], [alert()])
    storage.export_json(tmp_path / "r.json")
    storage.export_csv(tmp_path / "r.csv")
    storage.close_session()
    assert len(opened) >= 5
    for conn in opened:
        with pytest.raises(sqlite3.ProgrammingError):          # на закрытом соединении операции невозможны
            conn.execute("SELECT 1")


def test_speedtest_record_keeps_status_and_duration(storage):
    storage.record_speedtest(SpeedtestResult(timestamp=datetime.now(), download_mbps=90.1, upload_mbps=0.0,
                                             duration_s=3.2, status="PARTIAL"))
    with sqlite3.connect(storage.db_path) as conn:
        row = conn.execute("SELECT download_mbps, upload_mbps, duration_s, status FROM speedtests").fetchone()
    assert row == (90.1, 0.0, 3.2, "PARTIAL")


def test_old_database_is_migrated(tmp_path):
    """База, созданная прежней версией (без новых колонок), открывается и дополняется."""
    db = tmp_path / "old.db"
    with sqlite3.connect(db) as conn:
        conn.executescript("""
            CREATE TABLE sessions (session_id TEXT PRIMARY KEY, start_time TEXT NOT NULL, end_time TEXT,
                                   local_ip TEXT, gateway_ip TEXT, public_ip TEXT, isp_name TEXT);
            CREATE TABLE ping_records (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL,
                host TEXT NOT NULL, target_name TEXT NOT NULL, timestamp TEXT NOT NULL,
                is_success INTEGER NOT NULL, latency_ms REAL, protocol TEXT NOT NULL);
            CREATE TABLE speedtests (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL,
                timestamp TEXT NOT NULL, download_mbps REAL NOT NULL, upload_mbps REAL NOT NULL, server_name TEXT);
            CREATE TABLE alerts (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL,
                timestamp TEXT NOT NULL, host TEXT NOT NULL, severity TEXT NOT NULL, message TEXT NOT NULL,
                metric_name TEXT NOT NULL, current_value REAL NOT NULL);
            INSERT INTO sessions (session_id, start_time) VALUES ('old00001', '2026-01-01T00:00:00');
        """)
    storage = StorageManager(db_path=db)
    storage.record_batch([ping()], [alert()])
    storage.record_speedtest(SpeedtestResult(timestamp=datetime.now(), download_mbps=1, upload_mbps=1))
    assert count(db, "alerts") == 1 and count(db, "speedtests") == 1
    assert count(db, "sessions") == 2                          # старая сессия сохранилась


def test_indexes_exist(storage):
    with sqlite3.connect(storage.db_path) as conn:
        names = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='index'")}
    assert {"idx_ping_session", "idx_alerts_session", "idx_speed_session"} <= names


# ---- очистка старых данных -------------------------------------------------------------------

def test_purge_old_removes_only_expired_records_of_other_sessions(tmp_path):
    db = tmp_path / "t.db"
    old = StorageManager(db_path=db)
    old_when = datetime.now() - timedelta(days=45)
    old.record_batch([ping(when=old_when)], [])
    with sqlite3.connect(db) as conn:                          # состарим сессию вручную
        conn.execute("UPDATE sessions SET start_time = ? WHERE session_id = ?", (old_when.isoformat(), old.session_id))

    current = StorageManager(db_path=db)
    current.record_batch([ping(), ping(when=datetime.now() - timedelta(days=45))], [])

    removed = current.purge_old(30)
    assert removed == 1                                        # из старой сессии (1 запись); у текущей чистка не трогает
    with sqlite3.connect(db) as conn:
        sessions = {r[0] for r in conn.execute("SELECT session_id FROM sessions")}
    assert current.session_id in sessions and old.session_id not in sessions
    assert count(db, "ping_records") == 2                      # обе записи текущей сессии целы


def test_purge_old_with_zero_days_keeps_everything(storage):
    storage.record_ping(ping(when=datetime.now() - timedelta(days=400)))
    assert storage.purge_old(0) == 0
    assert count(storage.db_path, "ping_records") == 1


# ---- экспорт ----------------------------------------------------------------------------------

def test_json_export_is_valid_and_complete(storage, tmp_path):
    storage.start_session(SystemNetworkInfo(local_ip="192.168.1.5"))
    storage.record_batch([ping(), ping(ok=False, latency=None)], [alert()])
    path = storage.export_json(tmp_path / "r.json")
    data = json.loads(path.read_text(encoding="utf-8"))
    assert data["summary"] == {"total_pings": 2, "total_alerts": 1, "total_speedtests": 0}
    assert data["session"]["session_id"] == storage.session_id
    assert [r["is_success"] for r in data["ping_records"]] == [1, 0]
    assert data["alerts"][0]["message"] == "Узел недоступен"       # кириллица не превращается в \u-эскейпы


def test_json_export_of_empty_session_is_valid(storage, tmp_path):
    data = json.loads(storage.export_json(tmp_path / "e.json").read_text(encoding="utf-8"))
    assert data["ping_records"] == [] and data["summary"]["total_pings"] == 0


def test_export_contains_only_current_session(tmp_path):
    db = tmp_path / "t.db"
    first = StorageManager(db_path=db)
    first.record_ping(ping(name="from-first"))
    second = StorageManager(db_path=db)
    second.record_ping(ping(name="from-second"))
    data = json.loads(second.export_json(tmp_path / "x.json").read_text(encoding="utf-8"))
    assert [r["target_name"] for r in data["ping_records"]] == ["from-second"]


def test_csv_export_rows(storage, tmp_path):
    storage.record_batch([ping(), ping(ok=False)], [])
    rows = list(csv.reader(storage.export_csv(tmp_path / "m.csv").open(encoding="utf-8", newline="")))
    assert rows[0] == ["Timestamp", "TargetName", "Host", "Success", "Latency_ms", "Protocol"]
    assert rows[1][3:5] == ["1", "12.4"] and rows[2][3:5] == ["0", ""]


@pytest.mark.parametrize("payload", ["=HYPERLINK(\"http://evil\",\"x\")", "+cmd|' /C calc'!A0", "-2+3", "@SUM(A1)"])
def test_csv_formula_injection_is_neutralised(storage, tmp_path, payload):
    """Имя узла приходит из командной строки/DNS: формулы не должны исполняться при открытии в Excel."""
    storage.record_ping(ping(name=payload))
    rows = list(csv.reader(storage.export_csv(tmp_path / "m.csv").open(encoding="utf-8", newline="")))
    assert rows[1][1] == "'" + payload


def test_csv_safe_leaves_normal_values_alone():
    assert _csv_safe("Cloudflare") == "Cloudflare" and _csv_safe(12.5) == 12.5 and _csv_safe("") == ""


def test_default_exports_do_not_overwrite_each_other(storage):
    first = storage.export_json()
    second = storage.export_json()
    third = storage.export_csv()
    assert len({first, second, third}) == 3 and first.exists() and second.exists()
    assert first.parent == storage.export_dir


def test_close_session_sets_end_time(storage):
    storage.close_session()
    with sqlite3.connect(storage.db_path) as conn:
        end = conn.execute("SELECT end_time FROM sessions WHERE session_id = ?", (storage.session_id,)).fetchone()[0]
    assert end is not None
