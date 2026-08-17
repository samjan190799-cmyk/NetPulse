//
//  TrafficModels.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Период агрегации статистики расхода сетевого трафика
public enum TrafficPeriod: String, CaseIterable, Identifiable, Codable, Sendable {
    case today = "Сегодня"
    case week = "7 дней"
    case month = "30 дней"
    case allTime = "Всё время"

    public var id: String { rawValue }
}

/// Точечный замер сетевого трафика во времени (для построения графиков)
public struct TrafficDataPoint: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let downloadBytes: UInt64
    public let uploadBytes: UInt64
    public let wifiBytes: UInt64
    public let cellularBytes: UInt64

    public var totalBytes: UInt64 {
        downloadBytes + uploadBytes
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        downloadBytes: UInt64,
        uploadBytes: UInt64,
        wifiBytes: UInt64,
        cellularBytes: UInt64
    ) {
        self.id = id
        self.timestamp = timestamp
        self.downloadBytes = downloadBytes
        self.uploadBytes = uploadBytes
        self.wifiBytes = wifiBytes
        self.cellularBytes = cellularBytes
    }
}

/// Сессия подключения к конкретной сети (Wi-Fi точка, сотовая сеть, офисный интернет)
public struct TrafficSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public let networkName: String
    public let connectionType: String
    public let interfaceName: String
    public let startDate: Date
    public var endDate: Date?
    public var downloadedBytes: UInt64
    public var uploadedBytes: UInt64
    public var peakDownloadBps: Double
    public var peakUploadBps: Double
    public var isActive: Bool

    public var totalBytes: UInt64 {
        downloadedBytes + uploadedBytes
    }

    public var duration: TimeInterval {
        let end = endDate ?? Date()
        return max(end.timeIntervalSince(startDate), 1.0)
    }

    public var formattedDuration: String {
        let secs = Int(duration)
        let hours = secs / 3600
        let minutes = (secs % 3600) / 60
        let seconds = secs % 60

        if hours > 0 {
            return String(format: "%d ч %02d мин", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%d мин %02d сек", minutes, seconds)
        } else {
            return String(format: "%d сек", seconds)
        }
    }

    public init(
        id: UUID = UUID(),
        networkName: String,
        connectionType: String,
        interfaceName: String,
        startDate: Date = Date(),
        endDate: Date? = nil,
        downloadedBytes: UInt64 = 0,
        uploadedBytes: UInt64 = 0,
        peakDownloadBps: Double = 0,
        peakUploadBps: Double = 0,
        isActive: Bool = true
    ) {
        self.id = id
        self.networkName = networkName
        self.connectionType = connectionType
        self.interfaceName = interfaceName
        self.startDate = startDate
        self.endDate = endDate
        self.downloadedBytes = downloadedBytes
        self.uploadedBytes = uploadedBytes
        self.peakDownloadBps = peakDownloadBps
        self.peakUploadBps = peakUploadBps
        self.isActive = isActive
    }
}

/// Сводная статистика расхода трафика за выбранный период
public struct TrafficSummary: Codable, Sendable {
    public var totalDownload: UInt64
    public var totalUpload: UInt64
    public var wifiDownload: UInt64
    public var wifiUpload: UInt64
    public var cellularDownload: UInt64
    public var cellularUpload: UInt64
    public var activeSessionsCount: Int
    public var totalSessionsCount: Int

    public var totalTraffic: UInt64 {
        totalDownload + totalUpload
    }

    public var totalWifi: UInt64 {
        wifiDownload + wifiUpload
    }

    public var totalCellular: UInt64 {
        cellularDownload + cellularUpload
    }

    public var wifiPercentage: Double {
        guard totalTraffic > 0 else { return 0.0 }
        return (Double(totalWifi) / Double(totalTraffic)) * 100.0
    }

    public var cellularPercentage: Double {
        guard totalTraffic > 0 else { return 0.0 }
        return (Double(totalCellular) / Double(totalTraffic)) * 100.0
    }

    public init(
        totalDownload: UInt64 = 0,
        totalUpload: UInt64 = 0,
        wifiDownload: UInt64 = 0,
        wifiUpload: UInt64 = 0,
        cellularDownload: UInt64 = 0,
        cellularUpload: UInt64 = 0,
        activeSessionsCount: Int = 0,
        totalSessionsCount: Int = 0
    ) {
        self.totalDownload = totalDownload
        self.totalUpload = totalUpload
        self.wifiDownload = wifiDownload
        self.wifiUpload = wifiUpload
        self.cellularDownload = cellularDownload
        self.cellularUpload = cellularUpload
        self.activeSessionsCount = activeSessionsCount
        self.totalSessionsCount = totalSessionsCount
    }
}

/// Конфигурация лимита (квоты) трафика
public struct TrafficBudget: Codable, Sendable {
    public var isEnabled: Bool
    public var limitBytes: UInt64 // Например, 10 GB = 10 * 1024 * 1024 * 1024
    public var period: TrafficPeriod
    public var warningThresholdPct: Double // Порог предупреждения (например 80%)

    public init(
        isEnabled: Bool = false,
        limitBytes: UInt64 = 10 * 1024 * 1024 * 1024, // 10 GB по умолчанию
        period: TrafficPeriod = .month,
        warningThresholdPct: Double = 80.0
    ) {
        self.isEnabled = isEnabled
        self.limitBytes = limitBytes
        self.period = period
        self.warningThresholdPct = warningThresholdPct
    }

    public func usagePercentage(usedBytes: UInt64) -> Double {
        guard isEnabled && limitBytes > 0 else { return 0.0 }
        return min((Double(usedBytes) / Double(limitBytes)) * 100.0, 100.0)
    }

    public func isWarning(usedBytes: UInt64) -> Bool {
        guard isEnabled else { return false }
        return usagePercentage(usedBytes: usedBytes) >= warningThresholdPct
    }

    public func isExceeded(usedBytes: UInt64) -> Bool {
        guard isEnabled else { return false }
        return usedBytes >= limitBytes
    }
}

/// Форматирование байтов в человекочитаемый вид
public enum TrafficFormatter {
    public static func formatBytes(_ bytes: UInt64) -> String {
        let doubleBytes = Double(bytes)
        let gb = 1_073_741_824.0
        let mb = 1_048_576.0
        let kb = 1_024.0

        if doubleBytes >= gb {
            return String(format: "%.2f ГБ", doubleBytes / gb)
        } else if doubleBytes >= mb {
            return String(format: "%.1f МБ", doubleBytes / mb)
        } else if doubleBytes >= kb {
            return String(format: "%.0f КБ", doubleBytes / kb)
        } else {
            return "\(bytes) Б"
        }
    }

    public static func formatSpeedBps(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576 {
            return String(format: "%.1f МБ/с", bytesPerSec / 1_048_576)
        } else if bytesPerSec >= 1_024 {
            return String(format: "%.0f КБ/с", bytesPerSec / 1_024)
        } else {
            return String(format: "%.0f Б/с", bytesPerSec)
        }
    }
}
