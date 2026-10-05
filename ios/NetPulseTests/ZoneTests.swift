//
//  ZoneTests.swift
//  NetPulseTests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest
@testable import NetPulse

/// Зоны покрытия: клетка рисуется только там, где вы бывали не раз и замеров достаточно.
final class ZoneBuilderTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    /// Точка на карте и точка в 330 м к северу от неё: они попадают в разные клетки по 100 м
    private let home = GeoCoordinate(latitude: 55.7500, longitude: 37.6000)
    private let farNorth = GeoCoordinate(latitude: 55.7530, longitude: 37.6000)

    /// Маршрут из `count` точек в одном месте с одной и той же задержкой
    private func route(
        at place: GeoCoordinate,
        latency: Double? = 40,
        reachable: Bool = true,
        download: Double? = nil,
        count: Int = 4,
        startOffset: TimeInterval = 0
    ) -> RouteRecord {
        let points = (0..<count).map { index in
            RoutePoint(
                time: base.addingTimeInterval(startOffset + Double(index) * 5),
                latitude: place.latitude,
                longitude: place.longitude,
                latencyMs: latency,
                reachable: reachable,
                downloadMbps: download
            )
        }
        return RouteRecord(startedAt: base.addingTimeInterval(startOffset), points: points)
    }

    private func threeRoutes(at place: GeoCoordinate, latency: Double? = 40) -> [RouteRecord] {
        (0..<3).map { index in
            route(at: place, latency: latency, startOffset: Double(index) * 1_000)
        }
    }

    // MARK: Когда зоны появляются

    func testNoZonesUntilThreeRoutesAreSaved() {
        let two = Array(threeRoutes(at: home).prefix(2))
        XCTAssertTrue(ZoneBuilder.zones(from: two, metric: .latency).isEmpty, "двух маршрутов мало")
        XCTAssertEqual(ZoneBuilder.zones(from: threeRoutes(at: home), metric: .latency).count, 1)
    }

    func testRoutesWithOnePointDoNotCountTowardsTheMinimum() {
        var routes = Array(threeRoutes(at: home).prefix(2))
        routes.append(route(at: home, count: 1))
        XCTAssertEqual(ZoneBuilder.usableRouteCount(in: routes), 2)
        XCTAssertTrue(ZoneBuilder.zones(from: routes, metric: .latency).isEmpty)
    }

    func testCellNeedsTwoDifferentRoutes() {
        // Третий маршрут один набрал пятнадцать замеров севернее, но один проход зоной не становится
        let routes = [
            route(at: home, startOffset: 0),
            route(at: home, startOffset: 1_000),
            route(at: farNorth, count: 15, startOffset: 2_000)
        ]
        let zones = ZoneBuilder.zones(from: routes, metric: .latency)
        XCTAssertEqual(zones.count, 1, "клетка, где был только один маршрут, не рисуется, сколько бы там ни было замеров")
        XCTAssertEqual(zones.first?.routeCount, 2)
    }

    func testCellNeedsFourSamples() {
        func point(_ place: GeoCoordinate, _ seconds: TimeInterval) -> RoutePoint {
            RoutePoint(time: base.addingTimeInterval(seconds), latitude: place.latitude, longitude: place.longitude, latencyMs: 40)
        }
        func record(_ offset: TimeInterval, _ places: [GeoCoordinate]) -> RouteRecord {
            let points = places.enumerated().map { index, place in point(place, offset + Double(index) * 5) }
            return RouteRecord(startedAt: base.addingTimeInterval(offset), points: points)
        }

        // «Дом»: 2 точки первого маршрута и 1 второго — три замера из двух маршрутов
        // «Север»: 1 точка второго маршрута и 2 третьего — тоже три замера из двух маршрутов
        let threeEach = [
            record(0, [home, home]),
            record(1_000, [home, farNorth]),
            record(2_000, [farNorth, farNorth])
        ]
        XCTAssertTrue(ZoneBuilder.zones(from: threeEach, metric: .latency).isEmpty, "по три замера в клетке — мало")

        // Ещё одна точка первого маршрута в «доме»: там стало четыре замера из двух маршрутов
        let fourAtHome = [
            record(0, [home, home, home]),
            record(1_000, [home, farNorth]),
            record(2_000, [farNorth, farNorth])
        ]
        let zones = ZoneBuilder.zones(from: fourAtHome, metric: .latency)
        XCTAssertEqual(zones.count, 1, "четыре замера и два маршрута: зона есть только в «доме»")
        XCTAssertEqual(zones.first?.sampleCount, 4)
        XCTAssertEqual(zones.first?.routeCount, 2)
    }

    // MARK: Цвет клетки

    func testZoneColourFollowsTheMajorityOfSamples() {
        func quality(latencies: [Double?], reachable: [Bool]) -> RouteQuality? {
            let points = zip(latencies, reachable).enumerated().map { index, pair in
                RoutePoint(time: base.addingTimeInterval(Double(index) * 5), latitude: home.latitude, longitude: home.longitude, latencyMs: pair.0, reachable: pair.1)
            }
            // Три маршрута, в каждом одни и те же замеры: так в клетке есть и несколько проходов, и достаточно замеров
            let routes = (0..<3).map { RouteRecord(startedAt: base.addingTimeInterval(Double($0) * 1_000), points: points) }
            return ZoneBuilder.zones(from: routes, metric: .latency).first?.quality
        }

        XCTAssertEqual(quality(latencies: [40, 50, 60, 70], reachable: [true, true, true, true]), .good)
        XCTAssertEqual(quality(latencies: [200, 220, 240, 40], reachable: [true, true, true, true]), .fair)
        XCTAssertEqual(quality(latencies: [500, 600, 700, 40], reachable: [true, true, true, true]), .poor)
        XCTAssertEqual(quality(latencies: [nil, nil, nil, 40], reachable: [false, false, false, true]), .dead)
        // Один сбой среди хороших замеров не красит клетку в красный
        XCTAssertEqual(quality(latencies: [40, 45, 50, nil], reachable: [true, true, true, false]), .good)
    }

    func testTypicalQualityIsTheMiddleSampleAndTiesGoToTheWorse() {
        // counts: хорошо, средне, плохо, нет сети
        XCTAssertEqual(ZoneBuilder.typicalQuality([4, 2, 0, 0]), .good)
        XCTAssertEqual(ZoneBuilder.typicalQuality([3, 3, 0, 0]), .fair, "поровну: берём худшее из двух средних")
        XCTAssertEqual(ZoneBuilder.typicalQuality([2, 0, 4, 0]), .poor)
        XCTAssertEqual(ZoneBuilder.typicalQuality([0, 0, 0, 4]), .dead)
        XCTAssertEqual(ZoneBuilder.typicalQuality([4, 0, 0, 3]), .good, "меньше половины замеров без сети")
        XCTAssertEqual(ZoneBuilder.typicalQuality([3, 0, 0, 4]), .dead, "больше половины без сети")
    }

    func testSpeedMetricUsesDownloadAndSkipsPointsWithoutIt() {
        let withoutSpeed = threeRoutes(at: home)
        XCTAssertTrue(ZoneBuilder.zones(from: withoutSpeed, metric: .speed).isEmpty, "скорость не измерялась: клетку красить нечем")

        let slow = (0..<3).map { index in
            route(at: home, download: 0.4, startOffset: Double(index) * 1_000)
        }
        XCTAssertEqual(ZoneBuilder.zones(from: slow, metric: .speed).first?.quality, .poor)
        XCTAssertEqual(ZoneBuilder.zones(from: slow, metric: .latency).first?.quality, .good, "по задержке тот же маршрут хороший")
    }

    // MARK: Форма и расположение клеток

    func testZoneIsAHundredMetreSquareAroundTheSamples() throws {
        let zone = try XCTUnwrap(ZoneBuilder.zones(from: threeRoutes(at: home), metric: .latency).first)
        XCTAssertEqual(zone.corners.count, 4)

        let southWest = zone.corners[0], southEast = zone.corners[1], northEast = zone.corners[2], northWest = zone.corners[3]
        XCTAssertEqual(southWest.distance(to: southEast), 100, accuracy: 2)
        XCTAssertEqual(southWest.distance(to: northWest), 100, accuracy: 2)
        XCTAssertEqual(northWest.distance(to: northEast), 100, accuracy: 2)

        XCTAssertTrue(home.latitude >= southWest.latitude && home.latitude < northWest.latitude)
        XCTAssertTrue(home.longitude >= southWest.longitude && home.longitude < southEast.longitude)
    }

    func testDistantPlacesFallIntoDifferentCells() {
        let routes = (0..<3).map { index in
            RouteRecord(
                startedAt: base.addingTimeInterval(Double(index) * 1_000),
                points: route(at: home, startOffset: Double(index) * 1_000).points
                    + route(at: farNorth, startOffset: Double(index) * 1_000 + 100).points
            )
        }
        let zones = ZoneBuilder.zones(from: routes, metric: .latency)
        XCTAssertEqual(zones.count, 2)
        XCTAssertEqual(Set(zones.map(\.id)).count, 2)
        XCTAssertTrue(zones.allSatisfy { $0.routeCount == 3 && $0.sampleCount == 12 })
    }

    // MARK: Предел, порядок, устойчивость

    func testCapKeepsTheCellsWithTheMostSamples() {
        // Три клетки; в клетке с самым большим числом замеров зона нужна точно
        let rich = threeRoutes(at: home)                               // 12 замеров
        let medium = (0..<3).map { route(at: farNorth, count: 3, startOffset: Double($0) * 1_000 + 500) }  // 9 замеров
        let poor = (0..<3).map { route(at: GeoCoordinate(latitude: 55.7560, longitude: 37.6000), count: 2, startOffset: Double($0) * 1_000 + 900) }  // 6 замеров
        // Один маршрут проходит все три места, чтобы клетки собирали замеры из общих трёх маршрутов
        let routes = (0..<3).map { index in
            RouteRecord(startedAt: base.addingTimeInterval(Double(index) * 1_000),
                        points: rich[index].points + medium[index].points + poor[index].points)
        }

        let all = ZoneBuilder.zones(from: routes, metric: .latency)
        XCTAssertEqual(all.count, 3)

        let top = ZoneBuilder.zones(from: routes, metric: .latency, maxZones: 2)
        XCTAssertEqual(top.count, 2)
        XCTAssertEqual(Set(top.map(\.sampleCount)), [12, 9], "остаются клетки, где замеров больше всего")
    }

    func testOutputIsStableAndSortedFromSouthToNorth() {
        let routes = (0..<3).map { index in
            RouteRecord(startedAt: base.addingTimeInterval(Double(index) * 1_000),
                        points: route(at: farNorth, startOffset: Double(index) * 1_000).points
                            + route(at: home, startOffset: Double(index) * 1_000 + 100).points)
        }
        let first = ZoneBuilder.zones(from: routes, metric: .latency)
        let second = ZoneBuilder.zones(from: routes, metric: .latency)
        XCTAssertEqual(first, second)

        let latitudes = first.map { $0.corners[0].latitude }
        XCTAssertEqual(latitudes, latitudes.sorted(), "с юга на север")
    }

    func testBrokenCoordinatesAreIgnoredWithoutCrashing() {
        func broken(_ latitude: Double, _ longitude: Double, offset: TimeInterval) -> RouteRecord {
            let points = (0..<4).map { index in
                RoutePoint(time: base.addingTimeInterval(offset + Double(index) * 5), latitude: latitude, longitude: longitude, latencyMs: 40)
            }
            return RouteRecord(startedAt: base.addingTimeInterval(offset), points: points)
        }
        let routes = [
            broken(.nan, 37.6, offset: 0),
            broken(200, 37.6, offset: 1_000),
            broken(55.75, .infinity, offset: 2_000),
            broken(55.75, 400, offset: 3_000)
        ]
        XCTAssertTrue(ZoneBuilder.zones(from: routes, metric: .latency).isEmpty)
    }

    func testNothingIsDrawnForNoRoutes() {
        XCTAssertTrue(ZoneBuilder.zones(from: [], metric: .latency).isEmpty)
        XCTAssertEqual(ZoneBuilder.usableRouteCount(in: []), 0)
    }
}

/// Слой зон: выключенный слой пуст, включённый считает зоны вне главного потока.
@MainActor
final class CoverageZoneLayerTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func routes() -> [RouteRecord] {
        (0..<3).map { index in
            let points = (0..<4).map { step in
                RoutePoint(
                    time: base.addingTimeInterval(Double(index) * 1_000 + Double(step) * 5),
                    latitude: 55.75, longitude: 37.6, latencyMs: 40
                )
            }
            return RouteRecord(startedAt: base.addingTimeInterval(Double(index) * 1_000), points: points)
        }
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func testEnabledLayerFillsZonesAndDisabledLayerEmptiesThem() async {
        let layer = CoverageZoneLayer()
        XCTAssertTrue(layer.zones.isEmpty)

        layer.refresh(routes: routes(), metric: .latency, enabled: true)
        await waitUntil { !layer.zones.isEmpty }
        XCTAssertEqual(layer.zones.count, 1)

        layer.refresh(routes: routes(), metric: .latency, enabled: false)
        XCTAssertTrue(layer.zones.isEmpty, "выключили — зоны пропали сразу")
    }

    func testStaleResultDoesNotOverrideNewerRequest() async {
        let layer = CoverageZoneLayer()
        layer.refresh(routes: routes(), metric: .latency, enabled: true)
        // Сразу же выключаем: результат первого расчёта, пришедший позже, не должен вернуть зоны
        layer.refresh(routes: routes(), metric: .latency, enabled: false)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(layer.zones.isEmpty)
    }
}
