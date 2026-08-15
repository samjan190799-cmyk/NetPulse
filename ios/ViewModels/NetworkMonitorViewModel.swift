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
        totalReceivedBytes: 0,
        totalSentBytes: 0,
        timestamp: Date()
    )

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

    private var monitorTask: Task<Void, Never>?
    private var diagnosticsTask: Task<Void, Never>?
    private var prevLatencies: [String: Double] = [:]
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    public init() {
        initMetricsForTargets()
        setupBackgroundObservation()
    }

    private func setupBackgroundObservation() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDidEnterBackground()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWillEnterForeground()
        }
    }

    private func handleDidEnterBackground() {
        if liveActivityEnabled || isMonitoringActive {
            bgTask = UIApplication.shared.beginBackgroundTask(withName: "NetPulseBackgroundTelemetry") { [weak self] in
                guard let self else { return }
                if self.bgTask != .invalid {
                    UIApplication.shared.endBackgroundTask(self.bgTask)
                    self.bgTask = .invalid
                }
            }
        }
    }

    private func handleWillEnterForeground() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }

    private func initMetricsForTargets() {
        for target in targets {
            hostMetrics[target.id] = HostMetrics(
                targetId: target.id,
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

        if hapticsEnabled {
            HapticManager.shared.impactLight()
        }

        startPollingTask()
        startDiagnosticsTask()
    }

    public func stopMonitoring() {
        isMonitoringActive = false
        monitorTask?.cancel()
        monitorTask = nil
        diagnosticsTask?.cancel()
        diagnosticsTask = nil

        if hapticsEnabled {
            HapticManager.shared.impactLight()
        }
    }

    // MARK: - Фоновые задачи опроса

    private func startPollingTask() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, self.isMonitoringActive else { break }
                
                await self.pollAllHosts()

                // Снятие снимка РЕАЛЬНОГО сетевого трафика системы
                let snapshot = self.bandwidthEngine.sampleBandwidth()
                self.liveBandwidth = snapshot

                // Передача реальной скорости в Dynamic Island
                if self.liveActivityEnabled {
                    let dlText = self.isSpeedtestRunning ? String(format: "%.1f Мбит/с", self.liveDownloadSpeed) : snapshot.formattedDownloadSpeed
                    let ulText = self.isSpeedtestRunning ? String(format: "%.1f Мбит/с", self.liveUploadSpeed) : snapshot.formattedUploadSpeed
                    let compactDl = self.isSpeedtestRunning ? String(format: "↓%.0fM", self.liveDownloadSpeed) : snapshot.compactDownload
                    let compactUl = self.isSpeedtestRunning ? String(format: "↑%.0fM", self.liveUploadSpeed) : snapshot.compactUpload

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

                try? await Task.sleep(nanoseconds: UInt64(self.pollingInterval * 1_000_000_000))
            }
        }
    }

    private func startDiagnosticsTask() {
        diagnosticsTask?.cancel()
        diagnosticsTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, self.isMonitoringActive else { break }
                let info = await self.diagnostics.collectSystemDiagnostics()
                self.systemInfo = info
                try? await Task.sleep(nanoseconds: 10_000_000_000) // каждые 10 секунд
            }
        }
    }

    private func pollAllHosts() async {
        let currentTargets = targets
        await withTaskGroup(of: (String, PingRecord).self) { group in
            for target in currentTargets {
                group.addTask {
                    let record = await self.pingEngine.ping(host: target.address, port: target.port)
                    return (target.id, record)
                }
            }

            for await (targetId, record) in group {
                self.processPingRecord(targetId: targetId, record: record)
            }
        }
    }

    private func processPingRecord(targetId: String, record: PingRecord) {
        guard var metric = hostMetrics[targetId] else { return }

        metric.sentCount += 1
        let prevRtt = prevLatencies[targetId]

        if record.isSuccessful, let lat = record.latencyMs {
            metric.receivedCount += 1
            metric.lastLatencyMs = lat

            // Расчет RFC 3550 Jitter
            if let pRtt = prevRtt {
                let d = abs(lat - pRtt)
                metric.jitterMs = metric.jitterMs + (d - metric.jitterMs) / 16.0
            }
            prevLatencies[targetId] = lat

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
                triggerAlertIfNeeded(targetId: targetId, type: .highLatency(latency: lat))
            } else if lat > latencyWarnThreshold {
                metric.status = .warning
            } else {
                metric.status = .ok
            }
        } else {
            // Потеря пакета
            metric.lastLatencyMs = nil
            metric.latencyHistory.append(nil)
            if metric.latencyHistory.count > 30 {
                metric.latencyHistory.removeFirst()
            }

            let lossPct = metric.lossWindowPct
            if lossPct >= lossCritThreshold {
                metric.status = .down
                triggerAlertIfNeeded(targetId: targetId, type: .packetLoss(lossPct: lossPct))
            } else {
                metric.status = .warning
            }
        }

        hostMetrics[targetId] = metric
    }

    // MARK: - Алерты

    private func triggerAlertIfNeeded(targetId: String, type: NetworkAlert.AlertType) {
        guard let host = hostMetrics[targetId] else { return }
        
        let shouldAlert = recentAlerts.first(where: {
            $0.hostName == host.name && Date().timeIntervalSince($0.timestamp) < 30
        }) == nil

        guard shouldAlert else { return }

        let alert = NetworkAlert(
            hostName: host.name,
            hostAddress: host.address,
            type: type,
            timestamp: Date()
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
            let snapshot = bandwidthEngine.sampleBandwidth()
            ActivityManager.shared.startActivity(
                downloadSpeedText: snapshot.formattedDownloadSpeed,
                uploadSpeedText: snapshot.formattedUploadSpeed,
                compactDownloadText: snapshot.compactDownload,
                compactUploadText: snapshot.compactUpload,
                connectionType: systemInfo.connectionType.rawValue,
                ispName: systemInfo.ispName ?? "Интернет"
            )
        } else {
            ActivityManager.shared.stopActivity()
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
}
