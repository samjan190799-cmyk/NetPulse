//
//  PingRecord.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Результат единичной проверки доступности хоста.
public struct PingRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let host: String
    public let targetName: String
    public let timestamp: Date
    public let isSuccess: Bool
    public let latencyMs: Double?
    public let errorMessage: String?
    public let protocolType: String

    public init(
        id: UUID = UUID(),
        host: String,
        targetName: String,
        timestamp: Date = Date(),
        isSuccess: Bool,
        latencyMs: Double? = nil,
        errorMessage: String? = nil,
        protocolType: String = "tcp"
    ) {
        self.id = id
        self.host = host
        self.targetName = targetName
        self.timestamp = timestamp
        self.isSuccess = isSuccess
        self.latencyMs = latencyMs
        self.errorMessage = errorMessage
        self.protocolType = protocolType
    }
}
