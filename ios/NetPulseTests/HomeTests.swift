//
//  HomeTests.swift
//  NetPulseTests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest
@testable import NetPulse

// MARK: - Жесты нижней панели

final class HomePanelLayoutTests: XCTestCase {
    func testShortGestureKeepsPosition() {
        XCTAssertEqual(HomePanelLayout.detent(from: .medium, predictedTranslation: -30), .medium)
        XCTAssertEqual(HomePanelLayout.detent(from: .expanded, predictedTranslation: 30), .expanded)
        XCTAssertEqual(HomePanelLayout.detent(from: .medium, predictedTranslation: 0), .medium)
    }

    func testLongSwipeUpExpandsAndLongSwipeDownCollapses() {
        XCTAssertEqual(HomePanelLayout.detent(from: .medium, predictedTranslation: -200), .expanded)
        XCTAssertEqual(HomePanelLayout.detent(from: .expanded, predictedTranslation: 200), .medium)
    }

    func testSwipeInTheSameDirectionDoesNotChangeAnything() {
        XCTAssertEqual(HomePanelLayout.detent(from: .expanded, predictedTranslation: -200), .expanded)
        XCTAssertEqual(HomePanelLayout.detent(from: .medium, predictedTranslation: 200), .medium)
    }

    func testThresholdIsInclusive() {
        let threshold = HomePanelLayout.switchThreshold
        XCTAssertEqual(HomePanelLayout.detent(from: .medium, predictedTranslation: -threshold), .expanded)
        XCTAssertEqual(HomePanelLayout.detent(from: .expanded, predictedTranslation: threshold), .medium)
        XCTAssertEqual(HomePanelLayout.detent(from: .medium, predictedTranslation: -(threshold - 1)), .medium)
    }

    func testHeightFollowsFingerWithinLimits() {
        XCTAssertEqual(HomePanelLayout.height(base: 250, translation: -100, lower: 250, upper: 600), 350, accuracy: 0.001)
        // Потянули вниз уже свёрнутую панель — ниже нижнего предела она не опускается
        XCTAssertEqual(HomePanelLayout.height(base: 250, translation: 80, lower: 250, upper: 600), 250, accuracy: 0.001)
        XCTAssertEqual(HomePanelLayout.height(base: 250, translation: -900, lower: 250, upper: 600), 600, accuracy: 0.001)
        XCTAssertEqual(HomePanelLayout.height(base: 600, translation: 100, lower: 250, upper: 600), 500, accuracy: 0.001)
    }

    func testHeightOnVeryLowScreenNeverDropsBelowTheLowerLimit() {
        // Верхний предел меньше нижнего: панель остаётся нижней высоты
        XCTAssertEqual(HomePanelLayout.height(base: 300, translation: 0, lower: 300, upper: 200), 300, accuracy: 0.001)
    }
}

// MARK: - Связь сейчас

final class HomeLinkStatusTests: XCTestCase {
    func testOfflineIsDeadWithOrWithoutPing() {
        XCTAssertEqual(HomeLinkStatus.quality(isOnline: false, pingMs: nil), .dead)
        XCTAssertEqual(HomeLinkStatus.quality(isOnline: false, pingMs: 20), .dead)
    }

    func testNoPingMeansNoVerdict() {
        XCTAssertNil(HomeLinkStatus.quality(isOnline: true, pingMs: nil))
    }

    func testPingThresholdsMatchRouteQuality() {
        XCTAssertEqual(HomeLinkStatus.quality(isOnline: true, pingMs: 40), .good)
        XCTAssertEqual(HomeLinkStatus.quality(isOnline: true, pingMs: RouteQuality.goodMaxLatencyMs), .good)
        XCTAssertEqual(HomeLinkStatus.quality(isOnline: true, pingMs: RouteQuality.goodMaxLatencyMs + 1), .fair)
        XCTAssertEqual(HomeLinkStatus.quality(isOnline: true, pingMs: RouteQuality.fairMaxLatencyMs), .fair)
        XCTAssertEqual(HomeLinkStatus.quality(isOnline: true, pingMs: RouteQuality.fairMaxLatencyMs + 1), .poor)
    }

    func testLiveTitlesAreDistinct() {
        let titles = RouteQuality.allCases.map { $0.liveTitle }
        XCTAssertEqual(Set(titles).count, RouteQuality.allCases.count)
        XCTAssertEqual(RouteQuality.good.liveTitle, "Связь хорошая")
        XCTAssertEqual(RouteQuality.dead.liveTitle, "Нет связи")
    }
}

// MARK: - На что хватает сети

final class CapabilityTagsTests: XCTestCase {
    private func tags(download: Double, upload: Double, ping: Double?, jitter: Double? = 2) -> [String] {
        let items = NetworkCapabilityEvaluator(
            downloadMbps: download,
            uploadMbps: upload,
            pingMs: ping,
            jitterMs: jitter
        ).evaluateAll()
        return CapabilityTags.summary(items)
    }

    func testFastNetworkCoversEverything() {
        XCTAssertEqual(tags(download: 300, upload: 50, ping: 12), ["4K", "игры", "звонки"])
    }

    func testMediumNetworkStillCoversTheBasics() {
        XCTAssertEqual(tags(download: 40, upload: 8, ping: 40, jitter: 3), ["4K", "игры", "звонки"])
    }

    func testSlowNetworkHasNoTags() {
        XCTAssertEqual(tags(download: 3, upload: 0.5, ping: 200), [])
    }

    func testNoMeasurementGivesNoTags() {
        // Замера не было: «не измерено» не считается «хорошо»
        XCTAssertEqual(tags(download: 0, upload: 0, ping: nil), [])
    }

    func testGoodMediaWithoutFourKGetsGenericTag() {
        let item = CapabilityItem(title: "Стриминг HD", category: "Медиа", icon: "tv", level: .good, description: "", detail: "")
        XCTAssertEqual(CapabilityTags.summary([item]), ["видео"])
    }

    func testWeakLevelsAndUnknownCategoriesAreIgnored() {
        let weak = CapabilityItem(title: "Игры", category: "Гейминг", icon: "x", level: .moderate, description: "", detail: "")
        let other = CapabilityItem(title: "Что-то", category: "Другое", icon: "x", level: .excellent, description: "", detail: "")
        XCTAssertEqual(CapabilityTags.summary([weak, other]), [])
    }
}

// MARK: - Подписи

final class RussianPluralTests: XCTestCase {
    private func place(_ number: Int) -> String {
        RussianPlural.form(number, one: "место", few: "места", many: "мест")
    }

    func testBasicForms() {
        XCTAssertEqual(place(1), "место")
        XCTAssertEqual(place(2), "места")
        XCTAssertEqual(place(4), "места")
        XCTAssertEqual(place(5), "мест")
        XCTAssertEqual(place(0), "мест")
    }

    func testTeensAreAlwaysMany() {
        for number in [11, 12, 13, 14, 111, 112, 214] {
            XCTAssertEqual(place(number), "мест", "\(number)")
        }
    }

    func testCompoundNumbers() {
        XCTAssertEqual(place(21), "место")
        XCTAssertEqual(place(22), "места")
        XCTAssertEqual(place(25), "мест")
        XCTAssertEqual(place(101), "место")
    }
}

final class SpokenDurationTests: XCTestCase {
    func testSecondsMinutesAndHours() {
        XCTAssertEqual(RouteFormat.spokenDuration(0), "0 с")
        XCTAssertEqual(RouteFormat.spokenDuration(45), "45 с")
        XCTAssertEqual(RouteFormat.spokenDuration(60), "1 мин")
        XCTAssertEqual(RouteFormat.spokenDuration(134), "2 мин 14 с")
        XCTAssertEqual(RouteFormat.spokenDuration(3600), "1 ч 00 мин")
        XCTAssertEqual(RouteFormat.spokenDuration(3905), "1 ч 05 мин")
    }

    func testRoundingAndNegativeValues() {
        XCTAssertEqual(RouteFormat.spokenDuration(59.6), "1 мин")
        XCTAssertEqual(RouteFormat.spokenDuration(-5), "0 с")
    }
}

final class RouteTitleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private let locale = Locale(identifier: "ru_RU")
    /// 2 октября 2026, 18:40 по UTC
    private let start = Date(timeIntervalSince1970: 1_790_966_400)

    private func title(of route: RouteRecord, daysLater: Double = 0, hoursLater: Double = 1) -> String {
        let now = start.addingTimeInterval(daysLater * 24 * 3600 + hoursLater * 3600)
        return RouteTitle.dateRange(of: route, now: now, calendar: calendar, locale: locale)
    }

    func testTodayRouteShowsTimeRange() {
        let route = RouteRecord(startedAt: start, endedAt: start.addingTimeInterval(28 * 60))
        XCTAssertEqual(title(of: route), "Сегодня, 18:40 — 19:08")
    }

    func testYesterdayRoute() {
        let route = RouteRecord(startedAt: start, endedAt: start.addingTimeInterval(28 * 60))
        XCTAssertEqual(title(of: route, daysLater: 1), "Вчера, 18:40 — 19:08")
    }

    func testOlderRouteShowsTheDay() {
        let route = RouteRecord(startedAt: start, endedAt: start.addingTimeInterval(28 * 60))
        let result = title(of: route, daysLater: 5)
        XCTAssertTrue(result.hasPrefix("2 окт"), result)
        XCTAssertTrue(result.hasSuffix("18:40 — 19:08"), result)
    }

    func testRouteWithoutEndShowsOnlyTheStart() {
        let route = RouteRecord(startedAt: start, endedAt: nil, points: [])
        XCTAssertEqual(title(of: route), "Сегодня, 18:40")
    }

    func testEndFallsBackToTheLastPoint() {
        let point = RoutePoint(time: start.addingTimeInterval(600), latitude: 55, longitude: 37)
        let route = RouteRecord(startedAt: start, endedAt: nil, points: [point])
        XCTAssertEqual(title(of: route), "Сегодня, 18:40 — 18:50")
    }
}
