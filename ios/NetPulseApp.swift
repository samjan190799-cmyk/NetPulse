//
//  NetPulseApp.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import UIKit

/// Делегат нужен ради одного: узнать, что iOS запустила закрытое приложение из-за перемещения телефона
/// (ключ `location` в параметрах запуска), и дописать идущий маршрут. Окон при таком запуске нет: приложение
/// работает в фоне, пока идёт запись.
final class NetPulseAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if launchOptions?[.location] != nil {
            Task { @MainActor in
                await RouteRecorder.shared.resumeAfterRelaunch()
            }
        }
        return true
    }
}

@main
struct NetPulseApp: App {
    @UIApplicationDelegateAdaptor(NetPulseAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Регистрация системных обработчиков фонового сбора трафика BGTaskScheduler
        BackgroundTaskManager.shared.registerBackgroundTasks()

        // Рекламу Яндекса запускает onAppear/активация: при фоновом запуске (например, по геолокации) ей делать нечего
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    restoreLiveActivityIfNeeded()
                    YandexAdManager.shared.start()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        restoreLiveActivityIfNeeded()
                        YandexAdManager.shared.start()
                        // Окно разрешения на отслеживание показывается только у активного приложения: повторяем запрос
                        YandexAdManager.shared.requestTrackingAuthorization()
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
