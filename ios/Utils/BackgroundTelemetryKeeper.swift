//
//  BackgroundTelemetryKeeper.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import UIKit

/// Легковесный системный хранитель сессии телеметрии с нулевой нагрузкой на процессор и батарею (Zero CPU/Zero Thermal).
@MainActor
public final class BackgroundTelemetryKeeper: NSObject {
    public static let shared = BackgroundTelemetryKeeper()

    private var isRunning: Bool = false

    private override init() {
        super.init()
    }

    /// Запуск удержания фоновой сессии
    public func startKeepAlive() {
        guard !isRunning else { return }
        isRunning = true
        // Регистрация на фоновое обновление через BGTaskScheduler
        BackgroundTaskManager.shared.scheduleBackgroundFetch()
    }

    /// Остановка фонового удержания
    public func stopKeepAlive() {
        guard isRunning else { return }
        isRunning = false
    }
}
