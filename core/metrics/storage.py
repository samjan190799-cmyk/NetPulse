"""
Модуль постоянного хранения метрик в SQLite и экспорта в форматы JSON и CSV.
"""
import csv
import json
import sqlite3
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional
from metrics.models import NetworkAlert, PingResult, SpeedtestResult, SystemNetworkInfo


class StorageManager:
    """Менеджер базы данных SQLite и экспорта отчетов."""

    def __init__(self, db_path: Path = Path("netpulse_history.db")):
        self.db_path = db_path
        self.session_id: str = str(uuid.uuid4())[:8]
        self._init_db()

    def _init_db(self) -> None:
        """Инициализация схемы таблиц базы данных."""
        with sqlite3.connect(self.db_path) as conn:
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
            conn.commit()

    def start_session(self, sys_info: SystemNetworkInfo) -> str:
        """Регистрация начала новой сессии мониторинга."""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT OR REPLACE INTO sessions 
                (session_id, start_time, local_ip, gateway_ip, public_ip, isp_name)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                self.session_id,
                datetime.now().isoformat(),
                sys_info.local_ip,
                sys_info.gateway_ip,
                sys_info.public_ip,
                sys_info.isp_name,
            ))
            conn.commit()
        return self.session_id

    def close_session(self) -> None:
        """Завершение текущей сессии."""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                UPDATE sessions 
                SET end_time = ? 
                WHERE session_id = ?
            """, (datetime.now().isoformat(), self.session_id))
            conn.commit()

    def record_ping(self, result: PingResult) -> None:
        """Запись одного измерения пинга."""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO ping_records 
                (session_id, host, target_name, timestamp, is_success, latency_ms, protocol)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (
                self.session_id,
                result.host,
                result.target_name,
                result.timestamp.isoformat(),
                1 if result.is_success else 0,
                result.latency_ms,
                result.protocol,
            ))
            conn.commit()

    def record_ping_batch(self, results: List[PingResult]) -> None:
        """Пакетная запись измерений пинга."""
        if not results:
            return
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            data = [
                (
                    self.session_id,
                    r.host,
                    r.target_name,
                    r.timestamp.isoformat(),
                    1 if r.is_success else 0,
                    r.latency_ms,
                    r.protocol,
                )
                for r in results
            ]
            cursor.executemany("""
                INSERT INTO ping_records 
                (session_id, host, target_name, timestamp, is_success, latency_ms, protocol)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, data)
            conn.commit()

    def record_speedtest(self, res: SpeedtestResult) -> None:
        """Запись результатов замера пропускной способности."""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO speedtests 
                (session_id, timestamp, download_mbps, upload_mbps, server_name)
                VALUES (?, ?, ?, ?, ?)
            """, (
                self.session_id,
                res.timestamp.isoformat(),
                res.download_mbps,
                res.upload_mbps,
                res.server_name,
            ))
            conn.commit()

    def record_alert(self, alert: NetworkAlert) -> None:
        """Запись сетевого алерта."""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO alerts 
                (session_id, timestamp, host, severity, message, metric_name, current_value)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (
                self.session_id,
                alert.timestamp.isoformat(),
                alert.host,
                alert.severity.value,
                alert.message,
                alert.metric_name,
                alert.current_value,
            ))
            conn.commit()

    def export_json(self, export_path: Optional[Path] = None) -> Path:
        """Экспорт всех данных текущей сессии в JSON файл."""
        if export_path is None:
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            export_path = Path(f"netpulse_report_{self.session_id}_{ts}.json")

        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()

            # Сессия
            cursor.execute("SELECT * FROM sessions WHERE session_id = ?", (self.session_id,))
            session_row = cursor.fetchone()
            session_data = dict(session_row) if session_row else {}

            # Пинги
            cursor.execute("SELECT host, target_name, timestamp, is_success, latency_ms, protocol FROM ping_records WHERE session_id = ?", (self.session_id,))
            pings = [dict(r) for r in cursor.fetchall()]

            # Speedtest
            cursor.execute("SELECT timestamp, download_mbps, upload_mbps, server_name FROM speedtests WHERE session_id = ?", (self.session_id,))
            speedtests = [dict(r) for r in cursor.fetchall()]

            # Алерты
            cursor.execute("SELECT timestamp, host, severity, message, metric_name, current_value FROM alerts WHERE session_id = ?", (self.session_id,))
            alerts = [dict(r) for r in cursor.fetchall()]

        report = {
            "netpulse_version": "1.0.0",
            "session": session_data,
            "summary": {
                "total_pings": len(pings),
                "total_alerts": len(alerts),
                "total_speedtests": len(speedtests),
            },
            "speedtests": speedtests,
            "alerts": alerts,
            "ping_records": pings,
        }

        with open(export_path, "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=2)

        return export_path

    def export_csv(self, export_path: Optional[Path] = None) -> Path:
        """Экспорт измерений пинга текущей сессии в CSV файл."""
        if export_path is None:
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            export_path = Path(f"netpulse_metrics_{self.session_id}_{ts}.csv")

        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            cursor.execute("""
                SELECT timestamp, target_name, host, is_success, latency_ms, protocol 
                FROM ping_records 
                WHERE session_id = ?
                ORDER BY id ASC
            """, (self.session_id,))
            rows = cursor.fetchall()

        with open(export_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["Timestamp", "TargetName", "Host", "Success", "Latency_ms", "Protocol"])
            for row in rows:
                writer.writerow([
                    row["timestamp"],
                    row["target_name"],
                    row["host"],
                    row["is_success"],
                    row["latency_ms"] if row["latency_ms"] is not None else "",
                    row["protocol"],
                ])

        return export_path
