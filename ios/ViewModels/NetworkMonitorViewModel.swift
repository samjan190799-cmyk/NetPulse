//
//  NetworkMonitorViewModel.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import SwiftUI
import Observation

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
    public var backgroundMonitoringEnabled: Bool = true

    // Виджеты: Dynamic Island & Игровой HUD
    public var liveActivityEnabled: Bool = false
    public var floatingHUDEnabled: Bool = false

    // Настройки порогов
    public var latencyWarnThreshold: Double = 100.0
    public var latencyCritThreshold: Double = 180.0
    public var jitterWarnThreshold: Double = 20.0
    public var lossCritThreshold: Double = 5.0

    // MARK: - Движки и зависимости
    private let pingEngine = PingEngine(timeout: 2.0)
    private let bandwidthEngine = BandwidthEngine()
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
        initMetricsForTargets()
        setupBackgroundObservation()
        Task {
            let info = await self.diagnostics.collectSystemInfo()
            self.systemInfo = info
            // Аппаратная сверка пропущенного трафика с системным ядром
            await TrafficStorage.shared.reconcileBackgroundHardwareTraffic(
                currentConnectionType: info.connectionType.rawValue,
                currentNetworkName: self.currentNetworkTitle
            )
            await self.refreshTrafficData(period: .today)
        }
        startMonitoring()
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
    }

    private func handleDidEnterBackground() {
        if backgroundMonitoringEnabled || liveActivityEnabled || isMonitoringActive {
            BackgroundTelemetryKeeper.shared.startKeepAlive()
            bgTask = UIApplication.shared.beginBackgroundTask(withName: "NetPulseBackgroundTelemetry") { [weak self] in
                guard let self else { return }
                if self.bgTask != .invalid {
                    UIApplication.shared.endBackgroundTask(self.bgTask)
                    self.bgTask = .invalid
                }
            }
            if !isMonitoringActive {
                startBandwidthTask()
            }
        }
    }

    private func handleWillEnterForeground() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        Task {
            let info = await self.diagnostics.collectSystemInfo()
            self.systemInfo = info
            // Моментальная сверка с аппаратными счетчиками за время сна/фона
            await TrafficStorage.shared.reconcileBackgroundHardwareTraffic(
                currentConnectionType: info.connectionType.rawValue,
                currentNetworkName: self.currentNetworkTitle
            )
            await self.refreshTrafficData(period: self.selectedTrafficPeriod)
        }
        if !backgroundMonitoringEnabled && !liveActivityEnabled && !isMonitoringActive {
            BackgroundTelemetryKeeper.shared.stopKeepAlive()
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

    public func startMonitoring() {
        guard !isMonitoringActive else { return }
        isMonitoringActive = true

        BackgroundTelemetryKeeper.shared.startKeepAlive()

        if hapticsEnabled {
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
                guard let self = self, self.isMonitoringActive else { break }

                // Снятие снимка РЕАЛЬНОГО сетевого трафика системы
                let snapshot = self.bandwidthEngine.sampleBandwidth()
                self.liveBandwidth = snapshot

                // Фиксация расхода в постоянном хранилище TrafficStorage
                await TrafficStorage.shared.recordTrafficSample(
                    snapshot: snapshot,
                    networkName: self.currentNetworkTitle,
                    connectionType: self.systemInfo.connectionType.rawValue,
                    interfaceName: self.systemInfo.connectionType == .wifi ? "en0" : "pdp_ip0"
                )

                // Периодическое обновление данных раздела «Трафик» в UI
                loopCount += 1
                if loopCount % 3 == 0 {
                    await self.refreshTrafficData(period: self.selectedTrafficPeriod)
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

                try? await Task.sleep(nanoseconds: 2_000_000_000) // Стабильные 2.0 секунды
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
        await withTaskGroup(of: (String, PingRecord).self) { group in
            for target in currentTargets {
                group.addTask {
                    let record = await self.pingEngine.pingTarget(target)
                    return (target.address, record)
                }
            }

            for await (address, record) in group {
                self.processPingRecord(address: address, record: record)
            }
        }
    }

    private func processPingRecord(address: String, record: PingRecord) {
        guard var metric = hostMetrics[address] else { return }

        metric.sentCount += 1
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

            // Добавление в историю Sparkline
            metric.latencyHistory.append(lat)
            if metric.latencyHistory.count > 30 {
                metric.latencyHistory.removeFirst()
            }

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
            if metric.latencyHistory.count > 30 {
                metric.latencyHistory.removeFirst()
            }

            let lossPct = metric.lossWindowPct
            if lossPct >= lossCritThreshold {
                metric.status = .down
                triggerAlertIfNeeded(
                    address: address,
                    message: "Потеря пакетов: \(String(format: "%.0f", lossPct))%",
                    severity: .critical,
                    currentVal: lossPct,
                    threshVal: lossCritThreshold
                )
            } else {
                metric.status = .warning
            }
        }

        hostMetrics[address] = metric
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

    // MARK: - Алерты

    private func triggerAlertIfNeeded(
        address: String,
        message: String,
        severity: AlertSeverity,
        currentVal: Double,
        threshVal: Double
    ) {
        guard let host = hostMetrics[address] else { return }
        
        let isDuplicate = recentAlerts.contains { alert in
            alert.host == host.address && Date().timeIntervalSince(alert.timestamp) < 30
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

        if hapticsEnabled {
            HapticManager.shared.notificationWarning()
        }
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
                ispName: systemInfo.ispName ?? "Интернет"
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

                if self.liveActivityEnabled {
                    ActivityManager.shared.updateActivity(
                        downloadSpeedText: String(format: "↓ %.1f Мбит/с", result.downloadMbps),
                        uploadSpeedText: String(format: "↑ %.1f Мбит/с", result.uploadMbps),
                        compactDownloadText: String(format: "↓%.0fM", result.downloadMbps),
                        compactUploadText: String(format: "↑%.0fM", result.uploadMbps),
                        isTesting: false,
                        connectionType: self.systemInfo.connectionType.rawValue,
                        ispName: self.systemInfo.ispName ?? "Интернет"
                    )
                }

                if self.hapticsEnabled {
                    HapticManager.shared.notificationSuccess()
                }

                await self.storage.recordSpeedtest(result)
            } catch {
                self.isSpeedtestRunning = false
            }
        }
    }

    // MARK: - Управление виджетами

    public func toggleLiveActivity(enabled: Bool) {
        liveActivityEnabled = enabled
        if enabled {
            BackgroundTelemetryKeeper.shared.startKeepAlive()
            let snapshot = bandwidthEngine.sampleBandwidth()
            ActivityManager.shared.startActivity(
                downloadSpeedText: snapshot.formattedDownloadSpeed,
                uploadSpeedText: snapshot.formattedUploadSpeed,
                compactDownloadText: snapshot.compactDownload,
                compactUploadText: snapshot.compactUpload,
                isTesting: isSpeedtestRunning,
                connectionType: systemInfo.connectionType.rawValue,
                ispName: systemInfo.ispName ?? "Интернет"
            )
            if !isMonitoringActive {
                startMonitoring()
            }
        } else {
            ActivityManager.shared.stopActivity()
            if !isMonitoringActive {
                BackgroundTelemetryKeeper.shared.stopKeepAlive()
            }
        }
    }

    public var currentAveragePing: Double? {
        let latencies = hostMetrics.values.compactMap { $0.lastLatencyMs }
        guard !latencies.isEmpty else { return nil }
        return (latencies.reduce(0, +) / Double(latencies.count) * 10).rounded() / 10
    }

    public var currentAverageJitter: Double? {
        let jitters = hostMetrics.values.map { $0.jitterMs }.filter { $0 > 0 }
        guard !jitters.isEmpty else { return nil }
        return (jitters.reduce(0, +) / Double(jitters.count) * 10).rounded() / 10
    }

    public var currentPacketLossPct: Double {
        let losses = hostMetrics.values.map { $0.lossWindowPct }
        guard !losses.isEmpty else { return 0.0 }
        return (losses.reduce(0, +) / Double(losses.count) * 10).rounded() / 10
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
                    if self.hapticsEnabled {
                        HapticManager.shared.impactLight()
                    }
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

    // MARK: - AI Диагност (Network AI Copilot)

    public var currentHealthReport: NetworkHealthReport?
    public var aiMessages: [AIMessage] = []
    public var isAIAnalyzing: Bool = false
    public var aiProviderConfig: AIProviderConfig = AIProviderConfig()

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

    public func runAIDiagnosticsAudit() async {
        guard !isAIAnalyzing else { return }
        isAIAnalyzing = true
        HapticManager.shared.impactMedium()

        let context = buildDiagnosticsContext()
        let report = AIDiagnosticsEngine.shared.evaluateNetworkHealth(context: context)
        self.currentHealthReport = report

        if aiMessages.isEmpty {
            let greeting = """
            Привет! Я ваш интеллектуальный сетевой помощник **NetPulse AI**. 

            Я только что провел аудит вашего соединения: общий балл качества — **\(report.overallScore) из 100** (\(report.statusTitle)). 

            Вы можете задать мне любой вопрос о задержках, качестве связи в играх, скорости видео или настройке роутера.
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
        let response = await AIDiagnosticsEngine.shared.askAI(
            prompt: text,
            context: context,
            config: aiProviderConfig
        )

        aiMessages.append(AIMessage(role: .assistant, content: response))
        isAIAnalyzing = false

        if hapticsEnabled {
            HapticManager.shared.impactLight()
        }
    }

    public func updateAIConfig(_ newConfig: AIProviderConfig) {
        self.aiProviderConfig = newConfig
    }
}
