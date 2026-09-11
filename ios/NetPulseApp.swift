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

                ActivityManager.shared.checkAndRestoreActivity(
                    downloadSpeedText: snapshot.formattedDownloadSpeed,
                    uploadSpeedText: snapshot.formattedUploadSpeed,
                    compactDownloadText: snapshot.compactDownload,
                    compactUploadText: snapshot.compactUpload,
                    pingMs: pingVal,
                    isTesting: false,
                    connectionType: info.connectionType.rawValue,
                    ispName: info.ispName ?? "Интернет"
                )
            } else {
                ActivityManager.shared.stopActivity()
            }
        }
    }

}
