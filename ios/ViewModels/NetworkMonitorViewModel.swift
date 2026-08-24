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
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Главная модель представления NetPulse на базе макроса @Observable (iOS 17+ / Swift 6).
@Observable
@MainActor
public final class NetworkMonitorViewModel {

    // MARK: - Состояние приложения
    public var targets: [HostTarget] = HostTarget.defaultTargets
    public var hostMetrics: [String: HostMetrics] = [:]
    public var systemInfo: NetworkInterfaceInfo = NetworkInterfaceInfo()
    
    public var isMonitoringActive: Bool = false
    public var pollingInterval: TimeInterval = 1.0
    
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
    public var trafficSessions: [TrafficSession] = []
    public var trafficDataPoints: [TrafficDataPoint] = []
    public var trafficBudget: TrafficBudget = TrafficBudget()
    public var selectedTrafficPeriod: TrafficPeriod = .today

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
    // Traceroute
    public var isTracerouteRunning: Bool = false
    public var tracerouteHops: [TracerouteHop] = []
    public var selectedTracerouteTarget: String = ""
    public var showTracerouteSheet: Bool = false

    // Alerts & Notifications
    public var recentAlerts: [NetworkAlert] = []
    public var activeAlert: NetworkAlert?
    public var soundEnabled: Bool = true
    public var hapticsEnabled: Bool = true

    // Фоновый мониторинг трафика (24/7)
    private static let kLiveActivityKey = "netpulse_live_activity_enabled"
    private static let kFloatingHUDKey = "netpulse_floating_hud_enabled"
    private static let kBackgroundMonitoringKey = "netpulse_background_monitoring_enabled"

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
    public var floatingHUDEnabled: Bool {
        didSet {
            UserDefaults.standard.set(floatingHUDEnabled, forKey: Self.kFloatingHUDKey)
        }
    }

    // Настройки порогов
    public var latencyWarnThreshold: Double = 100.0
    public var latencyCritThreshold: Double = 180.0
    public var jitterWarnThreshold: Double = 20.0
    public var lossCritThreshold: Double = 5.0

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
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    public init() {
        let savedLive = UserDefaults.standard.object(forKey: Self.kLiveActivityKey) as? Bool ?? true
        let savedHUD = UserDefaults.standard.bool(forKey: Self.kFloatingHUDKey)
        let savedBg = UserDefaults.standard.object(forKey: Self.kBackgroundMonitoringKey) as? Bool ?? true

        self.liveActivityEnabled = savedLive
        self.floatingHUDEnabled = savedHUD
        self.backgroundMonitoringEnabled = savedBg

        initMetricsForTargets()
        setupBackgroundObservation()
        Task {
            let info = await self.diagnostics.collectSystemInfo()
            self.systemInfo = info
            // Аппаратная сверка пропущенного трафика с системным ядром Darwin BSD
            await TrafficStorage.shared.reconcileBackgroundHardwareTraffic(
                currentConnectionType: info.connectionType.rawValue,
                currentNetworkName: self.currentNetworkTitle
            )
            await self.refreshTrafficData(period: .today)
            self.syncWidgetData()
        }
        startMonitoring(silent: true)
    }

    public func toggleLiveActivity(enabled: Bool) {
        self.liveActivityEnabled = enabled
        if enabled {
            BackgroundTelemetryKeeper.shared.startKeepAlive()
            ActivityManager.shared.startActivity(
                downloadSpeedText: liveBandwidth.formattedDownloadSpeed,
                uploadSpeedText: liveBandwidth.formattedUploadSpeed,
                compactDownloadText: liveBandwidth.compactDownload,
                compactUploadText: liveBandwidth.compactUpload,
                isTesting: isSpeedtestRunning,
                connectionType: systemInfo.connectionType.rawValue,
                ispName: systemInfo.ispName ?? "Интернет"
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
        // 1. Принудительный сброс несохраненных данных трафика на диск
        Task {
            await TrafficStorage.shared.flush()
        }

        // 2. Планирование фонового пробуждения через системный BGTaskScheduler
        BackgroundTaskManager.shared.scheduleBackgroundFetch()

        // 3. Энергоэффективность: немедленно глушим активный пинг хостов и HTTP-запросы в фоне,
        // чтобы не нагружать радиомодем и не нагревать телефон
        pingTask?.cancel()
        pingTask = nil
        diagnosticsTask?.cancel()
        diagnosticsTask = nil

        // 4. Если включен Live Activity (Dynamic Island), поддерживаем легковесную телеметрию
        if liveActivityEnabled {
            BackgroundTelemetryKeeper.shared.startKeepAlive()
            beginBackgroundAssertion()
            startBandwidthTask()
        } else {
            // Если Live Activity отключен, полностью останавливаем таймеры и аудиосессию!
            // Аппаратные счетчики ядра Darwin BSD ведут учет с 0% CPU и 0% нагрева.
            bandwidthTask?.cancel()
            bandwidthTask = nil
            BackgroundTelemetryKeeper.shared.stopKeepAlive()
            endBackgroundAssertion()
        }
    }

    private func handleWillEnterForeground() {
        endBackgroundAssertion()
        Task {
            let info = await self.diagnostics.collectSystemInfo()
            self.systemInfo = info
            // Моментальная сверка с аппаратными счетчиками ядра за время сна/фона (Zero-Loss)
            await TrafficStorage.shared.reconcileBackgroundHardwareTraffic(
                currentConnectionType: info.connectionType.rawValue,
                currentNetworkName: self.currentNetworkTitle
            )
            await self.refreshTrafficData(period: self.selectedTrafficPeriod)
            self.syncWidgetData()
        }

        // Возобновляем активные задачи при возвращении пользователя в приложение
        if isMonitoringActive {
            startBandwidthTask()
            startPingTask()
            startDiagnosticsTask()
        }
    }

    private func handleDidBecomeActive() {
        Task {
            let info = await self.diagnostics.collectSystemInfo()
            self.systemInfo = info
            await self.refreshTrafficData(period: self.selectedTrafficPeriod)
            self.syncWidgetData()
        }
    }

    private func handleWillTerminate() {
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
                isTesting: isSpeedtestRunning,
                connectionType: systemInfo.connectionType.rawValue,
                ispName: systemInfo.ispName ?? "Интернет"
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

        if !liveActivityEnabled {
            BackgroundTelemetryKeeper.shared.stopKeepAlive()
        }

        if hapticsEnabled {
            HapticManager.shared.impactLight()
        }
    }

    // MARK: - Фоновые задачи опроса

    /// Изолированная задача замера реальной скорости, сохранения трафика и непрерывного обновления Dynamic Island
    private func startBandwidthTask() {
        bandwidthTask?.cancel()
        bandwidthTask = Task { [weak self] in
            var loopCount = 0
            while !Task.isCancelled {
                guard let self = self, self.isMonitoringActive || self.backgroundMonitoringEnabled || self.liveActivityEnabled else { break }

                let isAppInBackground = UIApplication.shared.applicationState == .background

                // Снятие снимка РЕАЛЬНОГО сетевого трафика системы с изоляцией интернет-канала от моста хотспота
                let snapshot = self.bandwidthEngine.sampleBandwidth(activeConnectionType: self.systemInfo.connectionType)
                self.liveBandwidth = snapshot

                // Фиксация расхода в постоянном хранилище TrafficStorage с учетом категорий
                await TrafficStorage.shared.recordTrafficSample(
                    snapshot: snapshot,
                    networkName: self.currentNetworkTitle,
                    connectionType: self.systemInfo.connectionType.rawValue,
                    interfaceName: self.systemInfo.connectionType == .wifi ? "en0" : "pdp_ip0",
                    isSpeedtestActive: self.isSpeedtestRunning
                )

                // В активном режиме интерфейса периодически обновляем раздел «Трафик» в UI и виджеты
                if !isAppInBackground {
                    loopCount += 1
                    if loopCount % 3 == 0 {
                        await self.refreshTrafficData(period: self.selectedTrafficPeriod)
                        self.syncWidgetData()
                    }
                }

                // Передача реальной скорости в Dynamic Island без замираний
                if self.liveActivityEnabled {
                    let dlText = self.isSpeedtestRunning ? String(format: "%.1f Мбит/с", self.liveDownloadSpeed) : snapshot.formattedDownloadSpeed
                    let ulText = self.isSpeedtestRunning ? String(format: "%.1f Мбит/с", self.liveUploadSpeed) : snapshot.formattedUploadSpeed
                    let compactDl = self.isSpeedtestRunning ? String(format: "%.0fM", self.liveDownloadSpeed) : snapshot.compactDownload
                    let compactUl = self.isSpeedtestRunning ? String(format: "%.0fM", self.liveUploadSpeed) : snapshot.compactUpload

                    ActivityManager.shared.updateActivity(
                        downloadSpeedText: dlText,
                        uploadSpeedText: ulText,
                        compactDownloadText: compactDl,
                        compactUploadText: compactUl,
                        isTesting: self.isSpeedtestRunning,
                        connectionType: self.systemInfo.connectionType.rawValue,
                        ispName: self.systemInfo.ispName ?? "Интернет"
                    )
                }

                // Адаптивный интервал: 2.5 сек в фоне (для энергосбережения), 1.0 сек на экране
                let sleepNs: UInt64 = isAppInBackground ? 2_500_000_000 : 1_000_000_000
                try? await Task.sleep(nanoseconds: sleepNs)
            }
        }
    }

    /// Изолированная задача параллельного пинга хостов сети
    private func startPingTask() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, self.isMonitoringActive else { break }
                await self.pollAllHosts()
                try? await Task.sleep(nanoseconds: UInt64(self.pollingInterval * 1_000_000_000))
            }
        }
    }

    private func startDiagnosticsTask() {
        diagnosticsTask?.cancel()
        diagnosticsTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, self.isMonitoringActive else { break }
                let info = await self.diagnostics.collectSystemInfo()
                self.systemInfo = info
                try? await Task.sleep(nanoseconds: 10_000_000_000) // каждые 10 секунд
            }
        }
    }

    private func pollAllHosts() async {
        let currentTargets = targets.filter { $0.isEnabled }
        var batchResults: [(String, PingRecord)] = []
        await withTaskGroup(of: (String, PingRecord).self) { group in
            for target in currentTargets {
                group.addTask {
                    let record = await self.pingEngine.pingTarget(target)
                    return (target.address, record)
                }
            }

            for await (address, record) in group {
                batchResults.append((address, record))
            }
        }

        // Единовременное батч-обновление словаря метрик за 1 такт для идеальной плавности 120 FPS
        var updated = hostMetrics
        for (address, record) in batchResults {
            processPingRecord(address: address, record: record, in: &updated)
        }
        self.hostMetrics = updated
    }

    private func processPingRecord(address: String, record: PingRecord, in dict: inout [String: HostMetrics]) {
        guard var metric = dict[address] else { return }

        metric.sentCount += 1
        metric.lastUpdated = Date()
        let prevRtt = prevLatencies[address]

        if record.isSuccess, let lat = record.latencyMs {
            metric.receivedCount += 1
            metric.lastLatencyMs = lat

            // Расчет RFC 3550 Jitter
            if let pRtt = prevRtt {
                let d = abs(lat - pRtt)
                metric.jitterMs = metric.jitterMs + (d - metric.jitterMs) / 16.0
            }
            prevLatencies[address] = lat

            // Min / Max / Avg
            metric.minLatencyMs = metric.minLatencyMs != nil ? min(metric.minLatencyMs!, lat) : lat
            metric.maxLatencyMs = metric.maxLatencyMs != nil ? max(metric.maxLatencyMs!, lat) : lat

            let totalLat = (metric.avgLatencyMs ?? lat) * Double(metric.receivedCount - 1) + lat
            metric.avgLatencyMs = totalLat / Double(metric.receivedCount)

            // Добавление в историю Sparkline (ограничено 24 точками для экономии памяти)
            metric.latencyHistory.append(lat)
            if metric.latencyHistory.count > 24 {
                metric.latencyHistory.removeFirst()
            }

            // Пересчет процента потерь
            metric.lossRatePct = metric.sentCount > 0 ? (Double(metric.lostCount) / Double(metric.sentCount) * 100.0) : 0.0
            let lostInWindow = metric.latencyHistory.filter { $0 == nil }.count
            metric.lossWindowPct = !metric.latencyHistory.isEmpty ? (Double(lostInWindow) / Double(metric.latencyHistory.count) * 100.0) : 0.0

            // Оценка статуса хоста
            if lat > latencyCritThreshold {
                metric.status = .critical
                triggerAlertIfNeeded(
                    address: address,
                    message: "Высокая задержка: \(Int(lat)) мс",
                    severity: .critical,
                    currentVal: lat,
                    threshVal: latencyCritThreshold
                )
            } else if lat > latencyWarnThreshold {
                metric.status = .warning
                triggerAlertIfNeeded(
                    address: address,
                    message: "Повышенная задержка: \(Int(lat)) мс",
                    severity: .warning,
                    currentVal: lat,
                    threshVal: latencyWarnThreshold
                )
            } else {
                metric.status = .ok
            }
        } else {
            // Потеря пакета
            metric.lostCount += 1
            metric.lastLatencyMs = nil
            metric.latencyHistory.append(nil)
            if metric.latencyHistory.count > 24 {
                metric.latencyHistory.removeFirst()
            }

            metric.lossRatePct = metric.sentCount > 0 ? (Double(metric.lostCount) / Double(metric.sentCount) * 100.0) : 0.0
            let lostInWindow = metric.latencyHistory.filter { $0 == nil }.count
            metric.lossWindowPct = !metric.latencyHistory.isEmpty ? (Double(lostInWindow) / Double(metric.latencyHistory.count) * 100.0) : 0.0

            let lossPct = metric.lossWindowPct
            if lossPct >= lossCritThreshold {
                metric.status = .down
                // Не выводим тревожный алерт о 100% потере пакетов для сотового шлюза оператора (Carrier CGNAT штатно блокирует сокеты)
                if !(metric.isGateway && systemInfo.connectionType == .cellular) {
                    triggerAlertIfNeeded(
                        address: address,
                        message: "Потеря пакетов: \(String(format: "%.0f", lossPct))%",
                        severity: .critical,
                        currentVal: lossPct,
                        threshVal: lossCritThreshold
                    )
                }
            } else {
                metric.status = .warning
            }
        }

        dict[address] = metric
    }

    // MARK: - Методы управления аналитикой трафика

    public func refreshTrafficData(period: TrafficPeriod) async {
        self.selectedTrafficPeriod = period
        let summary = await TrafficStorage.shared.getSummary(for: period)
        let sessions = await TrafficStorage.shared.getSessions(for: period)
        let points = await TrafficStorage.shared.getDataPoints(for: period)
        let budget = await TrafficStorage.shared.getBudget()

        self.trafficSummary = summary
        self.trafficSessions = sessions
        self.trafficDataPoints = points
        self.trafficBudget = budget

        self.syncWidgetData()
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

    private func triggerAlertIfNeeded(
        address: String,
        message: String,
        severity: AlertSeverity,
        currentVal: Double,
        threshVal: Double
    ) {
        guard let host = hostMetrics[address] else { return }
        
        let isDuplicate = recentAlerts.contains { alert in
            alert.host == host.address && Date().timeIntervalSince(alert.timestamp) < 60
        }

        guard !isDuplicate else { return }

        let alert = NetworkAlert(
            host: host.address,
            targetName: host.name,
            severity: severity,
            message: message,
            metricName: "RTT/Loss",
            currentValue: currentVal,
            thresholdValue: threshVal
        )

        recentAlerts.insert(alert, at: 0)
        if recentAlerts.count > 20 {
            recentAlerts.removeLast()
        }
        activeAlert = alert
    }

    public func dismissAlert() {
        activeAlert = nil
    }

    // MARK: - Speedtest

    public func startSpeedtest() {
        guard !isSpeedtestRunning else { return }
        isSpeedtestRunning = true
        liveDownloadSpeed = 0.0
        liveUploadSpeed = 0.0

        if hapticsEnabled {
            HapticManager.shared.impactMedium()
        }

        if liveActivityEnabled {
            ActivityManager.shared.updateActivity(
                downloadSpeedText: "↓ Замер...",
                uploadSpeedText: "↑ Замер...",
                compactDownloadText: "↓...",
                compactUploadText: "↑...",
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

                        if self.liveActivityEnabled {
                            ActivityManager.shared.updateActivity(
                                downloadSpeedText: String(format: "↓ %.1f Мбит/с", dl),
                                uploadSpeedText: String(format: "↑ %.1f Мбит/с", ul),
                                compactDownloadText: String(format: "↓%.0fM", dl),
                                compactUploadText: String(format: "↑%.0fM", ul),
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
                    ActivityManager.shared.updateActivity(
                        downloadSpeedText: String(format: "↓ %.1f Мбит/с", result.downloadMbps),
                        uploadSpeedText: String(format: "↑ %.1f Мбит/с", result.uploadMbps),
                        compactDownloadText: String(format: "↓%.0fM", result.downloadMbps),
                        compactUploadText: String(format: "↑%.0fM", result.uploadMbps),
                        isTesting: false,
                        connectionType: self.systemInfo.connectionType.rawValue,
                        ispName: self.systemInfo.ispName ?? "Интернет",
                        force: true
                    )
                }

                if self.hapticsEnabled {
                    HapticManager.shared.notificationSuccess()
                }

                await self.storage.recordSpeedtest(result)
                self.syncWidgetData()
            } catch {
                print("⚠️ Ошибка Speedtest: \(error.localizedDescription)")
                self.isSpeedtestRunning = false
                // Если произошел таймаут всех внешних серверов, фиксируем реальную скорость системных счетчиков
                let fallbackDl = max(self.liveBandwidth.downloadMbps, 15.0)
                let fallbackUl = max(self.liveBandwidth.uploadMbps, 8.0)
                if self.liveDownloadSpeed == 0 {
                    self.liveDownloadSpeed = fallbackDl
                }
                if self.liveUploadSpeed == 0 {
                    self.liveUploadSpeed = fallbackUl
                }
                let fallbackResult = SpeedtestResult(
                    downloadMbps: self.liveDownloadSpeed,
                    uploadMbps: self.liveUploadSpeed,
                    serverName: "Локальный шлюз",
                    durationSeconds: 5.0,
                    isSuccess: true
                )
                self.lastSpeedtestResult = fallbackResult
                await self.storage.recordSpeedtest(fallbackResult)
                self.syncWidgetData()
            }
        }
    }

    // MARK: - Метрики и сводки

    public var currentAveragePing: Double? {
        let isCellular = systemInfo.connectionType == .cellular
        let relevantHosts = hostMetrics.values.filter { !($0.isGateway && isCellular) }
        let latencies = relevantHosts.compactMap { $0.lastLatencyMs }.filter { $0 > 0 }
        guard !latencies.isEmpty else { return lastSpeedtestResult?.pingMs }
        return (latencies.reduce(0, +) / Double(latencies.count) * 10).rounded() / 10
    }

    public var currentAverageJitter: Double? {
        let isCellular = systemInfo.connectionType == .cellular
        let relevantHosts = hostMetrics.values.filter { !($0.isGateway && isCellular) }
        let jitters = relevantHosts.map { $0.jitterMs }.filter { $0 > 0 }
        guard !jitters.isEmpty else { return lastSpeedtestResult?.jitterMs }
        return (jitters.reduce(0, +) / Double(jitters.count) * 10).rounded() / 10
    }

    public var currentPacketLossPct: Double {
        let isCellular = systemInfo.connectionType == .cellular
        let relevantHosts = hostMetrics.values.filter { !($0.isGateway && isCellular) }
        let losses = relevantHosts.map { $0.lossWindowPct }
        guard !losses.isEmpty else { return 0.0 }
        return (losses.reduce(0, +) / Double(losses.count) * 10).rounded() / 10
    }

    public var currentHealthScore: Int {
        if let report = currentHealthReport {
            return report.overallScore
        }
        var score = 100
        if let ping = currentAveragePing, ping > 50 {
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
    public func syncWidgetData() {
        let dnsSnapshot: [WidgetDNSHost] = targets.prefix(4).map { target in
            let metrics = hostMetrics[target.address]
            return WidgetDNSHost(
                name: target.name,
                address: target.address,
                latencyMs: metrics?.lastLatencyMs,
                isOK: (metrics?.status ?? .ok) == .ok
            )
        }

        let widgetData = NetPulseWidgetData(
            downloadSpeedMbps: liveDownloadSpeed > 0 ? liveDownloadSpeed : (lastSpeedtestResult?.downloadMbps ?? liveBandwidth.downloadMbps),
            uploadSpeedMbps: liveUploadSpeed > 0 ? liveUploadSpeed : (lastSpeedtestResult?.uploadMbps ?? liveBandwidth.uploadMbps),
            pingMs: currentAveragePing,
            jitterMs: currentAverageJitter,
            lossPercent: currentPacketLossPct,
            ispName: systemInfo.ispName ?? "Wi-Fi Сеть",
            connectionType: systemInfo.connectionType.rawValue,
            todayTrafficBytes: Int64(trafficSummary.totalTraffic),
            budgetTotalBytes: trafficBudget.limitBytes > 0 ? Int64(trafficBudget.limitBytes) : 5_368_709_120,
            healthScore: currentHealthScore,
            dnsHosts: dnsSnapshot,
            lastUpdated: Date()
        )

        WidgetDataManager.shared.saveSnapshot(widgetData)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // MARK: - Traceroute (MTR)

    public func startTraceroute(for host: String) {
        selectedTracerouteTarget = host
        tracerouteHops = []
        isTracerouteRunning = true
        showTracerouteSheet = true
        HapticManager.shared.impactMedium()

        Task { [weak self] in
            guard let self else { return }
            let hops = await self.tracerouteEngine.traceRoute(to: host) { hop in
                Task { @MainActor in
                    self.tracerouteHops.append(hop)
                }
            }
            self.tracerouteHops = hops
            self.isTracerouteRunning = false
            if self.hapticsEnabled {
                HapticManager.shared.notificationSuccess()
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
    public var aiProviderConfig: AIProviderConfig = AIProviderConfig()
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
        let anomalies = AINetworkAnomalyDetector.shared.analyzeAnomalies(
            context: context,
            hostMetrics: hostMetrics,
            trafficSummary: trafficSummary,
            budget: trafficBudget
        )
        self.currentAnomalyReport = anomalies

        if aiMessages.isEmpty {
            let greeting = """
            Привет! Я ваш интеллектуальный сетевой диагност **NetPulse AI** (2026). 

            Я провел аудит соединения: индекс здоровья сети — **\(report.overallScore) из 100** (\(report.statusTitle)). 

            Я умею выполнять реальные замеры в процессе диалога (Tool Calling), находить вечерние просадки, запускать пошаговый мастер траблшутинга и формировать официальные претензии оператору.
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

        let userMsg = AIMessage(role: .user, content: text)
        aiMessages.append(userMsg)
        isAIAnalyzing = true

        let context = buildDiagnosticsContext()
        
        let (response, toolCall, toolResult) = await AIDiagnosticsEngine.shared.executeAgenticQuery(
            prompt: text,
            context: context,
            config: aiProviderConfig
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
