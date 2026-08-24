//
//  GamingRadarModels.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import Foundation

/// Названия и платформы популярных онлайн-игр
public enum GameTitle: String, CaseIterable, Identifiable, Codable, Sendable {
    case cs2 = "Counter-Strike 2"
    case dota2 = "Dota 2"
    case valorant = "Valorant"
    case apexLegends = "Apex Legends"
    case fortnite = "Fortnite"
    case codWarzone = "Call of Duty: Warzone"
    case eaFC = "EA SPORTS FC (FIFA)"
    case overwatch2 = "Overwatch 2"
    case pubg = "PUBG: BATTLEGROUNDS"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .cs2: return "cross.circle.fill"
        case .dota2: return "shield.fill"
        case .valorant: return "flame.fill"
        case .apexLegends: return "triangle.fill"
        case .fortnite: return "building.2.fill"
        case .codWarzone: return "target"
        case .eaFC: return "soccerball"
        case .overwatch2: return "atom"
        case .pubg: return "car.fill"
        }
    }

    public var publisher: String {
        switch self {
        case .cs2, .dota2: return "Valve Corporation"
        case .valorant: return "Riot Games"
        case .apexLegends, .eaFC: return "Electronic Arts"
        case .fortnite: return "Epic Games"
        case .codWarzone, .overwatch2: return "Activision Blizzard"
        case .pubg: return "Krafton"
        }
    }
}

/// Игровой регион и дата-центр
public struct GameClusterInfo: Identifiable, Codable, Sendable, Hashable {
    public var id: String { "\(game.rawValue)_\(regionName)" }
    public let game: GameTitle
    public let regionName: String
    public let countryCode: String // Флаг: "DE", "SE", "PL", "FI", "AE", "KZ", "US", "SG"
    public let cityName: String
    public let targetHost: String
    public let port: UInt16

    public init(
        game: GameTitle,
        regionName: String,
        countryCode: String,
        cityName: String,
        targetHost: String,
        port: UInt16 = 80
    ) {
        self.game = game
        self.regionName = regionName
        self.countryCode = countryCode
        self.cityName = cityName
        self.targetHost = targetHost
        self.port = port
    }

    public var flagEmoji: String {
        let base: UInt32 = 127397
        var s = ""
        for v in countryCode.uppercased().unicodeScalars {
            s.unicodeScalars.append(UnicodeScalar(base + v.value)!)
        }
        return s
    }

    /// Предустановленная база официальных игровых серверов
    public static let defaultClusters: [GameClusterInfo] = [
        // Counter-Strike 2
        GameClusterInfo(game: .cs2, regionName: "Европа (Франкфурт)", countryCode: "DE", cityName: "Франкфурт", targetHost: "155.133.243.1"),
        GameClusterInfo(game: .cs2, regionName: "Скандинавия (Стокгольм)", countryCode: "SE", cityName: "Стокгольм", targetHost: "155.133.252.1"),
        GameClusterInfo(game: .cs2, regionName: "Восточная Европа (Варшава)", countryCode: "PL", cityName: "Варшава", targetHost: "155.133.238.1"),
        GameClusterInfo(game: .cs2, regionName: "Финляндия (Хельсинки)", countryCode: "FI", cityName: "Хельсинки", targetHost: "155.133.250.1"),
        GameClusterInfo(game: .cs2, regionName: "Ближний Восток (Дубай)", countryCode: "AE", cityName: "Дубай", targetHost: "155.133.245.1"),
        GameClusterInfo(game: .cs2, regionName: "Казахстан (Алматы)", countryCode: "KZ", cityName: "Алматы", targetHost: "155.133.234.1"),

        // Dota 2
        GameClusterInfo(game: .dota2, regionName: "Западная Европа (Люксембург)", countryCode: "LU", cityName: "Люксембург", targetHost: "146.66.152.1"),
        GameClusterInfo(game: .dota2, regionName: "Восточная Европа (Вена)", countryCode: "AT", cityName: "Вена", targetHost: "146.66.155.1"),
        GameClusterInfo(game: .dota2, regionName: "Стокгольм (Россия)", countryCode: "SE", cityName: "Стокгольм", targetHost: "155.133.252.1"),
        GameClusterInfo(game: .dota2, regionName: "Дубай", countryCode: "AE", cityName: "Дубай", targetHost: "155.133.245.1"),

        // Valorant (Riot Direct)
        GameClusterInfo(game: .valorant, regionName: "Франкфурт 1", countryCode: "DE", cityName: "Франкфурт", targetHost: "162.249.72.1"),
        GameClusterInfo(game: .valorant, regionName: "Варшава", countryCode: "PL", cityName: "Варшава", targetHost: "162.249.77.1"),
        GameClusterInfo(game: .valorant, regionName: "Стокгольм", countryCode: "SE", cityName: "Стокгольм", targetHost: "162.249.78.1"),
        GameClusterInfo(game: .valorant, regionName: "Бахрейн", countryCode: "BH", cityName: "Манама", targetHost: "157.175.0.1"),

        // Apex Legends
        GameClusterInfo(game: .apexLegends, regionName: "Франкфурт 1 & 2", countryCode: "DE", cityName: "Франкфурт", targetHost: "52.59.0.1"),
        GameClusterInfo(game: .apexLegends, regionName: "Лондон", countryCode: "GB", cityName: "Лондон", targetHost: "35.176.0.1"),
        GameClusterInfo(game: .apexLegends, regionName: "Амстердам", countryCode: "NL", cityName: "Амстердам", targetHost: "18.156.0.1"),
        GameClusterInfo(game: .apexLegends, regionName: "Бахрейн", countryCode: "BH", cityName: "Бахрейн", targetHost: "157.175.0.1"),

        // Fortnite
        GameClusterInfo(game: .fortnite, regionName: "Европа (AWS Франкфурт)", countryCode: "DE", cityName: "Франкфурт", targetHost: "52.58.0.1"),
        GameClusterInfo(game: .fortnite, regionName: "Европа (AWS Лондон)", countryCode: "GB", cityName: "Лондон", targetHost: "3.8.0.1"),
        GameClusterInfo(game: .fortnite, regionName: "Ближний Восток (AWS Бахрейн)", countryCode: "BH", cityName: "Бахрейн", targetHost: "157.175.0.1"),

        // Call of Duty: Warzone
        GameClusterInfo(game: .codWarzone, regionName: "Европа (Амстердам)", countryCode: "NL", cityName: "Амстердам", targetHost: "185.34.106.1"),
        GameClusterInfo(game: .codWarzone, regionName: "Франкфурт", countryCode: "DE", cityName: "Франкфурт", targetHost: "185.34.107.1"),

        // EA SPORTS FC (FIFA)
        GameClusterInfo(game: .eaFC, regionName: "Европа (Франкфурт)", countryCode: "DE", cityName: "Франкфурт", targetHost: "159.153.64.1"),
        GameClusterInfo(game: .eaFC, regionName: "Варшава", countryCode: "PL", cityName: "Варшава", targetHost: "159.153.72.1"),
        GameClusterInfo(game: .eaFC, regionName: "Дубай", countryCode: "AE", cityName: "Дубай", targetHost: "159.153.76.1")
    ]
}

/// Статус качества пинга для соревновательных игр
public enum GamePingQuality: String, Codable, Sendable {
    case esportsReady = "Киберспорт (A+)"
    case rankedReady = "Отлично для Ranked (A)"
    case playable = "Играбельно (B)"
    case highLatency = "Высокая задержка (C)"
    case critical = "Непригодно для игры (D/F)"

    public var badgeColor: Color {
        switch self {
        case .esportsReady: return .green
        case .rankedReady: return .mint
        case .playable: return .yellow
        case .highLatency: return .orange
        case .critical: return .red
        }
    }
}

/// Результат замера конкретного игрового дата-центра
public struct GameClusterResult: Identifiable, Codable, Sendable {
    public var id: String { cluster.id }
    public let cluster: GameClusterInfo
    public var latencyMs: Double?
    public var jitterMs: Double?
    public var packetLossPct: Double
    public var isReachable: Bool

    public var quality: GamePingQuality {
        guard let lat = latencyMs, isReachable else { return .critical }
        if lat < 25.0 && packetLossPct == 0 { return .esportsReady }
        if lat < 50.0 && packetLossPct < 1.0 { return .rankedReady }
        if lat < 90.0 && packetLossPct < 3.0 { return .playable }
        if lat < 140.0 { return .highLatency }
        return .critical
    }

    public var formattedLatency: String {
        guard let lat = latencyMs, isReachable else { return "Таймаут" }
        return String(format: "%.1f мс", lat)
    }

    public init(
        cluster: GameClusterInfo,
        latencyMs: Double? = nil,
        jitterMs: Double? = nil,
        packetLossPct: Double = 0.0,
        isReachable: Bool = false
    ) {
        self.cluster = cluster
        self.latencyMs = latencyMs
        self.jitterMs = jitterMs
        self.packetLossPct = packetLossPct
        self.isReachable = isReachable
    }
}
