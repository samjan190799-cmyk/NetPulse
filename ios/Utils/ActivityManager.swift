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
    private var lastRenderedState: NetPulseAttributes.ContentState?
    private var lastUpdateTime: Date?
    private var pendingState: NetPulseAttributes.ContentState?
    private var isSendingUpdate: Bool = false
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
        compactDownloadText: String = "0K",
        compactUploadText: String = "0K",
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

        // Если активная сессия уже существует в системе — подключаемся к ней
        let validActivities = Activity<NetPulseAttributes>.activities.filter { $0.activityState != .ended && $0.activityState != .dismissed }
        if let existing = validActivities.first {
            self.currentActivity = existing
            self.isLiveActivityActive = true
            monitorActivityState(existing)
            if validActivities.count > 1 {
                for duplicate in validActivities.dropFirst() {
                    Task { await duplicate.end(nil, dismissalPolicy: .immediate) }
                }
            }
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

        // Иначе создаем новую сессию
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

    /// Запуск Live Activity в Dynamic Island с надежной инициализацией
    public func startActivity(
        downloadSpeedText: String = "0 Мбит/с",
        uploadSpeedText: String = "0 Мбит/с",
        compactDownloadText: String = "0K",
        compactUploadText: String = "0K",
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

        // Проверяем, есть ли уже живая сессия
        let validActivities = Activity<NetPulseAttributes>.activities.filter { $0.activityState != .ended && $0.activityState != .dismissed }
        if let active = validActivities.first {
            self.currentActivity = active
            self.isLiveActivityActive = true
            monitorActivityState(active)
            if validActivities.count > 1 {
                for duplicate in validActivities.dropFirst() {
                    Task { await duplicate.end(nil, dismissalPolicy: .immediate) }
                }
            }
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

        // staleDate: nil гарантирует, что iOS НИКОГДА не переведет сессию в статус .stale
        let content = ActivityContent(
            state: initialState,
            staleDate: nil,
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
            self.lastRenderedState = initialState
            monitorActivityState(activity)
            print("✅ Live Activity успешно запущена в Dynamic Island: \(activity.id)")
        } catch {
            print("⚠️ Ошибка запуска Live Activity: \(error.localizedDescription)")
            self.isLiveActivityActive = false
        }
        #endif
    }

    /// Принудительный перезапуск Live Activity
    public func restartActivity(
        downloadSpeedText: String = "0 Мбит/с",
        uploadSpeedText: String = "0 Мбит/с",
        compactDownloadText: String = "0K",
        compactUploadText: String = "0K",
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
        let validActivities = Activity<NetPulseAttributes>.activities.filter { $0.activityState != .ended && $0.activityState != .dismissed }
        if let existing = validActivities.first {
            self.currentActivity = existing
            self.isLiveActivityActive = true
            monitorActivityState(existing)
            if validActivities.count > 1 {
                for duplicate in validActivities.dropFirst() {
                    Task { await duplicate.end(nil, dismissalPolicy: .immediate) }
                }
            }
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
        } else {
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
        }
        #endif
    }

    #if canImport(ActivityKit)
    private func monitorActivityState(_ activity: Activity<NetPulseAttributes>) {
        stateObservationTask?.cancel()
        stateObservationTask = Task { [weak self, activityId = activity.id] in
            for await state in activity.activityStateUpdates {
                guard let self = self else { break }
                if state == .ended || state == .dismissed {
                    await MainActor.run {
                        if self.currentActivity?.id == activityId {
                            self.currentActivity = nil
                            self.lastRenderedState = nil
                            self.pendingState = nil
                            self.isSendingUpdate = false
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
        if activeActivity == nil || activeActivity?.activityState == .ended || activeActivity?.activityState == .dismissed {
            let valid = Activity<NetPulseAttributes>.activities.filter { $0.activityState != .ended && $0.activityState != .dismissed }
            activeActivity = valid.first
            if valid.count > 1 {
                for duplicate in valid.dropFirst() {
                    Task { await duplicate.end(nil, dismissalPolicy: .immediate) }
                }
            }
        }

        // Проверяем наличие активной сессии
        guard let activity = activeActivity else {
            if UIApplication.shared.applicationState != .background {
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
            }
            return
        }

        self.currentActivity = activity
        self.isLiveActivityActive = true

        let roundedPing = pingMs.map { ($0).rounded() }
        let roundedJitter = jitterMs.map { ($0 * 10).rounded() / 10.0 }

        let newState = NetPulseAttributes.ContentState(
            downloadSpeedText: downloadSpeedText,
            uploadSpeedText: uploadSpeedText,
            compactDownloadText: compactDownloadText,
            compactUploadText: compactUploadText,
            pingMs: roundedPing,
            jitterMs: roundedJitter,
            isTesting: isTesting,
            connectionType: connectionType,
            ispName: ispName,
            isGamingMode: isGamingMode,
            gameTitle: gameTitle,
            gameRegion: gameRegion,
            packetLossPct: packetLossPct
        )

        // Защита от перегрева и спама XPC (Apple HIG Energy Guidelines):
        // Если визуально видимые показатели (скорость в островке) не изменились,
        // и с момента прошлого вызова прошло меньше 2.5 секунд — пропускаем обновление.
        if !force, let last = lastRenderedState {
            let speedChanged = (last.compactDownloadText != newState.compactDownloadText) ||
                               (last.compactUploadText != newState.compactUploadText) ||
                               (last.isTesting != newState.isTesting)

            if !speedChanged {
                if let lastTime = lastUpdateTime, Date().timeIntervalSince(lastTime) < 2.5 {
                    return
                }
            }
        }

        // Запоминаем самый актуальный кадр телеметрии
        self.pendingState = newState

        // Если в данный момент уже идет XPC-вызов обновления в SpringBoard,
        // новый кадр отправится немедленно по завершении текущего вызова
        guard !isSendingUpdate else { return }

        dispatchNextUpdate()
        #endif
    }

    #if canImport(ActivityKit)
    /// Последовательная отправка кадров в SpringBoard без потери последних значений
    private func dispatchNextUpdate() {
        guard let stateToSend = pendingState,
              let activity = currentActivity,
              activity.activityState != .ended && activity.activityState != .dismissed else {
            isSendingUpdate = false
            return
        }

        isSendingUpdate = true
        pendingState = nil

        let content = ActivityContent(
            state: stateToSend,
            staleDate: nil,
            relevanceScore: stateToSend.isTesting ? 100.0 : (stateToSend.isGamingMode ? 90.0 : 80.0)
        )

        Task { @MainActor [weak self] in
            await activity.update(content)
            self?.lastRenderedState = stateToSend
            self?.lastUpdateTime = Date()
            self?.isSendingUpdate = false

            // Если во время обновления прибыл более свежий кадр — отправляем его без задержки
            if self?.pendingState != nil {
                self?.dispatchNextUpdate()
            }
        }
    }
    #endif

    /// Остановка Live Activity
    public func stopActivity() {
        #if canImport(ActivityKit)
        stateObservationTask?.cancel()
        stateObservationTask = nil
        isSendingUpdate = false
        pendingState = nil
        lastRenderedState = nil
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
