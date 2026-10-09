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
        // «Карта скорости»: автоматические замеры на маршруте входят в подписку PRO
        RouteRecorder.shared.speedSamplingAllowed = { ProStore.shared.isPro }
        AlertNotifier.shared.clearStaleReminder()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Подписка PRO: слушает покупки и подтверждает статус (остров, HUD и AI-аудит входят в подписку)
                    ProStore.shared.start()
                    restoreLiveActivityIfNeeded()
                    runRequestedSpeedtest()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        restoreLiveActivityIfNeeded()
                        runRequestedSpeedtest()
                    }
                }
        }
    }

    /// Команда «Замерить скорость» (Siri, Команды, Action Button) оставила просьбу: открываем главный экран и меряем
    private func runRequestedSpeedtest() {
        guard SpeedTestRequest.consume() else { return }
        NotificationCenter.default.post(name: .netPulseShowHome, object: nil)
        NetworkMonitorViewModel.shared.startSpeedtest()
    }

    private func restoreLiveActivityIfNeeded() {
        let isLiveEnabled = (UserDefaults.standard.object(forKey: "netpulse_live_activity_enabled") as? Bool ?? true)
            && ProStore.shared.isPro
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
