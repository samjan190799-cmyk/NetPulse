//
//  BackgroundTelemetryKeeper.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / Strict Concurrency) - 2026.
//

import Foundation

/// Планирует системные фоновые задачи (BGTaskScheduler) для сверки трафика и обновления виджетов.
///
/// Это НЕ удержание приложения в фоне. iOS приостанавливает свернутое приложение, а фоновые задачи запускаются
/// системой по её усмотрению (обычно не чаще раза в 15–30 минут и без гарантий). Аудиосессия и прочие приёмы
/// удержания процесса намеренно не используются (правило App Store 2.5.4). Раньше класс назывался «keep-alive»
/// и в интерфейсе подавался как «фоновый учёт 24/7».
public final class BackgroundTelemetryKeeper: NSObject, @unchecked Sendable {
    public static let shared = BackgroundTelemetryKeeper()

    private let lock = NSLock()
    private var isScheduled: Bool = false

    private override init() {
        super.init()
    }

    /// Запрос на фоновые запуски (если они ещё не запрошены)
    public func startKeepAlive() {
        lock.lock()
        let wasScheduled = isScheduled
        isScheduled = true
        lock.unlock()

        guard !wasScheduled else { return }
        BackgroundTaskManager.shared.scheduleBackgroundFetch()
    }

    /// Отмена запланированных фоновых запусков
    public func stopKeepAlive() {
        lock.lock()
        let wasScheduled = isScheduled
        isScheduled = false
        lock.unlock()

        guard wasScheduled else { return }
        BackgroundTaskManager.shared.cancelScheduledTasks()
    }
}
