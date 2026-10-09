//
//  SpeedHistoryStore.swift
//  NetPulse
//
//  Постоянная история замеров скорости: хранится на устройстве, живёт между запусками.
//

import Foundation
import Observation

/// Один замер скорости в истории
public struct SpeedHistoryEntry: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var date: Date
    public var downloadMbps: Double
    public var uploadMbps: Double
    public var pingMs: Double?
    public var jitterMs: Double?
    /// Как был подключён телефон: «Wi-Fi», «Сотовая», «Ethernet», «Другое»
    public var connection: String

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        downloadMbps: Double,
        uploadMbps: Double,
        pingMs: Double? = nil,
        jitterMs: Double? = nil,
        connection: String
    ) {
        self.id = id
        self.date = date
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.pingMs = pingMs
        self.jitterMs = jitterMs
        self.connection = connection
    }

    /// Короткое название вида подключения для истории
    public static func label(for type: NetworkConnectionType) -> String {
        switch type {
        case .wifi: return "Wi-Fi"
        case .cellular: return "Сотовая"
        case .ethernet: return "Ethernet"
        case .loopback, .unavailable: return "Другое"
        }
    }
}

/// Итог по набору замеров
public struct SpeedHistorySummary: Sendable, Equatable {
    public let count: Int
    public let averageDownloadMbps: Double
    public let averageUploadMbps: Double
    public let bestDownloadMbps: Double
    public let worstDownloadMbps: Double
    public let averagePingMs: Double?

    /// `nil`, если замеров нет
    public static func make(from entries: [SpeedHistoryEntry]) -> SpeedHistorySummary? {
        guard !entries.isEmpty else { return nil }
        let downloads = entries.map(\.downloadMbps)
        let uploads = entries.map(\.uploadMbps)
        let pings = entries.compactMap(\.pingMs)
        return SpeedHistorySummary(
            count: entries.count,
            averageDownloadMbps: downloads.reduce(0, +) / Double(downloads.count),
            averageUploadMbps: uploads.reduce(0, +) / Double(uploads.count),
            bestDownloadMbps: downloads.max() ?? 0,
            worstDownloadMbps: downloads.min() ?? 0,
            averagePingMs: pings.isEmpty ? nil : pings.reduce(0, +) / Double(pings.count)
        )
    }
}

/// История замеров скорости. Запись идёт у всех пользователей (это дёшево и остаётся на телефоне), а смотреть историю
/// с графиками можно в подписке PRO. Новые замеры сверху.
@MainActor
@Observable
public final class SpeedHistoryStore {
    public static let shared = SpeedHistoryStore()

    /// Сколько замеров помним: старые вытесняются
    public static let maxEntries = 500

    public private(set) var entries: [SpeedHistoryEntry]

    @ObservationIgnored private let fileURL: URL?

    public init(fileURL: URL? = SpeedHistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.history.decode([SpeedHistoryEntry].self, from: data) {
            self.entries = decoded.sorted { $0.date > $1.date }
        } else {
            self.entries = []
        }
    }

    nonisolated public static func defaultFileURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("NetPulse", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("speed_history.json")
    }

    /// Добавляет замер. Пустые и неудачные (нулевая скорость) в историю не попадают.
    public func add(_ entry: SpeedHistoryEntry) {
        guard entry.downloadMbps > 0 else { return }
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        save()
    }

    public func clear() {
        entries = []
        save()
    }

    /// Замеры только по одному виду подключения (`nil` — все)
    public func entries(connection: String?) -> [SpeedHistoryEntry] {
        guard let connection else { return entries }
        return entries.filter { $0.connection == connection }
    }

    private func save() {
        guard let fileURL else { return }
        let snapshot = entries
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder.history.encode(snapshot) else { return }
            try? data.write(to: fileURL, options: [.atomic])
        }
    }
}

private extension JSONEncoder {
    static var history: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var history: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
