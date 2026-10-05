//
//  RouteTests.swift
//  NetPulseTests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest
@testable import NetPulse

// MARK: - Вспомогательные функции

private let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

/// Точка маршрута через `seconds` секунд от начала. Без явных координат телефон «едет» на север:
/// 0,0001° широты в секунду, то есть около 11 м/с.
private func point(
    at seconds: Double,
    latency: Double? = 50,
    reachable: Bool = true,
    download: Double? = nil,
    lat: Double? = nil,
    lon: Double? = nil
) -> RoutePoint {
    RoutePoint(
        time: baseTime.addingTimeInterval(seconds),
        latitude: lat ?? (55.0 + seconds * 0.0001),
        longitude: lon ?? 37.0,
        accuracy: 8,
        speedMps: 11,
        latencyMs: reachable ? latency : nil,
        reachable: reachable,
        link: reachable ? .lte : .offline,
        downloadMbps: download
    )
}

// MARK: - Вид связи

final class LinkKindTests: XCTestCase {
    func testRadioTechnologyNamesMapToGenerations() {
        let expected: [String: LinkKind] = [
            "CTRadioAccessTechnologyNR": .g5,
            "CTRadioAccessTechnologyNRNSA": .g5,
            "CTRadioAccessTechnologyLTE": .lte,
            "CTRadioAccessTechnologyWCDMA": .g3,
            "CTRadioAccessTechnologyHSDPA": .g3,
            "CTRadioAccessTechnologyHSUPA": .g3,
            "CTRadioAccessTechnologyeHRPD": .g3,
            "CTRadioAccessTechnologyCDMAEVDORev0": .g3,
            "CTRadioAccessTechnologyEdge": .g2,
            "CTRadioAccessTechnologyGPRS": .g2,
            "CTRadioAccessTechnologyCDMA1x": .g2,
            "что-то новое": .cellular
        ]
        for (name, kind) in expected {
            XCTAssertEqual(LinkKind.fromRadioTechnology(name), kind, name)
        }
    }

    func testDetectUsesPathAndRadioTechnology() {
        XCTAssertEqual(
            LinkKind.detect(isSatisfied: false, usesWifi: true, usesCellular: false, usesWired: false, radioTechnology: nil),
            .offline,
            "Путь без связи — это «нет сети», даже если интерфейс Wi-Fi числится"
        )
        XCTAssertEqual(
            LinkKind.detect(isSatisfied: true, usesWifi: true, usesCellular: false, usesWired: false, radioTechnology: nil),
            .wifi
        )
        XCTAssertEqual(
            LinkKind.detect(isSatisfied: true, usesWifi: false, usesCellular: false, usesWired: true, radioTechnology: nil),
            .ethernet
        )
        XCTAssertEqual(
            LinkKind.detect(isSatisfied: true, usesWifi: false, usesCellular: true, usesWired: false, radioTechnology: "CTRadioAccessTechnologyNR"),
            .g5
        )
        XCTAssertEqual(
            LinkKind.detect(isSatisfied: true, usesWifi: false, usesCellular: true, usesWired: false, radioTechnology: nil),
            .cellular
        )
        XCTAssertEqual(
            LinkKind.detect(isSatisfied: true, usesWifi: false, usesCellular: false, usesWired: false, radioTechnology: nil),
            .other
        )
    }
}

// MARK: - Качество

final class RouteQualityTests: XCTestCase {
    func testLatencyBoundaries() {
        XCTAssertEqual(RouteQuality.byLatency(reachable: true, latencyMs: 120), .good)
        XCTAssertEqual(RouteQuality.byLatency(reachable: true, latencyMs: 120.1), .fair)
        XCTAssertEqual(RouteQuality.byLatency(reachable: true, latencyMs: 300), .fair)
        XCTAssertEqual(RouteQuality.byLatency(reachable: true, latencyMs: 300.1), .poor)
    }

    func testUnreachableIsDeadAndMissingLatencyIsNotInvented() {
        XCTAssertEqual(RouteQuality.byLatency(reachable: false, latencyMs: nil), .dead)
        XCTAssertEqual(RouteQuality.byLatency(reachable: false, latencyMs: 20), .dead, "Нет ответа важнее любой задержки")
        XCTAssertEqual(RouteQuality.byLatency(reachable: true, latencyMs: nil), .fair)
    }

    func testSpeedBoundariesAndMissingMeasurement() {
        XCTAssertEqual(RouteQuality.bySpeed(reachable: true, downloadMbps: 5), .good)
        XCTAssertEqual(RouteQuality.bySpeed(reachable: true, downloadMbps: 4.9), .fair)
        XCTAssertEqual(RouteQuality.bySpeed(reachable: true, downloadMbps: 1), .fair)
        XCTAssertEqual(RouteQuality.bySpeed(reachable: true, downloadMbps: 0.99), .poor)
        XCTAssertNil(RouteQuality.bySpeed(reachable: true, downloadMbps: nil), "Нет замера — нет оценки, а не «плохо»")
        XCTAssertNil(RouteQuality.bySpeed(reachable: true, downloadMbps: 0))
        XCTAssertEqual(RouteQuality.bySpeed(reachable: false, downloadMbps: nil), .dead)
    }

    func testOverallTakesWorstOfLatencyAndSpeed() {
        XCTAssertEqual(RouteQuality.overall(reachable: true, latencyMs: 50, downloadMbps: 0.5), .poor)
        XCTAssertEqual(RouteQuality.overall(reachable: true, latencyMs: 400, downloadMbps: 50), .poor)
        XCTAssertEqual(RouteQuality.overall(reachable: true, latencyMs: 50, downloadMbps: nil), .good)
        XCTAssertEqual(RouteQuality.overall(reachable: false, latencyMs: nil, downloadMbps: nil), .dead)
    }

    func testQualitiesAreOrderedFromBestToWorst() {
        XCTAssertTrue(RouteQuality.good < .fair)
        XCTAssertTrue(RouteQuality.fair < .poor)
        XCTAssertTrue(RouteQuality.poor < .dead)
        XCTAssertEqual(RouteQuality.allCases.max(), .dead)
    }
}

// MARK: - Расстояния и подписи

final class GeoAndFormatTests: XCTestCase {
    func testDistanceBetweenKnownPoints() {
        let origin = GeoCoordinate(latitude: 0, longitude: 0)
        XCTAssertEqual(origin.distance(to: origin), 0, accuracy: 0.001)
        XCTAssertEqual(origin.distance(to: GeoCoordinate(latitude: 0, longitude: 1)), 111_195, accuracy: 200)

        let moscow = GeoCoordinate(latitude: 55.7558, longitude: 37.6173)
        let petersburg = GeoCoordinate(latitude: 59.9343, longitude: 30.3351)
        XCTAssertEqual(moscow.distance(to: petersburg), 634_000, accuracy: 6_000)
    }

    func testFormats() {
        XCTAssertEqual(RouteFormat.distance(850), "850 м")
        XCTAssertEqual(RouteFormat.distance(3400), "3.4 км")
        XCTAssertEqual(RouteFormat.duration(754), "12:34")
        XCTAssertEqual(RouteFormat.duration(3909), "1:05:09")
        XCTAssertEqual(RouteFormat.duration(-5), "0:00")
        XCTAssertEqual(RouteFormat.percent(0.42), "42 %")
        XCTAssertEqual(RouteFormat.latency(84.6), "85 мс")
        XCTAssertEqual(RouteFormat.speed(12.54), "12.5 Мбит/с")
    }
}

// MARK: - Участки, зоны без сети, сводка

final class RouteAnalyzerTests: XCTestCase {

    func testAdjacentSegmentsOfSameQualityAreMergedAndShareBoundary() {
        let points = [
            point(at: 0, latency: 50),
            point(at: 5, latency: 50),
            point(at: 10, latency: 50),
            point(at: 15, latency: 400),
            point(at: 20, latency: 400),
            point(at: 25, latency: 400)
        ]
        let segments = RouteAnalyzer.segments(for: points, metric: .latency)

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].quality, .good)
        XCTAssertEqual(segments[0].path.count, 3)
        XCTAssertEqual(segments[1].quality, .poor)
        // Линия нового цвета начинается там, где закончилась прежняя: на карте нет разрывов
        XCTAssertEqual(segments[1].path.count, 4)
        XCTAssertEqual(segments[1].path.first, points[2].coordinate)
    }

    func testLongGapBreaksTheLine() {
        let points = [
            point(at: 0),
            point(at: 5),
            point(at: 10),
            point(at: 210),
            point(at: 215)
        ]
        let segments = RouteAnalyzer.segments(for: points, metric: .latency)

        XCTAssertEqual(segments.count, 2, "Между точками 200 секунд: линия не проводится")
        XCTAssertEqual(segments[0].path.count, 3)
        XCTAssertEqual(segments[1].path.count, 2)
    }

    func testTooFewPointsGiveNoSegments() {
        XCTAssertTrue(RouteAnalyzer.segments(for: [], metric: .latency).isEmpty)
        XCTAssertTrue(RouteAnalyzer.segments(for: [point(at: 0)], metric: .latency).isEmpty)
    }

    func testMeasuredSpeedIsCarriedToNextPointsOnlyForALimitedTime() {
        var points: [RoutePoint] = []
        for index in 0...10 {
            points.append(point(at: Double(index) * 5, download: index == 0 ? 25 : nil))
        }
        let qualities = RouteAnalyzer.qualities(for: points, metric: .speed)

        XCTAssertEqual(qualities[0], .good)
        XCTAssertEqual(qualities[9], .good, "45 секунд после замера — ещё действует")
        XCTAssertNil(qualities[10], "50 секунд — замер устарел, оценки нет")
    }

    func testUnreachablePointIsDeadForBothMetrics() {
        let points = [point(at: 0), point(at: 5, reachable: false)]
        XCTAssertEqual(RouteAnalyzer.qualities(for: points, metric: .latency)[1], .dead)
        XCTAssertEqual(RouteAnalyzer.qualities(for: points, metric: .speed)[1], .dead)
    }

    func testDistanceSumsStepsAndSkipsLongGaps() {
        let points = [
            point(at: 0, lat: 0.000, lon: 0),
            point(at: 5, lat: 0.001, lon: 0),
            point(at: 10, lat: 0.002, lon: 0),
            point(at: 500, lat: 0.050, lon: 0)
        ]
        // 0,002° широты — около 222 м; прыжок после паузы в 490 секунд в длину не входит
        XCTAssertEqual(RouteAnalyzer.distanceMeters(of: points), 222.4, accuracy: 1.5)
        XCTAssertEqual(RouteAnalyzer.distanceMeters(of: [point(at: 0)]), 0)
    }

    func testDeadZoneNeedsAtLeastTwoPointsInARow() {
        // Ответ есть (R) или нет (D): R R D D D R D R R
        let pattern: [Bool] = [true, true, false, false, false, true, false, true, true]
        var points: [RoutePoint] = []
        for (index, reachable) in pattern.enumerated() {
            points.append(point(at: Double(index) * 5, reachable: reachable))
        }

        let zones = RouteAnalyzer.deadZones(in: points)

        XCTAssertEqual(zones.count, 1, "Одиночный сбой в точке 6 — не зона без сети")
        XCTAssertEqual(zones[0].pointCount, 3)
        XCTAssertEqual(zones[0].duration, 10, accuracy: 0.001)
        XCTAssertEqual(zones[0].center, points[3].coordinate)
        XCTAssertEqual(zones[0].lengthMeters, 111, accuracy: 3)
    }

    func testStatsOfMixedRoute() {
        var points: [RoutePoint] = []
        for index in 0..<5 { points.append(point(at: Double(index) * 5, latency: 50)) }
        for index in 5..<7 { points.append(point(at: Double(index) * 5, latency: 200)) }
        points.append(point(at: 35, latency: 400))
        points.append(point(at: 40, reachable: false))
        points.append(point(at: 45, reachable: false))
        let record = RouteRecord(startedAt: baseTime, points: points)

        let stats = RouteAnalyzer.stats(of: record)

        XCTAssertEqual(stats.pointCount, 10)
        XCTAssertEqual(stats.duration, 45, accuracy: 0.001)
        XCTAssertEqual(stats.share(of: .good), 0.5, accuracy: 0.0001)
        XCTAssertEqual(stats.share(of: .fair), 0.2, accuracy: 0.0001)
        XCTAssertEqual(stats.share(of: .poor), 0.1, accuracy: 0.0001)
        XCTAssertEqual(stats.share(of: .dead), 0.2, accuracy: 0.0001)
        // Среднее только по точкам, где узел ответил: (5×50 + 2×200 + 400) / 8
        XCTAssertEqual(stats.averageLatencyMs ?? -1, 131.25, accuracy: 0.001)
        XCTAssertEqual(stats.worstLatencyMs, 400)
        XCTAssertNil(stats.averageDownloadMbps, "Скорость не измерялась — среднего нет")
        XCTAssertEqual(stats.deadZoneCount, 1)
        XCTAssertGreaterThan(stats.longestDeadStretchMeters, 0)
    }

    func testStatsOfEmptyRouteAreEmptyNotInvented() {
        let stats = RouteAnalyzer.stats(of: RouteRecord(startedAt: baseTime))
        XCTAssertEqual(stats.pointCount, 0)
        XCTAssertEqual(stats.distanceMeters, 0)
        XCTAssertNil(stats.averageLatencyMs)
        XCTAssertNil(stats.worstLatencyMs)
        XCTAssertEqual(stats.deadZoneCount, 0)
        XCTAssertTrue(stats.shares.isEmpty)
    }
}

// MARK: - Политика выборки точек

final class RouteSamplingPolicyTests: XCTestCase {
    private let policy = RouteSamplingPolicy()
    private let now = baseTime.addingTimeInterval(100)

    private func fix(lat: Double = 55.0, lon: Double = 37.0, accuracy: Double = 10, age: TimeInterval = 1) -> LocationFix {
        LocationFix(latitude: lat, longitude: lon, horizontalAccuracy: accuracy, speed: 5, timestamp: now.addingTimeInterval(-age))
    }

    func testNoFixOrStaleFixIsSkipped() {
        XCTAssertEqual(policy.decide(lastPoint: nil, fix: nil, now: now), .skipNoFix)
        XCTAssertEqual(policy.decide(lastPoint: nil, fix: fix(age: 21), now: now), .skipNoFix)
        XCTAssertEqual(policy.decide(lastPoint: nil, fix: fix(age: 20), now: now), .record)
    }

    func testPoorOrInvalidAccuracyIsSkipped() {
        XCTAssertEqual(policy.decide(lastPoint: nil, fix: fix(accuracy: 150), now: now), .skipPoorAccuracy)
        XCTAssertEqual(policy.decide(lastPoint: nil, fix: fix(accuracy: -1), now: now), .skipPoorAccuracy)
        XCTAssertEqual(policy.decide(lastPoint: nil, fix: fix(accuracy: 100), now: now), .record)
    }

    func testFirstPointIsAlwaysRecordedWhenFixIsGood() {
        XCTAssertEqual(policy.decide(lastPoint: nil, fix: fix(), now: now), .record)
    }

    func testStationaryPhoneWritesOnlyEveryThirtySeconds() {
        let recent = point(at: 90, lat: 55.0, lon: 37.0)       // 10 секунд назад, стоим на месте
        XCTAssertEqual(policy.decide(lastPoint: recent, fix: fix(), now: now), .skipStationary)

        let old = point(at: 70, lat: 55.0, lon: 37.0)          // 30 секунд назад
        XCTAssertEqual(policy.decide(lastPoint: old, fix: fix(), now: now), .record)
    }

    func testMovementBeyondThresholdIsRecordedImmediately() {
        let recent = point(at: 95, lat: 55.0, lon: 37.0)
        // 0,0002° широты — около 22 м
        XCTAssertEqual(policy.decide(lastPoint: recent, fix: fix(lat: 55.0002), now: now), .record)
        // 0,00005° — около 5,5 м: это шум GPS
        XCTAssertEqual(policy.decide(lastPoint: recent, fix: fix(lat: 55.00005), now: now), .skipStationary)
    }
}

// MARK: - Пример маршрута

final class RouteDemoTests: XCTestCase {
    func testSampleRouteShowsEveryQualityAndOneDeadZone() {
        let sample = RouteDemo.sample()

        XCTAssertEqual(sample.points.count, 72)
        let qualities = Set(sample.points.map { $0.quality })
        XCTAssertEqual(qualities, Set(RouteQuality.allCases))

        let zones = RouteAnalyzer.deadZones(in: sample.points)
        XCTAssertEqual(zones.count, 1)
        XCTAssertEqual(zones.first?.pointCount, 6)

        let stats = RouteAnalyzer.stats(of: sample)
        XCTAssertGreaterThan(stats.distanceMeters, 3_000)
        XCTAssertEqual(stats.shares.values.reduce(0, +), 1, accuracy: 0.000_001)
    }

    func testSampleRouteDrawsInBothMetrics() {
        let sample = RouteDemo.sample()
        let byLatency = RouteAnalyzer.segments(for: sample.points, metric: .latency)
        let bySpeed = RouteAnalyzer.segments(for: sample.points, metric: .speed)

        XCTAssertGreaterThanOrEqual(byLatency.count, 4)
        XCTAssertFalse(bySpeed.isEmpty)
        XCTAssertTrue(bySpeed.contains { $0.quality == .dead })
    }

    func testSampleRouteIsDeterministic() {
        XCTAssertEqual(RouteDemo.sample(), RouteDemo.sample())
    }
}
