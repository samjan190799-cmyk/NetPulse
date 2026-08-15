# ⚡ NetPulse iOS — Real-Time Network Quality Monitor

Нативное мобильное приложение для iOS (стандарты 2026 года), предназначенное для непрерывного мониторинга качества сетевого подключения, расчета джиттера по стандарту **RFC 3550**, замера пропускной способности (Speedtest), трассировки пути (MTR) и экспорта телеметрии.

---

## 🌟 Технологический стек и стандарты 2026 года

- **Язык программирования:** Swift 6.0+ со строгой проверкой многопоточности (**Strict Concurrency**).
- **UI-фреймворк:** **SwiftUI** (iOS 17+ / iOS 18+) на базе макроса `@Observable`.
- **Сетевой стек:** `Network.framework` (`NWConnection`, `NWPathMonitor`), асинхронные акторы (`actor`), `TaskGroup` и потоковый `URLSession.bytes`.
- **Графика и чарты:** **Swift Charts** (`import Charts`) с живыми интерактивными градиентными графиками задержки RTT и спарклайнами.
- **Премиальный UX/UI:**
  - Эффект глубокого стекла (**Glassmorphism**) с `.ultraThinMaterial`.
  - Тактильная отдача (**Haptic Feedback**) через `UIImpactFeedbackGenerator` и `UINotificationFeedbackGenerator`.
  - Анимированный неоновый спидометр (**Speedtest Gauge**).
  - Адаптивная темная тема (Dark Mode по умолчанию).
- **Экспорт данных:** Нативная интеграция с системным `UIActivityViewController` / `ShareLink` для выгрузки отчетов в **JSON** и **CSV**.

---

## 📂 Структура проекта

```
NetPulse-iOS/
├── NetPulseApp.swift             # Главная точка входа (@main, WindowGroup)
├── ContentView.swift             # Навигационный контейнер (TabView)
├── Models/
│   ├── HostTarget.swift          # Модель целевого узла (Cloudflare, Google, Gateway)
│   ├── PingRecord.swift          # Модель единичного измерения (Sendable)
│   ├── HostMetrics.swift         # Агрегированная статистика (Jitter RFC 3550, Loss, P50/P95/P99)
│   ├── NetworkInterfaceInfo.swift# Параметры Wi-Fi/Cellular, шлюз, DNS, внешний IP, ISP
│   ├── SpeedtestResult.swift     # Результаты теста скорости (Download/Upload Mbps)
│   ├── TracerouteHop.swift       # Узел пути трассировки
│   └── NetworkAlert.swift        # Модель сетевого алерта
├── Engines/
│   ├── PingEngine.swift          # Асинхронный многопоточный TCP Ping на Network.framework
│   ├── JitterAnalyzer.swift      # Стандарт RFC 3550 и расчет перцентилей задержки
│   ├── SpeedtestEngine.swift     # Потоковый замер пропускной способности (Download/Upload)
│   ├── NetworkDiagnostics.swift  # Определение локального IP, шлюза, DNS и ASN провайдера
│   └── TracerouteEngine.swift    # Асинхронный MTR/Traceroute сканер
├── ViewModels/
│   └── NetworkMonitorViewModel.swift # Реактивная модель представления (@Observable @MainActor)
├── Views/
│   ├── DashboardView.swift       # Главный экран с карточками и графиками
│   ├── SettingsView.swift        # Экран управления узлами и порогами
│   └── Components/
│       ├── NetworkInfoCardView.swift   # Glassmorphic карточка топологии
│       ├── HostMetricCardView.swift   # Карточка хоста со статусом и RTT
│       ├── LatencyChartView.swift     # Интерактивный график Swift Charts
│       ├── SpeedtestGaugeView.swift   # Неоновый спидометр
│       ├── TracerouteSheetView.swift  # Всплывающий экран MTR
│       └── AlertsBannerView.swift     # Всплывающие алерты
├── Utils/
│   ├── HapticManager.swift       # Генератор тактильной отдачи (Haptics)
│   └── HistoryStorage.swift      # Локальное хранилище и экспорт отчетов (JSON/CSV)
└── README.md
```

---

## 🚀 Инструкция по сборке и запуску в Xcode

1. Откройте **Xcode 16+** на macOS.
2. Выберите **File -> New -> Project -> iOS -> App**.
3. Укажите:
   - **Product Name:** `NetPulse`
   - **Interface:** `SwiftUI`
   - **Language:** `Swift`
   - **Minimum Deployments:** `iOS 17.0` (или выше).
4. Скопируйте папки `Models/`, `Engines/`, `ViewModels/`, `Views/`, `Utils/` и файлы `ContentView.swift`, `NetPulseApp.swift` в ваш Xcode-проект.
5. Запустите приложение на **iOS Simulator** (iPhone 15 Pro / iPhone 16) или на реальном устройстве (**Cmd + R**).

---

## 📄 Лицензия
MIT License.
