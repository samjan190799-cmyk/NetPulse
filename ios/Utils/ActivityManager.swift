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

/// Синглтон управления жизненным циклом Live Activity для Dynamic Island.
@MainActor
public final class ActivityManager {
    public static let shared = ActivityManager()

    #if canImport(ActivityKit)
    private var currentActivity: Activity<NetPulseAttributes>?
    private var lastContentState: NetPulseAttributes.ContentState?
    private var lastUpdateDate: Date?
    private var pendingUpdateTask: Task<Void, Never>?
    #endif

    public private(set) var isLiveActivityActive: Bool = false

    private init() {}

    /// Запуск Live Activity в Dynamic Island с реальной скоростью загрузки и отдачи
    public func startActivity(
        downloadSpeedText: String = "↓ 0 КБ/с",
        uploadSpeedText: String = "↑ 0 КБ/с",
        compactDownloadText: String = "↓0K",
        compactUploadText: String = "↑0K",
        isTesting: Bool = false,
        connectionType: String = "Wi-Fi",
        ispName: String = "Интернет"
    ) {
        #if canImport(ActivityKit)
        pendingUpdateTask?.cancel()
        pendingUpdateTask = nil

        // Завершаем старые активные сессии перед созданием новой
        for activity in Activity<NetPulseAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        let attributes = NetPulseAttributes(sessionTitle: "Мониторинг NetPulse")
        let initialState = NetPulseAttributes.ContentState(
            downloadSpeedText: downloadSpeedText,
            uploadSpeedText: uploadSpeedText,
            compactDownloadText: compactDownloadText,
            compactUploadText: compactUploadText,
            isTesting: isTesting,
            connectionType: connectionType,
            ispName: ispName
        )

        let content = ActivityContent(
            state: initialState,
            staleDate: Date(timeIntervalSinceNow: isTesting ? 4.0 : 6.0),
            relevanceScore: 100.0
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

    /// Обновление живых данных реальной скорости в Dynamic Island с умным троттлингом
    public func updateActivity(
        downloadSpeedText: String,
        uploadSpeedText: String,
        compactDownloadText: String,
        compactUploadText: String,
        isTesting: Bool,
        connectionType: String,
        ispName: String,
        force: Bool = false
    ) {
        #if canImport(ActivityKit)
        guard let activity = currentActivity ?? Activity<NetPulseAttributes>.activities.first else {
            // Если сессии не было, но вызван update - запускаем
            startActivity(
                downloadSpeedText: downloadSpeedText,
                uploadSpeedText: uploadSpeedText,
                compactDownloadText: compactDownloadText,
                compactUploadText: compactUploadText,
                isTesting: isTesting,
                connectionType: connectionType,
                ispName: ispName
            )
            return
        }

        // Если сессия была завершена операционной системой, пересоздаем ее
        guard activity.activityState == .active else {
            self.currentActivity = nil
            startActivity(
                downloadSpeedText: downloadSpeedText,
                uploadSpeedText: uploadSpeedText,
                compactDownloadText: compactDownloadText,
                compactUploadText: compactUploadText,
                isTesting: isTesting,
                connectionType: connectionType,
                ispName: ispName
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
            isTesting: isTesting,
            connectionType: connectionType,
            ispName: ispName
        )

        // 1. Проверка дублирующегося состояния (не жжем бюджет ActivityKit на одинаковые данные)
        if !force, let lastState = lastContentState, lastState == updatedState {
            return
        }

        // 2. Троттлинг вызовов: защита от исчерпания бюджета обновлений Apple ActivityKit
        let minInterval: TimeInterval = isTesting ? 1.0 : 1.8
        let now = Date()
        if !force, let lastDate = lastUpdateDate, now.timeIntervalSince(lastDate) < minInterval {
            return
        }

        self.lastContentState = updatedState
        self.lastUpdateDate = now

        let content = ActivityContent(
            state: updatedState,
            staleDate: Date(timeIntervalSinceNow: isTesting ? 4.0 : 6.0),
            relevanceScore: isTesting ? 100.0 : 50.0
        )

        // Отменяем предыдущую задачу обновления, если она еще не успела исполниться
        pendingUpdateTask?.cancel()
        pendingUpdateTask = Task {
            await activity.update(content)
        }
        #endif
    }

    /// Остановка Live Activity
    public func stopActivity() {
        #if canImport(ActivityKit)
        pendingUpdateTask?.cancel()
        pendingUpdateTask = nil
        lastContentState = nil
        lastUpdateDate = nil

        for activity in Activity<NetPulseAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        self.currentActivity = nil
        self.isLiveActivityActive = false
        #endif
    }
}

