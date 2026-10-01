"""
Модуль постоянного хранения метрик в SQLite и экспорта в форматы JSON и CSV.
"""
import csv
import json
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import datetime, timedelta
from pathlib import Path
from typing import Iterator, Optional, Sequence
from metrics.models import NetworkAlert, PingResult, SpeedtestResult, SystemNetworkInfo

# Колонки, добавленные после первого релиза: (таблица, колонка, тип)
_MIGRATIONS = (
    ("alerts", "target_name", "TEXT"),
    ("alerts", "threshold_value", "REAL"),
    ("speedtests", "duration_s", "REAL"),
    ("speedtests", "status", "TEXT"),
)


def _csv_safe(value):
    """Защита от CSV-инъекций (формулы в Excel/LibreOffice): текст, начинающийся с = + - @, экранируется."""
    if isinstance(value, str) and value and value[0] in ("=", "+", "-", "@", "\t", "\r"):
        return "'" + value
    return value


class StorageManager:
    """Менеджер базы данных SQLite и экспорта отчетов."""

    def __init__(self, db_path: Path = Path("netpulse_history.db"), export_dir: Optional[Path] = None):
        self.db_path = Path(db_path)
        self.export_dir = Path(export_dir) if export_dir is not None else Path(".")
        self.session_id: str = str(uuid.uuid4())[:8]
        self._init_db()
        self._ensure_session_row()

    # ---- соединения ---------------------------------------------------------

    @contextmanager
    def _connect(self) -> Iterator[sqlite3.Connection]:
        """
        Соединение с автокоммитом и ГАРАНТИРОВАННЫМ закрытием.
        (Контекст `with sqlite3.connect()` сам по себе соединение не закрывает.)
        Каждый вызов открывает своё соединение, поэтому методы безопасно вызывать
        из пула потоков (asyncio.to_thread).
        """
        conn = sqlite3.connect(self.db_path, timeout=10.0)
        try:
            try:
                conn.execute("PRAGMA journal_mode=WAL")
                conn.execute("PRAGMA synchronous=NORMAL")
            except sqlite3.DatabaseError:
                pass  # файловая система без поддержки WAL — работаем в обычном режиме
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    def _init_db(self) -> None:
        """Инициализация схемы таблиц базы данных."""
        with self._connect() as conn:
            cursor = conn.cursor()

            # Таблица сессий
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS sessions (
                    session_id TEXT PRIMARY KEY,
                    start_time TEXT NOT NULL,
                    end_time TEXT,
                    local_ip TEXT,
                    gateway_ip TEXT,
                    public_ip TEXT,
                    isp_name TEXT
                )
            """)

            # Таблица измерений пинга (time-series)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS ping_records (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id TEXT NOT NULL,
                    host TEXT NOT NULL,
                    target_name TEXT NOT NULL,
                    timestamp TEXT NOT NULL,
                    is_success INTEGER NOT NULL,
                    latency_ms REAL,
                    protocol TEXT NOT NULL,
                    FOREIGN KEY (session_id) REFERENCES sessions(session_id)
                )
            """)

            # Таблица результатов Speedtest
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS speedtests (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id TEXT NOT NULL,
                    timestamp TEXT NOT NULL,
                    download_mbps REAL NOT NULL,
                    upload_mbps REAL NOT NULL,
                    server_name TEXT,
                    FOREIGN KEY (session_id) REFERENCES sessions(session_id)
                )
            """)

            # Таблица алертов
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS alerts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id TEXT NOT NULL,
                    timestamp TEXT NOT NULL,
                    host TEXT NOT NULL,
                    severity TEXT NOT NULL,
                    message TEXT NOT NULL,
                    metric_name TEXT NOT NULL,
                    current_value REAL NOT NULL,
                    FOREIGN KEY (session_id) REFERENCES sessions(session_id)
                )
            """)

            # Миграции для баз, созданных старыми версиями
            for table, column, col_type in _MIGRATIONS:
                existing = {row[1] for row in cursor.execute(f"PRAGMA table_info({table})")}
                if column not in existing:
                    cursor.execute(f"ALTER TABLE {table} ADD COLUMN {column} {col_type}")

            # Индексы: без них экспорт сессии (WHERE session_id = ?) сканировал всю историю
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_ping_session ON ping_records(session_id, id)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_ping_ts ON ping_records(timestamp)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_alerts_session ON alerts(session_id, id)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_alerts_ts ON alerts(timestamp)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_speed_session ON speedtests(session_id, id)")

    def _ensure_session_row(self) -> None:
        """Строка сессии создаётся сразу при старте, чтобы записи никогда не «висели» без сессии."""
        with self._connect() as conn:
            conn.execute(
                "INSERT OR IGNORE INTO sessions (session_id, start_time) VALUES (?, ?)",
                (self.session_id, datetime.now().isoformat()),
            )

    # ---- сессия -------------------------------------------------------------

    def start_session(self, sys_info: SystemNetworkInfo) -> str:
        """Дополнение сессии сведениями о сети (после диагностики)."""
        with self._connect() as conn:
            conn.execute("""
                UPDATE sessions
                SET local_ip = ?, gateway_ip = ?, public_ip = ?, isp_name = ?
                WHERE session_id = ?
            """, (
                sys_info.local_ip,
                sys_info.gateway_ip,
                sys_info.public_ip,
                sys_info.isp_name,
                self.session_id,
            ))
        return self.session_id

    def close_session(self) -> None:
        """Завершение текущей сессии."""
        with self._connect() as conn:
            conn.execute(
                "UPDATE sessions SET end_time = ? WHERE session_id = ?",
                (datetime.now().isoformat(), self.session_id),
            )

    def purge_old(self, days: int) -> int:
        """Удаляет историю старше `days` дней (кроме текущей сессии). Возвращает число удалённых записей."""
        if days <= 0:
            return 0
        cutoff = (datetime.now() - timedelta(days=days)).isoformat()
        removed = 0
        with self._connect() as conn:
            for table in ("ping_records", "alerts", "speedtests"):
                removed += conn.execute(
                    f"DELETE FROM {table} WHERE timestamp < ? AND session_id != ?",
                    (cutoff, self.session_id),
                ).rowcount
            conn.execute("""
                DELETE FROM sessions
                WHERE start_time < ? AND session_id != ?
                  AND session_id NOT IN (SELECT DISTINCT session_id FROM ping_records)
                  AND session_id NOT IN (SELECT DISTINCT session_id FROM alerts)
                  AND session_id NOT IN (SELECT DISTINCT session_id FROM speedtests)
            """, (cutoff, self.session_id))
        return removed

    # ---- запись -------------------------------------------------------------

    @staticmethod
    def _ping_row(session_id: str, r: PingResult):
        return (
            session_id,
            r.host,
            r.target_name,
            r.timestamp.isoformat(),
            1 if r.is_success else 0,
            r.latency_ms,
            r.protocol,
        )

    @staticmethod
    def _alert_row(session_id: str, a: NetworkAlert):
        return (
            session_id,
            a.timestamp.isoformat(),
            a.host,
            a.severity.value,
            a.message,
            a.metric_name,
            a.current_value,
            a.target_name,
            a.threshold_value,
        )

    _PING_SQL = """
        INSERT INTO ping_records
        (session_id, host, target_name, timestamp, is_success, latency_ms, protocol)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """
    _ALERT_SQL = """
        INSERT INTO alerts
        (session_id, timestamp, host, severity, message, metric_name, current_value, target_name, threshold_value)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    def record_ping(self, result: PingResult) -> None:
        """Запись одного измерения пинга."""
        self.record_batch([result], [])

    def record_ping_batch(self, results: Sequence[PingResult]) -> None:
        """Пакетная запись измерений пинга."""
        self.record_batch(results, [])

    def record_alert(self, alert: NetworkAlert) -> None:
        """Запись сетевого алерта."""
        self.record_batch([], [alert])

    def record_batch(self, pings: Sequence[PingResult], alerts: Sequence[NetworkAlert]) -> None:
        """Запись пингов и алертов одной транзакцией (один fsync вместо десятков)."""
        if not pings and not alerts:
            return
        with self._connect() as conn:
            if pings:
                conn.executemany(self._PING_SQL, [self._ping_row(self.session_id, r) for r in pings])
            if alerts:
                conn.executemany(self._ALERT_SQL, [self._alert_row(self.session_id, a) for a in alerts])

    def record_speedtest(self, res: SpeedtestResult) -> None:
        """Запись результатов замера пропускной способности."""
        with self._connect() as conn:
            conn.execute("""
                INSERT INTO speedtests
                (session_id, timestamp, download_mbps, upload_mbps, server_name, duration_s, status)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (
                self.session_id,
                res.timestamp.isoformat(),
                res.download_mbps,
                res.upload_mbps,
                res.server_name,
                res.duration_s,
                res.status,
            ))

    # ---- экспорт ------------------------------------------------------------

    def _export_path(self, export_path: Optional[Path], prefix: str, ext: str) -> Path:
        if export_path is not None:
            path = Path(export_path)
            path.parent.mkdir(parents=True, exist_ok=True)
            return path
        self.export_dir.mkdir(parents=True, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        path = self.export_dir / f"{prefix}_{self.session_id}_{ts}.{ext}"
        counter = 1
        while path.exists():  # два экспорта в одну секунду не должны затирать друг друга
            path = self.export_dir / f"{prefix}_{self.session_id}_{ts}_{counter}.{ext}"
            counter += 1
        return path

    def export_json(self, export_path: Optional[Path] = None) -> Path:
        """
        Экспорт всех данных текущей сессии в JSON файл.
        Записи пинга пишутся потоком (курсор → файл), без загрузки всей сессии в память.
        """
        path = self._export_path(export_path, "netpulse_report", "json")

        def dump(obj, indent_level: int = 1) -> str:
            text = json.dumps(obj, ensure_ascii=False, indent=2)
            return text.replace("\n", "\n" + "  " * indent_level)

        with self._connect() as conn:
            conn.row_factory = sqlite3.Row

            session_row = conn.execute(
                "SELECT * FROM sessions WHERE session_id = ?", (self.session_id,)
            ).fetchone()
            session_data = dict(session_row) if session_row else {}

            total_pings = conn.execute(
                "SELECT COUNT(*) FROM ping_records WHERE session_id = ?", (self.session_id,)
            ).fetchone()[0]

            speedtests = [dict(r) for r in conn.execute(
                "SELECT timestamp, download_mbps, upload_mbps, server_name, duration_s, status "
                "FROM speedtests WHERE session_id = ? ORDER BY id", (self.session_id,))]
            alerts = [dict(r) for r in conn.execute(
                "SELECT timestamp, host, target_name, severity, message, metric_name, current_value, threshold_value "
                "FROM alerts WHERE session_id = ? ORDER BY id", (self.session_id,))]

            summary = {
                "total_pings": total_pings,
                "total_alerts": len(alerts),
                "total_speedtests": len(speedtests),
            }

            with open(path, "w", encoding="utf-8") as f:
                f.write("{\n")
                f.write('  "netpulse_version": "1.0.0",\n')
                f.write(f'  "session": {dump(session_data)},\n')
                f.write(f'  "summary": {dump(summary)},\n')
                f.write(f'  "speedtests": {dump(speedtests)},\n')
                f.write(f'  "alerts": {dump(alerts)},\n')
                f.write('  "ping_records": [')
                first = True
                cursor = conn.execute(
                    "SELECT host, target_name, timestamp, is_success, latency_ms, protocol "
                    "FROM ping_records WHERE session_id = ? ORDER BY id", (self.session_id,))
                for row in cursor:
                    f.write(("" if first else ",") + "\n    " + json.dumps(dict(row), ensure_ascii=False))
                    first = False
                f.write("\n  ]\n}\n" if not first else "]\n}\n")

        return path

    def export_csv(self, export_path: Optional[Path] = None) -> Path:
        """Экспорт измерений пинга текущей сессии в CSV файл (потоково)."""
        path = self._export_path(export_path, "netpulse_metrics", "csv")

        with self._connect() as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.execute("""
                SELECT timestamp, target_name, host, is_success, latency_ms, protocol
                FROM ping_records
                WHERE session_id = ?
                ORDER BY id ASC
            """, (self.session_id,))

            with open(path, "w", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                writer.writerow(["Timestamp", "TargetName", "Host", "Success", "Latency_ms", "Protocol"])
                for row in cursor:
                    writer.writerow([
                        row["timestamp"],
                        _csv_safe(row["target_name"]),
                        _csv_safe(row["host"]),
                        row["is_success"],
                        row["latency_ms"] if row["latency_ms"] is not None else "",
                        _csv_safe(row["protocol"]),
                    ])

        return path
