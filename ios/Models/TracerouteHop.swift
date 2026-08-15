//
//  TracerouteHop.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Информация об отдельном узле маршрута
public struct TracerouteHop: Identifiable, Codable, Sendable {
    public var id: Int { hopNumber }
    public let hopNumber: Int
    public let ipAddress: String?
    public let hostname: String?
    public let latencyMs: Double?
    public let lossPercent: Double

    public init(
        hopNumber: Int,
        ipAddress: String?,
        hostname: String? = nil,
        latencyMs: Double?,
        lossPercent: Double = 0.0
    ) {
        self.hopNumber = hopNumber
        self.ipAddress = ipAddress
        self.hostname = hostname
        self.latencyMs = latencyMs
        self.lossPercent = lossPercent
    }
}
