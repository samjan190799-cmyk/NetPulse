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
    case cellular = "Мобильная сеть (5G/LTE)"
    case ethernet = "Ethernet"
    case loopback = "Loopback"
    case unavailable = "Нет подключения"
}

/// Информация о локальной сетевой конфигурации и провайдере.
/// Значение, которое определить не удалось, — `nil` (для `localIP` — «—»), а не правдоподобная выдумка.
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

    /// Подпись сети: провайдер, а если он неизвестен — тип подключения
    public var displayTitle: String {
        switch connectionType {
        case .wifi:
            return ispName ?? "Wi-Fi Сеть"
        case .cellular:
            return ispName ?? "Мобильный интернет (5G/LTE)"
        case .ethernet:
            return ispName ?? "Ethernet Сеть"
        case .loopback:
            return "Локальная петля"
        case .unavailable:
            return "Нет подключения"
        }
    }

    public init(
        localIP: String = "—",
        gatewayIP: String? = nil,
        connectionType: NetworkConnectionType = .cellular,
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
