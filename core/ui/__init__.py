"""
Пользовательские интерфейсы NetPulse (Rich TUI и Web Dashboard).
"""
from ui.tui import TerminalUI
from ui.web import FASTAPI_AVAILABLE, StandaloneWebServer, create_web_app

__all__ = ["TerminalUI", "StandaloneWebServer", "create_web_app", "FASTAPI_AVAILABLE"]
