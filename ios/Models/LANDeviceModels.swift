//
//  LANDeviceModels.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import Foundation

/// Тип обнаруженного устройства в локальной сети
public enum LANDeviceType: String, CaseIterable, Codable, Sendable {
    case router = "Маршрутизатор / Шлюз"
    case smartphone = "Смартфон / Планшет"
    case computer = "Компьютер / Ноутбук"
    case console = "Игровая консоль"
    case smartTV = "Smart TV / Приставка"
    case iot = "Умный дом (IoT)"
    case printer = "Сетевой принтер"
    case unknown = "Сетевое устройство"

    public var icon: String {
        switch self {
        case .router: return "wifi.router.fill"
        case .smartphone: return "iphone.gen3"
        case .computer: return "laptopcomputer"
        case .console: return "gamecontroller.fill"
        case .smartTV: return "tv.fill"
        case .iot: return "homekit"
        case .printer: return "printer.fill"
        case .unknown: return "server.rack"
        }
    }
}

/// Открытый сетевой порт устройства
public struct LANOpenPort: Identifiable, Codable, Sendable, Hashable {
    public var id: UInt16 { portNumber }
    public let portNumber: UInt16
    public let serviceName: String
    public let isCriticalSecurityRisk: Bool

    public init(portNumber: UInt16, serviceName: String, isCriticalSecurityRisk: Bool = false) {
        self.portNumber = portNumber
        self.serviceName = serviceName
        self.isCriticalSecurityRisk = isCriticalSecurityRisk
    }
}

/// Устройство локальной сети
public struct LANDevice: Identifiable, Codable, Sendable {
    public var id: String { ipAddress }
    public let ipAddress: String
    public var macAddress: String?
    public var hostname: String?
    public var vendorName: String?
    public var deviceType: LANDeviceType
    public var latencyMs: Double
    public var openPorts: [LANOpenPort]
    public var isGateway: Bool
    public var isCurrentDevice: Bool
    public var firstSeen: Date

    public var displayName: String {
        if let host = hostname, !host.isEmpty {
            return host
        }
        if isGateway {
            return "Основной шлюз (Роутер)"
        }
        if isCurrentDevice {
            return "Этот iPhone"
        }
        if let vendor = vendorName, !vendor.isEmpty {
            return "\(vendor) (\(deviceType.rawValue))"
        }
        return "Устройство (\(ipAddress))"
    }

    public init(
        ipAddress: String,
        macAddress: String? = nil,
        hostname: String? = nil,
        vendorName: String? = nil,
        deviceType: LANDeviceType = .unknown,
        latencyMs: Double = 1.0,
        openPorts: [LANOpenPort] = [],
        isGateway: Bool = false,
        isCurrentDevice: Bool = false,
        firstSeen: Date = Date()
    ) {
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.hostname = hostname
        self.vendorName = vendorName
        self.deviceType = deviceType
        self.latencyMs = latencyMs
        self.openPorts = openPorts
        self.isGateway = isGateway
        self.isCurrentDevice = isCurrentDevice
        self.firstSeen = firstSeen
    }
}
