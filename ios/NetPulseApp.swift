//
//  NetPulseApp.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

@main
struct NetPulseApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Регистрация системных обработчиков фонового сбора трафика BGTaskScheduler
        BackgroundTaskManager.shared.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    restoreLiveActivityIfNeeded()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        restoreLiveActivityIfNeeded()
                    }
                }
        }
    }

    private func restoreLiveActivityIfNeeded() {
        let isLiveEnabled = UserDefaults.standard.object(forKey: "netpulse_live_activity_enabled") as? Bool ?? true
        let isBgEnabled = UserDefaults.standard.object(forKey: "netpulse_background_monitoring_enabled") as? Bool ?? true

        if isLiveEnabled || isBgEnabled {
            BackgroundTelemetryKeeper.shared.startKeepAlive()
        }

        // 1. Мгновенный синхронный запуск/восстановление сессии в Dynamic Island (< 1 мс)
        // Гарантирует запуск, пока приложение гарантированно активно в Foreground
        if isLiveEnabled {
            let cached = WidgetDataManager.shared.loadLatestSnapshot()
            let dlText = cached.downloadSpeedMbps > 0 ? String(format: "%.1f Мбит/с", cached.downloadSpeedMbps) : "0.0 Мбит/с"
            let ulText = cached.uploadSpeedMbps > 0 ? String(format: "%.1f Мбит/с", cached.uploadSpeedMbps) : "0.0 Мбит/с"
            let compactDl = cached.downloadSpeedMbps > 0 ? String(format: "%.0fM", cached.downloadSpeedMbps) : "0K"
            let compactUl = cached.uploadSpeedMbps > 0 ? String(format: "%.0fM", cached.uploadSpeedMbps) : "0K"

            ActivityManager.shared.checkAndRestoreActivity(
                downloadSpeedText: dlText,
                uploadSpeedText: ulText,
                compactDownloadText: compactDl,
                compactUploadText: compactUl,
                pingMs: cached.pingMs ?? 28.0,
                jitterMs: cached.jitterMs,
                isTesting: false,
                connectionType: cached.connectionType,
                ispName: cached.ispName
            )
        } else {
            ActivityManager.shared.stopActivity()
        }

        // 2. Параллельное асинхронное обновление метрик сети и виджетов
        Task { @MainActor in
            let info = await NetworkDiagnostics().collectSystemInfo()
            let snapshot = BandwidthEngine.shared.sampleBandwidth(activeConnectionType: info.connectionType)
            let summary = await TrafficStorage.shared.getSummary(for: .today)

            // Замер реального пинга и джиттера для виджетов и Dynamic Island
            let pingEngine = PingEngine(timeout: 2.0)
            let defaultTargets = HostTarget.defaultTargets.filter { $0.isEnabled }
            let pingResults = await pingEngine.pingAll(targets: defaultTargets)

            let successfulLatencies = pingResults.compactMap { $0.latencyMs }
            let avgPing: Double? = successfulLatencies.isEmpty ? nil : successfulLatencies.reduce(0, +) / Double(successfulLatencies.count)

            // Сборка DNS-хостов для Large-виджета
            let dnsHosts: [WidgetDNSHost] = pingResults.prefix(4).map { record in
                WidgetDNSHost(
                    name: record.targetName,
                    address: record.host,
                    latencyMs: record.latencyMs,
                    isOK: record.isSuccess
                )
            }

            // Вычисление Health Score
            var healthScore = 100
            if let ping = avgPing, ping > 50 {
                healthScore -= min(Int((ping - 50) * 0.4), 30)
            }
            let lossPct = pingResults.isEmpty ? 0.0 : Double(pingResults.filter { !$0.isSuccess }.count) / Double(pingResults.count) * 100
            if lossPct > 0 {
                healthScore -= min(Int(lossPct * 5), 40)
            }
            healthScore = max(healthScore, 10)

            let widgetData = NetPulseWidgetData(
                downloadSpeedMbps: snapshot.downloadMbps,
                uploadSpeedMbps: snapshot.uploadMbps,
                pingMs: avgPing,
                jitterMs: nil,
                lossPercent: lossPct,
                ispName: info.ispName ?? "Интернет",
                connectionType: info.connectionType.rawValue,
                todayTrafficBytes: Int64(summary.totalTraffic),
                budgetTotalBytes: 5_368_709_120,
                healthScore: healthScore,
                dnsHosts: dnsHosts,
                lastUpdated: Date()
            )
            WidgetDataManager.shared.saveSnapshot(widgetData)

            if isLiveEnabled {
                let pingVal = avgPing ?? 28.0

                ActivityManager.shared.updateActivity(
                    downloadSpeedText: snapshot.formattedDownloadSpeed,
                    uploadSpeedText: snapshot.formattedUploadSpeed,
                    compactDownloadText: snapshot.compactDownload,
                    compactUploadText: snapshot.compactUpload,
                    pingMs: pingVal,
                    jitterMs: nil,
                    isTesting: false,
                    connectionType: info.connectionType.rawValue,
                    ispName: info.ispName ?? "Интернет",
                    force: true
                )
            }
        }
    }

}
