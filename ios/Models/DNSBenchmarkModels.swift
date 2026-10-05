//
//  DNSBenchmarkModels.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import Foundation

/// Категория фильтрации и специализации DNS-сервера
public enum DNSFilterCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case all = "Все"
    case standard = "Скорость и надежность"
    case adBlock = "Блокировка рекламы"
    case privacy = "Приватность и No-Log"
    case family = "Семейная безопасность"
    case custom = "Пользовательские"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "globe"
        case .standard: return "bolt.fill"
        case .adBlock: return "shield.lefthalf.filled"
        case .privacy: return "hand.raised.fill"
        case .family: return "person.2.fill"
        case .custom: return "slider.horizontal.3"
        }
    }
}

/// Информация о DNS-провайдере
public struct DNSProviderInfo: Identifiable, Codable, Sendable, Hashable {
    public var id: String { primaryIPv4 }
    public let name: String
    public let provider: String
    public let primaryIPv4: String
    public let secondaryIPv4: String
    public let dohURL: String?
    public let dotHostname: String?
    public let category: DNSFilterCategory
    public let descriptionText: String
    public let supportsDNSSEC: Bool
    public let supportsEDNS: Bool
    public let logoSystemIcon: String

    public init(
        name: String,
        provider: String,
        primaryIPv4: String,
        secondaryIPv4: String,
        dohURL: String? = nil,
        dotHostname: String? = nil,
        category: DNSFilterCategory = .standard,
        descriptionText: String,
        supportsDNSSEC: Bool = true,
        supportsEDNS: Bool = true,
        logoSystemIcon: String = "server.rack"
    ) {
        self.name = name
        self.provider = provider
        self.primaryIPv4 = primaryIPv4
        self.secondaryIPv4 = secondaryIPv4
        self.dohURL = dohURL
        self.dotHostname = dotHostname
        self.category = category
        self.descriptionText = descriptionText
        self.supportsDNSSEC = supportsDNSSEC
        self.supportsEDNS = supportsEDNS
        self.logoSystemIcon = logoSystemIcon
    }

    /// Предустановленный каталог Anycast DNS серверов мирового уровня
    public static let defaultCatalog: [DNSProviderInfo] = [
        DNSProviderInfo(
            name: "Cloudflare (1.1.1.1)",
            provider: "Cloudflare, Inc.",
            primaryIPv4: "1.1.1.1",
            secondaryIPv4: "1.0.0.1",
            dohURL: "https://cloudflare-dns.com/dns-query",
            dotHostname: "one.one.one.one",
            category: .standard,
            descriptionText: "Публичный Anycast DNS Cloudflare: упор на скорость отклика и приватность.",
            supportsDNSSEC: true,
            logoSystemIcon: "bolt.shield.fill"
        ),
        DNSProviderInfo(
            name: "Google Public DNS",
            provider: "Google LLC",
            primaryIPv4: "8.8.8.8",
            secondaryIPv4: "8.8.4.4",
            dohURL: "https://dns.google/dns-query",
            dotHostname: "dns.google",
            category: .standard,
            descriptionText: "Публичный DNS Google на глобальной Anycast-инфраструктуре.",
            supportsDNSSEC: true,
            logoSystemIcon: "globe.americas.fill"
        ),
        DNSProviderInfo(
            name: "Quad9 (Malware Blocking)",
            provider: "Quad9 Foundation (Швейцария)",
            primaryIPv4: "9.9.9.9",
            secondaryIPv4: "149.112.112.112",
            dohURL: "https://dns.quad9.net/dns-query",
            dotHostname: "dns.quad9.net",
            category: .privacy,
            descriptionText: "Швейцарский фонд безопасности. Автоматически блокирует фишинг, ботнеты и вредоносные домены по базам Threat Intelligence.",
            supportsDNSSEC: true,
            logoSystemIcon: "shield.checkerboard"
        ),
        DNSProviderInfo(
            name: "AdGuard DNS (Default)",
            provider: "AdGuard Software",
            primaryIPv4: "94.140.14.14",
            secondaryIPv4: "94.140.15.15",
            dohURL: "https://dns.adguard-dns.com/dns-query",
            dotHostname: "dns.adguard-dns.com",
            category: .adBlock,
            descriptionText: "Блокирует рекламные баннеры, трекеры отслеживания аналитики и счетчики на уровне всей системы iOS.",
            supportsDNSSEC: true,
            logoSystemIcon: "xmark.shield.fill"
        ),
        DNSProviderInfo(
            name: "OpenDNS Home",
            provider: "Cisco Systems",
            primaryIPv4: "208.67.222.222",
            secondaryIPv4: "208.67.220.220",
            dohURL: "https://doh.opendns.com/dns-query",
            dotHostname: "dns.opendns.com",
            category: .standard,
            descriptionText: "Публичный DNS от Cisco с защитой от фишинговых сайтов.",
            supportsDNSSEC: false,
            logoSystemIcon: "network.badge.shield.half.filled"
        ),
        DNSProviderInfo(
            name: "NextDNS",
            provider: "NextDNS Inc.",
            primaryIPv4: "45.90.28.0",
            secondaryIPv4: "45.90.30.0",
            dohURL: "https://dns.nextdns.io/dns-query",
            dotHostname: "dns.nextdns.io",
            category: .privacy,
            descriptionText: "Персональный облачный файрвол с поддержкой современных протоколов DoH/DoT и защиты от криптоджекинга.",
            supportsDNSSEC: true,
            logoSystemIcon: "lock.shield.fill"
        ),
        DNSProviderInfo(
            name: "AdGuard Family",
            provider: "AdGuard Software",
            primaryIPv4: "94.140.14.15",
            secondaryIPv4: "94.140.15.16",
            dohURL: "https://family.adguard-dns.com/dns-query",
            dotHostname: "family.adguard-dns.com",
            category: .family,
            descriptionText: "Блокировка взрослого контента, безопасный поиск SafeSearch и фильтрация рекламы.",
            supportsDNSSEC: true,
            logoSystemIcon: "figure.2.and.child.holdinghands"
        ),
        DNSProviderInfo(
            name: "Яндекс.DNS (Базовый)",
            provider: "Yandex LLC",
            primaryIPv4: "77.88.8.8",
            secondaryIPv4: "77.88.8.1",
            dohURL: "https://common.dot.dns.yandex.net/dns-query",
            dotHostname: "common.dot.dns.yandex.net",
            category: .standard,
            descriptionText: "Публичный DNS Яндекса, серверы расположены в России и странах СНГ.",
            supportsDNSSEC: false,
            logoSystemIcon: "y.circle.fill"
        ),
        DNSProviderInfo(
            name: "Яндекс.DNS (Безопасный)",
            provider: "Yandex LLC",
            primaryIPv4: "77.88.8.88",
            secondaryIPv4: "77.88.8.2",
            dohURL: "https://safe.dot.dns.yandex.net/dns-query",
            dotHostname: "safe.dot.dns.yandex.net",
            category: .privacy,
            descriptionText: "Защита от зараженных сайтов и мошеннических ресурсов по вирусной базе Яндекса.",
            supportsDNSSEC: false,
            logoSystemIcon: "checkmark.shield.fill"
        ),
        DNSProviderInfo(
            name: "Comss.one DNS",
            provider: "Comss.one",
            primaryIPv4: "92.223.65.171",
            secondaryIPv4: "92.38.150.143",
            dohURL: "https://dns.comss.one/dns-query",
            dotHostname: "dns.comss.one",
            category: .privacy,
            descriptionText: "Публичный DNS-сервис Comss.one с фильтрацией вредоносных доменов.",
            supportsDNSSEC: false,
            logoSystemIcon: "arrow.triangle.2.circlepath.circle.fill"
        ),
        DNSProviderInfo(
            name: "Control D (реклама и вредоносные)",
            provider: "Control D",
            primaryIPv4: "76.76.2.2",
            secondaryIPv4: "76.76.10.2",
            dohURL: "https://freedns.controld.com/p2",
            dotHostname: "p2.freedns.controld.com",
            category: .privacy,
            descriptionText: "Высокоскоростной DNS нового поколения с блокировкой трекеров и фишинга.",
            supportsDNSSEC: true,
            logoSystemIcon: "cpu.fill"
        )
    ]

    /// Шлюз сети как возможный DNS-сервер. Адрес определяется системой (`NWPath.gateways`), а не угадывается:
    /// раньше в каталоге стоял «192.168.1.1», которого в большинстве сетей нет.
    public static func gateway(address: String) -> DNSProviderInfo {
        DNSProviderInfo(
            name: "Роутер (шлюз сети)",
            provider: "Локальная сеть",
            primaryIPv4: address,
            secondaryIPv4: "",
            dohURL: nil,
            dotHostname: nil,
            category: .standard,
            descriptionText: "DNS-кэш вашего роутера. Если роутер не отвечает на DNS-запросы, он не используется как резолвер.",
            supportsDNSSEC: false,
            supportsEDNS: false,
            logoSystemIcon: "wifi.router.fill"
        )
    }
}

/// Результат замера конкретного DNS-сервера (по реальным DNS-запросам, а не по TCP-подключению к порту 53)
public struct DNSBenchmarkResult: Identifiable, Codable, Sendable {
    /// Доля успешных ответов, ниже которой сервер считается нестабильным и в рейтинг не попадает
    public static let minimumReliableSuccessPct: Double = 60.0

    public var id: String { provider.id }
    public let provider: DNSProviderInfo
    /// Медиана времени ответа. `nil` — ни одного успешного ответа или замер ещё не выполнялся
    public var latencyMs: Double?
    public var isReachable: Bool
    /// Замер уже выполнялся (до этого строка — заготовка со статусом «ожидание»)
    public var isTested: Bool
    public var successRatePct: Double
    public var rank: Int?
    /// Сколько запросов получили корректный ответ
    public var queriesSucceeded: Int
    /// Сколько запросов отправлено
    public var queriesTotal: Int
    public var jitterMs: Double?

    /// Отвечает, но теряет слишком много запросов
    public var isUnstable: Bool {
        isTested && isReachable && successRatePct < Self.minimumReliableSuccessPct
    }

    public var formattedLatency: String {
        guard isTested else { return "—" }
        guard let latencyMs = latencyMs, isReachable else {
            return "Нет ответа"
        }
        return String(format: "%.1f мс", latencyMs)
    }

    public var statusBadgeColor: Color {
        guard isTested else { return .gray }
        guard let lat = latencyMs, isReachable else { return .red }
        if isUnstable { return .orange }
        if lat < 25.0 { return .green }
        if lat < 60.0 { return .blue }
        if lat < 120.0 { return .yellow }
        return .orange
    }

    public init(
        provider: DNSProviderInfo,
        latencyMs: Double? = nil,
        isReachable: Bool = false,
        isTested: Bool = false,
        successRatePct: Double = 0.0,
        rank: Int? = nil,
        queriesSucceeded: Int = 0,
        queriesTotal: Int = 0,
        jitterMs: Double? = nil
    ) {
        self.provider = provider
        self.latencyMs = latencyMs
        self.isReachable = isReachable
        self.isTested = isTested
        self.successRatePct = successRatePct
        self.rank = rank
        self.queriesSucceeded = queriesSucceeded
        self.queriesTotal = queriesTotal
        self.jitterMs = jitterMs
    }
}
