//
//  HostTarget.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Целевой узел для сетевого мониторинга.
public struct HostTarget: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var address: String
    public var tcpPort: Int
    public var isEnabled: Bool
    public var isGateway: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        address: String,
        tcpPort: Int = 443,
        isEnabled: Bool = true,
        isGateway: Bool = false
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.tcpPort = tcpPort
        self.isEnabled = isEnabled
        self.isGateway = isGateway
    }

    /// Список узлов по умолчанию
    public static var defaultTargets: [HostTarget] {
        [
            HostTarget(name: "Локальный шлюз", address: "gateway", tcpPort: 80, isGateway: true),
            HostTarget(name: "Cloudflare DNS", address: "1.1.1.1", tcpPort: 443),
            HostTarget(name: "Google DNS", address: "8.8.8.8", tcpPort: 53),
            HostTarget(name: "Yandex DNS", address: "77.88.8.8", tcpPort: 53),
            HostTarget(name: "Quad9 DNS", address: "9.9.9.9", tcpPort: 53)
        ]
    }
}
