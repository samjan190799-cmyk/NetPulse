//
//  WidgetDataManager.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / WidgetKit) - 2026.
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Информация о статусе отдельного DNS-узла для отображения в виджете
public struct WidgetDNSHost: Codable, Sendable, Identifiable {
    public var id: String { address }
    public let name: String
    public let address: String
    public let latencyMs: Double?
    public let isOK: Bool

    public init(name: String, address: String, latencyMs: Double?, isOK: Bool) {
        self.name = name
        self.address = address
        self.latencyMs = latencyMs
        self.isOK = isOK
    }
}

/// Универсальный снимок состояния сетевых метрик для всех семейств виджетов NetPulse
public struct NetPulseWidgetData: Codable, Sendable {
    public let downloadSpeedMbps: Double
    public let uploadSpeedMbps: Double
    public let pingMs: Double?
    public let jitterMs: Double?
    public let lossPercent: Double
    public let ispName: String
    public let connectionType: String
    public let todayTrafficBytes: Int64
    public let budgetTotalBytes: Int64
    public let healthScore: Int
    public let dnsHosts: [WidgetDNSHost]
    public let lastUpdated: Date

    public init(
        downloadSpeedMbps: Double = 0.0,
        uploadSpeedMbps: Double = 0.0,
        pingMs: Double? = nil,
        jitterMs: Double? = nil,
        lossPercent: Double = 0.0,
        ispName: String = "Wi-Fi Сеть",
        connectionType: String = "Wi-Fi",
        todayTrafficBytes: Int64 = 0,
        budgetTotalBytes: Int64 = 5_368_709_120, // 5 ГБ по умолчанию
        healthScore: Int = 100,
        dnsHosts: [WidgetDNSHost] = [],
        lastUpdated: Date = Date()
    ) {
        self.downloadSpeedMbps = downloadSpeedMbps
        self.uploadSpeedMbps = uploadSpeedMbps
        self.pingMs = pingMs
        self.jitterMs = jitterMs
        self.lossPercent = lossPercent
        self.ispName = ispName
        self.connectionType = connectionType
        self.todayTrafficBytes = todayTrafficBytes
        self.budgetTotalBytes = budgetTotalBytes
        self.healthScore = healthScore
        self.dnsHosts = dnsHosts
        self.lastUpdated = lastUpdated
    }

    /// Демонстрационный снимок данных по умолчанию
    public static var placeholder: NetPulseWidgetData {
        NetPulseWidgetData(
            downloadSpeedMbps: 285.4,
            uploadSpeedMbps: 84.1,
            pingMs: 16.5,
            jitterMs: 1.2,
            lossPercent: 0.0,
            ispName: "Wi-Fi (Fast Net)",
            connectionType: "Wi-Fi 6",
            todayTrafficBytes: 1_824_520_000,
            budgetTotalBytes: 5_368_709_120,
            healthScore: 98,
            dnsHosts: [
                WidgetDNSHost(name: "Cloudflare", address: "1.1.1.1", latencyMs: 14.2, isOK: true),
                WidgetDNSHost(name: "Google", address: "8.8.8.8", latencyMs: 18.7, isOK: true),
                WidgetDNSHost(name: "Шлюз", address: "192.168.1.1", latencyMs: 2.1, isOK: true),
                WidgetDNSHost(name: "Quad9", address: "9.9.9.9", latencyMs: 21.0, isOK: true)
            ],
            lastUpdated: Date()
        )
    }

    /// Процент использования дневного лимита трафика (0.0 ... 1.0)
    public var budgetProgress: Double {
        guard budgetTotalBytes > 0 else { return 0.0 }
        return min(max(Double(todayTrafficBytes) / Double(budgetTotalBytes), 0.0), 1.0)
    }

    /// Форматированная задержка
    public var formattedPing: String {
        if let ping = pingMs {
            return String(format: "%.0f мс", ping)
        }
        return "—"
    }

    /// Форматированный джиттер
    public var formattedJitter: String {
        if let jitter = jitterMs {
            return String(format: "%.1f мс", jitter)
        }
        return "—"
    }
}

/// Менеджер обмена данными между приложением и расширением виджетов через App Group
public final class WidgetDataManager: @unchecked Sendable {
    public static let shared = WidgetDataManager()

    private let appGroupSuite = "group.com.samjan.netpulse"
    private let dataKey = "netpulse_widget_shared_snapshot_v1"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupSuite) ?? UserDefaults.standard
    }

    private init() {}

    /// Сохранение снимка состояния для виджетов
    public func saveSnapshot(_ data: NetPulseWidgetData) {
        if let encoded = try? JSONEncoder().encode(data) {
            defaults.set(encoded, forKey: dataKey)
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    }

    /// Загрузка последнего сохраненного снимка данных
    public func loadLatestSnapshot() -> NetPulseWidgetData {
        guard let raw = defaults.data(forKey: dataKey),
              let decoded = try? JSONDecoder().decode(NetPulseWidgetData.self, from: raw) else {
            return .placeholder
        }
        return decoded
    }
}
