//
//  TripTests.swift
//  NetPulseTests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest
@testable import NetPulse

// MARK: - Подготовка данных

private let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

/// Прошлый маршрут строго на север вдоль долготы `longitude`: точки через 0,0002° (около 22 м) с интервалом 5 секунд.
/// Точки из `weak` — без связи (`dead`) или с большой задержкой (`poor`), остальные хорошие.
private func makeRoute(
    startLatitude: Double = 55.0,
    longitude: Double = 37.0,
    count: Int = 40,
    weak: ClosedRange<Int>? = nil,
    dead: Bool = true,
    id: UUID = UUID()
) -> RouteRecord {
    var points: [RoutePoint] = []
    for index in 0..<count {
        let isWeak = weak?.contains(index) ?? false
        points.append(RoutePoint(
            time: baseTime.addingTimeInterval(Double(index) * 5),
            latitude: startLatitude + Double(index) * 0.0002,
            longitude: longitude,
            speedMps: 10,
            latencyMs: isWeak ? (dead ? nil : 400) : 40,
            reachable: !(isWeak && dead),
            link: .lte
        ))
    }
    return RouteRecord(id: id, startedAt: baseTime, endedAt: points.last?.time, points: points)
}

private let origin = GeoCoordinate(latitude: 55.0, longitude: 37.0)

// MARK: - Поиск слабой связи впереди

final class TripAdvisorTests: XCTestCase {

    /// Слабый участок: точки 20…25, то есть широта 55,0040…55,0050 (от 445 до 556 м к северу от начала)
    private func advisorWithStretch(dead: Bool = true) -> TripAdvisor {
        TripAdvisor(routes: [makeRoute(weak: 20...25, dead: dead)])
    }

    func testWarnsAboutADeadStretchAhead() throws {
        let warning = try XCTUnwrap(advisorWithStretch().warning(at: origin, headingDegrees: 0, speedMps: 10))
        XCTAssertEqual(warning.quality, .dead)
        XCTAssertEqual(warning.distanceMeters, 445, accuracy: 6)
        XCTAssertEqual(warning.routeCount, 1)
    }

    func testPoorStretchIsReportedAsPoor() throws {
        let warning = try XCTUnwrap(advisorWithStretch(dead: false).warning(at: origin, headingDegrees: 0, speedMps: 10))
        XCTAssertEqual(warning.quality, .poor)
    }

    func testNoWarningWhenMovingAwayFromTheStretch() {
        XCTAssertNil(advisorWithStretch().warning(at: origin, headingDegrees: 180, speedMps: 10))
        XCTAssertNil(advisorWithStretch().warning(at: origin, headingDegrees: 90, speedMps: 10), "Строго на восток: участок остаётся сбоку")
    }

    func testStretchBehindIsIgnored() {
        let passed = GeoCoordinate(latitude: 55.0060, longitude: 37.0)
        XCTAssertNil(advisorWithStretch().warning(at: passed, headingDegrees: 0, speedMps: 10))
    }

    func testParallelRoadFarToTheSideDoesNotWarn() {
        // 0,004° долготы на этой широте около 255 м: дальше допустимых 150 м от линии движения
        let side = GeoCoordinate(latitude: 55.0, longitude: 37.004)
        XCTAssertNil(advisorWithStretch().warning(at: side, headingDegrees: 0, speedMps: 10))
    }

    func testRoadWithinTheCorridorStillWarns() {
        // 0,001° долготы около 64 м: в пределах коридора
        let near = GeoCoordinate(latitude: 55.0, longitude: 37.001)
        XCTAssertNotNil(advisorWithStretch().warning(at: near, headingDegrees: 0, speedMps: 10))
    }

    func testStandingOrCrawlingMeansNoWarning() {
        XCTAssertNil(advisorWithStretch().warning(at: origin, headingDegrees: 0, speedMps: 0.5))
        XCTAssertNil(advisorWithStretch().warning(at: origin, headingDegrees: 0, speedMps: 0))
        XCTAssertNil(advisorWithStretch().warning(at: origin, headingDegrees: 0, speedMps: .nan))
        XCTAssertNil(advisorWithStretch().warning(at: origin, headingDegrees: .nan, speedMps: 10))
    }

    func testAlreadyInAWeakPlaceMeansNothingToWarnAbout() {
        XCTAssertNil(advisorWithStretch().warning(at: origin, headingDegrees: 0, speedMps: 10, currentQuality: .dead))
        XCTAssertNil(advisorWithStretch().warning(at: origin, headingDegrees: 0, speedMps: 10, currentQuality: .poor))
        XCTAssertNotNil(advisorWithStretch().warning(at: origin, headingDegrees: 0, speedMps: 10, currentQuality: .fair))
    }

    func testTooCloseIsAlreadyUnderYourFeet() {
        // Участок из двух точек (55,0040 и 55,0042); мы в 11 и 33 м от них: ближе допустимых 80 м
        let advisor = TripAdvisor(routes: [makeRoute(weak: 20...21)])
        let almostThere = GeoCoordinate(latitude: 55.0039, longitude: 37.0)
        XCTAssertNil(advisor.warning(at: almostThere, headingDegrees: 0, speedMps: 10))
    }

    func testLookAheadDependsOnSpeed() throws {
        // Участок в 2,2 км: при 10 м/с смотрим на 1,2 км, при 30 м/с на 3 км
        let far = TripAdvisor(routes: [makeRoute(startLatitude: 55.0, count: 120, weak: 100...105)])
        XCTAssertNil(far.warning(at: origin, headingDegrees: 0, speedMps: 10))
        XCTAssertNotNil(far.warning(at: origin, headingDegrees: 0, speedMps: 30))
    }

    func testLookAheadIsClamped() {
        XCTAssertEqual(TripAdvisor.lookAheadMeters(speedMps: 0.5), TripAdvisor.minLookAheadMeters)
        XCTAssertEqual(TripAdvisor.lookAheadMeters(speedMps: 10), 1_200)
        XCTAssertEqual(TripAdvisor.lookAheadMeters(speedMps: 100), TripAdvisor.maxLookAheadMeters)
        XCTAssertEqual(TripAdvisor.lookAheadMeters(speedMps: -4), TripAdvisor.minLookAheadMeters)
        XCTAssertEqual(TripAdvisor.lookAheadMeters(speedMps: .nan), TripAdvisor.minLookAheadMeters)
    }

    // MARK: Что считается слабым участком

    func testOneWeakPointIsJustAGlitch() {
        let advisor = TripAdvisor(routes: [makeRoute(weak: 20...20)])
        XCTAssertTrue(advisor.isEmpty)
        XCTAssertNil(advisor.warning(at: origin, headingDegrees: 0, speedMps: 10))
    }

    func testTwoWeakPointsInARowMakeAStretch() {
        let advisor = TripAdvisor(routes: [makeRoute(weak: 20...21)])
        XCTAssertFalse(advisor.isEmpty)
        XCTAssertEqual(advisor.weakPointCount, 2)
    }

    func testAPauseInTheRouteSplitsTheStretch() {
        // Две слабые точки, но между ними 200 секунд без записи: это не один участок
        var route = makeRoute(weak: 20...21)
        route.points[21].time = route.points[20].time.addingTimeInterval(200)
        XCTAssertTrue(TripAdvisor(routes: [route]).isEmpty)
    }

    func testGoodPointBetweenWeakOnesSplitsTheStretch() {
        var route = makeRoute(count: 40)
        for index in [20, 22] {
            route.points[index].reachable = false
            route.points[index].latencyMs = nil
        }
        XCTAssertTrue(TripAdvisor(routes: [route]).isEmpty)
    }

    func testStretchIsCountedOnEveryRouteThatHasIt() throws {
        let advisor = TripAdvisor(routes: [makeRoute(weak: 20...25), makeRoute(weak: 21...24)])
        let warning = try XCTUnwrap(advisor.warning(at: origin, headingDegrees: 0, speedMps: 10))
        XCTAssertEqual(warning.routeCount, 2)
    }

    func testWorstQualityOfTheNearbyCluster() throws {
        // Сначала плохая связь, через сто метров её нет совсем: в предупреждении худшее
        var route = makeRoute(count: 40)
        for index in 20...21 {
            route.points[index].latencyMs = 400
        }
        for index in 24...25 {
            route.points[index].reachable = false
            route.points[index].latencyMs = nil
        }
        let warning = try XCTUnwrap(TripAdvisor(routes: [route]).warning(at: origin, headingDegrees: 0, speedMps: 10))
        XCTAssertEqual(warning.quality, .dead)
    }

    func testBrokenCoordinatesDoNotBreakTheIndex() {
        var route = makeRoute(weak: 20...25)
        route.points[20].latitude = .nan
        route.points[21].longitude = 999
        route.points[22].latitude = .infinity
        let advisor = TripAdvisor(routes: [route])
        // Остаются точки 23…25: три подряд
        XCTAssertEqual(advisor.weakPointCount, 3)
        XCTAssertNil(advisor.warning(at: GeoCoordinate(latitude: .nan, longitude: 37), headingDegrees: 0, speedMps: 10))
    }

    func testEmptyHistoryHasNothingToWarnAbout() {
        let advisor = TripAdvisor(routes: [])
        XCTAssertTrue(advisor.isEmpty)
        XCTAssertNil(advisor.warning(at: origin, headingDegrees: 0, speedMps: 10))
    }

    func testRouteWithSinglePointIsSkipped() {
        let single = RouteRecord(points: [RoutePoint(time: baseTime, latitude: 55, longitude: 37, latencyMs: nil, reachable: false)])
        XCTAssertTrue(TripAdvisor(routes: [single]).isEmpty)
    }
}

// MARK: - Направление и скорость по точкам записи

final class TripMovementTests: XCTestCase {

    private func points(latitudeStep: Double, longitudeStep: Double, count: Int = 4, seconds: TimeInterval = 5) -> [RoutePoint] {
        (0..<count).map { index in
            RoutePoint(
                time: baseTime.addingTimeInterval(Double(index) * seconds),
                latitude: 55.0 + Double(index) * latitudeStep,
                longitude: 37.0 + Double(index) * longitudeStep,
                speedMps: nil
            )
        }
    }

    func testHeadingNorth() throws {
        let heading = try XCTUnwrap(TripAdvisor.heading(from: points(latitudeStep: 0.0004, longitudeStep: 0)))
        XCTAssertEqual(heading, 0, accuracy: 1)
    }

    func testHeadingEastAndSouthWest() throws {
        let east = try XCTUnwrap(TripAdvisor.heading(from: points(latitudeStep: 0, longitudeStep: 0.0008)))
        XCTAssertEqual(east, 90, accuracy: 1)

        // Одинаковые метры на юг и на запад: на широте 55° градус долготы вдвое короче градуса широты
        let southWest = try XCTUnwrap(TripAdvisor.heading(from: points(latitudeStep: -0.0004, longitudeStep: -0.0004 / cos(55.0 * .pi / 180))))
        XCTAssertEqual(southWest, 225, accuracy: 2)
    }

    func testNoHeadingWhenBarelyMoved() {
        // Три точки в пределах 20 м: направление не определить
        XCTAssertNil(TripAdvisor.heading(from: points(latitudeStep: 0.00005, longitudeStep: 0)))
    }

    func testNoHeadingFromOnePointOrNone() {
        XCTAssertNil(TripAdvisor.heading(from: []))
        XCTAssertNil(TripAdvisor.heading(from: points(latitudeStep: 0.0004, longitudeStep: 0, count: 1)))
    }

    func testNoHeadingAcrossALongPause() {
        // Между точками пять минут: прежнее направление уже ничего не говорит
        XCTAssertNil(TripAdvisor.heading(from: points(latitudeStep: 0.0004, longitudeStep: 0, count: 2, seconds: 300)))
    }

    func testSpeedPrefersTheBiggerOfReportedAndMeasured() throws {
        // Геолокация сообщает 0 м/с, а за 5 секунд телефон прошёл около 44 м: считаем по точкам
        var track = points(latitudeStep: 0.0004, longitudeStep: 0, count: 2)
        track[1].speedMps = 0
        let measured = try XCTUnwrap(TripAdvisor.speed(from: track))
        XCTAssertEqual(measured, 8.9, accuracy: 0.5)

        track[1].speedMps = 14
        XCTAssertEqual(try XCTUnwrap(TripAdvisor.speed(from: track)), 14, accuracy: 0.001)
    }

    func testSpeedIsUnknownWithoutData() {
        XCTAssertNil(TripAdvisor.speed(from: []))
        XCTAssertNil(TripAdvisor.speed(from: points(latitudeStep: 0.0004, longitudeStep: 0, count: 1)))
        // Две точки с паузой дольше допустимой: скорость между ними ни о чём не говорит
        XCTAssertNil(TripAdvisor.speed(from: points(latitudeStep: 0.0004, longitudeStep: 0, count: 2, seconds: 300)))
    }
}

// MARK: - Когда сообщать

final class TripAnnouncerTests: XCTestCase {

    private func warning(_ key: String) -> TripWarning {
        TripWarning(quality: .dead, distanceMeters: 500, routeCount: 1, zoneKey: key)
    }

    func testFirstWarningIsAnnounced() {
        var announcer = TripAnnouncer()
        XCTAssertTrue(announcer.shouldAnnounce(warning("a"), now: baseTime))
    }

    func testSameStretchIsNotRepeatedSoon() {
        var announcer = TripAnnouncer()
        XCTAssertTrue(announcer.shouldAnnounce(warning("a"), now: baseTime))
        XCTAssertFalse(announcer.shouldAnnounce(warning("a"), now: baseTime.addingTimeInterval(60)))
        XCTAssertFalse(announcer.shouldAnnounce(warning("a"), now: baseTime.addingTimeInterval(TripAnnouncer.sameZoneInterval - 1)))
        XCTAssertTrue(announcer.shouldAnnounce(warning("a"), now: baseTime.addingTimeInterval(TripAnnouncer.sameZoneInterval)))
    }

    func testAnotherStretchWaitsForTheMinimumInterval() {
        var announcer = TripAnnouncer()
        XCTAssertTrue(announcer.shouldAnnounce(warning("a"), now: baseTime))
        XCTAssertFalse(announcer.shouldAnnounce(warning("b"), now: baseTime.addingTimeInterval(TripAnnouncer.minimumInterval - 1)))
        XCTAssertTrue(announcer.shouldAnnounce(warning("b"), now: baseTime.addingTimeInterval(TripAnnouncer.minimumInterval)))
    }

    func testResetForgetsEverything() {
        var announcer = TripAnnouncer()
        XCTAssertTrue(announcer.shouldAnnounce(warning("a"), now: baseTime))
        announcer.reset()
        XCTAssertTrue(announcer.shouldAnnounce(warning("a"), now: baseTime.addingTimeInterval(1)))
    }

    func testClockMovedBackwardsDoesNotMuteTheWarnings() {
        var announcer = TripAnnouncer()
        XCTAssertTrue(announcer.shouldAnnounce(warning("a"), now: baseTime))
        XCTAssertTrue(announcer.shouldAnnounce(warning("a"), now: baseTime.addingTimeInterval(-3_600)))
    }
}

// MARK: - Тексты предупреждения

final class TripWarningTextTests: XCTestCase {

    func testTitleDependsOnQuality() {
        XCTAssertEqual(TripWarning(quality: .dead, distanceMeters: 500, routeCount: 1, zoneKey: "k").title, "Впереди может пропасть связь")
        XCTAssertEqual(TripWarning(quality: .poor, distanceMeters: 500, routeCount: 1, zoneKey: "k").title, "Впереди слабая связь")
    }

    func testDistanceIsRoundedForReading() {
        func rounded(_ meters: Double) -> Double {
            TripWarning(quality: .poor, distanceMeters: meters, routeCount: 1, zoneKey: "k").roundedDistanceMeters
        }
        XCTAssertEqual(rounded(437), 450)
        XCTAssertEqual(rounded(81), 100)
        XCTAssertEqual(rounded(20), 50, "Меньше шага округления не бывает: «через 0 м» никому не нужно")
        XCTAssertEqual(rounded(1_234), 1_200)
        XCTAssertEqual(rounded(2_960), 3_000)
    }

    func testDetailNamesTheDistanceAndTheSource() {
        let detail = TripWarning(quality: .dead, distanceMeters: 437, routeCount: 2, zoneKey: "k").detail
        XCTAssertTrue(detail.contains("450 м"))
        XCTAssertTrue(detail.contains("по вашим прошлым поездкам"))
    }
}
