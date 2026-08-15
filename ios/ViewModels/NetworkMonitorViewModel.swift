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
            if hostMetrics[target.address] == nil {
                hostMetrics[target.address] = HostMetrics(
                    name: target.name,
                    address: target.address,
                    isGateway: target.isGateway
                )
            }
        }
    }

    // MARK: - Управление циклом мониторинга

    public func startMonitoring() {
        guard !isMonitoringActive else { return }
        isMonitoringActive = true
        HapticManager.shared.impactMedium()

        // Фоновый опрос сетевой конфигурации
        diagnosticsTask = Task { [weak self] in
            guard let self else { return }
            let info = await self.diagnostics.collectSystemInfo()
            self.systemInfo = info
            
            // Если шлюз определен, обновляем адрес в списке
            if let gw = info.gatewayIP, gw != "127.0.0.1" {
                if let idx = self.targets.firstIndex(where: { $0.isGateway }) {
                    self.targets[idx].address = gw
                    self.hostMetrics[gw] = self.hostMetrics.removeValue(forKey: "gateway") ?? HostMetrics(name: "Локальный шлюз", address: gw, isGateway: true)
                }
            }
        }

        // Основной асинхронный цикл пинга
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.isMonitoringActive {
                let records = await self.pingEngine.pingAll(targets: self.targets)
                self.processPingBatch(records)

                try? await Task.sleep(for: .seconds(self.pollingInterval))
            }
        }
    }

    public func stopMonitoring() {
        isMonitoringActive = false
        monitorTask?.cancel()
        diagnosticsTask?.cancel()
        monitorTask = nil
        diagnosticsTask = nil
        HapticManager.shared.impactLight()
    }

    // MARK: - Обработка результатов пинга

    private func processPingBatch(_ records: [PingRecord]) {
        for record in records {
            let address = record.host
            var metrics = hostMetrics[address] ?? HostMetrics(name: record.targetName, address: address)

            metrics.sentCount += 1
            metrics.lastUpdated = record.timestamp

            if record.isSuccess, let latency = record.latencyMs {
                metrics.receivedCount += 1
                metrics.lastLatencyMs = latency

                // Расчет джиттера по RFC 3550
                let prevLat = prevLatencies[address]
                metrics.jitterMs = JitterAnalyzer.calculateRFC3550Jitter(
                    previousJitter: metrics.jitterMs,
                    previousLatency: prevLat,
                    currentLatency: latency
                )
                prevLatencies[address] = latency

                metrics.latencyHistory.append(latency)
            } else {
                metrics.lostCount += 1
                metrics.lastLatencyMs = nil
                metrics.latencyHistory.append(nil)
            }

            // Ограничение длины истории для графиков (последние 40 точек)
            if metrics.latencyHistory.count > 40 {
                metrics.latencyHistory.removeFirst()
            }

            // Расчет процента потерь
            if metrics.sentCount > 0 {
                metrics.lossRatePct = ((Double(metrics.lostCount) / Double(metrics.sentCount)) * 1000).rounded() / 10
            }

            let windowLost = metrics.latencyHistory.filter { $0 == nil }.count
            metrics.lossWindowPct = ((Double(windowLost) / Double(metrics.latencyHistory.count)) * 1000).rounded() / 10

            // Расчет перцентилей задержки
            let validLatencies = metrics.latencyHistory.compactMap { $0 }
            if !validLatencies.isEmpty {
                metrics.minLatencyMs = (validLatencies.min()! * 10).rounded() / 10
                metrics.maxLatencyMs = (validLatencies.max()! * 10).rounded() / 10
                metrics.avgLatencyMs = ((validLatencies.reduce(0, +) / Double(validLatencies.count)) * 10).rounded() / 10
                let percentiles = JitterAnalyzer.calculatePercentiles(from: validLatencies)
                metrics.p95LatencyMs = percentiles.p95
                metrics.p99LatencyMs = percentiles.p99
            }

            // Оценка статуса
            evaluateHostStatus(&metrics)

            hostMetrics[address] = metrics

            // Сохранение в хранилище
            Task { [storage = self.storage] in
                await storage.recordPing(record)
            }
        }

        // Непрерывное обновление Dynamic Island при активной Live Activity
        if liveActivityEnabled {
            let speed = liveDownloadSpeed > 0 ? liveDownloadSpeed : (lastSpeedtestResult?.downloadMbps ?? 0.0)
            let upload = liveUploadSpeed > 0 ? liveUploadSpeed : (lastSpeedtestResult?.uploadMbps ?? 0.0)
            ActivityManager.shared.updateActivity(
                downloadMbps: speed,
                uploadMbps: upload,
                pingMs: currentAveragePing,
                jitterMs: currentAverageJitter,
                isTesting: isSpeedtestRunning,
                connectionType: systemInfo.connectionType.rawValue,
                ispName: systemInfo.ispName ?? "Интернет"
            )
        }
    }

    private func evaluateHostStatus(_ metrics: inout HostMetrics) {
        if metrics.lossWindowPct >= 99.0 && metrics.sentCount >= 3 {
            metrics.status = .down
            triggerAlert(for: metrics, severity: .critical, message: "Хост \(metrics.name) полностью недоступен")
            return
        }

        if metrics.lossWindowPct >= lossCritThreshold {
            metrics.status = .critical
            triggerAlert(for: metrics, severity: .critical, message: "Критические потери: \(metrics.lossWindowPct)%")
        } else if let lat = metrics.lastLatencyMs, lat >= latencyCritThreshold {
            metrics.status = .critical
            triggerAlert(for: metrics, severity: .critical, message: "Высокая задержка: \(lat) мс")
        } else if let lat = metrics.lastLatencyMs, lat >= latencyWarnThreshold {
            metrics.status = .warning
        } else if metrics.jitterMs >= jitterWarnThreshold {
            metrics.status = .warning
        } else {
            metrics.status = .ok
        }
    }

    private func triggerAlert(for metrics: HostMetrics, severity: AlertSeverity, message: String) {
        let alert = NetworkAlert(
            host: metrics.address,
            targetName: metrics.name,
            severity: severity,
            message: message,
            metricName: "network_quality",
            currentValue: metrics.lastLatencyMs ?? 0.0,
            thresholdValue: latencyCritThreshold
        )

        recentAlerts.insert(alert, at: 0)
        if recentAlerts.count > 50 {
            recentAlerts.removeLast()
        }

        activeAlert = alert

        if hapticsEnabled {
            if severity == .critical {
                HapticManager.shared.notificationError()
            } else {
                HapticManager.shared.notificationWarning()
            }
        }
    }

    // MARK: - Speedtest

    public func runSpeedtest() {
        guard !isSpeedtestRunning else { return }
        isSpeedtestRunning = true
        liveDownloadSpeed = 0.0
        liveUploadSpeed = 0.0
        HapticManager.shared.impactHeavy()

        if liveActivityEnabled {
            ActivityManager.shared.updateActivity(
                downloadMbps: 0.0,
                uploadMbps: 0.0,
                pingMs: currentAveragePing,
                jitterMs: currentAverageJitter,
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
                                downloadMbps: dl,
                                uploadMbps: ul,
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

                if self.liveActivityEnabled {
                    ActivityManager.shared.updateActivity(
                        downloadMbps: result.downloadMbps,
                        uploadMbps: result.uploadMbps,
                        pingMs: self.currentAveragePing,
                        jitterMs: self.currentAverageJitter,
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
            ActivityManager.shared.startActivity(
                downloadMbps: liveDownloadSpeed,
                uploadMbps: liveUploadSpeed,
                pingMs: currentAveragePing,
                jitterMs: currentAverageJitter,
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
