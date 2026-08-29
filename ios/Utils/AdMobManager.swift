//
//  AdMobManager.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / AdMob 2026).
//

import SwiftUI
import Combine
#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif

/// Конфигурация рекламных блоков Google AdMob (официальные тестовые идентификаторы Apple iOS)
public struct AdMobConfig: Sendable {
    public static let appID = "ca-app-pub-3940256099942544~1458602516" // Google Test App ID
    public static let bannerAdUnitID = "ca-app-pub-3940256099942544/2934735716"
    public static let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"
    public static let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"
    public static let nativeAdUnitID = "ca-app-pub-3940256099942544/3986739490"
}

/// Спонсорские нативные объявления по умолчанию (когда SDK не инициализирован или нет сети)
public struct SponsorAdItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let ctaText: String
    public let iconName: String
    public let rating: Double
    public let destinationURL: String

    public static let defaults: [SponsorAdItem] = [
        SponsorAdItem(
            id: "warp_plus",
            title: "Cloudflare 1.1.1.1 + WARP",
            subtitle: "Быстрый и защищенный интернет с протоколом WireGuard",
            ctaText: "Установить",
            iconName: "bolt.shield.fill",
            rating: 4.9,
            destinationURL: "https://1.1.1.1"
        ),
        SponsorAdItem(
            id: "nextdns_pro",
            title: "NextDNS Pro Security",
            subtitle: "Блокировка трекеров, фишинга и рекламы на уровне DNS-шлюза",
            ctaText: "Подробнее",
            iconName: "shield.lefthalf.filled",
            rating: 4.8,
            destinationURL: "https://nextdns.io"
        ),
        SponsorAdItem(
            id: "game_booster",
            title: "Gaming Ping Accelerator",
            subtitle: "Оптимизация сетевых маршрутов до серверов CS2 и Valorant",
            ctaText: "Попробовать",
            iconName: "gamecontroller.fill",
            rating: 4.9,
            destinationURL: "https://netpulse.app"
        )
    ]
}

/// Централизованный менеджер рекламы Google AdMob и подписки NetPulse Pro
@Observable
@MainActor
public final class AdMobManager {
    public static let shared = AdMobManager()

    // MARK: - Состояние подписки и рекламы
    public var isPremiumUser: Bool {
        didSet {
            UserDefaults.standard.set(isPremiumUser, forKey: "netpulse_is_premium_user")
        }
    }

    public var isBannerEnabled: Bool {
        !isPremiumUser
    }

    public var isNativeAdsEnabled: Bool {
        !isPremiumUser
    }

    public var isTestMode: Bool = false

    public var isShowingRewardedOverlay: Bool = false
    public var rewardedCountdown: Int = 5

    // Внутренний счетчик действий для умного показа межстраничной рекламы (Interstitial)
    private var actionCount: Int = 0
    private let interstitialFrequency: Int = 3 // Показ раз в 3 ключевых действия

    private init() {
        self.isPremiumUser = UserDefaults.standard.bool(forKey: "netpulse_is_premium_user")
    }

    // MARK: - Проверка прав показа
    public var canShowAds: Bool {
        return !isPremiumUser
    }

    // MARK: - Запрос разрешения App Tracking Transparency (ATT)
    public func requestTrackingAuthorization() {
        #if canImport(AppTrackingTransparency)
        if #available(iOS 14.5, *) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
                guard UIApplication.shared.applicationState == .active else { return }
                ATTrackingManager.requestTrackingAuthorization { status in
                    print("[AdMobManager] ATT Status: \(status.rawValue)")
                }
            }
        }
        #endif
    }

    // MARK: - Межстраничная реклама (Interstitial)
    public func recordActionAndTriggerInterstitialIfNeeded(onDismiss: (() -> Void)? = nil) {
        guard canShowAds else {
            onDismiss?()
            return
        }

        actionCount += 1
        if actionCount >= interstitialFrequency {
            actionCount = 0
            // Показ полноэкранного межстраничного баннера
            print("[AdMobManager] Triggering Interstitial Ad (Unit: \(AdMobConfig.interstitialAdUnitID))")
            HapticManager.shared.impactLight()
            onDismiss?()
        } else {
            onDismiss?()
        }
    }

    // MARK: - Вознаграждаемая реклама (Rewarded Video)
    public func showRewardedAd(forFeature featureName: String, onReward: @escaping () -> Void) {
        guard canShowAds else {
            onReward()
            return
        }

        // Запуск модального окна просмотра вознаграждения
        isShowingRewardedOverlay = true
        rewardedCountdown = 5
        HapticManager.shared.impactMedium()

        Task {
            for count in stride(from: 5, through: 1, by: -1) {
                self.rewardedCountdown = count
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            self.isShowingRewardedOverlay = false
            HapticManager.shared.notificationSuccess()
            onReward()
        }
    }

    // MARK: - Покупка NetPulse Pro (Удаление рекламы)
    public func purchaseProVersion() {
        isPremiumUser = true
        HapticManager.shared.notificationSuccess()
    }

    public func restorePurchases() {
        // Логика восстановления покупок StoreKit
        HapticManager.shared.notificationSuccess()
    }
}
