"""
NetPulse — Высокопроизводительный инструмент мониторинга качества сети в реальном времени.
Точка входа и оркестратор асинхронных подсистем.
"""
import argparse
import asyncio
import contextlib
import os
import platform
import signal
import socket
import sys
import time
import webbrowser
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

from rich.console import Console
from rich.live import Live
from rich.markup import escape

from config.settings import GATEWAY_PLACEHOLDER, AppConfig, HostTarget, PingMode
from engine.diagnostics import NetworkDiagnostics
from engine.ping import AsyncPingEngine
from engine.speedtest import AsyncSpeedtestEngine
from engine.traceroute import AsyncTracerouteEngine
from metrics.collector import MetricsCollector
from metrics.models import AlertSeverity, NetworkAlert, PingResult, SpeedtestResult
from metrics.storage import StorageManager
from ui.tui import TerminalUI
from ui.web import FASTAPI_AVAILABLE, StandaloneWebServer, create_web_app

GATEWAY_WATCH_INTERVAL_S = 30.0


class NetPulseApplication:
    """Главный оркестратор приложения NetPulse."""

    def __init__(self, config: AppConfig):
        self.config = config
        self.console = Console()
        self.shutdown_event = asyncio.Event()
        self.exit_code = 0

        # Инициализация хранилища и сборщика метрик
        self.storage = StorageManager(db_path=config.db_path)
        self.collector = MetricsCollector(
            thresholds=config.thresholds,
            window_size=config.history_window_size,
            on_alert_callback=self._handle_alert,
            alert_cooldown_s=config.alert_cooldown_s,
            status_window=config.status_window_size,
        )
        self.ping_engine = AsyncPingEngine(mode=config.ping_mode, timeout=config.ping_timeout)
        self.speedtest_engine = AsyncSpeedtestEngine()
        self.traceroute_engine = AsyncTracerouteEngine()
        # TUI использует ту же консоль, что и Live-дисплей (иначе звук/вывод идут мимо него)
        self.ui = TerminalUI(config=config, collector=self.collector, console=self.console)

        # Регистрация хостов
        for target in self.config.targets:
            self.collector.register_host(target.name, target.address, is_gateway=target.is_gateway)

        # Состояние фоновых задач
        # True с момента, когда трассировка ЗАПЛАНИРОВАНА, и до её завершения. Ставится синхронно:
        # иначе несколько алертов из одного батча проверок запустили бы несколько трассировок разом.
        self.auto_trace_in_progress = False
        self._last_auto_trace: Dict[str, float] = {}
        self.standalone_web_server: Optional[StandaloneWebServer] = None
        self._uvicorn_server = None
        self._tasks: Set[asyncio.Task] = set()
        self._pending_alerts: List[NetworkAlert] = []
        self._trace_lock = asyncio.Lock()

    # ---- служебное -----------------------------------------------------------

    def _spawn(self, coro, name: Optional[str] = None) -> asyncio.Task:
        """create_task с удержанием ссылки (иначе задачу может собрать GC) и разбором ошибок."""
        task = asyncio.get_running_loop().create_task(coro, name=name)
        self._tasks.add(task)
        task.add_done_callback(self._on_task_done)
        return task

    def _on_task_done(self, task: asyncio.Task) -> None:
        self._tasks.discard(task)
        if task.cancelled():
            return
        exc = task.exception()
        if exc is not None:
            self.ui.last_export_message = f"Ошибка задачи «{task.get_name()}»: {exc}"

    # ---- алерты и трассировка ----------------------------------------------------

    def _handle_alert(self, alert: NetworkAlert) -> None:
        """Обработчик сетевых аномалий. Вызывается коллектором синхронно, в потоке цикла событий."""
        # Запись в БД — пачкой в _ping_loop (в потоке), а не синхронно по алерту
        self._pending_alerts.append(alert)

        if alert.severity == AlertSeverity.INFO:
            return  # «узел восстановлен» — не повод ни для звука, ни для трассировки

        self.ui.trigger_sound_alert()
        if alert.severity == AlertSeverity.CRITICAL and self.config.auto_traceroute_on_alert:
            self._maybe_start_auto_traceroute(alert.host)

    def _maybe_start_auto_traceroute(self, target_host: str) -> None:
        if target_host == GATEWAY_PLACEHOLDER or not target_host:
            return
        if self.auto_trace_in_progress or self.ui.traceroute_running:
            return
        now = time.monotonic()
        last = self._last_auto_trace.get(target_host)
        if last is not None and now - last < self.config.auto_traceroute_cooldown_s:
            return
        self._last_auto_trace[target_host] = now
        self._start_traceroute(target_host)

    def _start_traceroute(self, target_host: str) -> None:
        self.auto_trace_in_progress = True  # синхронно: см. комментарий в __init__
        self._spawn(self._run_traceroute(target_host), name="traceroute")

    async def _run_traceroute(self, target_host: str) -> None:
        """Трассировка с отображением хопов в TUI. Одновременно выполняется не более одной."""
        try:
            async with self._trace_lock:
                self.ui.traceroute_running = True
                self.ui.traceroute_target = target_host
                self.ui.traceroute_hops = []
                self.ui.traceroute_error = None
                self.ui.traceroute_finished_at = None

                def on_hop(hop):
                    self.ui.traceroute_hops.append(hop)

                try:
                    hops = await self.traceroute_engine.trace(target_host, on_hop_callback=on_hop)
                    self.ui.traceroute_hops = hops
                    self.ui.traceroute_error = self.traceroute_engine.last_error
                except asyncio.CancelledError:
                    raise
                except Exception as e:
                    self.ui.traceroute_error = f"Ошибка трассировки: {e}"
                finally:
                    self.ui.traceroute_running = False
                    self.ui.traceroute_finished_at = time.monotonic()
        finally:
            self.auto_trace_in_progress = False

    # ---- speedtest ---------------------------------------------------------------

    async def run_manual_speedtest(self) -> SpeedtestResult:
        """
        Ручной запуск теста скорости из TUI или Web API.

        Если замер уже идёт — возвращается результат со статусом BUSY (а не устаревший прошлый).
        Ошибка замера не пробрасывается исключением: возвращается результат со статусом FAILED.
        """
        if self.ui.speedtest_running:
            return SpeedtestResult(timestamp=datetime.now(), download_mbps=0, upload_mbps=0, status="BUSY")

        self.ui.speedtest_running = True   # до первого await: цикл событий однопоточный, гонки нет
        self.ui.speedtest_status_text = "Идет замер скачивания..."

        def progress_cb(stage: str, mbps: float):
            if stage == "download":
                self.ui.speedtest_status_text = f"Загрузка: [bold green]{mbps:.1f} Mbps[/bold green]"
            elif stage == "upload":
                self.ui.speedtest_status_text = f"Отдача: [bold cyan]{mbps:.1f} Mbps[/bold cyan]"

        try:
            res = await self.speedtest_engine.run_full_speedtest(progress_cb=progress_cb)
        except asyncio.CancelledError:
            raise
        except Exception as e:
            self.ui.speedtest_status_text = f"Ошибка: {escape(str(e)[:60])}"
            return SpeedtestResult(timestamp=datetime.now(), download_mbps=0, upload_mbps=0, status="FAILED")
        finally:
            self.ui.speedtest_running = False

        if res.status == "FAILED":
            self.ui.speedtest_status_text = "Замер не удался: нет связи с серверами скорости"
        else:
            self.ui.last_speedtest = res
            if res.status == "PARTIAL":
                self.ui.speedtest_status_text = f"Скачивание {res.download_mbps:.1f} Mbps; отдачу измерить не удалось"
            else:
                self.ui.speedtest_status_text = f"Готово ({res.download_mbps:.1f} / {res.upload_mbps:.1f} Mbps)"
        try:
            await asyncio.to_thread(self.storage.record_speedtest, res)
        except Exception as e:
            self.ui.last_export_message = f"Не удалось сохранить результат замера: {e}"
        return res

    # ---- диагностика и опрос -----------------------------------------------------------

    def _apply_gateway(self, gateway_ip: Optional[str]) -> None:
        """Подстановка реального адреса шлюза в мониторинг (заглушка → IP; смена сети → новый IP)."""
        if not gateway_ip or gateway_ip == "127.0.0.1":
            return
        self.collector.update_gateway_address(gateway_ip)
        explicit = {t.address for t in self.config.targets if not t.is_gateway}
        for t in self.config.targets:
            if t.is_gateway:
                t.address = gateway_ip
                # шлюз уже есть в списке как обычный узел — один адрес не опрашиваем дважды
                t.enabled = gateway_ip not in explicit

    async def _diagnostics_task(self) -> None:
        """Фоновый сбор информации о сети и провайдере без задержки старта пинга."""
        try:
            sys_info = await NetworkDiagnostics.collect_full_info()
            self.collector.system_info = sys_info
            self._apply_gateway(sys_info.gateway_ip)
            await asyncio.to_thread(self.storage.start_session, sys_info)
        except asyncio.CancelledError:
            raise
        except Exception as e:
            self.ui.last_export_message = f"Диагностика сети не удалась: {e}"
        finally:
            self.ui.diagnostics_finished = True

    async def _gateway_watch_task(self) -> None:
        """Раз в 30 с проверяет шлюз по умолчанию (чтение таблицы маршрутов, без сетевых запросов): сеть могла смениться."""
        while not self.shutdown_event.is_set():
            try:
                await asyncio.wait_for(self.shutdown_event.wait(), timeout=GATEWAY_WATCH_INTERVAL_S)
                return
            except asyncio.TimeoutError:
                pass
            try:
                gw, _iface = await NetworkDiagnostics.get_gateway_and_interface()
                if gw and gw != self.collector.system_info.gateway_ip:
                    self.collector.system_info.gateway_ip = gw
                    self._apply_gateway(gw)
            except asyncio.CancelledError:
                raise
            except Exception:
                pass

    async def _ping_loop(self) -> None:
        """Основной непрерывный цикл параллельного пинга."""
        loop = asyncio.get_running_loop()
        while not self.shutdown_event.is_set():
            start_tick = loop.time()
            batch: List[PingResult] = []
            try:
                # Результаты записываются по мере готовности: быстрые узлы не ждут самый медленный
                async for res in self.ping_engine.ping_stream(self.config.targets):
                    batch.append(res)
                    self.collector.record_result(res)

                alerts, self._pending_alerts = self._pending_alerts, []
                try:
                    await asyncio.to_thread(self.storage.record_batch, batch, alerts)
                except Exception:
                    self._pending_alerts[:0] = alerts   # не теряем алерты при сбое записи
                    raise
            except asyncio.CancelledError:
                raise
            except Exception as e:
                # Любая ошибка итерации не должна «молча» убивать цикл опроса
                self.ui.last_export_message = f"Ошибка цикла опроса: {e}"

            elapsed = loop.time() - start_tick
            sleep_time = max(0.05, self.config.ping_interval - elapsed)

            try:
                await asyncio.wait_for(self.shutdown_event.wait(), timeout=sleep_time)
                break
            except asyncio.TimeoutError:
                pass

    # ---- клавиатура ---------------------------------------------------------------------

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
                    await self._safe_process_key(key)
                await asyncio.sleep(0.1)
            return

        # Unix / POSIX
        try:
            import select
            import termios
            import tty

            fd = sys.stdin.fileno()
            if not os.isatty(fd):
                return  # stdin не терминал (pipe, служба): горячие клавиши недоступны, но мониторинг работает
            old_settings = termios.tcgetattr(fd)
            tty.setcbreak(fd)
        except Exception:
            return

        def read_keys() -> str:
            # os.read, а не sys.stdin.read: буфер TextIOWrapper не виден select(), и при быстром
            # наборе часть нажатий «застревала» до следующей клавиши
            r, _, _ = select.select([fd], [], [], 0.1)
            if not r:
                return ""
            try:
                return os.read(fd, 64).decode("utf-8", errors="ignore").lower()
            except OSError:
                return ""

        try:
            while not self.shutdown_event.is_set():
                for key in await asyncio.to_thread(read_keys):
                    await self._safe_process_key(key)
                await asyncio.sleep(0.02)
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

    async def _safe_process_key(self, key: str) -> None:
        """Ошибка в обработчике клавиши не должна останавливать слушатель (иначе 'q' перестаёт работать)."""
        try:
            await self._process_key(key)
        except asyncio.CancelledError:
            raise
        except Exception as e:
            self.ui.last_export_message = f"Ошибка команды «{key}»: {e}"

    def _export_reports(self) -> Tuple[Path, Path]:
        return self.storage.export_json(), self.storage.export_csv()

    async def _process_key(self, key: str) -> None:
        """Обработка нажатия конкретной клавиши."""
        if key == "q":
            self.shutdown_event.set()
        elif key == "s":
            if not self.ui.speedtest_running:
                self._spawn(self.run_manual_speedtest(), name="speedtest")
        elif key == "t":
            if not self.ui.traceroute_running and not self.auto_trace_in_progress:
                gw = self.collector.system_info.gateway_ip or "1.1.1.1"
                self._start_traceroute(gw)
        elif key == "e":
            try:
                j_path, c_path = await asyncio.to_thread(self._export_reports)
                self.ui.last_export_message = f"Отчеты сохранены: {j_path.name}, {c_path.name}"
            except Exception as e:
                self.ui.last_export_message = f"Экспорт не удался: {e}"
        elif key == "w":
            if self.config.web.enabled:
                url = f"http://{self.config.web.host}:{self.config.web.port}"
                await asyncio.to_thread(webbrowser.open, url)

    # ---- веб ----------------------------------------------------------------------------

    def _check_web_port(self) -> Optional[str]:
        """None, если порт свободен; иначе текст причины. Проверка ДО запуска Live-интерфейса."""
        host, port = self.config.web.host, self.config.web.port
        family = socket.AF_INET6 if ":" in host else socket.AF_INET
        try:
            with socket.socket(family, socket.SOCK_STREAM) as s:
                if platform.system().lower() != "windows":
                    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                s.bind((host, port))
            return None
        except OSError as e:
            return f"{host}:{port} — {e.strerror or e}"

    async def _serve_uvicorn(self, server) -> None:
        try:
            await server.serve()
        except SystemExit:
            # uvicorn вызывает sys.exit(1) при ошибке запуска: не даём этому убить приложение
            self.ui.web_error = "Веб-интерфейс не запущен: не удалось занять порт"
        except asyncio.CancelledError:
            raise
        except Exception as e:
            self.ui.web_error = f"Веб-интерфейс остановлен: {e}"

    def _run_standalone_server(self) -> None:
        try:
            assert self.standalone_web_server is not None
            self.standalone_web_server.start_sync()
        except Exception as e:
            self.ui.web_error = f"Веб-интерфейс не запущен: {e}"

    def _start_web(self) -> Optional[asyncio.Task]:
        """Запуск веб-интерфейса. Возвращает задачу uvicorn (или None для standalone-сервера)."""
        if FASTAPI_AVAILABLE:
            try:
                import uvicorn
            except ImportError:
                uvicorn = None
            if uvicorn is not None:
                class _AppServer(uvicorn.Server):
                    # Сигналы обрабатывает приложение (Ctrl+C → корректное завершение с отчётом);
                    # собственные обработчики uvicorn (разные в разных версиях) отключаем.
                    def install_signal_handlers(self):  # uvicorn < 0.29
                        pass

                    @contextlib.contextmanager
                    def capture_signals(self):  # uvicorn >= 0.29
                        yield

                app = create_web_app(
                    config=self.config,
                    collector=self.collector,
                    storage=self.storage,
                    speedtest_callback=self.run_manual_speedtest,
                )
                server_config = uvicorn.Config(
                    app=app,
                    host=self.config.web.host,
                    port=self.config.web.port,
                    log_level="critical",
                )
                self._uvicorn_server = _AppServer(server_config)
                return self._spawn(self._serve_uvicorn(self._uvicorn_server), name="web")

        import threading
        self.standalone_web_server = StandaloneWebServer(
            config=self.config,
            collector=self.collector,
            storage=self.storage,
            speedtest_callback=self.run_manual_speedtest,
            loop=asyncio.get_running_loop(),
        )
        threading.Thread(target=self._run_standalone_server, name="netpulse-web", daemon=True).start()
        return None

    # ---- жизненный цикл ---------------------------------------------------------------------

    async def start(self) -> None:
        """Запуск приложения и всех параллельных сервисов."""
        if self.config.web.enabled:
            problem = self._check_web_port()
            if problem:
                self.console.print(f"[bold red]✖ Веб-интерфейс не может быть запущен:[/bold red] {escape(problem)}")
                self.console.print("Укажите другой порт: [bold]--port <номер>[/bold] (или запустите без [bold]--web[/bold]).")
                self.exit_code = 2
                await asyncio.to_thread(self.storage.close_session)
                return

        if self.config.retention_days > 0:
            with contextlib.suppress(Exception):
                await asyncio.to_thread(self.storage.purge_old, self.config.retention_days)

        self._spawn(self._diagnostics_task(), name="diagnostics")
        self._spawn(self._ping_loop(), name="ping")
        self._spawn(self._gateway_watch_task(), name="gateway-watch")
        self._spawn(self._keyboard_listener(), name="keyboard")

        web_task: Optional[asyncio.Task] = None
        if self.config.web.enabled:
            web_task = self._start_web()

        try:
            # Рендеринг Rich Live интерфейса
            with Live(self.ui.render(), console=self.console, refresh_per_second=4, screen=False) as live:
                while not self.shutdown_event.is_set():
                    live.update(self.ui.render())
                    await asyncio.sleep(0.25)
        finally:
            await self._graceful_shutdown(web_task)

    async def _graceful_shutdown(self, web_task: Optional[asyncio.Task]) -> None:
        """Остановка сервисов и сохранение отчёта. Сбой одного шага не прерывает остальные."""
        self.shutdown_event.set()

        # 1. Останавливаем веб-сервер корректно
        if self._uvicorn_server is not None:
            self._uvicorn_server.should_exit = True
        if self.standalone_web_server is not None:
            with contextlib.suppress(Exception):
                await asyncio.to_thread(self.standalone_web_server.shutdown)

        # 2. Отменяем фоновые задачи и ДОЖИДАЕМСЯ их: слушатель клавиш в finally возвращает
        #    терминал в обычный режим (иначе после выхода пропадало бы эхо ввода)
        others = [t for t in self._tasks if t is not web_task]
        for t in others:
            t.cancel()
        if others:
            await asyncio.wait(others, timeout=5.0)
        if web_task is not None and not web_task.done():
            await asyncio.wait({web_task}, timeout=3.0)
            if not web_task.done():
                web_task.cancel()
                await asyncio.wait({web_task}, timeout=2.0)

        # 3. Финализация БД и итоговые отчёты
        json_file = csv_file = None
        errors: List[str] = []
        try:
            if self._pending_alerts:
                alerts, self._pending_alerts = self._pending_alerts, []
                await asyncio.to_thread(self.storage.record_batch, [], alerts)
            await asyncio.to_thread(self.storage.close_session)
        except Exception as e:
            errors.append(f"закрытие сессии: {e}")
        try:
            json_file, csv_file = await asyncio.to_thread(self._export_reports)
        except Exception as e:
            errors.append(f"экспорт отчётов: {e}")

        self.console.print("\n[bold green]✔ Сессия NetPulse успешно завершена.[/bold green]")
        if json_file and csv_file:
            self.console.print(f"[bold cyan]📁 Итоговый отчет JSON:[/bold cyan] {escape(str(json_file))}")
            self.console.print(f"[bold cyan]📁 Итоговый отчет CSV:[/bold cyan] {escape(str(csv_file))}\n")
        for err in errors:
            self.console.print(f"[bold yellow]⚠ Не удалось выполнить {escape(err)}[/bold yellow]")


def _positive_float(value: str) -> float:
    try:
        number = float(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"ожидается число, получено {value!r}") from None
    if not (0 < number < float("inf")):
        raise argparse.ArgumentTypeError("значение должно быть больше 0")
    return number


def _port_number(value: str) -> int:
    try:
        number = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"ожидается целое число, получено {value!r}") from None
    if not 1 <= number <= 65535:
        raise argparse.ArgumentTypeError("порт должен быть в диапазоне 1–65535")
    return number


def parse_host_spec(spec: str) -> HostTarget:
    """
    «host», «host:port», «[ipv6]:port» → HostTarget. Порт задаёт TCP-порт проверки (по умолчанию 443).
    Адрес IPv6 без скобок (содержит несколько «:») считается адресом целиком.
    """
    spec = spec.strip()
    host, port = spec, 443
    if spec.startswith("[") and "]" in spec:
        host = spec[1:spec.index("]")]
        rest = spec[spec.index("]") + 1:]
        if rest.startswith(":"):
            port = _port_number(rest[1:])
    elif spec.count(":") == 1:
        host, port_text = spec.split(":", 1)
        port = _port_number(port_text)
    return HostTarget(name=spec, address=host, tcp_port=port)


def parse_arguments(argv: Optional[List[str]] = None) -> AppConfig:
    """Парсинг аргументов командной строки."""
    parser = argparse.ArgumentParser(
        description="NetPulse — Легковесный инструмент мониторинга качества сетевого соединения в реальном времени"
    )
    parser.add_argument(
        "-H", "--hosts",
        type=str,
        help="Список хостов через запятую для мониторинга (e.g. '1.1.1.1,8.8.8.8:53,google.com')"
    )
    parser.add_argument(
        "-i", "--interval",
        type=_positive_float,
        default=1.0,
        help="Интервал проверки в секундах (по умолчанию 1.0s)"
    )
    parser.add_argument(
        "-t", "--timeout",
        type=_positive_float,
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
        type=_port_number,
        default=8080,
        help="Порт Web Dashboard (по умолчанию 8080)"
    )
    parser.add_argument(
        "-s", "--sound",
        action="store_true",
        help="Включить звуковые оповещения при сбоях"
    )

    args = parser.parse_args(argv)
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
            if not h:
                continue
            try:
                custom_targets.append(parse_host_spec(h))
            except argparse.ArgumentTypeError as e:
                parser.error(f"некорректный хост {h!r}: {e}")
        if custom_targets:
            config.targets = custom_targets

    return config


def main(argv: Optional[List[str]] = None) -> int:
    """Точка входа в программу. Возвращает код выхода процесса."""
    config = parse_arguments(argv)
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
            with contextlib.suppress(Exception):
                loop.run_until_complete(loop.shutdown_asyncgens())
            loop.close()
    else:
        try:
            asyncio.run(app.start())
        except (KeyboardInterrupt, SystemExit):
            pass
    return app.exit_code


if __name__ == "__main__":
    sys.exit(main())
