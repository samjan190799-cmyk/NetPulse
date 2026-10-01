"""
Интерактивный терминальный интерфейс (TUI) на базе библиотеки Rich.
"""
import platform
import threading
import time
from datetime import datetime
from typing import List, Optional
from rich.console import Console, Group
from rich.markup import escape
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from config.settings import AppConfig
from metrics.collector import MetricsCollector
from metrics.models import AlertSeverity, SpeedtestResult, TracerouteHop

# Сколько секунд после завершения трассировки её результат показывается вместо журнала алертов
TRACE_PANEL_TTL_S = 60.0


class TerminalUI:
    """Терминальный интерфейс мониторинга NetPulse в реальном времени."""

    def __init__(self, config: AppConfig, collector: MetricsCollector, console: Optional[Console] = None):
        self.config = config
        self.collector = collector
        # Общая консоль с Live-дисплеем: звук и вывод должны идти через ту же консоль
        self.console = console or Console()
        self.start_time = datetime.now()

        # Состояние интерактивных операций
        self.speedtest_running = False
        self.speedtest_status_text = "Готов к замеру [нажмите S]"
        self.last_speedtest: Optional[SpeedtestResult] = None

        self.traceroute_running = False
        self.traceroute_target: str = ""
        self.traceroute_hops: List[TracerouteHop] = []
        self.traceroute_error: Optional[str] = None
        self.traceroute_finished_at: Optional[float] = None

        # Флаг уведомления об экспорте / ошибках
        self.last_export_message: Optional[str] = None
        self.web_error: Optional[str] = None
        self.diagnostics_finished = False
        self.is_running = True

    # ---- шапка ----------------------------------------------------------------

    def _connectivity_markup(self, uptime_seconds: int) -> str:
        """Реальный индикатор связи: ONLINE, если отвечает хотя бы один узел (а не просто «прошла секунда»)."""
        stats = [s for s in self.collector.get_all_stats() if s.sent_count > 0]
        if not stats:
            return "[yellow]INITIALIZING...[/yellow]"
        if any(s.last_latency_ms is not None for s in stats):
            return "[bold bright_green]● ONLINE[/bold bright_green]"
        return "[bold bright_red]● OFFLINE[/bold bright_red]"

    def build_header(self) -> Panel:
        """Построение верхнего информационного баннера с сетевой топологией."""
        info = self.collector.system_info
        uptime_seconds = int((datetime.now() - self.start_time).total_seconds())
        m, s = divmod(uptime_seconds, 60)
        h, m = divmod(m, 60)
        uptime_str = f"{h:02d}:{m:02d}:{s:02d}"

        grid = Table.grid(expand=True, padding=(0, 2))
        grid.add_column(justify="left", ratio=3)
        grid.add_column(justify="center", ratio=3)
        grid.add_column(justify="right", ratio=2)

        gateway_text = info.gateway_ip or ("не определён" if self.diagnostics_finished else "Определение...")

        left_text = Text()
        left_text.append("🌐 Локальный IP: ", style="bold cyan")
        left_text.append(f"{info.local_ip}  ", style="white")
        left_text.append("🚪 Шлюз: ", style="bold cyan")
        left_text.append(f"{gateway_text}  ", style="bright_yellow")

        mid_text = Text()
        mid_text.append("🌍 Публичный IP: ", style="bold magenta")
        mid_text.append(f"{info.public_ip or '...'} ", style="white")
        if info.isp_name:
            mid_text.append(f"({info.isp_name})", style="italic bright_black")

        right_text = Text()
        right_text.append("⏱ Аптайм: ", style="bold green")
        right_text.append(uptime_str, style="bold white")

        grid.add_row(left_text, mid_text, right_text)

        dns_str = escape(", ".join(info.dns_servers[:3])) if info.dns_servers else (
            "не определены" if self.diagnostics_finished else "Auto")
        sub_grid = Table.grid(expand=True, padding=(0, 2))
        sub_grid.add_column(justify="left")
        sub_grid.add_column(justify="right")
        sub_grid.add_row(
            Text.from_markup(f"[bold blue]📡 DNS:[/bold blue] [white]{dns_str}[/white] | [bold blue]Режим:[/bold blue] [cyan]{self.config.ping_mode.value.upper()}[/cyan]"),
            Text.from_markup(self._connectivity_markup(uptime_seconds))
        )

        return Panel(
            Group(grid, sub_grid),
            title="[bold bright_green]❯❯[/bold bright_green][bold bright_cyan]━▲━ NetPulse[/bold bright_cyan] [dim]|[/dim] [italic bright_white]Network Motion & Quality Telemetry v1.0[/italic bright_white]",
            border_style="bright_blue",
            padding=(0, 1)
        )

    # ---- таблица хостов ---------------------------------------------------------

    def build_hosts_table(self) -> Table:
        """Построение основной таблицы мониторинга целевых хостов."""
        table = Table(
            expand=True,
            border_style="cyan",
            header_style="bold bright_white on dark_blue",
            row_styles=["none", "dim"],
            show_edge=True,
        )

        table.add_column("Статус", justify="center", width=8)
        table.add_column("Целевой узел", justify="left", ratio=3)
        table.add_column("Адрес / IP", justify="left", ratio=2)
        table.add_column("RTT (мс)", justify="right", width=9)
        table.add_column("Min/Avg/Max", justify="right", width=16)
        table.add_column("P50 / P95 / P99", justify="right", width=17)
        table.add_column("Джиттер (RFC 3550)", justify="right", width=18)
        table.add_column("Потери (Окно/Все)", justify="right", width=17)
        table.add_column("История RTT", justify="center", width=16)

        stats_list = self.collector.get_all_stats()

        if not stats_list:
            table.add_row("⏳", "Инициализация списка хостов...", "", "", "", "", "", "", "")
            return table

        for stats in stats_list:
            # Иконка и цвет статуса
            if stats.status == "OK":
                status_markup = "[bold green]🟢 OK[/bold green]"
            elif stats.status == "WARN":
                status_markup = "[bold yellow]🟡 WARN[/bold yellow]"
            elif stats.status == "CRIT":
                status_markup = "[bold red]🔴 CRIT[/bold red]"
            elif stats.status == "DOWN":
                status_markup = "[bold bright_red]⭕ DOWN[/bold bright_red]"
            else:
                status_markup = "[dim]⚪ INIT[/dim]"

            # Текущий RTT
            if stats.last_latency_ms is not None:
                if stats.last_latency_ms > self.config.thresholds.latency_crit_ms:
                    rtt_str = f"[bold red]{stats.last_latency_ms:.1f}[/bold red]"
                elif stats.last_latency_ms > self.config.thresholds.latency_warn_ms:
                    rtt_str = f"[bold yellow]{stats.last_latency_ms:.1f}[/bold yellow]"
                else:
                    rtt_str = f"[bold green]{stats.last_latency_ms:.1f}[/bold green]"
            else:
                rtt_str = "[bold red]LOST[/bold red]" if stats.sent_count > 0 else "-"

            # Min / Avg / Max
            if stats.min_latency_ms is not None:
                min_max_str = f"{stats.min_latency_ms:.0f}/{stats.avg_latency_ms:.0f}/{stats.max_latency_ms:.0f}"
            else:
                min_max_str = "-/-/-"

            # P50 / P95 / P99
            if stats.p95_latency_ms is not None and stats.p50_latency_ms is not None:
                percentiles_str = f"{stats.p50_latency_ms:.0f} / {stats.p95_latency_ms:.0f} / {stats.p99_latency_ms:.0f}"
            else:
                percentiles_str = "- / - / -"

            # Jitter
            if stats.jitter_ms > self.config.thresholds.jitter_crit_ms:
                jitter_str = f"[bold red]{stats.jitter_ms:.1f} мс[/bold red]"
            elif stats.jitter_ms > self.config.thresholds.jitter_warn_ms:
                jitter_str = f"[bold yellow]{stats.jitter_ms:.1f} мс[/bold yellow]"
            else:
                jitter_str = f"[green]{stats.jitter_ms:.1f} мс[/green]"

            # Потери: «окно» — по всему скользящему окну истории, «все» — за сессию
            loss_window = f"{stats.loss_window_pct:.1f}%"
            loss_total = f"{stats.loss_rate_pct:.1f}%"
            if stats.loss_recent_pct > self.config.thresholds.loss_crit_pct:
                loss_str = f"[bold red]{loss_window}[/bold red] ([dim]{loss_total}[/dim])"
            elif stats.loss_recent_pct > self.config.thresholds.loss_warn_pct:
                loss_str = f"[bold yellow]{loss_window}[/bold yellow] ([dim]{loss_total}[/dim])"
            else:
                loss_str = f"[green]{loss_window}[/green] ([dim]{loss_total}[/dim])"

            # Sparkline (экранируем: символы графика не содержат разметки, но подстраховываемся)
            spark = f"[cyan]{escape(stats.sparkline)}[/cyan]"

            host_display = escape(stats.name)
            if stats.is_gateway:
                host_display = f"⭐ {host_display}"

            table.add_row(
                status_markup,
                host_display,
                escape(stats.address),
                rtt_str,
                min_max_str,
                percentiles_str,
                jitter_str,
                loss_str,
                spark,
            )

        return table

    # ---- нижняя секция ------------------------------------------------------------

    def _trace_panel_visible(self) -> bool:
        if self.traceroute_running:
            return True
        if not (self.traceroute_hops or self.traceroute_error):
            return False
        if self.traceroute_finished_at is None:
            return True
        return (time.monotonic() - self.traceroute_finished_at) < TRACE_PANEL_TTL_S

    def build_bottom_panels(self) -> Table:
        """Построение нижней секции: журнал алертов/трассировки и виджет Speedtest."""
        grid = Table.grid(expand=True, padding=(0, 1))
        grid.add_column(ratio=6)
        grid.add_column(ratio=4)

        # Левая панель: вывод MTR / Traceroute (временно) или журнал алертов
        if self._trace_panel_visible():
            trace_table = Table(expand=True, show_header=True, header_style="bold magenta", box=None)
            trace_table.add_column("#", width=3)
            trace_table.add_column("IP Узла", ratio=3)
            trace_table.add_column("RTT (мс)", justify="right", width=9)
            trace_table.add_column("Loss %", justify="right", width=8)

            for hop in self.traceroute_hops[-6:]:
                lat = f"{hop.latency_ms:.1f}" if hop.latency_ms is not None else "*"
                trace_table.add_row(
                    str(hop.hop_num),
                    escape(hop.ip_address or "*"),
                    lat,
                    f"{hop.loss_pct:.0f}%"
                )

            if self.traceroute_running:
                status_icon = "⏳ Трассировка в процессе..."
            elif self.traceroute_error and not self.traceroute_hops:
                status_icon = "⚠ Не выполнена"
            else:
                status_icon = "✅ Трассировка завершена"

            body = trace_table
            if self.traceroute_error and not self.traceroute_running:
                body = Group(trace_table, Text(self.traceroute_error, style="yellow"))

            left_panel = Panel(
                body,
                title=f"[bold magenta]📍 Traceroute MTR ({escape(self.traceroute_target) or 'шлюз'}) — {status_icon}[/bold magenta]",
                border_style="magenta",
            )
        else:
            alerts = self.collector.get_recent_alerts(limit=5)
            if alerts:
                alert_text = Text()
                for a in reversed(alerts):
                    ts_str = a.timestamp.strftime("%H:%M:%S")
                    if a.severity == AlertSeverity.CRITICAL:
                        style = "bold red"
                    elif a.severity == AlertSeverity.INFO:
                        style = "bold green"
                    else:
                        style = "yellow"
                    alert_text.append(f"[{ts_str}] ", style="dim")
                    alert_text.append(f"[{a.severity.value.upper()}] ", style=style)
                    alert_text.append(f"{a.message}\n", style="white")
            else:
                alert_text = Text("Аномалий и сбоев соединения не зафиксировано. Сеть стабильна.\n", style="green")

            left_panel = Panel(
                alert_text,
                title="[bold yellow]🔔 Журнал сетевых алертов и аномалий[/bold yellow]",
                border_style="yellow",
            )

        # Правая панель: Speedtest
        speed_table = Table.grid(expand=True, padding=(0, 1))
        speed_table.add_column(justify="left", ratio=1)
        speed_table.add_column(justify="right", ratio=1)

        last = self.last_speedtest
        dl_val = f"[bold green]{last.download_mbps:.1f} Mbps[/bold green]" if last and last.download_mbps > 0 else "[dim]--[/dim]"
        ul_val = f"[bold cyan]{last.upload_mbps:.1f} Mbps[/bold cyan]" if last and last.upload_mbps > 0 else "[dim]--[/dim]"

        speed_table.add_row(Text("📥 Скачивание:"), Text.from_markup(dl_val))
        speed_table.add_row(Text("📤 Отдача:"), Text.from_markup(ul_val))
        # speedtest_status_text формируется приложением (содержит собственную разметку и уже экранированный текст ошибок)
        speed_table.add_row(Text("⚡ Статус:"), Text.from_markup(f"[italic]{self.speedtest_status_text}[/italic]"))

        right_panel = Panel(
            speed_table,
            title="[bold green]🚀 Throughput & Speedtest[/bold green]",
            border_style="green",
        )

        grid.add_row(left_panel, right_panel)
        return grid

    def build_footer(self) -> Panel:
        """Построение панели горячих клавиш и статуса экспорта."""
        footer_grid = Table.grid(expand=True, padding=(0, 1))
        footer_grid.add_column(justify="left", ratio=4)
        footer_grid.add_column(justify="right", ratio=2)

        keys_text = Text()
        keys_text.append("Горячие клавиши: ", style="bold yellow")
        keys_text.append("[S] ", style="bold bright_green")
        keys_text.append("Тест скорости  ", style="white")
        keys_text.append("[T] ", style="bold magenta")
        keys_text.append("Traceroute  ", style="white")
        keys_text.append("[E] ", style="bold cyan")
        keys_text.append("Экспорт отчета  ", style="white")
        keys_text.append("[Q] ", style="bold red")
        keys_text.append("Выход", style="white")

        if self.web_error:
            msg_markup = f"[bold yellow]{escape(self.web_error)}[/bold yellow]"
        else:
            msg = self.last_export_message or "Нажмите [Q] для завершения сессии"
            msg_markup = f"[bold cyan]{escape(msg)}[/bold cyan]"
        footer_grid.add_row(keys_text, Text.from_markup(msg_markup))

        return Panel(footer_grid, border_style="bright_black", padding=(0, 1))

    def render(self) -> Group:
        """Сборка всего TUI-дашборда в единую структуру Rich Group."""
        return Group(
            self.build_header(),
            self.build_hosts_table(),
            self.build_bottom_panels(),
            self.build_footer()
        )

    def trigger_sound_alert(self) -> None:
        """
        Звуковое оповещение при сбое.

        POSIX: через console.bell(): запись в sys.stdout при активном Rich Live перехватывается
        и управляющий символ BEL отбрасывается — звука не было. Windows: Beep в отдельном потоке
        (winsound.Beep блокирует на 200 мс, а вызывается из цикла событий).
        """
        if not self.config.sound_alerts:
            return
        try:
            if platform.system().lower() == "windows":
                import winsound
                threading.Thread(target=winsound.Beep, args=(1000, 200), daemon=True).start()
            else:
                self.console.bell()
        except Exception:
            pass
