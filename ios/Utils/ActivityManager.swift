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

/// Синглтон управления жизненным циклом Live Activity для Dynamic Island без замираний.
@MainActor
public final class ActivityManager {
    public static let shared = ActivityManager()

    #if canImport(ActivityKit)
    private var currentActivity: Activity<NetPulseAttributes>?
    private var lastContentState: NetPulseAttributes.ContentState?
    private var lastUpdateDate: Date?
    private var isUpdating: Bool = false
    private var queuedState: NetPulseAttributes.ContentState?
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

    /// Восстановление или запуск сессии Dynamic Island
    public func checkAndRestoreActivity(
        downloadSpeedText: String = "100 Мбит/с",
        uploadSpeedText: String = "45 мс",
        compactDownloadText: String = "100M",
        compactUploadText: String = "45ms",
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
            return
        }

        // Если активная сессия уже существует в системе — подключаемся к ней
        if let existing = Activity<NetPulseAttributes>.activities.first(where: { $0.activityState == .active }) {
            self.currentActivity = existing
            self.isLiveActivityActive = true
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

    /// Запуск Live Activity в Dynamic Island с реальной скоростью загрузки и отдачи
    public func startActivity(
        downloadSpeedText: String = "100 Мбит/с",
        uploadSpeedText: String = "45 мс",
        compactDownloadText: String = "100M",
        compactUploadText: String = "45ms",
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

        // staleDate на 4 часа вперед предотвращает замораживание виджета операционной системой
        let content = ActivityContent(
            state: initialState,
            staleDate: Date().addingTimeInterval(14400),
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
            print("✅ Live Activity успешно запущена в Dynamic Island: \(activity.id)")
        } catch {
            print("❌ Ошибка запуска Live Activity: \(error.localizedDescription)")
            self.isLiveActivityActive = false
        }
        #endif
    }

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
        var activeActivity = currentActivity
        if activeActivity == nil || activeActivity?.activityState != .active {
            activeActivity = Activity<NetPulseAttributes>.activities.first(where: { $0.activityState == .active })
        }

        guard let activity = activeActivity else {
            // Если сессия отсутствует, создаем новую
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

        let now = Date()

        // 1. Проверка дублирующегося состояния: если данные не изменились, отправляем heartbeat каждые 5 секунд
        if !force, let lastState = lastContentState, lastState == updatedState {
            if let lastDate = lastUpdateDate, now.timeIntervalSince(lastDate) < 5.0 {
                return
            }
        }

        // 2. Троттлинг вызовов: защита от перегрузки XPC-очереди ActivityKit (0.4 сек во время теста, 1.0 сек в обычном)
        let minInterval: TimeInterval = isTesting ? 0.4 : 1.0
        if !force, let lastDate = lastUpdateDate, now.timeIntervalSince(lastDate) < minInterval {
            // Сохраняем в очередь на отправку после завершения интервала
            self.queuedState = updatedState
            return
        }

        self.lastContentState = updatedState
        self.lastUpdateDate = now
        self.queuedState = nil

        let content = ActivityContent(
            state: updatedState,
            staleDate: Date().addingTimeInterval(14400),
            relevanceScore: isTesting ? 100.0 : (isGamingMode ? 90.0 : 80.0)
        )

        // Надежный конвейер выполнения без прерывания активного вызова
        guard !isUpdating else {
            self.queuedState = updatedState
            return
        }

        isUpdating = true
        Task { [weak self] in
            await activity.update(content)
            guard let self = self else { return }
            self.isUpdating = false

            // Если за время отправки накопился свежий снимок, отправляем его
            if let queued = self.queuedState {
                self.queuedState = nil
                self.lastContentState = queued
                self.lastUpdateDate = Date()
                let nextContent = ActivityContent(
                    state: queued,
                    staleDate: Date().addingTimeInterval(14400),
                    relevanceScore: queued.isTesting ? 100.0 : (queued.isGamingMode ? 90.0 : 80.0)
                )
                await activity.update(nextContent)
            }
        }
        #endif
    }

    /// Остановка Live Activity
    public func stopActivity() {
        #if canImport(ActivityKit)
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
