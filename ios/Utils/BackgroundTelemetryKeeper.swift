//
//  BackgroundTelemetryKeeper.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / Strict Concurrency) - 2026.
//

import Foundation

/// Менеджер поддержания фоновых задач телеметрии через легальный системный BGTaskScheduler (Apple Guideline 2.5.4 compliant).
/// В продакшн-режиме не использует аудиоплеер и не удерживает аудиосессию, предотвращая перегрев процессора и отклонение цензорами App Store.
public final class BackgroundTelemetryKeeper: NSObject, @unchecked Sendable {
    public static let shared = BackgroundTelemetryKeeper()

    private var isRunning: Bool = false

    private override init() {
        super.init()
    }

    /// Запуск фонового сбора телеметрии
    public func startKeepAlive() {
        guard !isRunning else { return }
        isRunning = true

        // Регистрация на легальное фоновое обновление через системный BGTaskScheduler
        BackgroundTaskManager.shared.scheduleBackgroundFetch()
        print("⚡️ [BackgroundTelemetryKeeper] Фоновая сессия телеметрии через BGTaskScheduler запущена")
    }

    /// Остановка фонового сбора
    public func stopKeepAlive() {
        guard isRunning else { return }
        isRunning = false
        print("🛑 [BackgroundTelemetryKeeper] Фоновая сессия телеметрии остановлена")
    }
}