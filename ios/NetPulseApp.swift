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

        if isLiveEnabled {
            Task { @MainActor in
                let info = await NetworkDiagnostics().collectSystemInfo()
                let snapshot = BandwidthEngine.shared.sampleBandwidth(activeConnectionType: info.connectionType)
                ActivityManager.shared.checkAndRestoreActivity(
                    downloadSpeedText: snapshot.formattedDownloadSpeed,
                    uploadSpeedText: snapshot.formattedUploadSpeed,
                    compactDownloadText: snapshot.compactDownload,
                    compactUploadText: snapshot.compactUpload,
                    isTesting: false,
                    connectionType: info.connectionType.rawValue,
                    ispName: info.ispName ?? "Интернет"
                )
            }
        } else {
            Task { @MainActor in
                ActivityManager.shared.stopActivity()
            }
        }
    }
}
