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
    #endif

    public private(set) var isLiveActivityActive: Bool = false

    private init() {}

    /// Запуск Live Activity в Dynamic Island
    public func startActivity(
        downloadMbps: Double = 0.0,
        uploadMbps: Double = 0.0,
        pingMs: Double? = nil,
        jitterMs: Double? = nil,
        connectionType: String = "Wi-Fi",
        ispName: String = "Интернет"
    ) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Завершаем старую сессию, если она была
        stopActivity()

        let attributes = NetPulseAttributes(sessionTitle: "Мониторинг NetPulse")
        let initialState = NetPulseAttributes.ContentState(
            downloadMbps: downloadMbps,
            uploadMbps: uploadMbps,
            pingMs: pingMs,
            jitterMs: jitterMs,
            isTesting: false,
            connectionType: connectionType,
            ispName: ispName
        )

        do {
            let activity = try Activity<NetPulseAttributes>.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            self.currentActivity = activity
            self.isLiveActivityActive = true
        } catch {
            print("Не удалось запустить Live Activity: \(error.localizedDescription)")
        }
        #endif
    }

    /// Обновление живых данных скорости и пинга в Dynamic Island
    public func updateActivity(
        downloadMbps: Double,
        uploadMbps: Double,
        pingMs: Double?,
        jitterMs: Double?,
        isTesting: Bool,
        connectionType: String,
        ispName: String
    ) {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }

        let updatedState = NetPulseAttributes.ContentState(
            downloadMbps: downloadMbps,
            uploadMbps: uploadMbps,
            pingMs: pingMs,
            jitterMs: jitterMs,
            isTesting: isTesting,
            connectionType: connectionType,
            ispName: ispName
        )

        Task {
            await activity.update(.init(state: updatedState, staleDate: nil))
        }
        #endif
    }

    /// Остановка Live Activity
    public func stopActivity() {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }

        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        self.currentActivity = nil
        self.isLiveActivityActive = false
        #endif
    }
}
