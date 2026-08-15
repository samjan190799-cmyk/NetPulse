"""
NetPulse — Высокопроизводительный инструмент мониторинга качества сети в реальном времени.
Точка входа и оркестратор асинхронных подсистем.
"""
import argparse
import asyncio
import os
import platform
import signal
import sys
import webbrowser
from datetime import datetime
from pathlib import Path
from typing import Optional

from rich.console import Console
from rich.live import Live

from config.settings import AlertThresholds, AppConfig, HostTarget, PingMode, WebConfig
from engine.diagnostics import NetworkDiagnostics
from engine.ping import AsyncPingEngine
from engine.speedtest import AsyncSpeedtestEngine
from engine.traceroute import AsyncTracerouteEngine
from metrics.collector import MetricsCollector
from metrics.models import HostStats, NetworkAlert, PingResult, SpeedtestResult
from metrics.storage import StorageManager
from ui.tui import TerminalUI
from ui.web import FASTAPI_AVAILABLE, StandaloneWebServer, create_web_app


class NetPulseApplication:
    """Главный оркестратор приложения NetPulse."""

    def __init__(self, config: AppConfig):
        self.config = config
        self.console = Console()
        self.shutdown_event = asyncio.Event()

        # Инициализация хранилища и сборщика метрик
        self.storage = StorageManager(db_path=config.db_path)
        self.collector = MetricsCollector(
            thresholds=config.thresholds,
            window_size=config.history_window_size,
            on_alert_callback=self._handle_alert,
        )
        self.ping_engine = AsyncPingEngine(mode=config.ping_mode, timeout=config.ping_timeout)
        self.speedtest_engine = AsyncSpeedtestEngine()
        self.traceroute_engine = AsyncTracerouteEngine()
        self.ui = TerminalUI(config=config, collector=self.collector)

        # Регистрация хостов
        for target in self.config.targets:
            self.collector.register_host(target.name, target.address, is_gateway=target.is_gateway)

        # Состояние фоновых задач
        self.auto_trace_in_progress = False
        self.standalone_web_server: Optional[StandaloneWebServer] = None

    def _handle_alert(self, alert: NetworkAlert) -> None:
        """Обработчик сетевых аномалий и алертов."""
        self.storage.record_alert(alert)
        self.ui.trigger_sound_alert()

        # Автоматический запуск Traceroute при критическом сбое
        if self.config.auto_traceroute_on_alert and not self.auto_trace_in_progress:
            asyncio.create_task(self._trigger_auto_traceroute(alert.host))

    async def _trigger_auto_traceroute(self, target_host: str) -> None:
        """Автоматическая трассировка при обнаружении проблем."""
        self.auto_trace_in_progress = True
        self.ui.traceroute_running = True
        self.ui.traceroute_target = target_host
        self.ui.traceroute_hops = []

        def on_hop(hop):
            self.ui.traceroute_hops.append(hop)

        try:
            hops = await self.traceroute_engine.trace(target_host, on_hop_callback=on_hop)
            self.ui.traceroute_hops = hops
        finally:
            self.ui.traceroute_running = False
            self.auto_trace_in_progress = False

    async def run_manual_speedtest(self) -> SpeedtestResult:
        """Ручной запуск теста скорости из TUI или Web API."""
        if self.ui.speedtest_running:
            return self.ui.last_speedtest or SpeedtestResult(
                timestamp=datetime.now(),
                download_mbps=0,
                upload_mbps=0,
                status="BUSY"
            )

        self.ui.speedtest_running = True
        self.ui.speedtest_status_text = "Идет замер скачивания..."

        def progress_cb(stage: str, mbps: float):
            if stage == "download":
                self.ui.speedtest_status_text = f"Загрузка: [bold green]{mbps:.1f} Mbps[/bold green]"
            elif stage == "upload":
                self.ui.speedtest_status_text = f"Отдача: [bold cyan]{mbps:.1f} Mbps[/bold cyan]"

        try:
            res = await self.speedtest_engine.run_full_speedtest(progress_cb=progress_cb)
            self.ui.last_speedtest = res
            self.storage.record_speedtest(res)
            self.ui.speedtest_status_text = f"Готово ({res.download_mbps:.1f} / {res.upload_mbps:.1f} Mbps)"
            return res
        except Exception as e:
            self.ui.speedtest_status_text = f"Ошибка: {str(e)[:20]}"
            raise
        finally:
            self.ui.speedtest_running = False

    async def _diagnostics_task(self) -> None:
        """Фоновый сбор информации о сети и провайдере без задержки старта пинга."""
        try:
            sys_info = await NetworkDiagnostics.collect_full_info()
            self.collector.system_info = sys_info

            # Обновление адреса шлюза в списке мониторинга
            if sys_info.gateway_ip and sys_info.gateway_ip != "127.0.0.1":
                self.collector.update_gateway_address(sys_info.gateway_ip)
                for t in self.config.targets:
                    if t.is_gateway:
                        t.address = sys_info.gateway_ip

            # Запуск сессии в БД
            self.storage.start_session(sys_info)
        except Exception:
            pass

    async def _ping_loop(self) -> None:
        """Основной непрерывный цикл параллельного пинга."""
        while not self.shutdown_event.is_set():
            start_tick = asyncio.get_event_loop().time()
            results = await self.ping_engine.ping_all(self.config.targets)
            
            for res in results:
                self.collector.record_result(res)
            
            self.storage.record_ping_batch(results)

            elapsed = asyncio.get_event_loop().time() - start_tick
            sleep_time = max(0.05, self.config.ping_interval - elapsed)
            
            try:
                await asyncio.wait_for(self.shutdown_event.wait(), timeout=sleep_time)
                break
            except asyncio.TimeoutError:
                pass

    async def _keyboard_listener(self) -> None:
        """Асинхронное считывание нажатий горячих клавиш."""
        sys_name = platform.system().lower()

        if sys_name == "windows":
            import msvcrt

            def get_key():
                if msvcrt.kbhit():
                    ch = msvcrt.getch()
                    try:
                        return ch.decode("utf-8", errors="ignore").lower()
                    except Exception:
                        return None
                return None

            while not self.shutdown_event.is_set():
                key = await asyncio.to_thread(get_key)
                if key:
                    await self._process_key(key)
                await asyncio.sleep(0.1)
        else:
            # Unix / POSIX
            try:
                import select
                import termios
                import tty

                fd = sys.stdin.fileno()
                old_settings = termios.tcgetattr(fd)
                tty.setcbreak(fd)

                def get_key_posix():
                    r, _, _ = select.select([sys.stdin], [], [], 0.1)
                    if r:
                        return sys.stdin.read(1).lower()
                    return None

                try:
                    while not self.shutdown_event.is_set():
                        key = await asyncio.to_thread(get_key_posix)
                        if key:
                            await self._process_key(key)
                        await asyncio.sleep(0.05)
                finally:
                    termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
            except Exception:
                pass

    async def _process_key(self, key: str) -> None:
        """Обработка нажатия конкретной клавиши."""
        if key == "q":
            self.shutdown_event.set()
        elif key == "s":
            if not self.ui.speedtest_running:
                asyncio.create_task(self.run_manual_speedtest())
        elif key == "t":
            if not self.ui.traceroute_running:
                gw = self.collector.system_info.gateway_ip or "1.1.1.1"
                asyncio.create_task(self._trigger_auto_traceroute(gw))
        elif key == "e":
            j_path = self.storage.export_json()
            c_path = self.storage.export_csv()
            self.ui.last_export_message = f"Отчеты сохранены: {j_path.name}, {c_path.name}"
        elif key == "w":
            if self.config.web.enabled:
                url = f"http://{self.config.web.host}:{self.config.web.port}"
                webbrowser.open(url)

    async def start(self) -> None:
        """Запуск приложения и всех параллельных сервисов."""
        diag_task = asyncio.create_task(self._diagnostics_task())
        ping_task = asyncio.create_task(self._ping_loop())
        key_task = asyncio.create_task(self._keyboard_listener())

        web_task = None
        if self.config.web.enabled:
            if FASTAPI_AVAILABLE:
                import uvicorn
                app = create_web_app(
                    config=self.config,
                    collector=self.collector,
                    storage=self.storage,
                    speedtest_callback=self.run_manual_speedtest,
                    traceroute_callback=self._trigger_auto_traceroute,
                )
                server_config = uvicorn.Config(
                    app=app,
                    host=self.config.web.host,
                    port=self.config.web.port,
                    log_level="critical",
                )
                server = uvicorn.Server(server_config)
                web_task = asyncio.create_task(server.serve())
            else:
                self.standalone_web_server = StandaloneWebServer(
                    config=self.config,
                    collector=self.collector,
                    storage=self.storage,
                    speedtest_callback=self.run_manual_speedtest,
                )
                web_task = asyncio.create_task(asyncio.to_thread(self.standalone_web_server.start_sync))

        # Рендеринг Rich Live интерфейса
        try:
            with Live(self.ui.render(), console=self.console, refresh_per_second=4, screen=False) as live:
                while not self.shutdown_event.is_set():
                    live.update(self.ui.render())
                    await asyncio.sleep(0.25)
        finally:
            # Graceful Shutdown
            self.shutdown_event.set()
            self.storage.close_session()
            
            # Автоматический экспорт итогового отчета
            json_file = self.storage.export_json()
            csv_file = self.storage.export_csv()

            diag_task.cancel()
            ping_task.cancel()
            key_task.cancel()
            if self.standalone_web_server:
                self.standalone_web_server.shutdown()
            if web_task:
                web_task.cancel()

            self.console.print("\n[bold green]✔ Сессия NetPulse успешно завершена.[/bold green]")
            self.console.print(f"[bold cyan]📁 Итоговый отчет JSON:[/bold cyan] {json_file}")
            self.console.print(f"[bold cyan]📁 Итоговый отчет CSV:[/bold cyan] {csv_file}\n")


def parse_arguments() -> AppConfig:
    """Парсинг аргументов командной строки."""
    parser = argparse.ArgumentParser(
        description="NetPulse — Легковесный инструмент мониторинга качества сетевого соединения в реальном времени"
    )
    parser.add_argument(
        "-H", "--hosts",
        type=str,
        help="Список хостов через запятую для мониторинга (e.g. '1.1.1.1,8.8.8.8,google.com')"
    )
    parser.add_argument(
        "-i", "--interval",
        type=float,
        default=1.0,
        help="Интервал проверки в секундах (по умолчанию 1.0s)"
    )
    parser.add_argument(
        "-t", "--timeout",
        type=float,
        default=2.0,
        help="Таймаут одного пинга в секундах (по умолчанию 2.0s)"
    )
    parser.add_argument(
        "-m", "--mode",
        choices=["auto", "tcp", "icmp", "subprocess"],
        default="auto",
        help="Режим проверки доступности хостов (по умолчанию auto)"
    )
    parser.add_argument(
        "-w", "--web",
        action="store_true",
        help="Запустить встроенный Web Dashboard"
    )
    parser.add_argument(
        "-p", "--port",
        type=int,
        default=8080,
        help="Порт Web Dashboard (по умолчанию 8080)"
    )
    parser.add_argument(
        "-s", "--sound",
        action="store_true",
        help="Включить звуковые оповещения при сбоях"
    )

    args = parser.parse_args()
    config = AppConfig()
    config.ping_interval = args.interval
    config.ping_timeout = args.timeout
    config.ping_mode = PingMode(args.mode)
    config.sound_alerts = args.sound
    config.web.enabled = args.web
    config.web.port = args.port

    if args.hosts:
        custom_targets = []
        for h in args.hosts.split(","):
            h = h.strip()
            if h:
                custom_targets.append(HostTarget(name=h, address=h))
        if custom_targets:
            config.targets = custom_targets

    return config


def main():
    """Точка входа в программу."""
    config = parse_arguments()
    app = NetPulseApplication(config)

    # Регистрация системных сигналов
    def signal_handler(*_):
        app.shutdown_event.set()

    if platform.system().lower() != "windows":
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, signal_handler)
        try:
            loop.run_until_complete(app.start())
        finally:
            loop.close()
    else:
        try:
            asyncio.run(app.start())
        except (KeyboardInterrupt, SystemExit):
            pass


if __name__ == "__main__":
    main()
