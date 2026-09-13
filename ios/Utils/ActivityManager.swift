//
//  ActivityManager.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Синглтон управления жизненным циклом Live Activity для Dynamic Island с самовосстановлением и защитой от замираний.
@MainActor
public final class ActivityManager {
    public static let shared = ActivityManager()

    #if canImport(ActivityKit)
    private var currentActivity: Activity<NetPulseAttributes>?
    private var lastContentState: NetPulseAttributes.ContentState?
    private var lastUpdateDate: Date?
    private var isUpdating: Bool = false
    private var queuedState: NetPulseAttributes.ContentState?
    private var stateObservationTask: Task<Void, Never>?
    #endif

    public private(set) var isLiveActivityActive: Bool = false

    private init() {}

    /// Проверка системного разрешения Live Activity в iOS Settings
    public var areActivitiesEnabled: Bool {
        #if canImport(ActivityKit)
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }

    /// Текстовое описание статуса для настроек и UI
    public var statusDescription: String {
        guard areActivitiesEnabled else {
            return "Отключено в Настройках iOS"
        }
        if isLiveActivityActive {
            return "Активен в Dynamic Island"
        }
        return "В режиме ожидания"
    }

    /// Восстановление или немедленный запуск сессии Dynamic Island
    public func checkAndRestoreActivity(
        downloadSpeedText: String = "0 Мбит/с",
        uploadSpeedText: String = "0 Мбит/с",
        compactDownloadText: String = "0B",
        compactUploadText: String = "0B",
        pingMs: Double? = nil,
        jitterMs: Double? = nil,
        isTesting: Bool = false,
        connectionType: String = "5G / LTE",
        ispName: String = "Мобильный интернет",
        isGamingMode: Bool = false,
        gameTitle: String? = nil,
        gameRegion: String? = nil,
        packetLossPct: Double? = nil
    ) {
        #if canImport(ActivityKit)
        guard areActivitiesEnabled else {
            print("⚠️ Live Activities отключены пользователем в настройках iOS")
            self.isLiveActivityActive = false
            return
        }

        // 1. Очистка завершенных/сброшенных сессий
        for existing in Activity<NetPulseAttributes>.activities {
            if existing.activityState != .active {
                Task {
                    await existing.end(nil, dismissalPolicy: .immediate)
                }
            }
        }

        // 2. Если активная сессия уже существует в системе — подключаемся к ней
        if let existing = Activity<NetPulseAttributes>.activities.first(where: { $0.activityState == .active }) {
            self.currentActivity = existing
            self.isLiveActivityActive = true
            monitorActivityState(existing)
            updateActivity(
                downloadSpeedText: downloadSpeedText,
                uploadSpeedText: uploadSpeedText,
                compactDownloadText: compactDownloadText,
                compactUploadText: compactUploadText,
                pingMs: pingMs,
                jitterMs: jitterMs,
                isTesting: isTesting,
                connectionType: connectionType,
                ispName: ispName,
                isGamingMode: isGamingMode,
                gameTitle: gameTitle,
                gameRegion: gameRegion,
                packetLossPct: packetLossPct,
                force: true
            )
            return
        }

        // 3. Иначе создаем новую сессию
        startActivity(
            downloadSpeedText: downloadSpeedText,
            uploadSpeedText: uploadSpeedText,
            compactDownloadText: compactDownloadText,
            compactUploadText: compactUploadText,
            pingMs: pingMs,
            jitterMs: jitterMs,
            isTesting: isTesting,
            connectionType: connectionType,
            ispName: ispName,
            isGamingMode: isGamingMode,
            gameTitle: gameTitle,
            gameRegion: gameRegion,
            packetLossPct: packetLossPct
        )
        #endif
    }

    /// Запуск Live Activity в Dynamic Island с функцией самовосстановления (Self-Healing)
    public func startActivity(
        downloadSpeedText: String = "0 Мбит/с",
        uploadSpeedText: String = "0 Мбит/с",
        compactDownloadText: String = "0B",
        compactUploadText: String = "0B",
        pingMs: Double? = nil,
        jitterMs: Double? = nil,
        isTesting: Bool = false,
        connectionType: String = "5G / LTE",
        ispName: String = "Мобильный интернет",
        isGamingMode: Bool = false,
        gameTitle: String? = nil,
        gameRegion: String? = nil,
        packetLossPct: Double? = nil
    ) {
        #if canImport(ActivityKit)
        guard areActivitiesEnabled else {
            print("⚠️ Live Activities отключены в системе")
            self.isLiveActivityActive = false
            return
        }

        // 1. Проверяем, есть ли уже активная сессия
        if let active = Activity<NetPulseAttributes>.activities.first(where: { $0.activityState == .active }) {
            self.currentActivity = active
            self.isLiveActivityActive = true
            monitorActivityState(active)
            updateActivity(
                downloadSpeedText: downloadSpeedText,
                uploadSpeedText: uploadSpeedText,
                compactDownloadText: compactDownloadText,
                compactUploadText: compactUploadText,
                pingMs: pingMs,
                jitterMs: jitterMs,
                isTesting: isTesting,
                connectionType: connectionType,
                ispName: ispName,
                isGamingMode: isGamingMode,
                gameTitle: gameTitle,
                gameRegion: gameRegion,
                packetLossPct: packetLossPct,
                force: true
            )
            return
        }

        let attributes = NetPulseAttributes(sessionTitle: "Мониторинг NetPulse")
        let initialState = NetPulseAttributes.ContentState(
            downloadSpeedText: downloadSpeedText,
            uploadSpeedText: uploadSpeedText,
            compactDownloadText: compactDownloadText,
            compactUploadText: compactUploadText,
            pingMs: pingMs,
            jitterMs: jitterMs,
            isTesting: isTesting,
            connectionType: connectionType,
            ispName: ispName,
            isGamingMode: isGamingMode,
            gameTitle: gameTitle,
            gameRegion: gameRegion,
            packetLossPct: packetLossPct
        )

        let content = ActivityContent(
            state: initialState,
            staleDate: Date().addingTimeInterval(30), // 30 секунд для реалтайм телеметрии
            relevanceScore: isTesting ? 100.0 : (isGamingMode ? 90.0 : 80.0)
        )

        do {
            let activity = try Activity<NetPulseAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            self.currentActivity = activity
            self.isLiveActivityActive = true
            self.lastContentState = initialState
            self.lastUpdateDate = Date()
            monitorActivityState(activity)
            print("✅ Live Activity успешно запущена в Dynamic Island: \(activity.id)")
        } catch {
            print("⚠️ Ошибка запуска Live Activity: \(error.localizedDescription). Запуск цикла самовосстановления...")
            // Цикл самовосстановления: завершаем все устаревшие сессии и пробуем снова
            Task { @MainActor in
                for existing in Activity<NetPulseAttributes>.activities {
                    await existing.end(nil, dismissalPolicy: .immediate)
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
                do {
                    let activity = try Activity<NetPulseAttributes>.request(
                        attributes: attributes,
                        content: content,
                        pushType: nil
                    )
                    self.currentActivity = activity
                    self.isLiveActivityActive = true
                    self.lastContentState = initialState
                    self.lastUpdateDate = Date()
                    self.monitorActivityState(activity)
                    print("✅ Самовосстановление успешно: Live Activity запущена: \(activity.id)")
                } catch {
                    print("❌ Повторная попытка запуска Live Activity не удалась: \(error.localizedDescription)")
                    self.isLiveActivityActive = false
                }
            }
        }
        #endif
    }

    /// Принудительный перезапуск Live Activity (ручное управление и самовосстановление)
    public func restartActivity(
        downloadSpeedText: String = "0 Мбит/с",
        uploadSpeedText: String = "0 Мбит/с",
        compactDownloadText: String = "0B",
        compactUploadText: String = "0B",
        pingMs: Double? = nil,
        jitterMs: Double? = nil,
        isTesting: Bool = false,
        connectionType: String = "5G / LTE",
        ispName: String = "Мобильный интернет",
        isGamingMode: Bool = false,
        gameTitle: String? = nil,
        gameRegion: String? = nil,
        packetLossPct: Double? = nil
    ) {
        #if canImport(ActivityKit)
        stopActivity()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            self.startActivity(
                downloadSpeedText: downloadSpeedText,
                uploadSpeedText: uploadSpeedText,
                compactDownloadText: compactDownloadText,
                compactUploadText: compactUploadText,
                pingMs: pingMs,
                jitterMs: jitterMs,
                isTesting: isTesting,
                connectionType: connectionType,
                ispName: ispName,
                isGamingMode: isGamingMode,
                gameTitle: gameTitle,
                gameRegion: gameRegion,
                packetLossPct: packetLossPct
            )
        }
        #endif
    }

    #if canImport(ActivityKit)
    /// Отслеживание жизненного цикла системной активности (отслеживает свайп пользователя)
    private func monitorActivityState(_ activity: Activity<NetPulseAttributes>) {
        stateObservationTask?.cancel()
        stateObservationTask = Task { [weak self, activityId = activity.id] in
            for await state in activity.activityStateUpdates {
                if state == .ended || state == .dismissed {
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        if self.currentActivity?.id == activityId {
                            self.currentActivity = nil
                            self.lastContentState = nil
                            self.queuedState = nil
                            self.isUpdating = false
                            self.isLiveActivityActive = false
                            print("ℹ️ Live Activity завершена системой или пользователем — состояние сброшено")
                        }
                    }
                    break
                }
            }
        }
    }
    #endif

    /// Обновление живых данных реальной скорости в Dynamic Island с надежным неблокирующим конвейером
    public func updateActivity(
        downloadSpeedText: String,
        uploadSpeedText: String,
        compactDownloadText: String,
        compactUploadText: String,
        pingMs: Double? = nil,
        jitterMs: Double? = nil,
        isTesting: Bool,
        connectionType: String,
        ispName: String,
        isGamingMode: Bool = false,
        gameTitle: String? = nil,
        gameRegion: String? = nil,
        packetLossPct: Double? = nil,
        force: Bool = false
    ) {
        #if canImport(ActivityKit)
        guard areActivitiesEnabled else {
            self.isLiveActivityActive = false
            return
        }

        var activeActivity = currentActivity
        if activeActivity == nil || activeActivity?.activityState != .active {
            activeActivity = Activity<NetPulseAttributes>.activities.first(where: { $0.activityState == .active })
        }

        // 1. Проверяем наличие активной сессии ДО дедупликации — предотвращает зависание при пересоздании островка
        guard let activity = activeActivity else {
            self.lastContentState = nil
            self.queuedState = nil
            self.isUpdating = false
            startActivity(
                downloadSpeedText: downloadSpeedText,
                uploadSpeedText: uploadSpeedText,
                compactDownloadText: compactDownloadText,
                compactUploadText: compactUploadText,
                pingMs: pingMs,
                jitterMs: jitterMs,
                isTesting: isTesting,
                connectionType: connectionType,
                ispName: ispName,
                isGamingMode: isGamingMode,
                gameTitle: gameTitle,
                gameRegion: gameRegion,
                packetLossPct: packetLossPct
            )
            return
        }

        self.currentActivity = activity
        self.isLiveActivityActive = true

        let updatedState = NetPulseAttributes.ContentState(
            downloadSpeedText: downloadSpeedText,
            uploadSpeedText: uploadSpeedText,
            compactDownloadText: compactDownloadText,
            compactUploadText: compactUploadText,
            pingMs: pingMs,
            jitterMs: jitterMs,
            isTesting: isTesting,
            connectionType: connectionType,
            ispName: ispName,
            isGamingMode: isGamingMode,
            gameTitle: gameTitle,
            gameRegion: gameRegion,
            packetLossPct: packetLossPct
        )

        // 2. Дедупликация обновлений: если данные не изменились (в покое 0K / 0K), не спамим SpringBoard IPC
        if !force, let last = lastContentState, last == updatedState {
            return
        }

        // 3. Неблокирующая FIFO очередь: если апдейт уже в полете, запоминаем самый свежий кадр
        if isUpdating && !force {
            self.queuedState = updatedState
            return
        }

        self.isUpdating = true
        self.queuedState = nil
        self.lastContentState = updatedState
        self.lastUpdateDate = Date()

        let content = ActivityContent(
            state: updatedState,
            staleDate: Date().addingTimeInterval(30),
            relevanceScore: isTesting ? 100.0 : (isGamingMode ? 90.0 : 80.0)
        )

        Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.processNextQueuedUpdate()
                }
            }
            await activity.update(content)
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        #endif
    }

    #if canImport(ActivityKit)
    /// Обработка накопленного обновления из очереди (FIFO)
    private func processNextQueuedUpdate() {
        guard let nextState = queuedState, let activity = currentActivity, activity.activityState == .active else {
            self.isUpdating = false
            self.queuedState = nil
            return
        }

        if let last = lastContentState, last == nextState {
            self.isUpdating = false
            self.queuedState = nil
            return
        }

        self.queuedState = nil
        self.lastContentState = nextState
        self.lastUpdateDate = Date()

        let content = ActivityContent(
            state: nextState,
            staleDate: Date().addingTimeInterval(30),
            relevanceScore: nextState.isTesting ? 100.0 : (nextState.isGamingMode ? 90.0 : 80.0)
        )

        Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.processNextQueuedUpdate()
                }
            }
            await activity.update(content)
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }
    #endif

    /// Остановка Live Activity
    public func stopActivity() {
        #if canImport(ActivityKit)
        stateObservationTask?.cancel()
        stateObservationTask = nil
        isUpdating = false
        queuedState = nil
        lastContentState = nil
        lastUpdateDate = nil
        self.currentActivity = nil
        self.isLiveActivityActive = false

        Task {
            for activity in Activity<NetPulseAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        print("🛑 Live Activity остановлена")
        #endif
    }
}
