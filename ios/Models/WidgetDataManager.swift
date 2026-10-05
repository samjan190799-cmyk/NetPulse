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
    /// Лимит трафика в байтах; 0 — лимит не задан
    public let budgetTotalBytes: Int64
    /// Расход за период квоты (nil — как «трафик сегодня», для снимков старого формата)
    public let budgetUsedBytes: Int64?
    /// Индекс здоровья сети 0...100; nil — свежих данных нет
    public let healthScore: Int?
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
        budgetTotalBytes: Int64 = 0,
        budgetUsedBytes: Int64? = nil,
        healthScore: Int? = nil,
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
        self.budgetUsedBytes = budgetUsedBytes
        self.healthScore = healthScore
        self.dnsHosts = dnsHosts
        self.lastUpdated = lastUpdated
    }

    /// Пустой снимок: приложение ещё ни разу не сохраняло данные (никаких демонстрационных значений)
    public static var empty: NetPulseWidgetData {
        NetPulseWidgetData(
            ispName: "Откройте NetPulse",
            connectionType: "Нет данных",
            lastUpdated: Date.distantPast
        )
    }

    /// Демонстрационный снимок — только для предпросмотра в галерее виджетов, но не для показа как реальных данных
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

    /// Доля использования лимита трафика за его период (0.0 ... 1.0)
    public var budgetProgress: Double {
        guard budgetTotalBytes > 0 else { return 0.0 }
        let used = budgetUsedBytes ?? todayTrafficBytes
        return min(max(Double(used) / Double(budgetTotalBytes), 0.0), 1.0)
    }

    /// Данные устарели: в фоне приложение опрос не ведёт, и «замороженный» пинг нельзя выдавать за текущий
    public var isStale: Bool {
        Date().timeIntervalSince(lastUpdated) > 600
    }

    /// Задержка: только число (или «—»)
    public var pingValueText: String {
        if !isStale, let ping = pingMs {
            return String(format: "%.0f", ping)
        }
        return "—"
    }

    /// Джиттер: только число (или «—»)
    public var jitterValueText: String {
        if !isStale, let jitter = jitterMs {
            return String(format: "%.1f", jitter)
        }
        return "—"
    }

    /// Форматированная задержка
    public var formattedPing: String {
        let value = pingValueText
        return value == "—" ? value : value + " мс"
    }

    /// Форматированный джиттер
    public var formattedJitter: String {
        let value = jitterValueText
        return value == "—" ? value : value + " мс"
    }

    /// Скорость в Мбит/с; 0 означает «замера не было»
    public static func speedText(_ mbps: Double, decimals: Int = 1) -> String {
        mbps > 0 ? String(format: "%.\(decimals)f", mbps) : "—"
    }
}

/// Менеджер обмена данными между приложением и расширением виджетов через App Group
public final class WidgetDataManager: @unchecked Sendable {
    public static let shared = WidgetDataManager()

    /// Единственная группа приложения — по идентификатору пакета (com.samvel.netpulse). Вторая группа
    /// (group.com.samjan.netpulse) была остатком прежнего названия и требовала регистрации в аккаунте разработчика.
    private let appGroupSuite = "group.com.samvel.netpulse"
    private let dataKey = "netpulse_widget_shared_snapshot_v1"
    private let lock = NSLock()

    private var sharedContainerFileURLs: [URL] {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupSuite) else {
            return []
        }
        return [container.appendingPathComponent("netpulse_widget_snapshot.json")]
    }

    private var defaultsList: [UserDefaults] {
        var list: [UserDefaults] = []
        if let shared = UserDefaults(suiteName: appGroupSuite) {
            list.append(shared)
        }
        list.append(UserDefaults.standard)
        return list
    }

    private init() {}

    /// Сохранение снимка состояния для виджетов (файл группы приложения + UserDefaults).
    /// `reloadTimelines: false` — только обновить данные, не заставляя систему перерисовывать виджеты
    /// (раньше перезагрузка шла при каждой записи, то есть каждые несколько секунд).
    public func saveSnapshot(_ data: NetPulseWidgetData, reloadTimelines: Bool = true) {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        lock.lock()
        defer { lock.unlock() }

        // 1. Атомарная запись в общий файл App Group (наиболее надежный IPC-канал на физических устройствах)
        for fileURL in sharedContainerFileURLs {
            try? encoded.write(to: fileURL, options: .atomic)
        }

        // 2. Запись в UserDefaults (общая группа и стандартные)
        for defaults in defaultsList {
            defaults.set(encoded, forKey: dataKey)
        }

        #if canImport(WidgetKit)
        if reloadTimelines {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }

    /// Загрузка последнего сохраненного снимка данных с каскадным поиском (файл контейнера -> UserDefaults -> пустой снимок)
    public func loadLatestSnapshot() -> NetPulseWidgetData {
        lock.lock()
        defer { lock.unlock() }

        // 1. Приоритетное чтение из файла общего контейнера App Group
        for fileURL in sharedContainerFileURLs {
            if let data = try? Data(contentsOf: fileURL),
               let decoded = try? JSONDecoder().decode(NetPulseWidgetData.self, from: data) {
                return decoded
            }
        }

        // 2. Чтение из UserDefaults (общая группа -> стандартные)
        for defaults in defaultsList {
            if let raw = defaults.data(forKey: dataKey),
               let decoded = try? JSONDecoder().decode(NetPulseWidgetData.self, from: raw) {
                return decoded
            }
        }
        // Данных ещё нет — пустой снимок, а не демонстрационные «285 Мбит/с, здоровье 98»
        return .empty
    }
}

