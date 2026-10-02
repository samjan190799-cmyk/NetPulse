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

// MARK: - Покрытие сети на карте

private let coverageBase = Date(timeIntervalSince1970: 1_700_000_000)

/// Маршрут из точек с заданными задержками (мс; `nil` — узел не ответил): точки идут на север, по одной в `step` секунд
private func coverageRoute(
    latencies: [Double?],
    latitude: Double = 55.0,
    step: Double = 10,
    id: UUID = UUID()
) -> RouteRecord {
    let points = latencies.enumerated().map { index, latency in
        RoutePoint(
            time: coverageBase.addingTimeInterval(Double(index) * step),
            latitude: latitude + Double(index) * 0.0001,
            longitude: 37.0,
            latencyMs: latency,
            reachable: latency != nil
        )
    }
    return RouteRecord(id: id, startedAt: coverageBase, points: points)
}

final class HomeHaloTests: XCTestCase {
    func testIdleShowsLinkQuality() {
        XCTAssertEqual(HomeHalo.quality(isRecording: false, lastRecorded: .poor, link: .good), .good)
        XCTAssertEqual(HomeHalo.quality(isRecording: false, lastRecorded: nil, link: .dead), .dead)
    }

    func testRecordingPrefersTheLastRecordedPoint() {
        // Тот же цвет, что в карточке «Связь сейчас»: она тоже показывает оценку последней точки
        XCTAssertEqual(HomeHalo.quality(isRecording: true, lastRecorded: .poor, link: .good), .poor)
    }

    func testRecordingWithoutAPointYetFallsBackToTheLink() {
        XCTAssertEqual(HomeHalo.quality(isRecording: true, lastRecorded: nil, link: .fair), .fair)
    }

    func testNoVerdictMeansNoHalo() {
        XCTAssertNil(HomeHalo.quality(isRecording: false, lastRecorded: nil, link: nil))
        XCTAssertNil(HomeHalo.quality(isRecording: true, lastRecorded: nil, link: nil))
    }

    func testRecordedPointIsUsedEvenWithoutLinkVerdict() {
        XCTAssertEqual(HomeHalo.quality(isRecording: true, lastRecorded: .good, link: nil), .good)
    }
}

final class CoverageBuilderTests: XCTestCase {
    func testRunsFollowQualityChangesAlongTheRoute() {
        let route = coverageRoute(latencies: Array(repeating: 50, count: 5) + Array(repeating: 400, count: 5) + Array(repeating: 50, count: 5))
        let runs = CoverageBuilder.runs(from: [route], metric: .latency)
        XCTAssertEqual(runs.map(\.quality), [.good, .poor, .good])
    }

    func testDeadStretchBecomesItsOwnRun() {
        let route = coverageRoute(latencies: [50, 50, nil, nil, nil, 50, 50])
        let runs = CoverageBuilder.runs(from: [route], metric: .latency)
        XCTAssertTrue(runs.map(\.quality).contains(.dead), "Участок без сети пропал с карты: \(runs.map(\.quality))")
    }

    func testRunIdsAreUniqueAndStableBetweenCalls() {
        let route = coverageRoute(latencies: [50, 50, 400, 400, 50, 50])
        let first = CoverageBuilder.runs(from: [route], metric: .latency)
        let second = CoverageBuilder.runs(from: [route], metric: .latency)
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first.map(\.id)).count, first.count)
    }

    func testOlderRoutesAreDrawnFirstAndNewerOnTop() {
        let newer = coverageRoute(latencies: [50, 50, 50], latitude: 55.0)
        let older = coverageRoute(latencies: [50, 50, 50], latitude: 56.0)
        // Маршруты передаются новыми первыми, а рисуются в обратном порядке: новые поверх старых
        let runs = CoverageBuilder.runs(from: [newer, older], metric: .latency)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs.first?.path.first?.latitude ?? 0, 56.0, accuracy: 0.001)
        XCTAssertEqual(runs.last?.path.first?.latitude ?? 0, 55.0, accuracy: 0.001)
    }

    func testLimitKeepsNewestRoutesWhole() {
        let latencies: [Double?] = [50, 50, 400, 400]   // две полосы на маршрут
        let newest = coverageRoute(latencies: latencies, latitude: 55.0)
        let middle = coverageRoute(latencies: latencies, latitude: 56.0)
        let oldest = coverageRoute(latencies: latencies, latitude: 57.0)

        let runs = CoverageBuilder.runs(from: [newest, middle, oldest], metric: .latency, maxRuns: 5)
        XCTAssertEqual(runs.count, 4)
        XCTAssertFalse(runs.contains { $0.id.hasPrefix(oldest.id.uuidString) }, "Самый старый маршрут не должен попасть на карту")
        XCTAssertTrue(runs.contains { $0.id.hasPrefix(newest.id.uuidString) })
        XCTAssertTrue(runs.contains { $0.id.hasPrefix(middle.id.uuidString) })
    }

    func testNewestRouteIsCutWhenItAloneExceedsTheLimit() {
        let route = coverageRoute(latencies: [50, 50, 400, 400, 50, 50])   // три полосы
        let runs = CoverageBuilder.runs(from: [route], metric: .latency, maxRuns: 2)
        XCTAssertEqual(runs.map(\.quality), [.good, .poor])
    }

    func testRoutesWithoutAnyLineAreSkipped() {
        // Две точки с промежутком больше предела: линию между ними не проводим, полос нет
        let gap = coverageRoute(latencies: [50, 50], step: RouteAnalyzer.maxGapSeconds + 110)
        let normal = coverageRoute(latencies: [50, 50, 50], latitude: 56.0)
        let runs = CoverageBuilder.runs(from: [gap, normal], metric: .latency)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.path.first?.latitude ?? 0, 56.0, accuracy: 0.001)
        XCTAssertTrue(CoverageBuilder.runs(from: [], metric: .latency).isEmpty)
    }

    func testSpeedMetricShowsNothingWithoutSpeedMeasurements() {
        let route = coverageRoute(latencies: [50, 50, 50, 50])
        XCTAssertTrue(CoverageBuilder.runs(from: [route], metric: .speed).isEmpty)
        XCTAssertFalse(CoverageBuilder.runs(from: [route], metric: .latency).isEmpty)
    }

    func testLongRunIsThinned() {
        let route = coverageRoute(latencies: Array(repeating: 50, count: 300), step: 5)
        let runs = CoverageBuilder.runs(from: [route], metric: .latency)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.path.count, CoverageBuilder.maxPathPoints)
    }

    func testThinningKeepsEndsOrderAndLimit() {
        let path = (0..<1000).map { GeoCoordinate(latitude: 55.0 + Double($0) * 0.00001, longitude: 37.0) }
        let thinned = CoverageBuilder.thinned(path, limit: 80)
        XCTAssertEqual(thinned.count, 80)
        XCTAssertEqual(thinned.first, path.first)
        XCTAssertEqual(thinned.last, path.last)
        XCTAssertTrue(zip(thinned, thinned.dropFirst()).allSatisfy { $0.latitude < $1.latitude }, "Порядок точек нарушен")
    }

    func testThinningLeavesShortPathsAndNeverDropsBelowTwoPoints() {
        let short = (0..<5).map { GeoCoordinate(latitude: 55.0 + Double($0) * 0.0001, longitude: 37.0) }
        XCTAssertEqual(CoverageBuilder.thinned(short, limit: 80), short)

        let long = (0..<50).map { GeoCoordinate(latitude: 55.0 + Double($0) * 0.0001, longitude: 37.0) }
        let tiny = CoverageBuilder.thinned(long, limit: 0)
        XCTAssertEqual(tiny.count, 2)
        XCTAssertEqual(tiny.first, long.first)
        XCTAssertEqual(tiny.last, long.last)
    }
}
