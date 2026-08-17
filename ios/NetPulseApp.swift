//
//  NetPulseApp.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

@main
struct NetPulseApp: App {
    init() {
        // Регистрация системных обработчиков фонового сбора трафика BGTaskScheduler
        BackgroundTaskManager.shared.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
