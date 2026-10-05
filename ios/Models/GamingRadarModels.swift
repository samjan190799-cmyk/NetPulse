//
//  GamingRadarModels.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import Foundation

/// Ориентиры задержки для жанра игры, мс. Это рекомендации, а не жёсткие требования конкретной игры.
public struct GameLatencyProfile: Sendable, Equatable {
    public let excellentMs: Double
    public let goodMs: Double
    public let playableMs: Double
    public let highMs: Double

    /// Динамичные шутеры (CS2, Valorant, Apex, Overwatch, Warzone)
    public static let fastShooter = GameLatencyProfile(excellentMs: 30, goodMs: 55, playableMs: 90, highMs: 140)
    /// MOBA (Dota 2)
    public static let moba = GameLatencyProfile(excellentMs: 40, goodMs: 70, playableMs: 110, highMs: 160)
    /// Королевские битвы (Fortnite, PUBG)
    public static let battleRoyale = GameLatencyProfile(excellentMs: 40, goodMs: 70, playableMs: 110, highMs: 160)
    /// Спортивные симуляторы (EA SPORTS FC)
    public static let sports = GameLatencyProfile(excellentMs: 40, goodMs: 80, playableMs: 120, highMs: 170)
}

/// Названия и платформы популярных онлайн-игр. Игра определяет только пороги оценки задержки
/// (жанровый профиль); замер одинаков для всех игр.
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

    public var latencyProfile: GameLatencyProfile {
        switch self {
        case .cs2, .valorant, .apexLegends, .overwatch2, .codWarzone: return .fastShooter
        case .dota2: return .moba
        case .fortnite, .pubg: return .battleRoyale
        case .eaFC: return .sports
        }
    }

    /// Жанр, по которому подобраны ориентиры
    public var genreTitle: String {
        switch self {
        case .cs2, .valorant, .apexLegends, .overwatch2, .codWarzone: return "динамичный шутер"
        case .dota2: return "MOBA"
        case .fortnite, .pubg: return "королевская битва"
        case .eaFC: return "спортивный симулятор"
        }
    }
}

/// Региональный узел для замера задержки.
///
/// Это публичные эндпоинты облачных регионов AWS (`dynamodb.<регион>.amazonaws.com`, порт 443), а не серверы
/// конкретных игр: адреса игровых серверов не публикуются. Раньше здесь стояли «первые адреса сетей» (`x.x.x.1`)
/// с выдуманными подписями; они не соответствовали реальным серверам.
public struct GameClusterInfo: Identifiable, Codable, Sendable, Hashable {
    public var id: String { regionID }
    public let regionID: String
    public let regionName: String
    public let countryCode: String
    public let cityName: String
    public let targetHost: String
    public let port: UInt16

    public init(
        regionID: String,
        regionName: String,
        countryCode: String,
        cityName: String,
        port: UInt16 = 443
    ) {
        self.regionID = regionID
        self.regionName = regionName
        self.countryCode = countryCode
        self.cityName = cityName
        self.targetHost = "dynamodb.\(regionID).amazonaws.com"
        self.port = port
    }

    public var flagEmoji: String {
        let base: UInt32 = 127397
        var s = ""
        for v in countryCode.uppercased().unicodeScalars {
            if let scalar = UnicodeScalar(base + v.value) {
                s.unicodeScalars.append(scalar)
            }
        }
        return s
    }

    /// Регионы AWS, в которых размещаются серверы многих онлайн-игр и сервисов
    public static let referenceRegions: [GameClusterInfo] = [
        // Европа
        GameClusterInfo(regionID: "eu-central-1", regionName: "Европа: Франкфурт", countryCode: "DE", cityName: "Франкфурт"),
        GameClusterInfo(regionID: "eu-west-2", regionName: "Европа: Лондон", countryCode: "GB", cityName: "Лондон"),
        GameClusterInfo(regionID: "eu-west-1", regionName: "Европа: Ирландия", countryCode: "IE", cityName: "Дублин"),
        GameClusterInfo(regionID: "eu-west-3", regionName: "Европа: Париж", countryCode: "FR", cityName: "Париж"),
        GameClusterInfo(regionID: "eu-north-1", regionName: "Европа: Стокгольм", countryCode: "SE", cityName: "Стокгольм"),
        GameClusterInfo(regionID: "eu-south-1", regionName: "Европа: Милан", countryCode: "IT", cityName: "Милан"),
        GameClusterInfo(regionID: "eu-south-2", regionName: "Европа: Испания", countryCode: "ES", cityName: "Сарагоса"),
        GameClusterInfo(regionID: "eu-central-2", regionName: "Европа: Цюрих", countryCode: "CH", cityName: "Цюрих"),
        // Ближний Восток и Азия
        GameClusterInfo(regionID: "me-south-1", regionName: "Ближний Восток: Бахрейн", countryCode: "BH", cityName: "Манама"),
        GameClusterInfo(regionID: "me-central-1", regionName: "Ближний Восток: ОАЭ", countryCode: "AE", cityName: "Дубай"),
        GameClusterInfo(regionID: "ap-south-1", regionName: "Азия: Мумбаи", countryCode: "IN", cityName: "Мумбаи"),
        GameClusterInfo(regionID: "ap-southeast-1", regionName: "Азия: Сингапур", countryCode: "SG", cityName: "Сингапур"),
        GameClusterInfo(regionID: "ap-northeast-1", regionName: "Азия: Токио", countryCode: "JP", cityName: "Токио"),
        // Америка
        GameClusterInfo(regionID: "us-east-1", regionName: "США: Вирджиния", countryCode: "US", cityName: "Ашберн"),
        GameClusterInfo(regionID: "us-west-2", regionName: "США: Орегон", countryCode: "US", cityName: "Портленд"),
        GameClusterInfo(regionID: "sa-east-1", regionName: "Южная Америка: Сан-Паулу", countryCode: "BR", cityName: "Сан-Паулу")
    ]
}

/// Оценка задержки для игры
public enum GamePingQuality: String, Codable, Sendable {
    case esportsReady = "Отлично"
    case rankedReady = "Хорошо"
    case playable = "Приемлемо"
    case highLatency = "Высокая задержка"
    case critical = "Плохо или нет ответа"

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

/// Результат замера регионального узла
public struct GameClusterResult: Identifiable, Codable, Sendable {
    public var id: String { cluster.id }
    public let cluster: GameClusterInfo
    /// Медиана времени установления TCP-соединения. `nil` — ни одного ответа или замер ещё не выполнялся
    public var latencyMs: Double?
    public var jitterMs: Double?
    public var packetLossPct: Double
    public var isReachable: Bool
    /// Замер выполнялся (до этого строка — заготовка со статусом «ожидание»)
    public var isTested: Bool

    /// Оценка по ориентирам жанра выбранной игры
    public func quality(for game: GameTitle) -> GamePingQuality {
        guard isTested else { return .critical }
        guard let lat = latencyMs, isReachable else { return .critical }
        let profile = game.latencyProfile
        if lat < profile.excellentMs && packetLossPct == 0 { return .esportsReady }
        if lat < profile.goodMs && packetLossPct <= 20 { return .rankedReady }
        if lat < profile.playableMs && packetLossPct < 40 { return .playable }
        if lat < profile.highMs { return .highLatency }
        return .critical
    }

    public func badgeColor(for game: GameTitle) -> Color {
        isTested ? quality(for: game).badgeColor : .gray
    }

    public var formattedLatency: String {
        guard isTested else { return "—" }
        guard let lat = latencyMs, isReachable else { return "Нет ответа" }
        return String(format: "%.1f мс", lat)
    }

    public init(
        cluster: GameClusterInfo,
        latencyMs: Double? = nil,
        jitterMs: Double? = nil,
        packetLossPct: Double = 0.0,
        isReachable: Bool = false,
        isTested: Bool = false
    ) {
        self.cluster = cluster
        self.latencyMs = latencyMs
        self.jitterMs = jitterMs
        self.packetLossPct = packetLossPct
        self.isReachable = isReachable
        self.isTested = isTested
    }
}
