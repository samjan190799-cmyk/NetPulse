//
//  BackgroundTaskManager.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import BackgroundTasks
import UIKit

/// Менеджер системных фоновых задач iOS (BGTaskScheduler) для гарантированного сбора трафика (Zero-Loss 24/7)
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
        // Планирование App Refresh (минимум через 15 минут)
        let refreshRequest = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        refreshRequest.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(refreshRequest)
            print("🗓️ Фоновое обновление BGAppRefreshTask запланировано")
        } catch {
            print("⚠️ Не удалось запланировать BGAppRefreshTask: \(error.localizedDescription)")
        }

        // Планирование Processing Task (минимум через 30 минут)
        let processingRequest = BGProcessingTaskRequest(identifier: Self.telemetryTaskId)
        processingRequest.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        processingRequest.requiresNetworkConnectivity = false
        processingRequest.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(processingRequest)
            print("🗓️ Фоновая обработка BGProcessingTask запланирована")
        } catch {
            print("⚠️ Не удалось запланировать BGProcessingTask: \(error.localizedDescription)")
        }
    }

    // MARK: - Обработчики выполнения фоновых задач

    private func handleAppRefreshTask(_ task: BGAppRefreshTask) {
        // Планируем следующий запуск
        scheduleBackgroundFetch()

        let queueTask = Task {
            let diagnostics = NetworkDiagnostics()
            let info = await diagnostics.collectSystemInfo()
            await TrafficStorage.shared.reconcileBackgroundHardwareTraffic(
                currentConnectionType: info.connectionType.rawValue,
                currentNetworkName: info.ispName ?? info.connectionType.rawValue
            )
            await TrafficStorage.shared.flush()

            let snapshot = BandwidthEngine.shared.sampleBandwidth(activeConnectionType: info.connectionType)
            let trafficSummary = await TrafficStorage.shared.getSummary(for: .today)

            let widgetData = NetPulseWidgetData(
                downloadSpeedMbps: snapshot.downloadMbps,
                uploadSpeedMbps: snapshot.uploadMbps,
                pingMs: nil,
                jitterMs: nil,
                lossPercent: 0.0,
                ispName: info.ispName ?? "Интернет",
                connectionType: info.connectionType.rawValue,
                todayTrafficBytes: Int64(trafficSummary.totalTraffic),
                budgetTotalBytes: 5_368_709_120,
                healthScore: 100,
                dnsHosts: [],
                lastUpdated: Date()
            )
            WidgetDataManager.shared.saveSnapshot(widgetData)

            // Автовосстановление сессии Dynamic Island при фоновом пробуждении
            let isLiveEnabled = UserDefaults.standard.bool(forKey: "netpulse_live_activity_enabled")
            if isLiveEnabled {
                await MainActor.run {
                    ActivityManager.shared.checkAndRestoreActivity(
                        downloadSpeedText: snapshot.formattedDownloadSpeed,
                        uploadSpeedText: snapshot.formattedUploadSpeed,
                        compactDownloadText: snapshot.compactDownload,
                        compactUploadText: snapshot.compactUpload,
                        isTesting: false,
                        connectionType: info.connectionType.rawValue,
                        ispName: info.ispName ?? "Интернет"
                    )
                }
            }

            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            queueTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    private func handleTelemetryProcessingTask(_ task: BGProcessingTask) {
        scheduleBackgroundFetch()

        let queueTask = Task {
            let diagnostics = NetworkDiagnostics()
            let info = await diagnostics.collectSystemInfo()
            await TrafficStorage.shared.reconcileBackgroundHardwareTraffic(
                currentConnectionType: info.connectionType.rawValue,
                currentNetworkName: info.ispName ?? info.connectionType.rawValue
            )
            await TrafficStorage.shared.flush()

            let snapshot = BandwidthEngine.shared.sampleBandwidth(activeConnectionType: info.connectionType)
            let trafficSummary = await TrafficStorage.shared.getSummary(for: .today)

            let widgetData = NetPulseWidgetData(
                downloadSpeedMbps: snapshot.downloadMbps,
                uploadSpeedMbps: snapshot.uploadMbps,
                pingMs: nil,
                jitterMs: nil,
                lossPercent: 0.0,
                ispName: info.ispName ?? "Интернет",
                connectionType: info.connectionType.rawValue,
                todayTrafficBytes: Int64(trafficSummary.totalTraffic),
                budgetTotalBytes: 5_368_709_120,
                healthScore: 100,
                dnsHosts: [],
                lastUpdated: Date()
            )
            WidgetDataManager.shared.saveSnapshot(widgetData)

            let isLiveEnabled = UserDefaults.standard.bool(forKey: "netpulse_live_activity_enabled")
            if isLiveEnabled {
                await MainActor.run {
                    ActivityManager.shared.checkAndRestoreActivity(
                        downloadSpeedText: snapshot.formattedDownloadSpeed,
                        uploadSpeedText: snapshot.formattedUploadSpeed,
                        compactDownloadText: snapshot.compactDownload,
                        compactUploadText: snapshot.compactUpload,
                        isTesting: false,
                        connectionType: info.connectionType.rawValue,
                        ispName: info.ispName ?? "Интернет"
                    )
                }
            }

            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            queueTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
