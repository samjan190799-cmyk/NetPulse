//
//  AdTests.swift
//  NetPulseTests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest
@testable import NetPulse

// MARK: - Частота межстраничной рекламы

final class AdFrequencyCapTests: XCTestCase {
    func testAdIsDueOnlyAfterEveryNthAction() {
        var cap = AdFrequencyCap(every: 3)
        XCTAssertFalse(cap.recordAction())
        XCTAssertFalse(cap.recordAction())
        XCTAssertTrue(cap.recordAction())
    }

    func testResetStartsCountingAgain() {
        var cap = AdFrequencyCap(every: 3)
        _ = cap.recordAction()
        _ = cap.recordAction()
        XCTAssertTrue(cap.recordAction())
        cap.reset()
        XCTAssertEqual(cap.actions, 0)
        XCTAssertFalse(cap.recordAction())
        XCTAssertFalse(cap.recordAction())
        XCTAssertTrue(cap.recordAction())
    }

    /// Реклама положена, но ролик не был готов: она остаётся положенной и показывается при ближайшем действии
    func testAdStaysDueUntilItIsReset() {
        var cap = AdFrequencyCap(every: 2)
        _ = cap.recordAction()
        XCTAssertTrue(cap.recordAction())
        XCTAssertTrue(cap.recordAction(), "без reset() реклама остаётся положенной")
        XCTAssertTrue(cap.recordAction())
    }

    func testEveryIsNeverBelowOne() {
        var cap = AdFrequencyCap(every: 0)
        XCTAssertEqual(cap.every, 1)
        XCTAssertTrue(cap.recordAction())
        var negative = AdFrequencyCap(every: -5)
        XCTAssertEqual(negative.every, 1)
        XCTAssertTrue(negative.recordAction())
    }
}

// MARK: - Паузы между повторными запросами

final class AdRetryPolicyTests: XCTestCase {
    func testDelaysGrowWithEachFailure() {
        var previous: TimeInterval = 0
        for failures in 1...AdRetryPolicy.delays.count {
            let delay = AdRetryPolicy.delay(afterFailures: failures)
            XCTAssertGreaterThan(delay, previous, "пауза после \(failures)-й неудачи должна быть длиннее предыдущей")
            previous = delay
        }
    }

    func testDelayIsCappedAtTheLastValue() {
        let last = AdRetryPolicy.delays[AdRetryPolicy.delays.count - 1]
        XCTAssertEqual(AdRetryPolicy.delay(afterFailures: AdRetryPolicy.delays.count + 1), last)
        XCTAssertEqual(AdRetryPolicy.delay(afterFailures: 1_000), last)
    }

    func testNonPositiveFailureCountUsesTheFirstDelay() {
        XCTAssertEqual(AdRetryPolicy.delay(afterFailures: 0), AdRetryPolicy.delays[0])
        XCTAssertEqual(AdRetryPolicy.delay(afterFailures: -3), AdRetryPolicy.delays[0])
    }

    func testRetryNeverBecomesALoopOfRequests() {
        XCTAssertGreaterThanOrEqual(AdRetryPolicy.delays[0], 5, "первая пауза не короче 5 секунд")
    }
}

// MARK: - Реклама внутри тестов отключена

@MainActor
final class YandexAdManagerTests: XCTestCase {
    /// Юнит-тесты запускаются внутри приложения: SDK рекламы не должен стартовать и ходить в сеть
    func testAdsAreDisabledInsideUnitTests() {
        XCTAssertTrue(YandexAdManager.isDisabledForTesting)
        XCTAssertFalse(YandexAdManager.shared.canShowAds)
        XCTAssertFalse(YandexAdManager.shared.canLoadBanners)
    }

    /// Награда не выдаётся, когда ролика нет: вызывается «недоступно», а не «награда»
    func testRewardedWithoutAdReportsUnavailable() {
        var rewarded = false
        var unavailable = false
        YandexAdManager.shared.showRewarded(
            onRewardConfirmed: { rewarded = true },
            onUnavailable: { unavailable = true }
        )
        XCTAssertFalse(rewarded)
        XCTAssertTrue(unavailable)
    }

    /// Без загруженной рекламы показ межстраничной не падает и ничего не делает
    func testInterstitialWithoutAdIsHarmless() {
        for _ in 0..<10 {
            YandexAdManager.shared.recordActionAndTriggerInterstitial()
        }
        YandexAdManager.shared.presentInterstitial()
        XCTAssertFalse(YandexAdManager.shared.isInterstitialLoaded)
    }

    func testAdUnitIdentifiersAreFilled() {
        XCTAssertFalse(YandexAdConfig.bannerUnitID.isEmpty)
        XCTAssertFalse(YandexAdConfig.interstitialUnitID.isEmpty)
        XCTAssertFalse(YandexAdConfig.rewardedUnitID.isEmpty)
        XCTAssertEqual(YandexAdConfig.bannerWidth, 320)
        XCTAssertEqual(YandexAdConfig.bannerHeight, 50)
    }
}

// MARK: - Info.plist: настройки для рекламы

final class AdInfoPlistTests: XCTestCase {
    private var skAdNetworkIdentifiers: [String] {
        let items = Bundle.main.object(forInfoDictionaryKey: "SKAdNetworkItems") as? [[String: String]] ?? []
        return items.compactMap { $0["SKAdNetworkIdentifier"] }
    }

    /// Без идентификаторов SKAdNetwork рекламодатели не могут засчитать установки, и доход от рекламы падает.
    /// Список взят у Яндекса целиком; ошибочные строки (опечатки, повторы) молча игнорируются системой, поэтому
    /// их ловит этот тест.
    func testSKAdNetworkListIsCompleteAndValid() {
        let ids = skAdNetworkIdentifiers
        XCTAssertGreaterThanOrEqual(ids.count, 200, "список SKAdNetwork Яндекса неполный")
        XCTAssertEqual(Set(ids).count, ids.count, "в списке SKAdNetwork есть повторы")
        for id in ids {
            XCTAssertNotNil(
                id.range(of: "^[a-z0-9]{10}\\.skadnetwork$", options: .regularExpression),
                "неверный формат идентификатора SKAdNetwork: \(id)"
            )
        }
        XCTAssertTrue(ids.contains("ydx93a7ass.skadnetwork"), "нет собственного идентификатора Яндекса")
    }

    /// Окно iOS с вопросом «Разрешить отслеживание?» не появится без текста объяснения
    func testTrackingPurposeStringIsDeclared() {
        let purpose = Bundle.main.object(forInfoDictionaryKey: "NSUserTrackingUsageDescription") as? String
        XCTAssertFalse((purpose ?? "").isEmpty, "в Info.plist нет NSUserTrackingUsageDescription")
    }
}
