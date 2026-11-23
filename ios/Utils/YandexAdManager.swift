//
//  YandexAdManager.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / Yandex Mobile Ads SDK 8) - 2026.
//

import SwiftUI
import UIKit

/// Идентификаторы рекламных блоков Яндекса (Рекламная сеть Яндекса, РСЯ).
///
/// ВАЖНО: ниже — ДЕМО-блоки Яндекса. Они показывают тестовую рекламу и денег не приносят. Настоящие идентификаторы
/// вида `R-M-123456-1` выдаёт кабинет РСЯ (partner.yandex.ru → «Мобильные приложения»): добавьте приложение
/// с идентификатором `com.samvel.netpulse` и создайте три блока: баннер 320×50, межстраничный и с вознаграждением.
/// Подставьте их сюда — больше ничего менять не нужно.
enum YandexAdConfig {
    static let bannerUnitID = "demo-banner-yandex"
    static let interstitialUnitID = "demo-interstitial-yandex"
    static let rewardedUnitID = "demo-rewarded-yandex"

    /// Размер баннера. Стандартный 320×50 занимает заранее известное место, поэтому раскладка экрана не прыгает
    /// в момент загрузки объявления.
    static let bannerWidth: CGFloat = 320
    static let bannerHeight: CGFloat = 50

    /// Пока стоят демо-блоки, реклама тестовая и дохода не приносит
    static var usesDemoUnits: Bool {
        [bannerUnitID, interstitialUnitID, rewardedUnitID].contains { $0.hasPrefix("demo-") }
    }

    /// Можно ли показывать рекламу в этой сборке. В отладочной (симулятор, CI) демо-блоки показывают тестовую
    /// рекламу, чтобы проверять работу SDK. В выпускной (TestFlight, App Store) реклама молчит, пока блоки демо:
    /// тестовая реклама пользователям ни к чему, а доход приносят только блоки из кабинета РСЯ.
    static func isAllowed(inDebugBuild debug: Bool, usesDemoUnits demo: Bool) -> Bool {
        debug || !demo
    }

    static var isAllowedInThisBuild: Bool {
        #if DEBUG
        return isAllowed(inDebugBuild: true, usesDemoUnits: usesDemoUnits)
        #else
        return isAllowed(inDebugBuild: false, usesDemoUnits: usesDemoUnits)
        #endif
    }
}

/// КОНТРОЛЬНАЯ СБОРКА БЕЗ SDK ЯНДЕКСА: проверка, не из-за SDK ли приложение вылетает при запуске.
/// Менеджер сохраняет прежний набор свойств и методов, но рекламу не запускает и ничего не показывает.
@Observable
@MainActor
final class YandexAdManager: NSObject {
    static let shared = YandexAdManager()

    private(set) var isSDKInitialized = false
    private(set) var isATTAuthorized = false
    private(set) var isInterstitialLoaded = false
    private(set) var isRewardedLoaded = false

    var canShowAds: Bool { false }
    var canLoadBanners: Bool { false }

    nonisolated static var isDisabledForTesting: Bool { true }

    private override init() {
        super.init()
    }

    func start() {}
    func requestTrackingAuthorization() {}
    func recordActionAndTriggerInterstitial() {}
    func presentInterstitial() {}

    func showRewarded(
        onRewardConfirmed: @escaping @MainActor () -> Void,
        onUnavailable: (@MainActor () -> Void)? = nil
    ) {
        onUnavailable?()
    }
}
