//
//  RouteStorage.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Хранилище записанных маршрутов.
///
/// Маршруты лежат только в файлах на этом устройстве (по файлу на маршрут) и никуда не отправляются.
/// Каталог исключён из резервных копий iCloud и iTunes. Идущая запись дважды в минуту сохраняется в отдельный
/// файл: если систему закроет приложение посреди пути, при следующем запуске запись восстанавливается как
/// прерванный маршрут, а не пропадает.
public actor RouteStorage {
    /// Сколько маршрутов хранить; более старые удаляются при сохранении нового
    public static let maxRoutes = 30
    /// Предел числа точек во всех маршрутах вместе
    public static let maxTotalPoints = 120_000

    private static let routePrefix = "route-"
    private static let activeFileName = "active-route.json"

    public static let shared = RouteStorage(directory: RouteStorage.defaultDirectory())

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Каталог по умолчанию: Application Support/NetPulse/Routes
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("NetPulse", isDirectory: true)
            .appendingPathComponent("Routes", isDirectory: true)
    }

    // MARK: - Маршруты

    /// Все сохранённые маршруты, новые первыми. Повреждённые файлы пропускаются.
    public func loadAll() -> [RouteRecord] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = Self.makeDecoder()
        var routes: [RouteRecord] = []
        for url in urls where url.lastPathComponent.hasPrefix(Self.routePrefix) && url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(RouteRecord.self, from: data) else { continue }
            routes.append(record)
        }
        routes.sort { $0.startedAt > $1.startedAt }
        return routes
    }

    /// Сохраняет готовый маршрут и удаляет лишние старые
    public func save(_ record: RouteRecord) throws {
        try write(record, to: routeURL(for: record.id))
        trim()
    }

    public func delete(id: UUID) {
        try? FileManager.default.removeItem(at: routeURL(for: id))
    }

    /// Удаляет все маршруты и недописанную запись
    public func deleteAll() {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for url in urls where url.lastPathComponent.hasPrefix(Self.routePrefix) || url.lastPathComponent == Self.activeFileName {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Идущая запись

    public func saveActive(_ record: RouteRecord) throws {
        try write(record, to: activeURL)
    }

    public func loadActive() -> RouteRecord? {
        guard let data = try? Data(contentsOf: activeURL) else { return nil }
        return try? Self.makeDecoder().decode(RouteRecord.self, from: data)
    }

    public func clearActive() {
        try? FileManager.default.removeItem(at: activeURL)
    }

    // MARK: - Внутреннее

    private var activeURL: URL {
        directory.appendingPathComponent(Self.activeFileName)
    }

    private func routeURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(Self.routePrefix)\(id.uuidString).json")
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    private func ensureDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Геопозиция не должна попадать в резервные копии
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private func write(_ record: RouteRecord, to url: URL) throws {
        try ensureDirectory()
        let data = try Self.makeEncoder().encode(record)
        // Запись должна работать и при заблокированном телефоне: маршрут пишется, пока экран погашен
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Оставляет не больше `maxRoutes` маршрутов и `maxTotalPoints` точек; удаляются самые старые
    private func trim() {
        var routes = loadAll()
        while routes.count > Self.maxRoutes, let oldest = routes.popLast() {
            delete(id: oldest.id)
        }
        var total = routes.reduce(0) { $0 + $1.points.count }
        while total > Self.maxTotalPoints, routes.count > 1, let oldest = routes.popLast() {
            total -= oldest.points.count
            delete(id: oldest.id)
        }
    }
}
