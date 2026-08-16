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
    private var isUpdating: Bool = false
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
            staleDate: nil,
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

    /// Обновление живых данных реальной скорости в Dynamic Island с надежным XPC-шлюзом
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

        // 1. Проверка дублирующегося состояния: если данные не изменились, отправляем heartbeat каждые 10 секунд
        if !force, let lastState = lastContentState, lastState == updatedState {
            if let lastDate = lastUpdateDate, Date().timeIntervalSince(lastDate) < 10.0 {
                return
            }
        }

        // 2. Троттлинг вызовов: защита от перегрузки очереди (минимум 2.0 сек между обновлениями)
        let minInterval: TimeInterval = isTesting ? 1.5 : 2.0
        let now = Date()
        if !force, let lastDate = lastUpdateDate, now.timeIntervalSince(lastDate) < minInterval {
            return
        }

        // 3. Защита от наложения одновременных XPC-запросов к SpringBoard/ActivityKit
        guard !isUpdating else { return }
        isUpdating = true

        self.lastContentState = updatedState
        self.lastUpdateDate = now

        let content = ActivityContent(
            state: updatedState,
            staleDate: nil,
            relevanceScore: isTesting ? 100.0 : 75.0
        )

        Task {
            await activity.update(content)
            self.isUpdating = false
        }
        #endif
    }

    /// Остановка Live Activity
    public func stopActivity() {
        #if canImport(ActivityKit)
        lastContentState = nil
        lastUpdateDate = nil
        isUpdating = false

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

