//
//  YandexAdManager.swift
//  NetPulse
//
//  Менеджер рекламы Yandex Mobile Ads SDK 8.x (баннер, межстраничная, вознаграждаемая).
//

import AppTrackingTransparency
import SwiftUI
import UIKit
import YandexMobileAds

/// Идентификаторы рекламных блоков Яндекса.
///
/// После публикации приложения создайте блоки в кабинете Рекламной сети Яндекса
/// (partner.yandex.ru → Приложения → Добавить приложение → Добавить блок),
/// вставьте боевые ID ниже и выпустите обновление. Пока стоят демо-ID (`demo-...`),
/// в Release-сборке реклама выключена, SDK не инициализируется и данные не передаются.
public enum YandexAdConfig {
    public static let bannerUnitID = "demo-banner-yandex"
    public static let interstitialUnitID = "demo-interstitial-yandex"
    public static let rewardedUnitID = "demo-rewarded-yandex"

    /// Реклама включена, если в Debug (демо-блоки допустимы) или во всех блоках заданы боевые ID
    public static var isEnabled: Bool {
        #if DEBUG
        return true
        #else
        return ![bannerUnitID, interstitialUnitID, rewardedUnitID].contains { $0.hasPrefix("demo-") }
        #endif
    }
}

/// Централизованный менеджер рекламы Яндекса
@Observable
@MainActor
public final class YandexAdManager: NSObject {
    public static let shared = YandexAdManager()

    public private(set) var isSDKInitialized = false
    public private(set) var isInterstitialLoaded = false
    public private(set) var isRewardedLoaded = false

    /// Показывать ли рекламу: заданы боевые ID блоков (или Debug-сборка)
    public var canShowAds: Bool {
        YandexAdConfig.isEnabled
    }

    private let interstitialLoader = InterstitialAdLoader()
    private let rewardedLoader = RewardedAdLoader()
    private var interstitialAd: InterstitialAd?
    private var rewardedAd: RewardedAd?
    private var pendingReward: (() -> Void)?
    private var rewardGranted = false

    // Умный показ межстраничной рекламы: раз в N ключевых действий и не чаще интервала
    private var actionCount = 0
    private let interstitialFrequency = 3
    private let minInterstitialInterval: TimeInterval = 120
    private var lastInterstitialDate: Date = .distantPast

    private override init() {
        super.init()
    }

    // MARK: - Инициализация

    public func initialize() {
        guard YandexAdConfig.isEnabled, !isSDKInitialized else { return }
        Task { @MainActor in
            await YandexAds.initializeSDK()
            self.isSDKInitialized = true
            self.loadInterstitial()
            self.loadRewarded()
        }
    }

    // MARK: - Запрос разрешения App Tracking Transparency (ATT)

    /// Обёртка вне MainActor: колбэк ATT приходит не на главной очереди (иначе падение _dispatch_assert_queue_fail)
    private nonisolated static func requestATTAuth() async -> ATTrackingManager.AuthorizationStatus {
        await withCheckedContinuation { continuation in
            ATTrackingManager.requestTrackingAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    public func requestTrackingAuthorization() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined,
                  UIApplication.shared.applicationState == .active else { return }
            _ = await Self.requestATTAuth()
        }
    }

    // MARK: - Межстраничная реклама

    private func loadInterstitial() {
        guard canShowAds, isSDKInitialized, interstitialAd == nil else { return }
        let request = AdRequest(adUnitID: YandexAdConfig.interstitialUnitID)
        interstitialLoader.loadAd(with: request) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let ad):
                ad.delegate = self
                self.interstitialAd = ad
                self.isInterstitialLoaded = true
            case .failure(let error):
                print("[YandexAdManager] Interstitial load failed: \(error)")
            }
        }
    }

    /// Учитывает ключевое действие (например, завершённый замер скорости) и при необходимости показывает ролик
    public func recordActionAndTriggerInterstitial() {
        guard canShowAds else { return }
        actionCount += 1
        guard actionCount >= interstitialFrequency,
              Date().timeIntervalSince(lastInterstitialDate) >= minInterstitialInterval,
              let ad = interstitialAd,
              let controller = Self.topViewController() else { return }
        actionCount = 0
        lastInterstitialDate = Date()
        ad.show(from: controller)
    }

    // MARK: - Вознаграждаемая реклама

    private func loadRewarded() {
        guard canShowAds, isSDKInitialized, rewardedAd == nil else { return }
        let request = AdRequest(adUnitID: YandexAdConfig.rewardedUnitID)
        rewardedLoader.loadAd(with: request) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let ad):
                ad.delegate = self
                self.rewardedAd = ad
                self.isRewardedLoaded = true
            case .failure(let error):
                print("[YandexAdManager] Rewarded load failed: \(error)")
            }
        }
    }

    /// Показывает вознаграждаемое видео. Если рекламы нет (не загружена, выключена) — функция выдаётся сразу.
    public func showRewardedVideo(onReward: @escaping () -> Void) {
        guard canShowAds, let ad = rewardedAd, let controller = Self.topViewController() else {
            onReward()
            return
        }
        pendingReward = onReward
        rewardGranted = false
        ad.show(from: controller)
    }

    private func finishRewarded() {
        rewardedAd = nil
        isRewardedLoaded = false
        let callback = pendingReward
        pendingReward = nil
        if rewardGranted { callback?() }
        rewardGranted = false
        loadRewarded()
    }

    // MARK: - Вспомогательное

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

// MARK: - InterstitialAdDelegate

extension YandexAdManager: InterstitialAdDelegate {
    public func interstitialAdDidShow(_ interstitialAd: InterstitialAd) {}

    public func interstitialAdDidDismiss(_ interstitialAd: InterstitialAd) {
        self.interstitialAd = nil
        isInterstitialLoaded = false
        loadInterstitial()
    }

    public func interstitialAdDidClick(_ interstitialAd: InterstitialAd) {}

    public func interstitialAd(_ interstitialAd: InterstitialAd, didTrackImpression impressionData: ImpressionData?) {}

    public func interstitialAd(_ interstitialAd: InterstitialAd, didFailToShow error: Error) {
        self.interstitialAd = nil
        isInterstitialLoaded = false
        loadInterstitial()
    }
}

// MARK: - RewardedAdDelegate

extension YandexAdManager: RewardedAdDelegate {
    public func rewardedAd(_ rewardedAd: RewardedAd, didReward reward: Reward) {
        rewardGranted = true
    }

    public func rewardedAd(_ rewardedAd: RewardedAd, didFailToShow error: Error) {
        // Ролик не показан — не наказываем пользователя, выдаём функцию
        rewardGranted = true
        finishRewarded()
    }

    public func rewardedAdDidShow(_ rewardedAd: RewardedAd) {}

    public func rewardedAdDidDismiss(_ rewardedAd: RewardedAd) {
        finishRewarded()
    }

    public func rewardedAdDidClick(_ rewardedAd: RewardedAd) {}

    public func rewardedAd(_ rewardedAd: RewardedAd, didTrackImpression impressionData: ImpressionData?) {}
}
