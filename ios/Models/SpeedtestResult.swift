//
//  SpeedtestResult.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Результаты измерения скорости подключения
public struct SpeedtestResult: Identifiable, Codable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var downloadMbps: Double
    public var uploadMbps: Double
    public var serverName: String
    public var durationSeconds: Double
    public var isSuccess: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        downloadMbps: Double = 0.0,
        uploadMbps: Double = 0.0,
        serverName: String = "Cloudflare CDN Edge",
        durationSeconds: Double = 0.0,
        isSuccess: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.serverName = serverName
        self.durationSeconds = durationSeconds
        self.isSuccess = isSuccess
    }
}
