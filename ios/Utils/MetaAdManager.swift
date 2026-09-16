//
//  MetaAdManager.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / Meta Audience Network 2026).
//

import SwiftUI
import Combine
import UIKit
#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif

#if canImport(FBAudienceNetwork)
import FBAudienceNetwork
#endif

/// Конфигурация идентификаторов Meta Audience Network (Meta Ads 2026)
public struct MetaAdConfig: Sendable {
    public static let appID = "987654321098765"
    public static let bannerPlacementID = "987654321098765_1234567890"
    public static let interstitialPlacementID = "987654321098765_3456789012"
    public static let rewardedPlacementID = "987654321098765_4567890123"
    public static let nativePlacementID = "987654321098765_2345678901"
}

/// Модель резервного рекламного объявления Meta (Graceful Fallback при No Fill / отсутствии сети)
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
public final class MetaAdManager: NSObject {
    public static let shared = MetaAdManager()

    // MARK: - Состояние SDK и аукциона
    public var isSDKInitialized: Bool = false
    public var isATTAuthorized: Bool = false
    public var isLocalServingActive: Bool = true
    public var isStickyBannerVisible: Bool = true

    /// Флаг доступности рекламы (полностью скрыта для пользователей NetPulse PRO / Owner)
    public var isBannerEnabled: Bool {
        !AdMobManager.shared.isPremiumUser && !AdMobManager.shared.isOwnerUnlocked
    }

    public var canShowAds: Bool {
        isBannerEnabled
    }

    // MARK: - Межстраничная реклама (Interstitial)
    public var isInterstitialLoaded: Bool = false
    private var interstitialActionCount: Int = 0
    public let interstitialFrequency: Int = 3 // Показ раз в 3 действия

    #if canImport(FBAudienceNetwork)
    private var fbInterstitialAd: FBInterstitialAd?
    private var fbRewardedVideoAd: FBRewardedVideoAd?
    #endif

    // MARK: - Вознаграждаемая реклама (Rewarded Video)
    public var isRewardedVideoLoaded: Bool = false
    public var onRewardConfirmedCallback: (@MainActor () -> Void)?

    // MARK: - Резервные объявления (Fallback)
    public var adsList: [MetaAdItem] = MetaAdItem.defaultMetaAds
    public var currentAdIndex: Int = 0
    private var rotationTimer: AnyCancellable?

    public var currentAd: MetaAdItem {
        guard !adsList.isEmpty else { return MetaAdItem.defaultMetaAds[0] }
        let safeIndex = currentAdIndex % adsList.count
        return adsList[safeIndex]
    }

    // MARK: - Инициализация
    private override init() {
        super.init()
        startRotationTimer()
    }

    /// Инициализация официального SDK Meta Audience Network
    public func initialize() {
        guard !isSDKInitialized else { return }

        #if canImport(FBAudienceNetwork)
        print("🚀 [Meta Audience Network] Инициализация SDK...")
        FBAudienceNetworkAds.initialize(with: nil) { [weak self] result in
            let isSuccess = result.isSuccess
            let message = result.message
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSDKInitialized = isSuccess
                print("✔ [Meta Audience Network] Результат инициализации: \(isSuccess ? "УСПЕХ" : "ОШИБКА: \(message)")")

                // Предзагрузка межстраничного и вознаграждаемого баннера
                self.loadInterstitial()
                self.loadRewardedVideo()
            }
        }
        #else
        print("ℹ [Meta Audience Network] SDK не скомпилирован в бинарник, активен локальный Graceful Fallback.")
        isSDKInitialized = true
        #endif
    }

    // MARK: - Интеграция с App Tracking Transparency (ATT)
    public func updateAdvertiserTracking(authorized: Bool) {
        self.isATTAuthorized = authorized
        #if canImport(FBAudienceNetwork)
        FBAdSettings.setAdvertiserTrackingEnabled(authorized)
        print("⚡ [Meta Audience Network] Флаг отслеживания рекламы: \(authorized)")
        #endif
    }

    public func requestTrackingAuthorization() {
        #if canImport(AppTrackingTransparency)
        if #available(iOS 14.5, *) {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
                    let isAuth = ATTrackingManager.trackingAuthorizationStatus == .authorized
                    self.updateAdvertiserTracking(authorized: isAuth)
                    return
                }
                guard UIApplication.shared.applicationState == .active else { return }

                let status = await withCheckedContinuation { continuation in
                    ATTrackingManager.requestTrackingAuthorization { res in
                        continuation.resume(returning: res)
                    }
                }
                self.updateAdvertiserTracking(authorized: status == .authorized)
            }
        }
        #endif
    }

    // MARK: - Межстраничная реклама (Interstitial Ads)
    public func loadInterstitial() {
        guard canShowAds else { return }

        #if canImport(FBAudienceNetwork)
        let interstitial = FBInterstitialAd(placementID: MetaAdConfig.interstitialPlacementID)
        interstitial.delegate = self
        self.fbInterstitialAd = interstitial
        interstitial.load()
        print("⏳ [Meta Audience Network] Запрос на загрузку Interstitial Ad...")
        #endif
    }

    /// Проверка счетчика действий и показ межстраничной рекламы (например, после завершения Speedtest)
    public func recordActionAndTriggerInterstitial(from viewController: UIViewController? = nil, onComplete: (() -> Void)? = nil) {
        guard canShowAds else {
            onComplete?()
            return
        }

        interstitialActionCount += 1
        if interstitialActionCount >= interstitialFrequency {
            interstitialActionCount = 0

            #if canImport(FBAudienceNetwork)
            if let ad = fbInterstitialAd, ad.isAdValid {
                let presenter = viewController ?? getRootViewController()
                if let presenter {
                    ad.show(fromRootViewController: presenter)
                    print("🚀 [Meta Audience Network] Показ Interstitial Ad")
                    HapticManager.shared.impactLight()
                    onComplete?()
                    return
                }
            }
            #endif

            // Если SDK недоступен или реклама не готова — просто продолжаем без задержки
            onComplete?()
        } else {
            onComplete?()
        }
    }

    // MARK: - Вознаграждаемая реклама (Rewarded Video Ads)
    public func loadRewardedVideo() {
        guard canShowAds else { return }

        #if canImport(FBAudienceNetwork)
        let rewarded = FBRewardedVideoAd(placementID: MetaAdConfig.rewardedPlacementID)
        rewarded.delegate = self
        self.fbRewardedVideoAd = rewarded
        rewarded.load()
        print("⏳ [Meta Audience Network] Запрос на загрузку Rewarded Video...")
        #endif
    }

    /// Показ рекламы за вознаграждение (например, для бесплатного сеанса AI-диагностики)
    public func showRewardedVideo(from viewController: UIViewController? = nil, onRewardConfirmed: @escaping @MainActor () -> Void) {
        self.onRewardConfirmedCallback = onRewardConfirmed

        #if canImport(FBAudienceNetwork)
        if let ad = fbRewardedVideoAd, ad.isAdValid {
            let presenter = viewController ?? getRootViewController()
            if let presenter {
                ad.show(fromRootViewController: presenter)
                print("🚀 [Meta Audience Network] Показ Rewarded Video")
                HapticManager.shared.impactMedium()
                return
            }
        }
        #endif

        // Локальная симуляция награды, если видео не загружено
        print("ℹ [Meta Audience Network] Локальная симуляция награды за просмотр видео")
        HapticManager.shared.notificationSuccess()
        onRewardConfirmed()
    }

    // MARK: - Вспомогательные методы
    private func getRootViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        return rootVC
    }

    // MARK: - Ротация локальных креативов (Fallback)
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

    public func rotateToNextAd() {
        guard !adsList.isEmpty else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentAdIndex = (currentAdIndex + 1) % adsList.count
        }
    }

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

    public func recordAdClick(ad: MetaAdItem) {
        HapticManager.shared.impactMedium()
        print("⚡ [Meta Audience Network] Клик по объявлению: \(ad.title) (\(ad.destinationURL))")
    }
}

// MARK: - Делегаты FBInterstitialAdDelegate & FBRewardedVideoAdDelegate
#if canImport(FBAudienceNetwork)
extension MetaAdManager: @preconcurrency FBInterstitialAdDelegate {
    nonisolated public func interstitialAdDidLoad(_ interstitialAd: FBInterstitialAd) {
        Task { @MainActor in
            print("✔ [Meta Audience Network] Interstitial Ad успешно загружен")
            self.isInterstitialLoaded = true
        }
    }

    nonisolated public func interstitialAd(_ interstitialAd: FBInterstitialAd, didFailWithError error: Error) {
        Task { @MainActor in
            print("⚠ [Meta Audience Network] Ошибка загрузки Interstitial: \(error.localizedDescription)")
            self.isInterstitialLoaded = false
        }
    }

    nonisolated public func interstitialAdDidClose(_ interstitialAd: FBInterstitialAd) {
        Task { @MainActor in
            print("⚡ [Meta Audience Network] Interstitial Ad закрыт пользователем")
            self.isInterstitialLoaded = false
            self.loadInterstitial() // Предзагрузка следующего
        }
    }

    nonisolated public func interstitialAdWillLogImpression(_ interstitialAd: FBInterstitialAd) {
        print("⚡ [Meta Audience Network] Зафиксирован показ Interstitial Ad")
    }

    nonisolated public func interstitialAdDidClick(_ interstitialAd: FBInterstitialAd) {
        Task { @MainActor in
            print("⚡ [Meta Audience Network] Клик по Interstitial Ad")
            HapticManager.shared.impactMedium()
        }
    }
}

extension MetaAdManager: @preconcurrency FBRewardedVideoAdDelegate {
    nonisolated public func rewardedVideoAdDidLoad(_ rewardedVideoAd: FBRewardedVideoAd) {
        Task { @MainActor in
            print("✔ [Meta Audience Network] Rewarded Video успешно загружено")
            self.isRewardedVideoLoaded = true
        }
    }

    nonisolated public func rewardedVideoAd(_ rewardedVideoAd: FBRewardedVideoAd, didFailWithError error: Error) {
        Task { @MainActor in
            print("⚠ [Meta Audience Network] Ошибка загрузки Rewarded Video: \(error.localizedDescription)")
            self.isRewardedVideoLoaded = false
        }
    }

    nonisolated public func rewardedVideoAdDidClose(_ rewardedVideoAd: FBRewardedVideoAd) {
        Task { @MainActor in
            print("⚡ [Meta Audience Network] Rewarded Video закрыто пользователем")
            self.isRewardedVideoLoaded = false
            self.loadRewardedVideo() // Предзагрузка следующего
        }
    }

    nonisolated public func rewardedVideoAdDidComplete(_ rewardedVideoAd: FBRewardedVideoAd) {
        Task { @MainActor in
            print("🎁 [Meta Audience Network] Rewarded Video завершено! Начисление награды пользователю...")
            HapticManager.shared.notificationSuccess()
            self.onRewardConfirmedCallback?()
            self.onRewardConfirmedCallback = nil
        }
    }

    nonisolated public func rewardedVideoAdWillLogImpression(_ rewardedVideoAd: FBRewardedVideoAd) {
        print("⚡ [Meta Audience Network] Зафиксирован показ Rewarded Video")
    }

    nonisolated public func rewardedVideoAdDidClick(_ rewardedVideoAd: FBRewardedVideoAd) {
        Task { @MainActor in
            print("⚡ [Meta Audience Network] Клик по Rewarded Video")
            HapticManager.shared.impactMedium()
        }
    }
}
#endif
