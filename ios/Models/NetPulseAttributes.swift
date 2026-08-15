//
//  NetPulseAttributes.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Атрибуты и состояние Live Activity для Dynamic Island и экрана блокировки.
#if canImport(ActivityKit)
public struct NetPulseAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var downloadMbps: Double
        public var uploadMbps: Double
        public var pingMs: Double?
        public var jitterMs: Double?
        public var isTesting: Bool
        public var connectionType: String
        public var ispName: String

        public init(
            downloadMbps: Double = 0.0,
            uploadMbps: Double = 0.0,
            pingMs: Double? = nil,
            jitterMs: Double? = nil,
            isTesting: Bool = false,
            connectionType: String = "Wi-Fi",
            ispName: String = "Интернет"
        ) {
            self.downloadMbps = downloadMbps
            self.uploadMbps = uploadMbps
            self.pingMs = pingMs
            self.jitterMs = jitterMs
            self.isTesting = isTesting
            self.connectionType = connectionType
            self.ispName = ispName
        }
    }

    public var sessionTitle: String

    public init(sessionTitle: String = "NetPulse Monitor") {
        self.sessionTitle = sessionTitle
    }
}
#endif
