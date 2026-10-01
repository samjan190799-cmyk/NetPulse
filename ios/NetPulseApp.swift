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

        // Инициализация официального SDK Meta Audience Network (Meta Ads 2026)
        MetaAdManager.shared.initialize()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    restoreLiveActivityIfNeeded()
                    MetaAdManager.shared.requestTrackingAuthorization()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        restoreLiveActivityIfNeeded()
                        MetaAdManager.shared.requestTrackingAuthorization()
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

        // Dynamic Island, виджеты и учёт трафика обслуживает NetworkMonitorViewModel реальными измерениями
        // (запуск/восстановление сессии — в startMonitoring и цикле обновления). Раньше здесь дублировался
        // собственный замер: он перезаписывал снимок виджета выдуманными значениями (бюджет 5 ГБ, пинг 28 мс),
        // на каждую активацию создавал новый NetworkDiagnostics с HTTP-запросами и «воровал» дельту трафика
        // у общего BandwidthEngine, из-за чего часть трафика не попадала в учёт.
        if !isLiveEnabled {
            ActivityManager.shared.stopActivity()
        }
    }

}
