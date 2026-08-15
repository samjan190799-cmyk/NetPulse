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
        public var isTesting: Bool
        public var connectionType: String
        public var ispName: String

        public init(
            downloadSpeedText: String = "↓ 0 КБ/с",
            uploadSpeedText: String = "↑ 0 КБ/с",
            compactDownloadText: String = "↓0K",
            compactUploadText: String = "↑0K",
            isTesting: Bool = false,
            connectionType: String = "Wi-Fi",
            ispName: String = "Интернет"
        ) {
            self.downloadSpeedText = downloadSpeedText
            self.uploadSpeedText = uploadSpeedText
            self.compactDownloadText = compactDownloadText
            self.compactUploadText = compactUploadText
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
