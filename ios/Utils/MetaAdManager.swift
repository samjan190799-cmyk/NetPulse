//
//  MetaAdManager.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / Meta Audience Network 2026).
//

import SwiftUI
import Combine

/// Конфигурация рекламных блоков Meta Audience Network (Meta Ads 2026)
public struct MetaAdConfig: Sendable {
    public static let appID = "987654321098765"
    public static let bannerPlacementID = "987654321098765_1234567890"
    public static let nativePlacementID = "987654321098765_2345678901"
    public static let interstitialPlacementID = "987654321098765_3456789012"
}

/// Модель рекламного объявления Meta Audience Network
public struct MetaAdItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let ctaText: String
    public let iconSystemName: String
    public let customLogoGradient: [Color]
    public let rating: Double
    public let reviewsCount: String
    public let destinationURL: String
    public let sponsorTag: String
    public let category: String

    public static let defaultMetaAds: [MetaAdItem] = [
        MetaAdItem(
            id: "meta_quest_3s",
            title: "Meta Quest 3S",
            subtitle: "Пространственные игры и сверхбыстрый Wi-Fi 6E стриминг",
            ctaText: "В магазин",
            iconSystemName: "vr.headset.fill",
            customLogoGradient: [Color(red: 0.0, green: 0.5, blue: 1.0), Color(red: 0.6, green: 0.1, blue: 0.9)],
            rating: 4.9,
            reviewsCount: "42K",
            destinationURL: "https://www.meta.com/quest",
            sponsorTag: "Meta Hardware",
            category: "Гейминг и VR"
        ),
        MetaAdItem(
            id: "threads_app",
            title: "Threads от Meta",
            subtitle: "Платформа для живых обсуждений новостей и трендов в реальном времени",
            ctaText: "Открыть",
            iconSystemName: "bubble.left.and.text.bubble.right.fill",
            customLogoGradient: [Color(red: 0.1, green: 0.1, blue: 0.15), Color(red: 0.2, green: 0.2, blue: 0.3)],
            rating: 4.8,
            reviewsCount: "128K",
            destinationURL: "https://www.threads.net",
            sponsorTag: "Meta Verified",
            category: "Социальные сети"
        ),
        MetaAdItem(
            id: "whatsapp_business",
            title: "WhatsApp Business API",
            subtitle: "Автоматизация сообщений и техподдержка клиентов через Cloud API",
            ctaText: "Подключить",
            iconSystemName: "phone.bubble.fill",
            customLogoGradient: [Color(red: 0.15, green: 0.75, blue: 0.4), Color(red: 0.05, green: 0.5, blue: 0.25)],
            rating: 4.9,
            reviewsCount: "85K",
            destinationURL: "https://business.whatsapp.com",
            sponsorTag: "Meta Business",
            category: "Бизнес и API"
        ),
        MetaAdItem(
            id: "meta_ai_llama",
            title: "Meta AI & Llama 3",
            subtitle: "Передовой искусственный интеллект для анализа данных и автоматизации",
            ctaText: "Изучить",
            iconSystemName: "sparkles",
            customLogoGradient: [Color(red: 0.3, green: 0.4, blue: 1.0), Color(red: 0.8, green: 0.2, blue: 0.6)],
            rating: 5.0,
            reviewsCount: "150K",
            destinationURL: "https://ai.meta.com",
            sponsorTag: "Meta AI Lab",
            category: "Искусственный интеллект"
        ),
        MetaAdItem(
            id: "instagram_creators",
            title: "Instagram Creators Pro",
            subtitle: "Монетизация контента и инструменты охвата аудитории",
            ctaText: "Перейти",
            iconSystemName: "camera.viewfinder",
            customLogoGradient: [Color(red: 0.95, green: 0.2, blue: 0.4), Color(red: 0.98, green: 0.6, blue: 0.15)],
            rating: 4.8,
            reviewsCount: "310K",
            destinationURL: "https://about.instagram.com",
            sponsorTag: "Meta Verified",
            category: "Креаторы"
        )
    ]
}

/// Централизованный менеджер рекламы Meta Audience Network (2026)
@Observable
@MainActor
public final class MetaAdManager {
    public static let shared = MetaAdManager()

    // MARK: - Состояние
    public var adsList: [MetaAdItem] = MetaAdItem.defaultMetaAds
    public var currentAdIndex: Int = 0

    /// Текущее активное рекламное объявление Meta
    public var currentAd: MetaAdItem {
        guard !adsList.isEmpty else { return MetaAdItem.defaultMetaAds[0] }
        let safeIndex = currentAdIndex % adsList.count
        return adsList[safeIndex]
    }

    /// Флаг показа баннеров (скрывается для пользователей Pro / Owner)
    public var isBannerEnabled: Bool {
        !AdMobManager.shared.isPremiumUser && !AdMobManager.shared.isOwnerUnlocked
    }

    /// Локальный режим показа рекламы Meta (гарантированная работа оффлайн и онлайн)
    public var isLocalServingActive: Bool = true

    /// Показывать ли закрепленный нижний баннер (Sticky Banner)
    public var isStickyBannerVisible: Bool = true

    private var rotationTimer: AnyCancellable?

    private init() {
        startRotationTimer()
    }

    /// Запуск автоматической плавной ротации объявлений Meta
    public func startRotationTimer(interval: TimeInterval = 18.0) {
        rotationTimer?.cancel()
        rotationTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.rotateToNextAd()
                }
            }
    }

    /// Переключение на следующее объявление Meta
    public func rotateToNextAd() {
        guard !adsList.isEmpty else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentAdIndex = (currentAdIndex + 1) % adsList.count
        }
    }

    /// Получение релевантного объявления для конкретного экрана/контекста
    public func adForContext(_ context: String?) -> MetaAdItem {
        guard let ctx = context?.lowercased() else { return currentAd }
        if ctx.contains("гейминг") || ctx.contains("game") {
            return adsList.first(where: { $0.id == "meta_quest_3s" }) ?? currentAd
        } else if ctx.contains("ai") || ctx.contains("ии") {
            return adsList.first(where: { $0.id == "meta_ai_llama" }) ?? currentAd
        } else if ctx.contains("трафик") || ctx.contains("api") || ctx.contains("бизнес") {
            return adsList.first(where: { $0.id == "whatsapp_business" }) ?? currentAd
        }
        return currentAd
    }

    /// Фиксация клика по баннеру
    public func recordAdClick(ad: MetaAdItem) {
        HapticManager.shared.impactMedium()
        print("⚡ [Meta Audience Network] Клик по объявлению: \(ad.title) (\(ad.destinationURL))")
    }
}
