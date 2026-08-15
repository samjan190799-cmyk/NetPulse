//
//  NetworkAlert.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

public enum AlertSeverity: String, Codable, Sendable {
    case info = "info"
    case warning = "warning"
    case critical = "critical"
}

/// Оповещение о сетевой аномалии
public struct NetworkAlert: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let host: String
    public let targetName: String
    public let severity: AlertSeverity
    public let message: String
    public let metricName: String
    public let currentValue: Double
    public let thresholdValue: Double

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        host: String,
        targetName: String,
        severity: AlertSeverity,
        message: String,
        metricName: String,
        currentValue: Double,
        thresholdValue: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.host = host
        self.targetName = targetName
        self.severity = severity
        self.message = message
        self.metricName = metricName
        self.currentValue = currentValue
        self.thresholdValue = thresholdValue
    }
}
