# ⚡ NetPulse iOS — Real-Time Network Quality Monitor

Нативное приложение для iOS: мониторинг качества сетевого подключения, расчёт джиттера по **RFC 3550**, замер скорости, трассировка маршрута, учёт трафика, диагностика (Bufferbloat, DNS, локальная сеть) и AI-диагност.

---

## 🌟 Технологический стек

- **Язык программирования:** Swift 6.0+ со строгой проверкой многопоточности (**Strict Concurrency**).
- **UI-фреймворк:** **SwiftUI** (iOS 17+) на базе макроса `@Observable`.
- **Сетевой стек:** `Network.framework` (`NWConnection`, `NWPathMonitor`), асинхронные акторы (`actor`), `TaskGroup`, `URLSession` с потоковым приёмом данных, ICMP-датаграммные сокеты для трассировки.
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
│   ├── HostMetrics.swift         # Агрегированная статистика (джиттер RFC 3550, потери, Min/Avg/Max RTT)
│   ├── NetworkInterfaceInfo.swift# Параметры Wi-Fi/Cellular, шлюз, DNS, внешний IP, ISP
│   ├── SpeedtestResult.swift     # Результаты теста скорости (Download/Upload Mbps)
│   ├── TracerouteHop.swift       # Узел пути трассировки
│   └── NetworkAlert.swift        # Модель сетевого алерта
├── Engines/
│   ├── PingEngine.swift          # Проверка узлов: время установления TCP-соединения (RST = узел жив)
│   ├── SpeedtestEngine.swift     # Многопоточный замер скорости загрузки и отдачи
│   ├── NetworkDiagnostics.swift  # Тип сети, локальный IP, шлюз (NWPath), публичный IP и провайдер
│   ├── TracerouteEngine.swift    # Трассировка по ICMP-датаграммному сокету (реальные хопы)
│   ├── BandwidthEngine.swift     # Скорость и счётчики трафика по интерфейсам (getifaddrs)
│   ├── BufferbloatEngine.swift   # Задержка под нагрузкой (скачивание/отдача)
│   ├── DNSBenchmarkEngine.swift  # Реальные DNS-запросы (UDP/53) к публичным серверам
│   ├── LANScannerEngine.swift    # Поиск устройств в Wi-Fi по TCP-портам (Wi-Fi/Ethernet, RFC 1918)
│   ├── GamingRadarEngine.swift   # Задержка до облачных регионов AWS (ориентир для игр)
│   └── AIDiagnosticsEngine.swift # Оценка сети, мастер траблшутинга, агент с инструментами, провайдеры AI
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
│   ├── HistoryStorage.swift      # История сеанса и экспорт отчётов (JSON/CSV)
│   ├── TrafficStorage.swift      # Учёт трафика, сессии, квоты
│   ├── ContinuousModeManager.swift # «Непрерывный режим»: фоновая геолокация, чтобы остров не замирал в фоне
│   └── AdMobManager.swift        # Покупка NetPulse PRO (StoreKit 2) и запрос ATT
└── README.md
```

Не вошедшие в схему файлы (виджеты, Live Activity, остальные экраны) лежат в `NetPulseWidgets/`, `Views/` и `Models/`.

---

## ℹ️ Как работают измерения и чего приложение не умеет

- **Пинг — это время установления TCP-соединения**, а не ICMP. Закрытый порт, на который узел ответил `RST`, считается «узел жив». Значения немного выше ICMP-пинга.
- **Фон.** iOS приостанавливает свернутое приложение (обычно через ~30 секунд). Dynamic Island и виджеты показывают последние полученные данные; трафик за время «сна» добавляется по счётчикам интерфейсов при возврате. Фоновые задачи (BGTaskScheduler) запускает система — гарантий по времени нет.
- **Непрерывный режим** (`Utils/ContinuousModeManager.swift`, выключен по умолчанию). Скорость устройства знает только сам телефон, поэтому остров может обновляться в фоне лишь пока приложение живо. Режим удерживает его с помощью фоновой геолокации низкой точности (код NetPulse не читает координаты, не сохраняет и не передаёт их; за сторонние SDK, в том числе рекламный, это не гарантируется — проверьте их политику сбора данных перед заполнением App Privacy). Цена: значок геолокации в строке состояния и повышенный расход батареи. Ограничения: Live Activity живёт не дольше 8 часов, а после закрытия приложения смахиванием режим вернётся только при следующем открытии. Правило App Store 2.5.4 допускает фоновую геолокацию для функций, которым нужно местоположение, — при отправке на ревью объясните назначение режима в Review Notes прямо, без обходных формулировок. Чтобы сделать режим частью PRO, поставьте `ContinuousModeManager.requiresPro = true`.
- **Нет данных — нет значения.** Если измерить нельзя (нет сети, замер не удался), приложение показывает «—» или объясняет причину, а не подставляет «нормальные» цифры.
- **Что iOS не сообщает приложениям:** DNS-серверы сети, диапазон и канал Wi-Fi, MAC-адреса устройств в локальной сети. Поэтому такие данные приложением не определяются.
- **Сканер локальной сети** находит устройства, открывшие один из проверяемых TCP-портов или ответившие отказом; устройства, молча отбрасывающие соединения, не видны. Работает только в Wi-Fi/Ethernet и требует разрешения «Локальная сеть».

---

## 🔧 Что настроить перед выпуском

1. **Meta Audience Network:** в `Info.plist` (`FacebookAppID`, `FacebookClientToken`) и в `MetaAdConfig` (`Utils/MetaAdManager.swift`) сейчас **заглушки** — подставьте значения из Meta Business Suite, иначе реклама не загрузится.
2. **NetPulse PRO:** создайте в App Store Connect продукт с идентификатором `com.samvel.netpulse.pro` (см. `StoreConfig` в `Utils/AdMobManager.swift`). Пока продукта нет, покупка сообщает «недоступна», и PRO не выдаётся.
3. **Подпись и App Group:** группа приложения — `group.com.samvel.netpulse` (приложение и расширение виджетов).
4. **Сборка и выгрузка:** workflow *iOS: проверка сборки* компилирует проект на каждый pull request; выгрузка в TestFlight запускается только вручную (*Actions → Выгрузка в TestFlight*).

---

## 🚀 Сборка и запуск в Xcode

1. Откройте `NetPulse.xcodeproj` в **Xcode 16+** на macOS; Swift Package Manager сам подтянет зависимости (FBAudienceNetwork).
2. Выберите схему **NetPulse**, в *Signing & Capabilities* укажите свою команду разработчика для приложения и расширения виджетов.
3. Запустите приложение на **iOS Simulator** или на реальном устройстве (**Cmd + R**). Live Activity, виджеты, доступ к локальной сети и фоновые задачи надёжно проверяются только на устройстве.

---

## 📄 Лицензия
MIT License.
