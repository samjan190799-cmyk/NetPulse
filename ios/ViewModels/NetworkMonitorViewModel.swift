//
//  NetworkMonitorViewModel.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import SwiftUI
import Observation
import UIKit
import AudioToolbox
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Главная модель представления NetPulse на базе макроса @Observable (iOS 17+ / Swift 6).
@Observable
@MainActor
public final class NetworkMonitorViewModel {

    /// Единственный экземпляр. Инициализатор запускает задачи опроса и подписки на уведомления, а
    /// `@State private var vm = NetworkMonitorViewModel()` вычисляется при каждом пересоздании `ContentView`
    /// (например, при смене `scenePhase`) — лишние экземпляры запускали дублирующие циклы и никогда не освобождались.
    public static let shared = NetworkMonitorViewModel()

    // MARK: - Состояние приложения
    public var targets: [HostTarget] = HostTarget.defaultTargets {
        didSet { persistTargets() }
    }
    public var hostMetrics: [String: HostMetrics] = [:]
    public var systemInfo: NetworkInterfaceInfo = NetworkInterfaceInfo()
    
    public var isMonitoringActive: Bool = false
    /// Пауза между циклами проверки узлов в активном режиме, секунд
    public var pollingInterval: TimeInterval = 4.0 {
        didSet { UserDefaults.standard.set(pollingInterval, forKey: Self.kPollingIntervalKey) }
    }
    
    // Регулярный системный замер реального трафика (getifaddrs)
    public var liveBandwidth: BandwidthSnapshot = BandwidthSnapshot(
        downloadBytesPerSec: 0,
        uploadBytesPerSec: 0,
        downloadMbps: 0,
        uploadMbps: 0,
        wifiDownloadBps: 0,
        wifiUploadBps: 0,
        cellularDownloadBps: 0,
        cellularUploadBps: 0,
        totalReceivedBytes: 0,
        totalSentBytes: 0,
        wifiReceivedBytes: 0,
        wifiSentBytes: 0,
        cellularReceivedBytes: 0,
        cellularSentBytes: 0,
        deltaDownloadBytes: 0,
        deltaUploadBytes: 0,
        deltaWifiBytes: 0,
        deltaCellularBytes: 0,
        timestamp: Date()
    )

    // MARK: - Аналитика трафика (Traffic & Sessions)
    public var trafficSummary: TrafficSummary = TrafficSummary()
    /// Расход за сегодня (для виджета) — не зависит от выбранного в интерфейсе периода
    public var todayTrafficSummary: TrafficSummary = TrafficSummary()
    /// Расход за период квоты (для лимита и AI) — не зависит от выбранного в интерфейсе периода
    public var budgetPeriodSummary: TrafficSummary = TrafficSummary()
    public var trafficSessions: [TrafficSession] = []
    public var trafficDataPoints: [TrafficDataPoint] = []
    public var trafficBudget: TrafficBudget = TrafficBudget()
    public var selectedTrafficPeriod: TrafficPeriod = .today

    /// Расход за период квоты в байтах
    public var budgetUsedBytes: UInt64 {
        budgetPeriodSummary.totalTraffic
    }

    public var currentNetworkTitle: String {
        switch systemInfo.connectionType {
        case .wifi:
            return systemInfo.ispName ?? "Wi-Fi Сеть"
        case .cellular:
            return systemInfo.ispName ?? "Мобильный интернет (5G/LTE)"
        case .ethernet:
            return systemInfo.ispName ?? "Ethernet Сеть"
        case .loopback:
            return "Локальная петля"
        case .unavailable:
            return "Нет подключения"
        }
    }

    // Speedtest
    public var isSpeedtestRunning: Bool = false
    public var liveDownloadSpeed: Double = 0.0
    public var liveUploadSpeed: Double = 0.0
    public var lastSpeedtestResult: SpeedtestResult?
    public var instantAISummary: String?
    /// Сообщение об ошибке или неполном результате замера (nil — замер прошёл без замечаний)
    public var speedtestError: String?
    // Traceroute
    public var isTracerouteRunning: Bool = false
    public var tracerouteHops: [TracerouteHop] = []
    /// Причина, по которой трассировка не удалась (nil — всё в порядке)
    public var tracerouteError: String?
    public var selectedTracerouteTarget: String = ""
    public var showTracerouteSheet: Bool = false

    // Alerts & Notifications
    public var recentAlerts: [NetworkAlert] = []
    public var activeAlert: NetworkAlert?
    public var soundEnabled: Bool = true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: Self.kSoundKey) }
    }
    public var hapticsEnabled: Bool = true {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: Self.kHapticsKey) }
    }

    // Фоновый мониторинг трафика (24/7)
    private static let kLiveActivityKey = "netpulse_live_activity_enabled"
    private static let kFloatingHUDKey = "netpulse_floating_hud_enabled"
    private static let kFloatingHUDCollapsedKey = "netpulse_floating_hud_collapsed"
    private static let kBackgroundMonitoringKey = "netpulse_background_monitoring_enabled"
    // Пользовательские настройки (раньше не сохранялись и сбрасывались при каждом запуске)
    private static let kTargetsKey = "netpulse_targets_v1"
    private static let kPollingIntervalKey = "netpulse_polling_interval"
    private static let kSoundKey = "netpulse_sound_enabled"
    private static let kHapticsKey = "netpulse_haptics_enabled"
    private static let kLatencyWarnKey = "netpulse_latency_warn_threshold"
    private static let kLatencyCritKey = "netpulse_latency_crit_threshold"
    private static let kJitterWarnKey = "netpulse_jitter_warn_threshold"
    private static let kLossCritKey = "netpulse_loss_crit_threshold"

    public var backgroundMonitoringEnabled: Bool {
        didSet {
            UserDefaults.standard.set(backgroundMonitoringEnabled, forKey: Self.kBackgroundMonitoringKey)
        }
    }

    // Виджеты: Dynamic Island & Игровой HUD
    public var liveActivityEnabled: Bool {
        didSet {
            UserDefaults.standard.set(liveActivityEnabled, forKey: Self.kLiveActivityKey)
        }
    }
    // Подсказка на главном экране: остров замирал, пока приложение было свёрнуто, а запись маршрута не шла
    // (пока она идёт, приложение остаётся активным в фоне, и остров обновляется)
    public var showRecordingHint: Bool = false
    private static let kRecordingHintDismissedKey = "netpulse_recording_hint_dismissed"

    /// Сколько трафика прошло, пока приложение спало: остров в это время стоит, а сеть работает. Показывается на главном
    /// экране после возвращения и скрывается сам.
    public var sleepTraffic: SleepTrafficNote?
    private var sleepTrafficClearTask: Task<Void, Never>?

    public var floatingHUDEnabled: Bool {
        didSet {
            UserDefaults.standard.set(floatingHUDEnabled, forKey: Self.kFloatingHUDKey)
        }
    }
    public var isFloatingHUDCollapsed: Bool {
        didSet {
            UserDefaults.standard.set(isFloatingHUDCollapsed, forKey: Self.kFloatingHUDCollapsedKey)
        }
    }

    // Настройки порогов
    public var latencyWarnThreshold: Double = 100.0 {
        didSet { UserDefaults.standard.set(latencyWarnThreshold, forKey: Self.kLatencyWarnKey) }
    }
    public var latencyCritThreshold: Double = 180.0 {
        didSet { UserDefaults.standard.set(latencyCritThreshold, forKey: Self.kLatencyCritKey) }
    }
    public var jitterWarnThreshold: Double = 20.0 {
        didSet { UserDefaults.standard.set(jitterWarnThreshold, forKey: Self.kJitterWarnKey) }
    }
    public var lossCritThreshold: Double = 5.0 {
        didSet { UserDefaults.standard.set(lossCritThreshold, forKey: Self.kLossCritKey) }
    }

    // MARK: - Движки и зависимости
    private let pingEngine = PingEngine(timeout: 2.0)
    private let bandwidthEngine = BandwidthEngine.shared
    private let speedtestEngine = SpeedtestEngine()
    private let tracerouteEngine = TracerouteEngine()
    private let diagnostics = NetworkDiagnostics()
    private let storage = HistoryStorage()

    private var bandwidthTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var diagnosticsTask: Task<Void, Never>?
    private var prevLatencies: [String: Double] = [:]
    /// Состояние подавления повторов алертов: «адрес|метрика» -> (серьёзность, время выпуска)
    private var alertStates: [String: (severity: AlertSeverity, date: Date)] = [:]
    /// Узлы, переживающие эпизод сбоя (от DOWN до полного восстановления)
    private var outageEpisodes: Set<String> = []
    private let alertCooldown: TimeInterval = 60
    /// Адрес шлюза, под который накоплена статистика строки «gateway»
    private var lastResolvedGatewayIP: String?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    /// Метка времени последнего успешного обновления Live Activity (watchdog)
    public var lastLiveActivityUpdateDate: Date?
    /// Когда приложение свернули (для подсказки про непрерывный режим)
    private var backgroundedAt: Date?
    /// Когда в последний раз записывали остаток памяти в журнал
    private var lastMemorySampleAt = Date.distantPast

    public init() {
        // Журнал острова: заодно проверяет, не был ли предыдущий запуск закрыт системой без штатного выхода
        IslandDiagnostics.shared.beginSession()

        // Значения по умолчанию видны и тем, кто читает ключи напрямую (BackgroundTaskManager): иначе на свежей
        // установке `bool(forKey:)` возвращал false, хотя в приложении функции включены.
        UserDefaults.standard.register(defaults: [
            Self.kLiveActivityKey: true,
            Self.kFloatingHUDKey: false,
            Self.kBackgroundMonitoringKey: true
        ])
        let savedLive = UserDefaults.standard.object(forKey: Self.kLiveActivityKey) as? Bool ?? true
        let savedHUD = UserDefaults.standard.object(forKey: Self.kFloatingHUDKey) as? Bool ?? false
        let savedBg = UserDefaults.standard.object(forKey: Self.kBackgroundMonitoringKey) as? Bool ?? true
        let savedCollapsed = UserDefaults.standard.bool(forKey: Self.kFloatingHUDCollapsedKey)

        self.liveActivityEnabled = savedLive
        self.floatingHUDEnabled = savedHUD
        self.isFloatingHUDCollapsed = savedCollapsed
        self.backgroundMonitoringEnabled = savedBg

        loadSavedSettings()
        initMetricsForTargets()
        setupBackgroundObservation()
        Task {
            // Быстрый снимок локальной сети (без интернет-запросов): тип подключения нужен сразу —
            // раньше он появлялся только после опроса сервисов публичного IP (до 10 секунд)
            let quickInfo = await self.diagnostics.collectLocalInfo()
            self.systemInfo = quickInfo
            let info = await self.diagnostics.collectSystemInfo()
            self.systemInfo = info
            // Аппаратная сверка пропущенного трафика с системным ядром Darwin BSD
            await TrafficStorage.shared.reconcileBackgroundHardwareTraffic(
                currentConnectionType: info.connectionType.rawValue,
                currentNetworkName: self.currentNetworkTitle
            )
            await self.refreshTrafficData(period: .today)
            self.syncWidgetData(reloadTimelines: true)
        }
        startMonitoring(silent: true)
        // Запись, которую система оборвала посреди маршрута (приложение закрыли), сохраняется как прерванный маршрут
        Task {
            await RouteRecorder.shared.recoverInterruptedRoute()
        }
    }

    /// Настоящий перезапуск острова (кнопка «Перезапустить» и значок на главном экране): активность создаётся заново
    public func restartLiveActivity() {
        ActivityManager.shared.restartActivity(
            downloadSpeedText: liveBandwidth.formattedDownloadSpeed,
            uploadSpeedText: liveBandwidth.formattedUploadSpeed,
            compactDownloadText: liveBandwidth.compactDownload,
            compactUploadText: liveBandwidth.compactUpload,
            pingMs: currentAveragePing,
            jitterMs: currentAverageJitter,
            isTesting: isSpeedtestRunning,
            connectionType: systemInfo.connectionType.rawValue,
            ispName: systemInfo.ispName ?? "Интернет",
            isGamingMode: floatingHUDEnabled,
            packetLossPct: currentPacketLossPct
        )
    }

    /// Скрывает подсказку про запись маршрута; `forever` — больше не показывать
    /// Скрывает заметку о трафике за время сна
    public func dismissSleepTraffic() {
        sleepTrafficClearTask?.cancel()
        sleepTrafficClearTask = nil
        sleepTraffic = nil
    }

    /// Запоминает, сколько трафика прошло, пока приложение спало (по системным счётчикам), и на время показывает это
    /// на главном экране
    private func noteTrafficWhileAway(_ summary: SleepTrafficSummary?, since: Date?) {
        let away = since.map { Date().timeIntervalSince($0) }
        guard let note = SleepTrafficNote.make(summary: summary, awaySeconds: away) else { return }
        sleepTraffic = note
        IslandDiagnostics.shared.log(
            "Пока приложение спало (\(IslandDiagnostics.formatAge(note.awaySeconds))): принято \(note.downloadBytes) Б, отправлено \(note.uploadBytes) Б",
            .lifecycle
        )
        sleepTrafficClearTask?.cancel()
        sleepTrafficClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { return }
            self?.sleepTraffic = nil
        }
    }

    public func dismissRecordingHint(forever: Bool) {
        showRecordingHint = false
        if forever {
            UserDefaults.standard.set(true, forKey: Self.kRecordingHintDismissedKey)
        }
    }

    public func toggleLiveActivity(enabled: Bool) {
        self.liveActivityEnabled = enabled
        if enabled {
            BackgroundTelemetryKeeper.shared.startKeepAlive()

            let dlText = liveBandwidth.formattedDownloadSpeed
            let ulText = liveBandwidth.formattedUploadSpeed
            let compactDl = liveBandwidth.compactDownload
            let compactUl = liveBandwidth.compactUpload

            ActivityManager.shared.startActivity(
                downloadSpeedText: dlText,
                uploadSpeedText: ulText,
                compactDownloadText: compactDl,
                compactUploadText: compactUl,
                pingMs: currentAveragePing,
                jitterMs: currentAverageJitter,
                isTesting: isSpeedtestRunning,
                connectionType: systemInfo.connectionType.rawValue,
                ispName: systemInfo.ispName ?? "Интернет",
                isGamingMode: floatingHUDEnabled
            )
            startBandwidthTask()
            syncWidgetData()
            if hapticsEnabled {
                HapticManager.shared.notificationSuccess()
            }
        } else {
            ActivityManager.shared.stopActivity()
            if !backgroundMonitoringEnabled {
                BackgroundTelemetryKeeper.shared.stopKeepAlive()
            }
            if hapticsEnabled {
                HapticManager.shared.impactLight()
            }
        }
    }

    private func setupBackgroundObservation() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDidEnterBackground()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWillEnterForeground()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDidBecomeActive()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWillTerminate()
            }
        }
    }

    private func beginBackgroundAssertion() {
        endBackgroundAssertion()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "NetPulseBackgroundTelemetry") { [weak self] in
            Task { @MainActor in
                self?.endBackgroundAssertion()
            }
        }
    }

    private func endBackgroundAssertion() {
        if bgTask != .invalid {
            let taskToClose = bgTask
            bgTask = .invalid
            UIApplication.shared.endBackgroundTask(taskToClose)
        }
    }

    private func handleDidEnterBackground() {
        backgroundedAt = Date()
        // Если фоновая запись выключена в настройках, идущая запись встаёт на паузу до возвращения в приложение
        RouteRecorder.shared.appDidEnterBackground()
        IslandDiagnostics.shared.log("Приложение свёрнуто. \(RouteRecorder.shared.diagnosticContext())", .lifecycle)

        // 1. Принудительный сброс несохраненных данных трафика на диск
        Task {
            await TrafficStorage.shared.flush()
        }

        // 2. Планирование фонового пробуждения через системный BGTaskScheduler
        BackgroundTaskManager.shared.scheduleBackgroundFetch()

        // 3. Энергоэффективность: глушим тяжелый параллельный опрос всех хостов и HTTP-диагностику в фоне
        pingTask?.cancel()
        pingTask = nil
        diagnosticsTask?.cancel()
        diagnosticsTask = nil

        // 4. Если включен Live Activity (Dynamic Island) или фоновый мониторинг / HUD, удерживаем непрерывную телеметрию
        if liveActivityEnabled || backgroundMonitoringEnabled || floatingHUDEnabled {
            BackgroundTelemetryKeeper.shared.startKeepAlive()
            beginBackgroundAssertion()
            startBandwidthTask()
        } else {
            // Если фоновые сервисы отключены пользователем, полностью останавливаем таймеры и аудиосессию
            bandwidthTask?.cancel()
            bandwidthTask = nil
            BackgroundTelemetryKeeper.shared.stopKeepAlive()
            endBackgroundAssertion()
        }
    }

    private func handleWillEnterForeground() {
        IslandDiagnostics.shared.log("Приложение возвращается на экран.", .lifecycle)
        endBackgroundAssertion()
        // Когда приложение свернули: к моменту сверки счётчиков метка ещё не сброшена (её снимает handleDidBecomeActive)
        let sleptSince = backgroundedAt
        Task {
            let info = await self.diagnostics.collectSystemInfo()
            self.systemInfo = info
            // Моментальная сверка с аппаратными счетчиками ядра за время сна/фона (Zero-Loss)
            let missed = await TrafficStorage.shared.reconcileBackgroundHardwareTraffic(
                currentConnectionType: info.connectionType.rawValue,
                currentNetworkName: self.currentNetworkTitle
            )
            self.noteTrafficWhileAway(missed, since: sleptSince)
            await self.refreshTrafficData(period: self.selectedTrafficPeriod)
            self.syncWidgetData(reloadTimelines: true)
        }

        // Возобновляем активные задачи при возвращении пользователя в приложение
        if isMonitoringActive {
            startBandwidthTask()
            startPingTask()
            startDiagnosticsTask()
        }
    }

    private func handleDidBecomeActive() {
        // Пока приложение было свёрнуто, система могла остановить геолокацию: идущая запись маршрута запускает её заново
        RouteRecorder.shared.appDidBecomeActive()

        // Сколько приложение пробыло свёрнутым. Без записи маршрута iOS усыпляет его примерно через 30 секунд,
        // и остров всё это время стоял на последних цифрах — предлагаем записать маршрут.
        let awaySeconds = backgroundedAt.map { Date().timeIntervalSince($0) }
        backgroundedAt = nil
        if let away = awaySeconds, away > 40, liveActivityEnabled, !RouteRecorder.shared.isActive,
           !UserDefaults.standard.bool(forKey: Self.kRecordingHintDismissedKey) {
            showRecordingHint = true
        }

        // Остров, который не обновился после возврата из фона, пересоздаётся сам. При холодном запуске и коротких
        // прерываниях (системные окна) проверка не нужна: приложение не сворачивалось, и остров обновляется как обычно.
        if liveActivityEnabled, awaySeconds != nil {
            ActivityManager.shared.scheduleForegroundHealthCheck()
        }

        Task {
            let info = await self.diagnostics.collectSystemInfo()
            self.systemInfo = info
            await self.refreshTrafficData(period: self.selectedTrafficPeriod)
            self.syncWidgetData(reloadTimelines: true)
        }

        // Watchdog: если цикл обновления Dynamic Island умер — принудительный перезапуск
        if liveActivityEnabled || backgroundMonitoringEnabled || floatingHUDEnabled {
            let isStale: Bool
            if let lastUpdate = lastLiveActivityUpdateDate {
                isStale = Date().timeIntervalSince(lastUpdate) > 5.0
            } else {
                isStale = true
            }
            if isStale {
                print("🔄 [Watchdog] Цикл обновления Dynamic Island не активен — перезапуск")
                bandwidthTask?.cancel()
                bandwidthTask = nil
                startBandwidthTask()
            }
        }
    }

    private func handleWillTerminate() {
        IslandDiagnostics.shared.log("Штатное завершение приложения.", .lifecycle)
        IslandDiagnostics.shared.endSession()
        endBackgroundAssertion()
        BackgroundTelemetryKeeper.shared.stopKeepAlive()
        Task {
            let info = await self.diagnostics.collectSystemInfo()
            await TrafficStorage.shared.reconcileBackgroundHardwareTraffic(
                currentConnectionType: info.connectionType.rawValue,
                currentNetworkName: self.currentNetworkTitle
            )
            await TrafficStorage.shared.flush()
        }
    }

    /// Загрузка сохранённых настроек (узлы, пороги, интервал, звук и тактильный отклик)
    private func loadSavedSettings() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.kTargetsKey),
           let saved = try? JSONDecoder().decode([HostTarget].self, from: data),
           !saved.isEmpty {
            self.targets = saved
        }
        if let value = defaults.object(forKey: Self.kPollingIntervalKey) as? Double, value >= 1.0 {
            self.pollingInterval = value
        }
        if let value = defaults.object(forKey: Self.kSoundKey) as? Bool { self.soundEnabled = value }
        if let value = defaults.object(forKey: Self.kHapticsKey) as? Bool { self.hapticsEnabled = value }
        if let value = defaults.object(forKey: Self.kLatencyWarnKey) as? Double { self.latencyWarnThreshold = value }
        if let value = defaults.object(forKey: Self.kLatencyCritKey) as? Double { self.latencyCritThreshold = value }
        if let value = defaults.object(forKey: Self.kJitterWarnKey) as? Double { self.jitterWarnThreshold = value }
        if let value = defaults.object(forKey: Self.kLossCritKey) as? Double { self.lossCritThreshold = value }
    }

    private func persistTargets() {
        if let data = try? JSONEncoder().encode(targets) {
            UserDefaults.standard.set(data, forKey: Self.kTargetsKey)
        }
    }

    private func initMetricsForTargets() {
        for target in targets {
            hostMetrics[target.address] = HostMetrics(
                name: target.name,
                address: target.address,
                isGateway: target.isGateway
            )
        }
    }

    // MARK: - Запуск / Остановка мониторинга

    public func startMonitoring(silent: Bool = false) {
        guard !isMonitoringActive else { return }
        isMonitoringActive = true

        if liveActivityEnabled {
            BackgroundTelemetryKeeper.shared.startKeepAlive()
            ActivityManager.shared.checkAndRestoreActivity(
                downloadSpeedText: liveBandwidth.formattedDownloadSpeed,
                uploadSpeedText: liveBandwidth.formattedUploadSpeed,
                compactDownloadText: liveBandwidth.compactDownload,
                compactUploadText: liveBandwidth.compactUpload,
                pingMs: currentAveragePing,
                jitterMs: currentAverageJitter,
                isTesting: isSpeedtestRunning,
                connectionType: systemInfo.connectionType.rawValue,
                ispName: systemInfo.ispName ?? "Интернет",
                isGamingMode: floatingHUDEnabled
            )
        }

        if !silent && hapticsEnabled {
            HapticManager.shared.impactLight()
        }

        startBandwidthTask()
        startPingTask()
        startDiagnosticsTask()
    }

    public func stopMonitoring() {
        isMonitoringActive = false
        bandwidthTask?.cancel()
        bandwidthTask = nil
        pingTask?.cancel()
        pingTask = nil
        diagnosticsTask?.cancel()
        diagnosticsTask = nil

        if !liveActivityEnabled && !floatingHUDEnabled {
            BackgroundTelemetryKeeper.shared.stopKeepAlive()
        }

        if hapticsEnabled {
            HapticManager.shared.impactLight()
        }
    }

    // MARK: - Фоновые задачи опроса


    /// Результат попытки добавить узел мониторинга
    public enum AddTargetResult: Equatable, Sendable {
        case added
        case invalidAddress
        case invalidPort
        case duplicate
    }

    /// Допустимый адрес узла: IPv4/IPv6 или доменное имя (без пробелов и служебных символов).
    /// «gateway» зарезервировано под шлюз по умолчанию.
    public static func isValidHostAddress(_ address: String) -> Bool {
        guard !address.isEmpty, address.count <= 253, !address.hasPrefix("-"), address.lowercased() != "gateway" else {
            return false
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_:")
        return address.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Единый путь добавления узла (из настроек и из быстрого пинга): валидация, список и карточка метрик
    /// создаются вместе. Раньше узел из настроек попадал только в список — без карточки его результаты отбрасывались.
    @discardableResult
    public func addTarget(name: String, address: String, port: Int) -> AddTargetResult {
        let cleanedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidHostAddress(cleanedAddress) else { return .invalidAddress }
        guard (1...65_535).contains(port) else { return .invalidPort }
        guard !targets.contains(where: { $0.address.lowercased() == cleanedAddress.lowercased() }) else {
            return .duplicate
        }
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = HostTarget(
            name: cleanedName.isEmpty ? cleanedAddress : cleanedName,
            address: cleanedAddress,
            tcpPort: port
        )
        targets.append(target)
        hostMetrics[target.address] = HostMetrics(name: target.name, address: target.address, isGateway: false)
        return .added
    }

    /// Удаление узлов вместе с накопленными метриками: раньше метрики оставались и продолжали влиять на средние значения.
    public func removeTargets(atOffsets offsets: IndexSet) {
        let removed = offsets.compactMap { targets.indices.contains($0) ? targets[$0] : nil }
        targets.remove(atOffsets: offsets)
        for target in removed {
            hostMetrics.removeValue(forKey: target.address)
            prevLatencies.removeValue(forKey: target.address)
            clearAlertState(for: target.address)
        }
    }

    /// Добавление пользовательского хоста для мгновенного отображения в карточках мониторинга
    public func addCustomTarget(_ host: String) {
        let cleaned = host.trimmingCharacters(in: .whitespacesAndNewlines)
        addTarget(name: cleaned, address: cleaned, port: 443)
    }

    /// Следит за ровностью цикла обновления: пауза между тиками означает, что код не выполнялся.
    /// В фоне это значит, что iOS приостановила приложение, и именно поэтому остров замирает.
    private func observeLoopTick(now: Date, previousTickAt: Date, previousWasBackground: Bool, isBackground: Bool) {
        let journal = IslandDiagnostics.shared
        journal.heartbeat(isBackground: isBackground, now: now)

        let gap = now.timeIntervalSince(previousTickAt)
        switch LoopTiming.classify(gap: gap, previousTickWasBackground: previousWasBackground) {
        case .normal:
            break
        case .suspendedInBackground(let seconds):
            journal.recordPause(
                seconds: seconds,
                inBackground: true,
                context: RouteRecorder.shared.diagnosticContext(),
                now: now
            )
            RouteRecorder.shared.noteBackgroundPause(seconds: seconds, now: now)
        case .stalledInForeground(let seconds):
            journal.recordPause(seconds: seconds, inBackground: false, context: "", now: now)
        }

        // Остаток памяти до лимита системы: в фоне раз в 5 минут, при открытом приложении раз в 15
        let sampleInterval: TimeInterval = isBackground ? 300 : 900
        if now.timeIntervalSince(lastMemorySampleAt) >= sampleInterval {
            lastMemorySampleAt = now
            journal.sampleMemory(isBackground: isBackground, now: now)
        }
    }

    /// Изолированная задача замера реальной скорости, сохранения трафика и непрерывного обновления Dynamic Island
    public func startBandwidthTask() {
        guard bandwidthTask == nil || bandwidthTask?.isCancelled == true else { return }
        bandwidthTask = Task { [weak self] in
            var loopCount = 0
            var lastTickAt = Date()
            var lastTickWasBackground = UIApplication.shared.applicationState == .background
            defer {
                // Гарантированная очистка ссылки при любом завершении цикла — позволяет перезапуск
                Task { @MainActor [weak self] in
                    self?.bandwidthTask = nil
                }
            }
            while !Task.isCancelled {
                // ViewModel освобождена — цикл должен завершиться (раньше он бесконечно «ждал» её)
                guard let self else { return }
                guard self.isMonitoringActive || self.backgroundMonitoringEnabled || self.liveActivityEnabled || self.floatingHUDEnabled else {
                    // Все флаги выключены — ждём, не ломаем цикл
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    lastTickAt = Date()
                    continue
                }

                let tickStartedAt = Date()
                let isAppInBackground = UIApplication.shared.applicationState == .background
                // Пауза между тиками — признак того, что приложение усыпили (в фоне) или оно было занято (на экране)
                self.observeLoopTick(
                    now: tickStartedAt,
                    previousTickAt: lastTickAt,
                    previousWasBackground: lastTickWasBackground,
                    isBackground: isAppInBackground
                )
                lastTickAt = tickStartedAt
                lastTickWasBackground = isAppInBackground

                // Пассивный замер системного трафика через счетчики ядра BSD getifaddrs (0 сетевых пакетов, 0 Вт, защита от нагрева)
                let snapshot = self.bandwidthEngine.sampleBandwidth(activeConnectionType: self.systemInfo.connectionType)
                self.liveBandwidth = snapshot

                let dlText: String
                let ulText: String
                let compactDl: String
                let compactUl: String

                if self.isSpeedtestRunning {
                    dlText = BandwidthSnapshot.formatSpeed(mbps: self.liveDownloadSpeed)
                    ulText = BandwidthSnapshot.formatSpeed(mbps: self.liveUploadSpeed)
                    compactDl = BandwidthSnapshot.compactSpeed(mbps: self.liveDownloadSpeed)
                    compactUl = BandwidthSnapshot.compactSpeed(mbps: self.liveUploadSpeed)
                } else {
                    // Строго скорость скачивания и отдачи в Dynamic Island (пинг отображается по зажатию)
                    dlText = self.liveBandwidth.formattedDownloadSpeed
                    ulText = self.liveBandwidth.formattedUploadSpeed
                    compactDl = self.liveBandwidth.compactDownload
                    compactUl = self.liveBandwidth.compactUpload
                }

                // 1. МГНОВЕННАЯ передача в Dynamic Island (0.05 мс, без блокировок и ожидания БД)
                if self.liveActivityEnabled {
                    self.lastLiveActivityUpdateDate = Date()
                    ActivityManager.shared.updateActivity(
                        downloadSpeedText: dlText,
                        uploadSpeedText: ulText,
                        compactDownloadText: compactDl,
                        compactUploadText: compactUl,
                        pingMs: self.currentAveragePing,
                        jitterMs: self.currentAverageJitter,
                        isTesting: self.isSpeedtestRunning,
                        connectionType: self.systemInfo.connectionType.rawValue,
                        ispName: self.systemInfo.ispName ?? "Интернет",
                        isGamingMode: self.floatingHUDEnabled,
                        packetLossPct: self.currentPacketLossPct
                    )
                }

                // 2. Непрерывная передача в PiP (Picture-in-Picture)
                PiPHUDManager.shared.updateTelemetry(
                    downloadText: dlText,
                    uploadText: ulText,
                    pingMs: self.currentAveragePing,
                    jitterMs: self.currentAverageJitter,
                    connectionType: self.systemInfo.connectionType.rawValue,
                    isTesting: self.isSpeedtestRunning
                )

                // 3. Асинхронное сохранение трафика в базе данных (только при наличии активности)
                if snapshot.deltaDownloadBytes > 0 || snapshot.deltaUploadBytes > 0 {
                    Task { [snapshot = self.liveBandwidth, netName = self.currentNetworkTitle, connType = self.systemInfo.connectionType.rawValue, isWifi = (self.systemInfo.connectionType == .wifi), testing = self.isSpeedtestRunning] in
                        await TrafficStorage.shared.recordTrafficSample(
                            snapshot: snapshot,
                            networkName: netName,
                            connectionType: connType,
                            interfaceName: isWifi ? "en0" : "pdp_ip0",
                            isSpeedtestActive: testing
                        )
                    }
                }

                // 4. Периодическое фоновое обновление аналитики UI (раз в 5 сек без троттлинга виджетов)
                if !isAppInBackground {
                    loopCount += 1
                    if loopCount % 5 == 0 {
                        Task { [weak self] in
                            guard let self else { return }
                            await self.refreshTrafficData(period: self.selectedTrafficPeriod)
                        }
                    }
                }

                // Строгий такт 1.0 секунда: непрерывное обновление Dynamic Island без замирания
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }


    /// Изолированная задача параллельного пинга хостов сети (энергоэффективная)
    private func startPingTask() {
        guard pingTask == nil || pingTask?.isCancelled == true else { return }
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, self.isMonitoringActive else { break }
                if UIApplication.shared.applicationState == .active {
                    await self.pollAllHosts()
                    // Пауза берётся из настроек (раньше значение в «Интервал проверки» нигде не использовалось)
                    let pause = max(1.0, self.pollingInterval)
                    try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
                } else {
                    // В фоновом режиме сетевой пинг полностью приостанавливается для защиты от нагрева и разряда батареи
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
    }

    private func startDiagnosticsTask() {
        guard diagnosticsTask == nil || diagnosticsTask?.isCancelled == true else { return }
        diagnosticsTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, self.isMonitoringActive else { break }
                let info = await self.diagnostics.collectSystemInfo()
                self.systemInfo = info
                try? await Task.sleep(nanoseconds: 20_000_000_000) // каждые 20 секунд
            }
        }
    }

    /// Сколько проверок подряд без ответа считать недоступностью узла (DOWN)
    private static let downAfterFailures = 3
    /// Минимум проверок в окне, чтобы оценивать потери в процентах (1 потеря из 2 — это не «50 %»)
    private static let minSamplesForLossPct = 10

    private typealias PendingAlert = (message: String, severity: AlertSeverity, metric: String, currentVal: Double, threshVal: Double)

    /// Узлы для опроса с подставленным реальным адресом шлюза. Шлюз, адрес которого неизвестен
    /// (мобильная сеть, нет сети), не опрашивается: раньше вместо него пинговался выдуманный 192.168.1.1.
    /// `key` — ключ в `hostMetrics` (для шлюза это «gateway»), `target` — что реально пинговать.
    private func resolvedTargetsForPolling() -> [(key: String, target: HostTarget)] {
        var result: [(key: String, target: HostTarget)] = []
        for target in targets where target.isEnabled {
            if target.isGateway && (target.address == "gateway" || target.address.isEmpty) {
                guard let gatewayIP = systemInfo.gatewayIP, !gatewayIP.isEmpty else { continue }
                var resolved = target
                resolved.address = gatewayIP
                result.append((key: target.address, target: resolved))
            } else {
                result.append((key: target.address, target: target))
            }
        }
        return result
    }

    /// При смене шлюза (другая сеть) прежняя статистика к новому шлюзу не относится — строка начинается с нуля.
    private func refreshGatewayMetrics() {
        let current = systemInfo.gatewayIP
        guard current != lastResolvedGatewayIP else { return }
        lastResolvedGatewayIP = current
        for target in targets where target.isGateway {
            hostMetrics[target.address] = HostMetrics(
                name: target.name,
                address: current ?? target.address,
                isGateway: true
            )
            prevLatencies.removeValue(forKey: target.address)
            clearAlertState(for: target.address)
        }
    }

    private func pollAllHosts() async {
        refreshGatewayMetrics()
        let polling = resolvedTargetsForPolling()
        var batchResults: [(String, PingRecord)] = []
        await withTaskGroup(of: (String, PingRecord).self) { group in
            for item in polling {
                group.addTask {
                    let record = await self.pingEngine.pingTarget(item.target)
                    return (item.key, record)
                }
            }

            for await (key, record) in group {
                batchResults.append((key, record))
            }
        }

        var pendingAlerts: [(address: String, conditions: [PendingAlert])] = []
        var updated = hostMetrics

        for (address, record) in batchResults {
            let existing: HostMetrics
            if let known = updated[address] {
                existing = known
            } else if let target = targets.first(where: { $0.address == address }) {
                // Узел добавлен без карточки метрик (раньше такие результаты молча отбрасывались)
                existing = HostMetrics(name: target.name, address: target.address, isGateway: target.isGateway)
            } else {
                continue
            }
            let prevRtt = prevLatencies[address]
            let (newMetric, newRtt, conditions) = processPingRecord(metric: existing, record: record, prevRtt: prevRtt)
            updated[address] = newMetric
            if let rtt = newRtt {
                prevLatencies[address] = rtt
            }
            pendingAlerts.append((address: address, conditions: conditions))
        }
        self.hostMetrics = updated

        for item in pendingAlerts {
            if let status = updated[item.address]?.status {
                emitAlerts(address: item.address, status: status, conditions: item.conditions)
            }
        }

        // Записи попадают в историю сеанса для экспорта (раньше `recordPing` нигде не вызывался, и отчёт был пустым)
        for (_, record) in batchResults {
            await storage.recordPing(record)
        }
    }

    private func processPingRecord(
        metric: HostMetrics,
        record: PingRecord,
        prevRtt: Double?
    ) -> (updated: HostMetrics, newRtt: Double?, conditions: [PendingAlert]) {
        var m = metric
        m.sentCount += 1
        m.lastUpdated = Date()

        var conditions: [PendingAlert] = []
        var emittedRtt: Double? = nil

        if record.isSuccess, let lat = record.latencyMs {
            m.receivedCount += 1
            m.consecutiveFailures = 0
            m.lastLatencyMs = lat
            emittedRtt = lat

            // Расчет RFC 3550 Jitter
            if let pRtt = prevRtt {
                let d = abs(lat - pRtt)
                m.jitterMs = m.jitterMs + (d - m.jitterMs) / 16.0
            }

            // Min / Max / Avg
            m.minLatencyMs = m.minLatencyMs.map { min($0, lat) } ?? lat
            m.maxLatencyMs = m.maxLatencyMs.map { max($0, lat) } ?? lat

            let totalLat = (m.avgLatencyMs ?? lat) * Double(m.receivedCount - 1) + lat
            m.avgLatencyMs = totalLat / Double(m.receivedCount)

            // Добавление в историю Sparkline (ограничено 24 точками для экономии памяти)
            m.latencyHistory.append(lat)
        } else {
            // Потеря пакета
            m.lostCount += 1
            m.consecutiveFailures += 1
            m.lastLatencyMs = nil
            m.latencyHistory.append(nil)
        }
        if m.latencyHistory.count > 24 {
            m.latencyHistory.removeFirst()
        }

        // Пересчет процента потерь: за сессию и по скользящему окну
        m.lossRatePct = m.sentCount > 0 ? (Double(m.lostCount) / Double(m.sentCount) * 100.0) : 0.0
        let lostInWindow = m.latencyHistory.filter { $0 == nil }.count
        m.lossWindowPct = !m.latencyHistory.isEmpty ? (Double(lostInWindow) / Double(m.latencyHistory.count) * 100.0) : 0.0

        // Оценка статуса. «Недоступен» — только после нескольких неудач подряд: раньше один сбой в самом начале
        // (потери 1 из 1 = 100 %) или 2 потери из 24 (8 %) сразу объявляли узел упавшим.
        if m.consecutiveFailures >= Self.downAfterFailures {
            m.status = .down
            conditions.append((
                message: "Узел недоступен: \(m.consecutiveFailures) проверок подряд без ответа",
                severity: .critical,
                metric: "availability",
                currentVal: Double(m.consecutiveFailures),
                threshVal: Double(Self.downAfterFailures)
            ))
        } else {
            var isCritical = false
            var isWarning = false

            // Потери — по окну и только при достаточном числе проверок
            if m.latencyHistory.count >= Self.minSamplesForLossPct {
                if m.lossWindowPct >= lossCritThreshold {
                    isCritical = true
                    conditions.append((
                        message: "Потеря пакетов: \(String(format: "%.0f", m.lossWindowPct))%",
                        severity: .critical,
                        metric: "packet_loss",
                        currentVal: m.lossWindowPct,
                        threshVal: lossCritThreshold
                    ))
                } else if m.lossWindowPct >= lossCritThreshold / 2.0 {
                    isWarning = true
                    conditions.append((
                        message: "Повышенные потери пакетов: \(String(format: "%.0f", m.lossWindowPct))%",
                        severity: .warning,
                        metric: "packet_loss",
                        currentVal: m.lossWindowPct,
                        threshVal: lossCritThreshold / 2.0
                    ))
                }
            } else if m.consecutiveFailures > 0 {
                isWarning = true   // данных мало: последняя проверка неудачна — это предупреждение, а не тревога
            }

            // Задержка
            if let lat = m.lastLatencyMs {
                if lat > latencyCritThreshold {
                    isCritical = true
                    conditions.append((
                        message: "Высокая задержка: \(Int(lat)) мс",
                        severity: .critical,
                        metric: "latency",
                        currentVal: lat,
                        threshVal: latencyCritThreshold
                    ))
                } else if lat > latencyWarnThreshold {
                    isWarning = true
                    conditions.append((
                        message: "Повышенная задержка: \(Int(lat)) мс",
                        severity: .warning,
                        metric: "latency",
                        currentVal: lat,
                        threshVal: latencyWarnThreshold
                    ))
                }
            }

            // Джиттер (порог предупреждения задаётся в настройках, критический — вдвое выше)
            if m.jitterMs >= jitterWarnThreshold * 2.0 {
                isCritical = true
                conditions.append((
                    message: "Высокий джиттер: \(String(format: "%.1f", m.jitterMs)) мс",
                    severity: .critical,
                    metric: "jitter",
                    currentVal: m.jitterMs,
                    threshVal: jitterWarnThreshold * 2.0
                ))
            } else if m.jitterMs >= jitterWarnThreshold {
                isWarning = true
                conditions.append((
                    message: "Повышенный джиттер: \(String(format: "%.1f", m.jitterMs)) мс",
                    severity: .warning,
                    metric: "jitter",
                    currentVal: m.jitterMs,
                    threshVal: jitterWarnThreshold
                ))
            }

            m.status = isCritical ? .critical : (isWarning ? .warning : .ok)
        }

        return (m, emittedRtt, conditions)
    }

    // MARK: - Методы управления аналитикой трафика

    public func refreshTrafficData(period: TrafficPeriod) async {
        self.selectedTrafficPeriod = period
        let summary = await TrafficStorage.shared.getSummary(for: period)
        let sessions = await TrafficStorage.shared.getSessions(for: period)
        let points = await TrafficStorage.shared.getDataPoints(for: period)
        let budget = await TrafficStorage.shared.getBudget()

        // Виджет и квота считаются по СВОИМ периодам, а не по выбранному на экране (раньше любой выбранный
        // период — «7 дней», «Всё время» — попадал в виджет как «трафик сегодня» и сравнивался с лимитом)
        let today: TrafficSummary
        if period == .today {
            today = summary
        } else {
            today = await TrafficStorage.shared.getSummary(for: .today)
        }
        let budgetSummary: TrafficSummary
        if budget.period == period {
            budgetSummary = summary
        } else {
            budgetSummary = await TrafficStorage.shared.getSummary(for: budget.period)
        }

        self.trafficSummary = summary
        self.todayTrafficSummary = today
        self.budgetPeriodSummary = budgetSummary
        self.trafficSessions = sessions
        self.trafficDataPoints = points
        self.trafficBudget = budget

        self.syncWidgetData(reloadTimelines: true)
    }

    public func updateTrafficBudget(_ newBudget: TrafficBudget) async {
        await TrafficStorage.shared.updateBudget(newBudget)
        self.trafficBudget = newBudget
    }

    public func resetTrafficHistory() async {
        await TrafficStorage.shared.resetAllData()
        await refreshTrafficData(period: selectedTrafficPeriod)
    }

    public func exportTrafficCSV() async -> URL? {
        try? await TrafficStorage.shared.exportTrafficCSV()
    }

    public func exportTrafficJSON() async -> URL? {
        try? await TrafficStorage.shared.exportTrafficJSON()
    }

    // MARK: - Алерты (Только визуальное отображение в интерфейсе, без фоновой вибрации)

    private static func severityRank(_ severity: AlertSeverity) -> Int {
        switch severity {
        case .info: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    private func clearAlertState(for address: String) {
        let prefix = "\(address)|"
        let stale = alertStates.keys.filter { $0.hasPrefix(prefix) }
        for key in stale {
            alertStates.removeValue(forKey: key)
        }
        outageEpisodes.remove(address)
    }

    /// Алерты «по фронту»: выпускаются, когда условие появилось, усилилось (WARNING → CRITICAL) или держится
    /// дольше минуты. Раньше любой алерт по узлу глушил все остальные на 60 секунд, включая эскалацию.
    ///
    /// Эпизод сбоя (DOWN → … → OK): потери в окне после обрыва — «хвост» того же события, поэтому отдельный
    /// алерт по потерям в этот период не выпускается и состояние подавления не сбрасывается.
    private func emitAlerts(address: String, status: HostStatus, conditions: [PendingAlert]) {
        if status == .down {
            outageEpisodes.insert(address)
        } else if status == .ok {
            outageEpisodes.remove(address)
        }
        let inEpisode = outageEpisodes.contains(address)

        var activeKeys: Set<String> = []
        let now = Date()
        for condition in conditions {
            if inEpisode && condition.metric == "packet_loss" { continue }
            let key = "\(address)|\(condition.metric)"
            activeKeys.insert(key)

            let shouldEmit: Bool
            if let previous = alertStates[key] {
                shouldEmit = Self.severityRank(condition.severity) > Self.severityRank(previous.severity)
                    || now.timeIntervalSince(previous.date) >= alertCooldown
            } else {
                shouldEmit = true
            }
            if shouldEmit {
                alertStates[key] = (severity: condition.severity, date: now)
                publishAlert(address: address, condition: condition)
            }
        }

        // Условия, которые перестали выполняться, сбрасываем (повтор снова вызовет алерт)
        if !inEpisode {
            let prefix = "\(address)|"
            let stale = alertStates.keys.filter { $0.hasPrefix(prefix) && !activeKeys.contains($0) }
            for key in stale {
                alertStates.removeValue(forKey: key)
            }
        }
    }

    private func publishAlert(address: String, condition: PendingAlert) {
        guard let host = hostMetrics[address] else { return }

        let alert = NetworkAlert(
            host: host.address,
            targetName: host.name,
            severity: condition.severity,
            message: condition.message,
            metricName: condition.metric,
            currentValue: condition.currentVal,
            thresholdValue: condition.threshVal
        )

        recentAlerts.insert(alert, at: 0)
        if recentAlerts.count > 20 {
            recentAlerts.removeLast()
        }
        activeAlert = alert

        let history = storage
        Task {
            await history.recordAlert(alert)
        }

        // Тумблер «Звуковые предупреждения» раньше нигде не читался
        if soundEnabled && condition.severity == .critical {
            AudioServicesPlaySystemSound(1007)
        }
    }

    public func dismissAlert() {
        activeAlert = nil
    }

    // MARK: - Speedtest

    public func startSpeedtest() {
        guard !isSpeedtestRunning else { return }
        isSpeedtestRunning = true
        speedtestError = nil
        liveDownloadSpeed = 0.0
        liveUploadSpeed = 0.0

        if hapticsEnabled {
            HapticManager.shared.impactMedium()
        }

        if liveActivityEnabled {
            ActivityManager.shared.updateActivity(
                downloadSpeedText: "↓ Замер...",
                uploadSpeedText: "↑ Замер...",
                compactDownloadText: "…",
                compactUploadText: "…",
                pingMs: currentAveragePing,
                jitterMs: currentAverageJitter,
                isTesting: true,
                connectionType: systemInfo.connectionType.rawValue,
                ispName: systemInfo.ispName ?? "Интернет",
                force: true
            )
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.speedtestEngine.runSpeedtest { dl, ul in
                    Task { @MainActor in
                        self.liveDownloadSpeed = dl
                        self.liveUploadSpeed = ul

                        PiPHUDManager.shared.updateTelemetry(
                            downloadText: String(format: "%.1f Мбит/с", dl),
                            uploadText: String(format: "%.1f Мбит/с", ul),
                            pingMs: self.currentAveragePing,
                            jitterMs: self.currentAverageJitter,
                            connectionType: self.systemInfo.connectionType.rawValue,
                            isTesting: true
                        )

                        if self.liveActivityEnabled {
                            ActivityManager.shared.updateActivity(
                                downloadSpeedText: String(format: "↓ %.1f Мбит/с", dl),
                                uploadSpeedText: String(format: "↑ %.1f Мбит/с", ul),
                                compactDownloadText: BandwidthSnapshot.compactSpeed(mbps: dl),
                                compactUploadText: BandwidthSnapshot.compactSpeed(mbps: ul),
                                pingMs: self.currentAveragePing,
                                jitterMs: self.currentAverageJitter,
                                isTesting: true,
                                connectionType: self.systemInfo.connectionType.rawValue,
                                ispName: self.systemInfo.ispName ?? "Интернет"
                            )
                        }
                    }
                }
                self.lastSpeedtestResult = result
                self.liveDownloadSpeed = result.downloadMbps
                self.liveUploadSpeed = result.uploadMbps
                self.isSpeedtestRunning = false
                if !result.isSuccess {
                    self.speedtestError = "Скачивание измерено, а отдачу измерить не удалось — значение отдачи не показывается."
                }

                // Генерация мгновенного AI-вердикта
                let summary = AIDiagnosticsEngine.shared.generateSpeedtestSummary(
                    downloadMbps: result.downloadMbps,
                    uploadMbps: result.uploadMbps,
                    pingMs: self.currentAveragePing,
                    jitterMs: self.currentAverageJitter,
                    packetLossPct: self.currentPacketLossPct
                )
                self.instantAISummary = summary

                if self.liveActivityEnabled {
                    let ping = self.currentAveragePing
                    ActivityManager.shared.updateActivity(
                        downloadSpeedText: String(format: "%.1f Мбит/с", result.downloadMbps),
                        uploadSpeedText: result.uploadMbps > 0 ? String(format: "%.1f Мбит/с", result.uploadMbps) : "— Мбит/с",
                        compactDownloadText: BandwidthSnapshot.compactSpeed(mbps: result.downloadMbps),
                        compactUploadText: result.uploadMbps > 0 ? BandwidthSnapshot.compactSpeed(mbps: result.uploadMbps) : "—",
                        pingMs: ping,
                        jitterMs: self.currentAverageJitter,
                        isTesting: false,
                        connectionType: self.systemInfo.connectionType.rawValue,
                        ispName: self.systemInfo.ispName ?? "Интернет",
                        isGamingMode: self.floatingHUDEnabled,
                        packetLossPct: self.currentPacketLossPct,
                        force: true
                    )
                }

                if self.hapticsEnabled {
                    HapticManager.shared.notificationSuccess()
                }

                await self.storage.recordSpeedtest(result)
                self.syncWidgetData(reloadTimelines: true)
            } catch {
                print("⚠️ Ошибка Speedtest: \(error.localizedDescription)")
                self.isSpeedtestRunning = false
                // Замера не было — ничего не выдумываем: раньше подставлялось max(реальное, 15) Мбит/с вниз и 8 вверх,
                // результат помечался успешным («Локальный шлюз») и попадал в историю и виджеты.
                self.liveDownloadSpeed = 0.0
                self.liveUploadSpeed = 0.0
                self.instantAISummary = nil
                let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.speedtestError = "Замер скорости не удался. \(reason)"

                if self.hapticsEnabled {
                    HapticManager.shared.notificationError()
                }

                if self.liveActivityEnabled {
                    ActivityManager.shared.updateActivity(
                        downloadSpeedText: self.liveBandwidth.formattedDownloadSpeed,
                        uploadSpeedText: self.liveBandwidth.formattedUploadSpeed,
                        compactDownloadText: self.liveBandwidth.compactDownload,
                        compactUploadText: self.liveBandwidth.compactUpload,
                        pingMs: self.currentAveragePing,
                        jitterMs: self.currentAverageJitter,
                        isTesting: false,
                        connectionType: self.systemInfo.connectionType.rawValue,
                        ispName: self.systemInfo.ispName ?? "Интернет",
                        isGamingMode: self.floatingHUDEnabled,
                        packetLossPct: self.currentPacketLossPct,
                        force: true
                    )
                }
                self.syncWidgetData(reloadTimelines: true)
            }
        }
    }

    // MARK: - Метрики и сводки

    /// Данные узла считаются актуальными, если проверка была недавно. В фоне опрос остановлен, и «замороженное»
    /// значение не должно выдаваться за текущее: раньше остров показывал его бесконечно, а при отказе всех
    /// узлов подставлялся пинг прошлого speedtest (или выдуманные 28 мс).
    private func isFresh(_ metric: HostMetrics) -> Bool {
        guard let updated = metric.lastUpdated else { return false }
        return Date().timeIntervalSince(updated) < 15.0
    }

    /// Узлы, участвующие в сводных показателях (на сотовой сети домашнего шлюза нет)
    private var relevantHosts: [HostMetrics] {
        let isCellular = systemInfo.connectionType == .cellular
        return hostMetrics.values.filter { !($0.isGateway && isCellular) && isFresh($0) }
    }

    /// Средний пинг по узлам, отвечающим прямо сейчас; nil — свежих данных нет
    public var currentAveragePing: Double? {
        let latencies = relevantHosts.compactMap { $0.lastLatencyMs }.filter { $0 > 0 }
        guard !latencies.isEmpty else { return nil }
        return (latencies.reduce(0, +) / Double(latencies.count) * 10).rounded() / 10
    }

    /// Средний джиттер по отвечающим узлам (нужно минимум два успешных замера); nil — данных нет
    public var currentAverageJitter: Double? {
        let jitters = relevantHosts
            .filter { $0.lastLatencyMs != nil && $0.receivedCount >= 2 }
            .map { $0.jitterMs }
        guard !jitters.isEmpty else { return nil }
        return (jitters.reduce(0, +) / Double(jitters.count) * 10).rounded() / 10
    }

    /// Средний процент потерь по узлам со свежими данными (0, если данных нет — см. `hasLiveData`)
    public var currentPacketLossPct: Double {
        let losses = relevantHosts.map { $0.lossWindowPct }
        guard !losses.isEmpty else { return 0.0 }
        return (losses.reduce(0, +) / Double(losses.count) * 10).rounded() / 10
    }

    /// Есть ли свежие результаты проверок (иначе «0 % потерь» — это отсутствие данных, а не отличное качество)
    public var hasLiveData: Bool {
        !relevantHosts.isEmpty
    }

    /// Индекс здоровья сети по живым измерениям; nil — свежих данных нет.
    /// Раньше без данных выдавалось 100 («идеально»), а после первого AI-аудита значение «замораживалось».
    public var currentHealthScore: Int? {
        guard hasLiveData else { return nil }
        // Все узлы молчат — связи нет, это не «идеальное качество»
        guard let ping = currentAveragePing else { return 10 }
        var score = 100
        if ping > 50 {
            score -= min(Int((ping - 50) * 0.4), 30)
        }
        if let jitter = currentAverageJitter, jitter > 10 {
            score -= min(Int((jitter - 10) * 1.5), 25)
        }
        if currentPacketLossPct > 0 {
            score -= min(Int(currentPacketLossPct * 5), 40)
        }
        return max(score, 10)
    }

    /// Синхронизация снимка сетевых показателей с домашними виджетами и экраном блокировки
    public func syncWidgetData(reloadTimelines: Bool = false) {
        // В виджет попадают только узлы, которые реально проверялись; «нет данных» не рисуется как «онлайн»
        let dnsSnapshot: [WidgetDNSHost] = targets.compactMap { target -> WidgetDNSHost? in
            guard let metrics = hostMetrics[target.address], metrics.sentCount > 0 else { return nil }
            let fresh = isFresh(metrics)
            return WidgetDNSHost(
                name: target.name,
                address: metrics.address,
                latencyMs: fresh ? metrics.lastLatencyMs : nil,
                isOK: fresh && metrics.status == .ok
            )
        }

        let widgetData = NetPulseWidgetData(
            downloadSpeedMbps: liveDownloadSpeed > 0 ? liveDownloadSpeed : (lastSpeedtestResult?.downloadMbps ?? liveBandwidth.downloadMbps),
            uploadSpeedMbps: liveUploadSpeed > 0 ? liveUploadSpeed : (lastSpeedtestResult?.uploadMbps ?? liveBandwidth.uploadMbps),
            pingMs: currentAveragePing,
            jitterMs: currentAverageJitter,
            lossPercent: currentPacketLossPct,
            ispName: currentNetworkTitle,
            connectionType: systemInfo.connectionType.rawValue,
            todayTrafficBytes: Int64(todayTrafficSummary.totalTraffic),
            budgetTotalBytes: (trafficBudget.isEnabled && trafficBudget.limitBytes > 0) ? Int64(trafficBudget.limitBytes) : 0,
            budgetUsedBytes: Int64(budgetPeriodSummary.totalTraffic),
            healthScore: currentHealthScore,
            dnsHosts: Array(dnsSnapshot.prefix(4)),
            lastUpdated: Date()
        )

        WidgetDataManager.shared.saveSnapshot(widgetData, reloadTimelines: reloadTimelines)
    }

    // MARK: - Traceroute (MTR)

    public func startTraceroute(for host: String) {
        // Для шлюза в списке стоит заглушка «gateway» — трассируется его реальный адрес
        var resolvedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedHost == "gateway" || resolvedHost.isEmpty {
            resolvedHost = systemInfo.gatewayIP ?? ""
        }

        // Уже идёт трассировка — просто показываем её, а не запускаем вторую параллельно
        if isTracerouteRunning {
            showTracerouteSheet = true
            return
        }

        selectedTracerouteTarget = resolvedHost.isEmpty ? host : resolvedHost
        tracerouteHops = []
        tracerouteError = nil
        showTracerouteSheet = true
        HapticManager.shared.impactMedium()

        guard !resolvedHost.isEmpty else {
            tracerouteError = "Адрес шлюза не определён (мобильная сеть или нет подключения)"
            isTracerouteRunning = false
            return
        }

        isTracerouteRunning = true
        let targetHost = resolvedHost

        Task { [weak self] in
            guard let self else { return }
            let hops = await self.tracerouteEngine.traceRoute(to: targetHost) { hop in
                Task { @MainActor in
                    // Хоп мог уже попасть в итоговый список — не дублируем
                    if !self.tracerouteHops.contains(where: { $0.hopNumber == hop.hopNumber }) {
                        self.tracerouteHops.append(hop)
                    }
                }
            }
            self.tracerouteHops = hops
            self.tracerouteError = await self.tracerouteEngine.lastError
            self.isTracerouteRunning = false
            if self.hapticsEnabled {
                if hops.contains(where: { $0.ipAddress != nil }) {
                    HapticManager.shared.notificationSuccess()
                } else {
                    HapticManager.shared.notificationError()
                }
            }
        }
    }

    // MARK: - Экспорт отчетов

    public func getExportJSONURL() async throws -> URL {
        try await storage.exportSessionToJSON()
    }

    public func getExportCSVURL() async throws -> URL {
        try await storage.exportSessionToCSV()
    }

    // MARK: - AI Диагност (Network AI Copilot & Agent)

    public var currentHealthReport: NetworkHealthReport?
    public var currentAnomalyReport: NetworkAnomalyReport?
    public var aiMessages: [AIMessage] = []
    public var isAIAnalyzing: Bool = false
    public var activeToolCall: AIToolCall? = nil
    /// Провайдер и модель хранятся в настройках, ключ API — в Keychain (раньше конфигурация сбрасывалась при каждом запуске)
    public var aiProviderConfig: AIProviderConfig = AIConfigStore.load()
    public var selectedTroubleshootingScenario: TroubleshootingScenarioType = .gaming
    public var selectedDisputeTemplate: ISPDisputeTemplate = .packetLossAndLatency
    public var showDisputeSheet: Bool = false

    public func buildDiagnosticsContext() -> NetworkDiagnosticsContext {
        NetworkDiagnosticsContext(
            connectionType: systemInfo.connectionType.rawValue,
            localIP: systemInfo.localIP,
            gatewayIP: systemInfo.gatewayIP,
            publicIP: systemInfo.publicIP,
            ispName: systemInfo.ispName,
            dnsServers: systemInfo.dnsServers,
            averagePingMs: currentAveragePing,
            jitterMs: currentAverageJitter,
            packetLossPct: currentPacketLossPct,
            hasLiveData: hasLiveData,
            liveDownloadMbps: liveBandwidth.downloadMbps,
            liveUploadMbps: liveBandwidth.uploadMbps,
            speedtestDownloadMbps: lastSpeedtestResult?.downloadMbps,
            speedtestUploadMbps: lastSpeedtestResult?.uploadMbps,
            recentAlertsCount: recentAlerts.count,
            tracerouteHopsCount: tracerouteHops.count
        )
    }

    public var smartContextChips: [String] {
        let context = buildDiagnosticsContext()
        return AIDiagnosticsEngine.shared.generateSmartContextChips(context: context, anomalyReport: currentAnomalyReport)
    }

    public func runAIDiagnosticsAudit() async {
        guard !isAIAnalyzing else { return }
        isAIAnalyzing = true
        HapticManager.shared.impactMedium()

        let context = buildDiagnosticsContext()
        let report = AIDiagnosticsEngine.shared.evaluateNetworkHealth(context: context)
        self.currentHealthReport = report

        // Сканирование предиктивных сетевых аномалий
        // Расход берётся за период квоты, а не за период, выбранный на экране «Трафик»
        let anomalies = AINetworkAnomalyDetector.shared.analyzeAnomalies(
            context: context,
            hostMetrics: hostMetrics,
            trafficSummary: budgetPeriodSummary,
            budget: trafficBudget
        )
        self.currentAnomalyReport = anomalies

        if aiMessages.isEmpty {
            let scoreLine: String
            if let score = report.overallScore {
                scoreLine = "Индекс здоровья сети — **\(score) из 100** (\(report.statusTitle))."
            } else {
                scoreLine = "\(report.statusTitle): \(report.summaryText)"
            }
            let greeting = """
            Привет! Я сетевой диагност **NetPulse AI**.

            \(scoreLine)

            В диалоге я могу выполнять реальные замеры (пинг, трассировка, DNS, Bufferbloat), объяснять показатели, запускать пошаговый мастер траблшутинга и готовить обращение к провайдеру.
            """
            aiMessages.append(AIMessage(role: .assistant, content: greeting))
        }

        isAIAnalyzing = false
        if hapticsEnabled {
            HapticManager.shared.notificationSuccess()
        }
    }

    public func sendAIMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // История диалога без текущего вопроса: он передаётся отдельно (раньше модель получала только последнюю реплику)
        let history = aiMessages
        let userMsg = AIMessage(role: .user, content: text)
        aiMessages.append(userMsg)
        isAIAnalyzing = true

        let context = buildDiagnosticsContext()

        let (response, toolCall, toolResult) = await AIDiagnosticsEngine.shared.executeAgenticQuery(
            prompt: text,
            context: context,
            config: aiProviderConfig,
            history: history,
            anomalyReport: currentAnomalyReport
        ) { [weak self] call in
            Task { @MainActor in
                self?.activeToolCall = call
            }
        }

        self.activeToolCall = nil
        let assistantMsg = AIMessage(
            role: .assistant,
            content: response,
            toolCall: toolCall,
            toolResult: toolResult
        )
        aiMessages.append(assistantMsg)
        isAIAnalyzing = false

        if hapticsEnabled {
            HapticManager.shared.impactLight()
        }
    }

    public func updateAIConfig(_ newConfig: AIProviderConfig) {
        self.aiProviderConfig = newConfig
        AIConfigStore.save(newConfig)
    }

    // MARK: - Интерактивный мастер устранения неполадок (Fixer Wizard)

    public var isTroubleshootingRunning: Bool = false
    public var troubleshootingReport: TroubleshootingReport?
    public var currentTroubleshootingStep: TroubleshootingStep?
    public var showTroubleshootingSheet: Bool = false

    public func runTroubleshootingWizard(scenario: TroubleshootingScenarioType? = nil) async {
        guard !isTroubleshootingRunning else { return }
        let targetScenario = scenario ?? selectedTroubleshootingScenario
        self.selectedTroubleshootingScenario = targetScenario
        isTroubleshootingRunning = true
        showTroubleshootingSheet = true
        HapticManager.shared.impactMedium()

        let context = buildDiagnosticsContext()
        let report = await AIDiagnosticsEngine.shared.runTroubleshootingWizard(
            scenario: targetScenario,
            context: context,
            hostMetrics: hostMetrics
        ) { [weak self] step in
            Task { @MainActor in
                self?.currentTroubleshootingStep = step
            }
        }
        self.troubleshootingReport = report
        self.isTroubleshootingRunning = false
        if hapticsEnabled {
            HapticManager.shared.notificationSuccess()
        }
    }

    public func copyISPSupportReport(template: ISPDisputeTemplate = .packetLossAndLatency) -> String {
        let context = buildDiagnosticsContext()
        let report = context.generateISPSupportReport(template: template)
        UIPasteboard.general.string = report
        if hapticsEnabled {
            HapticManager.shared.notificationSuccess()
        }
        return report
    }
}
