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

    public var systemIcon: String { icon }
}

/// Открытый сетевой порт устройства
public struct LANOpenPort: Identifiable, Codable, Sendable, Hashable {
    public var id: UInt16 { portNumber }
    public let portNumber: UInt16
    public var port: UInt16 { portNumber }
    public let serviceName: String
    public let serviceDescription: String
    public let isCriticalSecurityRisk: Bool

    public init(
        portNumber: UInt16,
        serviceName: String,
        serviceDescription: String = "",
        isCriticalSecurityRisk: Bool = false
    ) {
        self.portNumber = portNumber
        self.serviceName = serviceName
        self.serviceDescription = serviceDescription.isEmpty ? serviceName : serviceDescription
        self.isCriticalSecurityRisk = isCriticalSecurityRisk
    }
}

/// Устройство локальной сети
public struct LANDevice: Identifiable, Codable, Sendable {
    public var id: String { ipAddress }
    public let ipAddress: String
    public var macAddress: String?
    public var hostname: String?
    /// Производитель — только при однозначном признаке (например, служба синхронизации Apple на порту 62078)
    public var vendorName: String?
    /// Предположение о назначении устройства по открытым портам (не факт)
    public var serviceHint: String?
    public var deviceType: LANDeviceType
    /// Задержка до устройства, мс. 0 — не измерялась (адрес известен системе, но устройство не отвечало на проверку)
    public var latencyMs: Double
    public var responseTimeMs: Double? { latencyMs > 0 ? latencyMs : nil }
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
            return "Это устройство"
        }
        return "Узел \(ipAddress)"
    }

    public init(
        ipAddress: String,
        macAddress: String? = nil,
        hostname: String? = nil,
        vendorName: String? = nil,
        serviceHint: String? = nil,
        deviceType: LANDeviceType = .unknown,
        latencyMs: Double = 0.0,
        openPorts: [LANOpenPort] = [],
        isGateway: Bool = false,
        isCurrentDevice: Bool = false,
        firstSeen: Date = Date()
    ) {
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.hostname = hostname
        self.vendorName = vendorName
        self.serviceHint = serviceHint
        self.deviceType = deviceType
        self.latencyMs = latencyMs
        self.openPorts = openPorts
        self.isGateway = isGateway
        self.isCurrentDevice = isCurrentDevice
        self.firstSeen = firstSeen
    }
}

/// Диапазон адресов, который сканируется. Определяется по маске интерфейса, а не по догадке «/24».
public struct LANSubnet: Sendable, Equatable {
    /// Адрес сети (хостовый порядок байт)
    public let networkAddress: UInt32
    /// Длина префикса реальной сети (по маске интерфейса)
    public let prefixLength: Int
    /// Адреса, которые будут проверены (без адреса сети и широковещательного, без адреса самого устройства)
    public let hostAddresses: [UInt32]
    /// Реальная сеть шире /24: проверяется только блок /24, в котором находится это устройство
    public let isTruncated: Bool

    public var cidrDescription: String {
        "\(LANSubnet.string(from: networkAddress))/\(prefixLength)"
    }

    public static func string(from address: UInt32) -> String {
        "\((address >> 24) & 0xFF).\((address >> 16) & 0xFF).\((address >> 8) & 0xFF).\(address & 0xFF)"
    }

    public static func address(from string: String) -> UInt32? {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part) else { return nil }
            result = (result << 8) | UInt32(octet)
        }
        return result
    }

    /// Частные адреса RFC 1918 — только их имеет смысл сканировать как локальную сеть
    public static func isPrivate(_ address: UInt32) -> Bool {
        let first = (address >> 24) & 0xFF
        let second = (address >> 16) & 0xFF
        return first == 10 || (first == 172 && (16...31).contains(second)) || (first == 192 && second == 168)
    }
}

/// Итог сканирования локальной сети
public struct LANScanReport: Sendable {
    public let devices: [LANDevice]
    public let subnet: LANSubnet
    /// Сколько адресов проверено
    public let scannedHostCount: Int
}

/// Причины, по которым сканирование не выполнено
public enum LANScanError: Error, LocalizedError, Sendable, Equatable {
    /// Нет Wi-Fi/Ethernet-подключения или адрес устройства не из частного диапазона (например, мобильная сеть)
    case notOnLocalNetwork
    /// В настройках iOS запрещён доступ приложения к локальной сети
    case localNetworkAccessDenied
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notOnLocalNetwork:
            return "Сканирование доступно только в домашней или офисной сети (Wi-Fi/Ethernet). В мобильной сети сканер не запускается: он проверял бы чужую сеть оператора."
        case .localNetworkAccessDenied:
            return "Нет доступа к локальной сети. Разрешите его для NetPulse в Настройках iOS: Конфиденциальность → Локальная сеть."
        case .cancelled:
            return "Сканирование остановлено."
        }
    }
}
