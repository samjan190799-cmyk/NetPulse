//
//  YandexAdManager.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / Yandex Mobile Ads SDK 8) - 2026.
//

import SwiftUI
import UIKit
import OSLog
import YandexMobileAds
#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif

/// Журнал рекламы: строки видны в Console.app и в журнале приложения на CI (категория `ads`).
private let adLog = Logger(subsystem: "com.samvel.netpulse", category: "ads")

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

/// Менеджер рекламы Яндекса: запуск SDK, запрос разрешения на отслеживание (ATT), межстраничная реклама и реклама
/// за вознаграждение. Баннеры показывают отдельные представления (`YandexBannerSlot`), менеджер лишь говорит им,
/// когда SDK готов.
///
/// Приватность. Геолокация приложения нужна карте маршрутов и остаётся на устройстве, поэтому SDK Яндекса она
/// не отдаётся (`setLocationTracking(false)`). Идентификатор для рекламы (IDFA) SDK получает, только если
/// пользователь разрешил отслеживание в системном окне.
@Observable
@MainActor
final class YandexAdManager: NSObject {
    static let shared = YandexAdManager()

    // MARK: - Состояние

    private(set) var isSDKInitialized = false
    private(set) var isATTAuthorized = false
    private(set) var isInterstitialLoaded = false
    private(set) var isRewardedLoaded = false

    /// Реклама показывается, пока не куплен PRO и если сборка её допускает (в выпускной сборке — только с боевыми
    /// блоками, см. `YandexAdConfig.isAllowed`)
    var canShowAds: Bool {
        !Self.isDisabledForTesting && YandexAdConfig.isAllowedInThisBuild && !AdMobManager.shared.isPremiumUser
    }

    /// Баннеры можно запрашивать, когда SDK инициализирован
    var canLoadBanners: Bool {
        canShowAds && isSDKInitialized
    }

    /// Реклама выключена для проверок. Юнит-тесты запускаются внутри приложения и не должны ходить за рекламой
    /// в сеть; UI-тесты передают аргумент запуска `-netpulse_ads_disabled YES` (только в отладочной сборке: в
    /// выпускной такого выключателя нет).
    nonisolated static var isDisabledForTesting: Bool {
        if NSClassFromString("XCTestCase") != nil { return true }
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "netpulse_ads_disabled")
        #else
        return false
        #endif
    }

    // MARK: - Межстраничная реклама

    private let interstitialLoader = InterstitialAdLoader()
    @ObservationIgnored private var readyInterstitial: InterstitialAd?
    @ObservationIgnored private var isLoadingInterstitial = false
    @ObservationIgnored private var interstitialFailures = 0
    /// Показ положен раз в 3 действия (после замера скорости)
    @ObservationIgnored private var interstitialCap = AdFrequencyCap(every: 3)

    // MARK: - Реклама за вознаграждение

    private let rewardedLoader = RewardedAdLoader()
    @ObservationIgnored private var readyRewarded: RewardedAd?
    @ObservationIgnored private var isLoadingRewarded = false
    @ObservationIgnored private var rewardedFailures = 0
    @ObservationIgnored private var rewardEarned = false
    @ObservationIgnored private var onRewardConfirmed: (@MainActor () -> Void)?
    @ObservationIgnored private var onRewardUnavailable: (@MainActor () -> Void)?

    // MARK: - Запуск

    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var isRequestingATT = false

    private override init() {
        super.init()
    }

    /// Запускает SDK. Вызывается, когда приложение на экране: при фоновом запуске (например, по геолокации)
    /// рекламе делать нечего. Повторные вызовы безвредны.
    func start() {
        guard !hasStarted, canShowAds else { return }
        hasStarted = true

        #if DEBUG
        YandexAds.enableLogging()
        #endif
        YandexAds.setLocationTracking(false)

        if YandexAdConfig.usesDemoUnits {
            adLog.notice("Стоят демо-блоки Яндекса: реклама тестовая, дохода нет")
        }

        Task { [weak self] in
            // Сначала разрешение на отслеживание: тогда первые же запросы рекламы уйдут с идентификатором
            await self?.requestTrackingAuthorizationIfNeeded()
            await YandexAds.initializeSDK()
            self?.sdkDidInitialize()
        }
    }

    private func sdkDidInitialize() {
        isSDKInitialized = true
        adLog.notice("SDK Яндекса запущен, версия \(String(describing: YandexAds.sdkVersion), privacy: .public)")
        loadInterstitial()
        loadRewarded()
    }

    // MARK: - Разрешение на отслеживание (ATT)

    /// Повторяет запрос при возврате в приложение: окно показывается только у активного приложения, поэтому
    /// первый запрос мог не состояться
    func requestTrackingAuthorization() {
        guard canShowAds else { return }
        Task { await requestTrackingAuthorizationIfNeeded() }
    }

    private func requestTrackingAuthorizationIfNeeded() async {
        #if canImport(AppTrackingTransparency)
        let current = ATTrackingManager.trackingAuthorizationStatus
        guard current == .notDetermined else {
            isATTAuthorized = current == .authorized
            return
        }
        guard !isRequestingATT else { return }
        isRequestingATT = true
        defer { isRequestingATT = false }

        // Окно, показанное слишком рано после запуска, iOS молча отбрасывает
        try? await Task.sleep(for: .seconds(1.2))
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined,
              UIApplication.shared.applicationState == .active else { return }

        let status = await Self.requestATT()
        isATTAuthorized = status == .authorized
        adLog.notice("Разрешение на отслеживание: код \(status.rawValue)")
        #endif
    }

    #if canImport(AppTrackingTransparency)
    private nonisolated static func requestATT() async -> ATTrackingManager.AuthorizationStatus {
        await withCheckedContinuation { continuation in
            ATTrackingManager.requestTrackingAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
    #endif

    // MARK: - Межстраничная реклама (после замера скорости)

    private func loadInterstitial() {
        guard canShowAds, isSDKInitialized, readyInterstitial == nil, !isLoadingInterstitial else { return }
        isLoadingInterstitial = true
        interstitialLoader.loadAd(with: AdRequest(adUnitID: YandexAdConfig.interstitialUnitID)) { [weak self] result in
            guard let self else { return }
            self.isLoadingInterstitial = false
            switch result {
            case .success(let ad):
                ad.delegate = self
                self.readyInterstitial = ad
                self.interstitialFailures = 0
                self.isInterstitialLoaded = true
                adLog.notice("Межстраничная реклама загружена")
            case .failure(let error):
                self.interstitialFailures += 1
                self.isInterstitialLoaded = false
                adLog.error("Межстраничная реклама не загрузилась: \(error.localizedDescription, privacy: .public)")
                self.scheduleInterstitialRetry()
            }
        }
    }

    private func scheduleInterstitialRetry() {
        let delay = AdRetryPolicy.delay(afterFailures: interstitialFailures)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.loadInterstitial()
        }
    }

    private func interstitialFinished() {
        readyInterstitial = nil
        isInterstitialLoaded = false
        loadInterstitial()
    }

    /// Учитывает действие пользователя (например, завершённый замер скорости) и раз в несколько действий
    /// показывает межстраничную рекламу, если она уже загружена. Если не загружена, пользователя не задерживаем.
    func recordActionAndTriggerInterstitial() {
        guard canShowAds else { return }
        guard interstitialCap.recordAction() else { return }
        presentInterstitial()
    }

    /// Показывает межстраничную рекламу сразу, минуя счётчик (кнопка в отладочной панели настроек)
    func presentInterstitial() {
        guard canShowAds else { return }
        guard isInterstitialLoaded, let ad = readyInterstitial, let presenter = Self.topViewController() else {
            adLog.notice("Межстраничная реклама положена, но ещё не готова")
            loadInterstitial()
            return
        }
        interstitialCap.reset()
        ad.show(from: presenter)
    }

    // MARK: - Реклама за вознаграждение

    private func loadRewarded() {
        guard canShowAds, isSDKInitialized, readyRewarded == nil, !isLoadingRewarded else { return }
        isLoadingRewarded = true
        rewardedLoader.loadAd(with: AdRequest(adUnitID: YandexAdConfig.rewardedUnitID)) { [weak self] result in
            guard let self else { return }
            self.isLoadingRewarded = false
            switch result {
            case .success(let ad):
                ad.delegate = self
                self.readyRewarded = ad
                self.rewardedFailures = 0
                self.isRewardedLoaded = true
                adLog.notice("Реклама за вознаграждение загружена")
            case .failure(let error):
                self.rewardedFailures += 1
                self.isRewardedLoaded = false
                adLog.error("Реклама за вознаграждение не загрузилась: \(error.localizedDescription, privacy: .public)")
                self.scheduleRewardedRetry()
            }
        }
    }

    private func scheduleRewardedRetry() {
        let delay = AdRetryPolicy.delay(afterFailures: rewardedFailures)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.loadRewarded()
        }
    }

    /// Закрывает показ ролика с наградой: выдаёт награду, только если ролик досмотрен
    private func rewardedFinished(failedToShow: Bool) {
        let earned = rewardEarned
        let confirmed = onRewardConfirmed
        let unavailable = onRewardUnavailable
        rewardEarned = false
        onRewardConfirmed = nil
        onRewardUnavailable = nil
        readyRewarded = nil
        isRewardedLoaded = false
        loadRewarded()

        if failedToShow {
            unavailable?()
        } else if earned {
            confirmed?()
        }
    }

    /// Показывает рекламу за вознаграждение. Награда выдаётся ТОЛЬКО после просмотра ролика до конца. Если ролика
    /// нет (нет сети, нет подходящих объявлений, SDK ещё запускается), вызывается `onUnavailable`: награду не
    /// симулируем, пусть вызывающий сам решает, что делать без неё.
    func showRewarded(
        onRewardConfirmed: @escaping @MainActor () -> Void,
        onUnavailable: (@MainActor () -> Void)? = nil
    ) {
        guard canShowAds, isRewardedLoaded, let ad = readyRewarded, let presenter = Self.topViewController() else {
            adLog.notice("Ролик с наградой не готов, награда не выдана")
            loadRewarded()
            onUnavailable?()
            return
        }
        rewardEarned = false
        self.onRewardConfirmed = onRewardConfirmed
        self.onRewardUnavailable = onUnavailable
        ad.show(from: presenter)
    }

    // MARK: - Вспомогательное

    /// Самый верхний экран приложения: рекламу нужно показывать поверх открытых листов (настройки, маршруты)
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

// MARK: - Делегат межстраничной рекламы

extension YandexAdManager: InterstitialAdDelegate {
    func interstitialAd(_ interstitialAd: InterstitialAd, didFailToShow error: any Error) {
        adLog.error("Межстраничная реклама не показалась: \(error.localizedDescription, privacy: .public)")
        interstitialFinished()
    }

    func interstitialAdDidShow(_ interstitialAd: InterstitialAd) {
        adLog.notice("Показана межстраничная реклама")
    }

    func interstitialAdDidDismiss(_ interstitialAd: InterstitialAd) {
        adLog.notice("Межстраничная реклама закрыта")
        interstitialFinished()
    }

    func interstitialAdDidClick(_ interstitialAd: InterstitialAd) {
        adLog.notice("Нажатие на межстраничную рекламу")
    }

    func interstitialAd(_ interstitialAd: InterstitialAd, didTrackImpression impressionData: (any ImpressionData)?) {
        adLog.notice("Засчитан показ межстраничной рекламы")
    }
}

// MARK: - Делегат рекламы за вознаграждение

extension YandexAdManager: RewardedAdDelegate {
    func rewardedAd(_ rewardedAd: RewardedAd, didReward reward: any Reward) {
        adLog.notice("Награда заработана: \(reward.amount) \(reward.type, privacy: .public)")
        rewardEarned = true
    }

    func rewardedAd(_ rewardedAd: RewardedAd, didFailToShow error: any Error) {
        adLog.error("Ролик с наградой не показался: \(error.localizedDescription, privacy: .public)")
        rewardedFinished(failedToShow: true)
    }

    func rewardedAdDidShow(_ rewardedAd: RewardedAd) {
        adLog.notice("Показан ролик с наградой")
    }

    func rewardedAdDidDismiss(_ rewardedAd: RewardedAd) {
        adLog.notice("Ролик с наградой закрыт, награда заработана: \(self.rewardEarned)")
        rewardedFinished(failedToShow: false)
    }

    func rewardedAdDidClick(_ rewardedAd: RewardedAd) {
        adLog.notice("Нажатие на ролик с наградой")
    }

    func rewardedAd(_ rewardedAd: RewardedAd, didTrackImpression impressionData: (any ImpressionData)?) {
        adLog.notice("Засчитан показ ролика с наградой")
    }
}
