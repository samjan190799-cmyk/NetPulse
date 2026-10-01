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

/// Конфигурация идентификаторов Meta Audience Network (Meta Ads 2026).
///
/// ВАЖНО: ниже — ЗАГЛУШКИ. Реальные App ID и Placement ID выдаёт Meta Business Suite; с заглушками реклама
/// не загрузится (баннеры просто не показываются). Те же значения нужно прописать в Info.plist
/// (`FacebookAppID`, `FacebookClientToken`).
public struct MetaAdConfig: Sendable {
    public static let appID = "987654321098765"
    public static let bannerPlacementID = "987654321098765_1234567890"
    public static let interstitialPlacementID = "987654321098765_3456789012"
    public static let rewardedPlacementID = "987654321098765_4567890123"
    public static let nativePlacementID = "987654321098765_2345678901"
}

/// Централизованный менеджер рекламы Meta Audience Network (2026)
@Observable
@MainActor
public final class MetaAdManager: NSObject {
    public static let shared = MetaAdManager()

    // MARK: - Состояние SDK и аукциона
    public var isSDKInitialized: Bool = false
    public var isATTAuthorized: Bool = false
    public var isStickyBannerVisible: Bool = true

    /// Флаг доступности рекламы (полностью скрыта для пользователей NetPulse PRO)
    public var isBannerEnabled: Bool {
        !AdMobManager.shared.isPremiumUser
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

    // MARK: - Инициализация
    private override init() {
        super.init()
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

    /// Показ рекламы за вознаграждение (например, для бонусного глубокого AI-аудита).
    ///
    /// Награда выдаётся ТОЛЬКО после реального просмотра ролика. Если ролик не загружен (нет сети, нет заполнения,
    /// идентификаторы площадок — заглушки), вызывается `onUnavailable`: раньше в этом случае награда «симулировалась»
    /// и выдавалась мгновенно, то есть просмотр рекламы ничего не значил.
    public func showRewardedVideo(
        from viewController: UIViewController? = nil,
        onRewardConfirmed: @escaping @MainActor () -> Void,
        onUnavailable: (@MainActor () -> Void)? = nil
    ) {
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

        // Ролика нет — награду не симулируем
        print("ℹ [Meta Audience Network] Ролик не загружен — награда не выдана")
        self.onRewardConfirmedCallback = nil
        onUnavailable?()
    }

    // MARK: - Вспомогательные методы
    private func getRootViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        return rootVC
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
