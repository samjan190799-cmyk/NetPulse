//
//  BackgroundTaskManager.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import BackgroundTasks
import UIKit

/// Менеджер системных фоновых задач iOS (BGTaskScheduler): сверка трафика и обновление виджетов в фоне.
/// Запуск задач остаётся на усмотрение системы — гарантий по времени нет.
public final class BackgroundTaskManager: @unchecked Sendable {
    public static let shared = BackgroundTaskManager()

    public static let telemetryTaskId = "com.samvel.netpulse.telemetry"
    public static let refreshTaskId = "com.samvel.netpulse.refresh"

    private init() {}

    /// Регистрация системных обработчиков BGTaskScheduler при старте приложения (до окончания launch)
    public func registerBackgroundTasks() {
        // 1. Быстрое фоновое обновление (App Refresh)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskId,
            using: nil
        ) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else { return }
            self.handleAppRefreshTask(appRefreshTask)
        }

        // 2. Фоновая обработка телеметрии (Processing Task)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.telemetryTaskId,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            self.handleTelemetryProcessingTask(processingTask)
        }

        print("✅ Системные фоновые задачи BGTaskScheduler зарегистрированы")
    }

    /// Планирование следующего цикла фонового пробуждения системы
    public func scheduleBackgroundFetch() {
        // В режиме экономии заряда систему просят будить приложение реже (по умолчанию: 15 и 30 минут)
        let profile = PowerProfile.current
        // Планирование App Refresh (минимум через 15 минут)
        let refreshRequest = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        refreshRequest.earliestBeginDate = Date(timeIntervalSinceNow: profile.backgroundRefreshMinutes * 60)

        do {
            try BGTaskScheduler.shared.submit(refreshRequest)
            print("🗓️ Фоновое обновление BGAppRefreshTask запланировано")
        } catch {
            print("⚠️ Не удалось запланировать BGAppRefreshTask: \(error.localizedDescription)")
        }

        // Планирование Processing Task (минимум через 30 минут)
        let processingRequest = BGProcessingTaskRequest(identifier: Self.telemetryTaskId)
        processingRequest.earliestBeginDate = Date(timeIntervalSinceNow: profile.backgroundProcessingMinutes * 60)
        processingRequest.requiresNetworkConnectivity = false
        processingRequest.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(processingRequest)
            print("🗓️ Фоновая обработка BGProcessingTask запланирована")
        } catch {
            print("⚠️ Не удалось запланировать BGProcessingTask: \(error.localizedDescription)")
        }
    }

    /// Отмена запланированных фоновых запусков
    public func cancelScheduledTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskId)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.telemetryTaskId)
    }

    // MARK: - Обработчики выполнения фоновых задач

    private func handleAppRefreshTask(_ task: BGAppRefreshTask) {
        // Планируем следующий запуск
        scheduleBackgroundFetch()
        runBackgroundSync(for: task)
    }

    private func handleTelemetryProcessingTask(_ task: BGProcessingTask) {
        scheduleBackgroundFetch()
        runBackgroundSync(for: task)
    }

    /// Общий запуск фоновой синхронизации (раньше один и тот же код был продублирован в двух обработчиках)
    private func runBackgroundSync(for task: BGTask) {
        let completion = BackgroundTaskCompletion(task)

        let work = Task { @Sendable in
            await BackgroundTaskManager.performBackgroundSync()
            completion.complete(success: !Task.isCancelled)
        }

        task.expirationHandler = {
            work.cancel()
            completion.complete(success: false)
        }
    }

    /// Фоновая сверка трафика и обновление снимка для виджетов.
    ///
    /// В фоне нет ни проверок узлов, ни замера скорости — поэтому пинг, джиттер, «здоровье» и список узлов в снимок
    /// НЕ подставляются (виджет покажет «—»). Раньше сюда писались выдуманные «здоровье 100», «0 % потерь» и лимит 5 ГБ.
    /// Живую активность (Dynamic Island) отсюда не трогаем: из фона её нельзя запустить, а обновление «нулями»
    /// затирало реальные показания.
    private static func performBackgroundSync() async {
        let diagnostics = NetworkDiagnostics()
        // Только локальные сведения: интернет-запросы в фоновом окне не нужны
        let info = await diagnostics.collectLocalInfo()

        await TrafficStorage.shared.reconcileBackgroundHardwareTraffic(
            currentConnectionType: info.connectionType.rawValue,
            currentNetworkName: info.displayTitle
        )
        await TrafficStorage.shared.flush()

        let todaySummary = await TrafficStorage.shared.getSummary(for: .today)
        let budget = await TrafficStorage.shared.getBudget()
        let budgetSummary = await TrafficStorage.shared.getSummary(for: budget.period)

        let widgetData = NetPulseWidgetData(
            downloadSpeedMbps: 0,
            uploadSpeedMbps: 0,
            pingMs: nil,
            jitterMs: nil,
            lossPercent: 0.0,
            ispName: info.displayTitle,
            connectionType: info.connectionType.rawValue,
            todayTrafficBytes: Int64(todaySummary.totalTraffic),
            budgetTotalBytes: (budget.isEnabled && budget.limitBytes > 0) ? Int64(budget.limitBytes) : 0,
            budgetUsedBytes: Int64(budgetSummary.totalTraffic),
            healthScore: nil,
            dnsHosts: [],
            lastUpdated: Date()
        )
        WidgetDataManager.shared.saveSnapshot(widgetData)
    }
}

/// Гарантирует, что BGTask будет завершён ровно один раз: `expirationHandler` и сама задача могли вызвать
/// `setTaskCompleted` дважды (повторное завершение — ошибка).
private final class BackgroundTaskCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var isCompleted = false
    private let task: BGTask

    init(_ task: BGTask) {
        self.task = task
    }

    func complete(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCompleted else { return }
        isCompleted = true
        task.setTaskCompleted(success: success)
    }
}
