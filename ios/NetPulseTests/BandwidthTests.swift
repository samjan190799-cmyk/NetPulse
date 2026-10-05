//
//  BandwidthTests.swift
//  NetPulseTests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest
@testable import NetPulse

/// Скорость и учёт трафика: единая единица Мбит/с, классификация интерфейсов, защита от скачков счётчиков.
final class BandwidthTests: XCTestCase {

    // MARK: - Форматирование скорости

    /// Раньше остров в покое показывал МБ/с, а при замере скорости — Мбит/с (числа различались в 8 раз).
    func testFormatSpeedAlwaysUsesMegabitsPerSecond() {
        XCTAssertEqual(BandwidthSnapshot.formatSpeed(mbps: 0), "0 Мбит/с")
        XCTAssertEqual(BandwidthSnapshot.formatSpeed(mbps: 0.0004), "0 Мбит/с")
        XCTAssertEqual(BandwidthSnapshot.formatSpeed(mbps: 0.5), "500 Кбит/с")
        XCTAssertEqual(BandwidthSnapshot.formatSpeed(mbps: 1.234), "1.23 Мбит/с")
        XCTAssertEqual(BandwidthSnapshot.formatSpeed(mbps: 12.34), "12.3 Мбит/с")
        XCTAssertEqual(BandwidthSnapshot.formatSpeed(mbps: 123.4), "123 Мбит/с")
    }

    /// Компактный вид для острова — только число: суффикс «M» раньше мог означать и МБ/с, и Мбит/с.
    func testCompactSpeedIsPlainNumber() {
        XCTAssertEqual(BandwidthSnapshot.compactSpeed(mbps: 0), "0")
        XCTAssertEqual(BandwidthSnapshot.compactSpeed(mbps: 0.04), "0")
        XCTAssertEqual(BandwidthSnapshot.compactSpeed(mbps: 0.5), "0.5")
        XCTAssertEqual(BandwidthSnapshot.compactSpeed(mbps: 9.94), "9.9")
        XCTAssertEqual(BandwidthSnapshot.compactSpeed(mbps: 10), "10")
        XCTAssertEqual(BandwidthSnapshot.compactSpeed(mbps: 96.4), "96")

        for value in [0.0, 0.3, 4.2, 12.0, 250.0] {
            let text = BandwidthSnapshot.compactSpeed(mbps: value)
            XCTAssertNotNil(Double(text), "Компактный вид должен быть числом, получено «\(text)»")
        }
    }

    // MARK: - Классификация интерфейсов

    func testInterfaceKindCountsOnlyRealInternetInterfaces() {
        XCTAssertEqual(BandwidthEngine.interfaceKind(for: "en0"), .wifi)
        XCTAssertEqual(BandwidthEngine.interfaceKind(for: "en1"), .wifi)
        XCTAssertEqual(BandwidthEngine.interfaceKind(for: "pdp_ip0"), .cellular)
        XCTAssertEqual(BandwidthEngine.interfaceKind(for: "utun3"), .vpn)
        XCTAssertEqual(BandwidthEngine.interfaceKind(for: "ipsec0"), .vpn)
        XCTAssertEqual(BandwidthEngine.interfaceKind(for: "ppp0"), .vpn)
    }

    /// Раздача интернета (bridge*/ap*) раньше считалась дважды: на физическом интерфейсе и на мосту.
    func testTetheringAndPeerToPeerInterfacesAreIgnored() {
        for name in ["bridge100", "ap1", "anpi0", "awdl0", "llw0", "lo0"] {
            XCTAssertEqual(BandwidthEngine.interfaceKind(for: name), .ignored, "Интерфейс \(name) не должен учитываться")
        }
    }

    // MARK: - Приращения счётчиков

    func testDeltaOfMonotonicCounter() {
        XCTAssertEqual(BandwidthEngine.computeSingleInterfaceDelta(prev: 1_000, current: 5_000), 4_000)
        XCTAssertEqual(BandwidthEngine.computeSingleInterfaceDelta(prev: 5_000, current: 5_000), 0)
    }

    func testDeltaWithoutBaselineIsZero() {
        // Первый замер: базовой точки нет, считать весь счётчик «скоростью» нельзя
        XCTAssertEqual(BandwidthEngine.computeSingleInterfaceDelta(prev: 0, current: 5_000_000), 0)
    }

    func testDeltaSurvives32BitCounterRollover() {
        // 4 294 967 000 → 100: счётчик Darwin переполнился, прирост = 396 байт
        XCTAssertEqual(BandwidthEngine.computeSingleInterfaceDelta(prev: 4_294_967_000, current: 100), 396)
    }

    func testImplausibleSpikeIsDiscarded() {
        XCTAssertEqual(BandwidthEngine.computeSingleInterfaceDelta(prev: 1_000, current: 3_000_000_000), 0)
        XCTAssertEqual(BandwidthEngine.computeDelta(prev: 1_000, current: 3_000_000_000), 0)
    }
}
