//
//  NetworkInterfaceInfo.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Тип активного сетевого подключения
public enum NetworkConnectionType: String, Codable, Sendable {
    case wifi = "Wi-Fi"
    case cellular = "Cellular (5G/LTE)"
    case ethernet = "Ethernet"
    case loopback = "Loopback"
    case unavailable = "Нет соединения"
}

/// Информация о локальной сетевой конфигурации и провайдере
public struct NetworkInterfaceInfo: Codable, Sendable {
    public var localIP: String
    public var gatewayIP: String?
    public var connectionType: NetworkConnectionType
    public var dnsServers: [String]
    public var publicIP: String?
    public var ispName: String?
    public var country: String?
    public var city: String?
    public var isExpensive: Bool
    public var isConstrained: Bool

    public init(
        localIP: String = "127.0.0.1",
        gatewayIP: String? = nil,
        connectionType: NetworkConnectionType = .unavailable,
        dnsServers: [String] = [],
        publicIP: String? = nil,
        ispName: String? = nil,
        country: String? = nil,
        city: String? = nil,
        isExpensive: Bool = false,
        isConstrained: Bool = false
    ) {
        self.localIP = localIP
        self.gatewayIP = gatewayIP
        self.connectionType = connectionType
        self.dnsServers = dnsServers
        self.publicIP = publicIP
        self.ispName = ispName
        self.country = country
        self.city = city
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }
}
