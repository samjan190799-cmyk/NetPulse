//
//  StabilityHistoryStore.swift
//  NetPulse
//
//  Прошлые тесты стабильности: хранятся на устройстве и живут между запусками.
//

import Foundation
import Observation

@MainActor
@Observable
public final class StabilityHistoryStore {
    public static let shared = StabilityHistoryStore()

    /// Сколько тестов помним: старые вытесняются
    public static let maxEntries = 20

    /// Новые тесты сверху
    public private(set) var results: [StabilityResult]

    @ObservationIgnored private let fileURL: URL?

    public init(fileURL: URL? = StabilityHistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.stability.decode([StabilityResult].self, from: data) {
            self.results = decoded.sorted { $0.startedAt > $1.startedAt }
        } else {
            self.results = []
        }
    }

    nonisolated public static func defaultFileURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("NetPulse", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("stability_history.json")
    }

    public func add(_ result: StabilityResult) {
        results.removeAll { $0.id == result.id }
        results.insert(result, at: 0)
        if results.count > Self.maxEntries {
            results.removeLast(results.count - Self.maxEntries)
        }
        save()
    }

    public func remove(id: UUID) {
        results.removeAll { $0.id == id }
        save()
    }

    public func clear() {
        results = []
        save()
    }

    private func save() {
        guard let fileURL else { return }
        let snapshot = results
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder.stability.encode(snapshot) else { return }
            try? data.write(to: fileURL, options: [.atomic])
        }
    }
}

private extension JSONEncoder {
    static var stability: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var stability: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
