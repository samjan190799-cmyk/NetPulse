//
//  ContinuedProcessing.swift
//  NetPulse
//
//  Системная фоновая задача для теста стабильности (iOS 26 и новее): пользователь сам запустил долгий тест, и iOS
//  не усыпляет приложение, пока он идёт. Система показывает прогресс теста в своём окне, и пользователь может
//  отменить его оттуда. На более ранних iOS задачи нет: тест идёт, пока приложение открыто.
//

import Foundation
import BackgroundTasks
import Observation

/// Коробка для системной задачи: сама задача не Sendable, а обработчики вызываются на разных потоках.
/// Гарантирует, что задача будет завершена ровно один раз.
@available(iOS 26.0, *)
private final class ContinuedTaskBox: @unchecked Sendable {
    let task: BGContinuedProcessingTask
    private let lock = NSLock()
    private var completed = false

    init(_ task: BGContinuedProcessingTask) {
        self.task = task
    }

    func complete(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        completed = true
        task.setTaskCompleted(success: success)
    }
}

@MainActor
@Observable
public final class ContinuedProcessingHost: StabilityBackgroundHosting {
    public static let shared = ContinuedProcessingHost()

    /// Идентификатор задачи: он же записан в `BGTaskSchedulerPermittedIdentifiers` в Info.plist
    public nonisolated static let taskIdentifier = "com.samvel.netpulse.stability"

    /// Запущено ли приложение в симуляторе. Условие проверяется во время работы, а не при сборке: так код запроса
    /// задачи компилируется (и проверяется на типы) в обеих сборках.
    nonisolated static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Система приняла задачу, тест идёт под её защитой
    public private(set) var isActive = false

    @ObservationIgnored private var attachedBox: AnyObject?
    @ObservationIgnored private var onExpire: (@MainActor () -> Void)?
    @ObservationIgnored private var requested = false
    @ObservationIgnored private var title = ""
    @ObservationIgnored private var totalSeconds = 0
    @ObservationIgnored private var latestCompleted = 0
    @ObservationIgnored private var latestSubtitle = ""
    @ObservationIgnored private var lastTitleUpdate = Date.distantPast

    private init() {}

    /// При запуске приложения: регистрирует обработчик системной задачи. Без регистрации запрос задачи завершил бы
    /// приложение аварийно, поэтому вызывать нужно до окончания запуска (как и для остальных задач BGTaskScheduler).
    public nonisolated static func register() {
        guard #available(iOS 26.0, *) else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let continued = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let box = ContinuedTaskBox(continued)
            Task { @MainActor in
                ContinuedProcessingHost.shared.attach(box)
            }
        }
    }

    // MARK: - StabilityBackgroundHosting

    public func begin(
        totalSeconds: Int,
        title: String,
        subtitle: String,
        onExpire: @escaping @MainActor () -> Void
    ) -> Bool {
        // В симуляторе системных фоновых задач нет: тест идёт, пока приложение открыто
        guard !Self.isSimulator, #available(iOS 26.0, *) else { return false }

        self.totalSeconds = max(1, totalSeconds)
        self.title = title
        latestSubtitle = subtitle
        latestCompleted = 0
        lastTitleUpdate = .distantPast
        self.onExpire = onExpire
        requested = true

        let request = BGContinuedProcessingTaskRequest(identifier: Self.taskIdentifier, title: title, subtitle: subtitle)
        // Не вставать в очередь: если система не может начать задачу сейчас, тест просто идёт, пока приложение открыто
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
            IslandDiagnostics.shared.log("Тест стабильности: системная фоновая задача запрошена", .info)
            return true
        } catch {
            requested = false
            self.onExpire = nil
            IslandDiagnostics.shared.log(
                "Тест стабильности: система не дала фоновую задачу (\(error.localizedDescription))",
                .warning
            )
            return false
        }
    }

    public func update(completedSeconds: Int, subtitle: String) {
        latestCompleted = completedSeconds
        latestSubtitle = subtitle
        guard #available(iOS 26.0, *), let box = attachedBox as? ContinuedTaskBox else { return }
        box.task.progress.completedUnitCount = Int64(min(completedSeconds, totalSeconds))
        // Подпись в системном окне обновляется не чаще раза в 5 секунд: чаще незачем
        if Date().timeIntervalSince(lastTitleUpdate) >= 5 {
            lastTitleUpdate = Date()
            box.task.updateTitle(title, subtitle: subtitle)
        }
    }

    public func end(success: Bool) {
        requested = false
        onExpire = nil
        let stored = attachedBox
        attachedBox = nil
        isActive = false
        guard #available(iOS 26.0, *), let box = stored as? ContinuedTaskBox else { return }
        box.complete(success: success)
    }

    // MARK: - События системы

    /// Система запустила задачу: сообщаем ей объём работы и подключаем обработчик отмены
    @available(iOS 26.0, *)
    private func attach(_ box: ContinuedTaskBox) {
        // Тест уже закончился или остановлен, пока система собиралась: задача не нужна
        guard requested else {
            box.complete(success: true)
            return
        }
        attachedBox = box
        isActive = true

        let task = box.task
        task.progress.totalUnitCount = Int64(totalSeconds)
        task.progress.completedUnitCount = Int64(min(latestCompleted, totalSeconds))
        task.updateTitle(title, subtitle: latestSubtitle)
        task.expirationHandler = {
            Task { @MainActor in
                ContinuedProcessingHost.shared.systemEndedTask()
            }
        }
        IslandDiagnostics.shared.log("Тест стабильности: система приняла фоновую задачу, приложение можно свернуть", .info)
    }

    /// Задачу прекратила система или пользователь из системного окна
    private func systemEndedTask() {
        let handler = onExpire
        IslandDiagnostics.shared.log("Тест стабильности: системная фоновая задача прекращена", .warning)
        handler?()
    }
}
