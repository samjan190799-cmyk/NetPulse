# ⚡ NetPulse — Real-Time Network Quality Monitor

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Python: 3.11+](https://img.shields.io/badge/Python-3.11%2B-brightgreen.svg)](https://www.python.org/)
[![Swift: 6.0+](https://img.shields.io/badge/Swift-6.0%2B-orange.svg)](https://swift.org)
[![iOS: 17.0+](https://img.shields.io/badge/iOS-17.0%2B-purple.svg)](https://developer.apple.com/ios/)
[![TestFlight: Ready](https://img.shields.io/badge/TestFlight-v1.0.0-blue.svg)](https://appstoreconnect.apple.com/)
[![CI/CD: GitHub Actions](https://img.shields.io/badge/CI%2FCD-Active-success.svg)](.github/workflows/testflight.yml)

**NetPulse** — это кроссплатформенный набор легковесных, высокопроизводительных инструментов для мониторинга качества сетевого соединения в реальном времени, анализа стабильности каналов связи, расчета джиттера по стандарту **RFC 3550**, потокового замера скорости (Speedtest) и автоматической MTR-трассировки.

---

## 📂 Структура репозитория

```
NetPulse/
├── core/                         # 🐍 Python 3.11+ Core, Rich TUI & Web Dashboard
│   ├── config/                   # Конфигурация хостов, порогов и интервалов
│   ├── engine/                   # Multi-mode Ping, Network Diagnostics, Speedtest, Traceroute
│   ├── metrics/                  # Расчет Jitter RFC 3550, перцентили, SQLite хранилище
│   ├── ui/                       # Rich Live TUI в терминале и FastAPI Web Dashboard (Chart.js)
│   ├── tests/                    # Модульные и интеграционные тесты
│   ├── main.py                   # Главная точка входа
│   └── requirements.txt
│
└── ios/                          # 📱 Нативное приложение для iOS (Swift 6.0+ / SwiftUI)
    ├── Models/                   # Sendable структуры (HostTarget, PingRecord, HostMetrics)
    ├── Engines/                  # PingEngine (NWConnection), SpeedtestEngine, NetworkDiagnostics
    ├── ViewModels/               # NetworkMonitorViewModel на базе макроса @Observable
    ├── Views/                    # DashboardView, SettingsView, Swift Charts, Glassmorphism UI
    ├── Utils/                    # Тактильная отдача (HapticManager), экспорт JSON/CSV
    └── NetPulseApp.swift         # Точка входа в iOS-приложение
```

---

## 🌟 Ключевые возможности

### 1. Многопротокольный Ping Engine
- **Параллельный опрос узлов**: непрерывная проверка ключевых DNS-серверов (Cloudflare `1.1.1.1`, Google `8.8.8.8`, Yandex `77.88.8.8`, Quad9 `9.9.9.9`) и локального шлюза.
- **Поддержка режимов**: `TCP Connect Ping` (работает без повышенных привилегий root/Admin), `Raw ICMP Socket` и `Subprocess Ping` с авто-фолбеком.

### 2. Математический анализ качества (RFC 3550 Jitter & Latency)
- Строгий расчет межпакетного джиттера по стандарту **RFC 3550**:
  $$J_i = J_{i-1} + \frac{|D(i-1, i)| - J_{i-1}}{16}$$
- Аналитика перцентилей задержки (**P50 / Median**, **P95**, **P99**), Min/Avg/Max RTT.
- Подсчет процента потерь пакетов (**Packet Loss %**) в скользящем окне и за сессию.

### 3. Авто-MTR / Traceroute
- Автоматический запуск трассировки маршрута при фиксации скачка задержки (> 150 мс) или потерь пакетов (> 5%) для точной локализации проблемного узла.

### 4. Измерение пропускной способности (Bandwidth & Speedtest)
- Встроенный потоковый замер скорости скачивания (**Download Mbps**) и отдачи (**Upload Mbps**) через CDN-эндпоинты Cloudflare без использования тяжелых внешних утилит.

### 5. Премиальный UX / UI
- **Terminal (Rich TUI)**: Интерактивный терминальный интерфейс с Unicode/Braille sparklines, журналом алертов и горячими клавишами.
- **Web Dashboard**: Glassmorphism темная панель с живыми графиками на базе **Chart.js**.
- **iOS App**: Нативный SwiftUI интерфейс с поддержкой **Swift Charts**, эффектами глубокого стекла (`.ultraThinMaterial`) и тактильной отдачей (**Haptic Feedback**).

---

## 🚀 Быстрый старт

### 🐍 Запуск Python-версии (CLI / Web)

```bash
cd core

# Установка зависимостей (опционально)
pip install -r requirements.txt

# 1. Интерактивный TUI-монитор в терминале
python main.py

# 2. Запуск с веб-интерфейсом на порту 8080 (http://127.0.0.1:8080)
python main.py --web --port 8080

# 3. Мониторинг пользовательских хостов
python main.py --hosts "1.1.1.1,8.8.8.8,google.com" --interval 0.5

# 4. Запуск тестов
python -m unittest discover tests
```

#### Горячие клавиши в терминале:
* `[S]` — Запуск Speedtest (Download/Upload)
* `[T]` — Запуск Traceroute / MTR
* `[E]` — Экспорт отчетов сессии в `.json` и `.csv`
* `[W]` — Открыть Web Dashboard в браузере
* `[Q]` — Безопасный выход (Graceful Shutdown)

---

### 📱 Запуск iOS-версии (Swift 6.0+ / SwiftUI)

1. Откройте **Xcode 16+** на macOS.
2. Создайте новый проект (*iOS -> App -> SwiftUI*).
3. Перенесите файлы из папки `ios/` в проект Xcode.
4. Скомпилируйте и запустите на симуляторе iPhone 15 Pro / iPhone 16 или реальном устройстве (**Cmd + R**).

---

## 📄 Лицензия

Проект распространяется под лицензией [MIT](LICENSE).
