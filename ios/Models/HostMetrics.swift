//
//  HostMetrics.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Статус доступности узла
public enum HostStatus: String, Codable, Sendable, Equatable {
    case ok = "OK"
    case warning = "WARN"
    case critical = "CRIT"
    case down = "DOWN"
    case unknown = "INIT"
}

/// Агрегированные метрики качества соединения для целевого узла.
public struct HostMetrics: Identifiable, Codable, Sendable {
    public var id: String { address }
    public let name: String
    public var address: String
    public let isGateway: Bool

    public var sentCount: Int = 0
    public var receivedCount: Int = 0
    public var lostCount: Int = 0

    public var lastLatencyMs: Double?
    public var minLatencyMs: Double?
    public var maxLatencyMs: Double?
    public var avgLatencyMs: Double?
    public var p95LatencyMs: Double?
    public var p99LatencyMs: Double?

    /// Джиттер по RFC 3550
    public var jitterMs: Double = 0.0

    /// Процент потерь пакетов
    public var lossRatePct: Double = 0.0
    public var lossWindowPct: Double = 0.0

    public var status: HostStatus = .unknown
    public var lastUpdated: Date?
    public var latencyHistory: [Double?] = []

    public init(
        name: String,
        address: String,
        isGateway: Bool = false
    ) {
        self.name = name
        self.address = address
        self.isGateway = isGateway
    }
}
