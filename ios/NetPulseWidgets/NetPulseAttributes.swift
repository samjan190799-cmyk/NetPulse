//
//  NetPulseAttributes.swift
//  NetPulseWidgets
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Атрибуты и состояние Live Activity для Dynamic Island с реальной скоростью загрузки и отдачи.
#if canImport(ActivityKit)
public struct NetPulseAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var downloadSpeedText: String
        public var uploadSpeedText: String
        public var compactDownloadText: String
        public var compactUploadText: String
        public var pingMs: Double?
        public var jitterMs: Double?
        public var isTesting: Bool
        public var connectionType: String
        public var ispName: String
        public var isGamingMode: Bool
        public var gameTitle: String?
        public var gameRegion: String?
        public var packetLossPct: Double?

        public init(
            downloadSpeedText: String = "100 Мбит/с",
            uploadSpeedText: String = "45 мс",
            compactDownloadText: String = "100M",
            compactUploadText: String = "45ms",
            pingMs: Double? = nil,
            jitterMs: Double? = nil,
            isTesting: Bool = false,
            connectionType: String = "5G / LTE",
            ispName: String = "Мобильный интернет",
            isGamingMode: Bool = false,
            gameTitle: String? = nil,
            gameRegion: String? = nil,
            packetLossPct: Double? = nil
        ) {
            self.downloadSpeedText = downloadSpeedText
            self.uploadSpeedText = uploadSpeedText
            self.compactDownloadText = compactDownloadText
            self.compactUploadText = compactUploadText
            self.pingMs = pingMs
            self.jitterMs = jitterMs
            self.isTesting = isTesting
            self.connectionType = connectionType
            self.ispName = ispName
            self.isGamingMode = isGamingMode
            self.gameTitle = gameTitle
            self.gameRegion = gameRegion
            self.packetLossPct = packetLossPct
        }
    }

    public var sessionTitle: String

    public init(sessionTitle: String = "NetPulse Monitor") {
        self.sessionTitle = sessionTitle
    }
}
#endif

