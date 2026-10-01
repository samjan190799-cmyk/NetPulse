//
//  ToolsLogicTests.swift
//  NetPulseTests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest
@testable import NetPulse

// MARK: - Bufferbloat

/// Оценка Bufferbloat: неудачный замер больше не превращается в «A+».
final class BufferbloatTests: XCTestCase {

    func testGradeBoundaries() {
        XCTAssertEqual(BufferbloatGrade.grade(forDelta: 0), .aPlus)
        XCTAssertEqual(BufferbloatGrade.grade(forDelta: 4.99), .aPlus)
        XCTAssertEqual(BufferbloatGrade.grade(forDelta: 5), .a)
        XCTAssertEqual(BufferbloatGrade.grade(forDelta: 14.9), .a)
        XCTAssertEqual(BufferbloatGrade.grade(forDelta: 15), .b)
        XCTAssertEqual(BufferbloatGrade.grade(forDelta: 39.9), .b)
        XCTAssertEqual(BufferbloatGrade.grade(forDelta: 40), .c)
        XCTAssertEqual(BufferbloatGrade.grade(forDelta: 89.9), .c)
        XCTAssertEqual(BufferbloatGrade.grade(forDelta: 90), .d)
        XCTAssertEqual(BufferbloatGrade.grade(forDelta: 179.9), .d)
        XCTAssertEqual(BufferbloatGrade.grade(forDelta: 180), .f)
        XCTAssertEqual(BufferbloatGrade.grade(forDelta: 1_000), .f)
    }

    func testDowngradeMovesOneStepWorse() {
        XCTAssertEqual(BufferbloatGrade.aPlus.downgraded(), .a)
        XCTAssertEqual(BufferbloatGrade.a.downgraded(), .b)
        XCTAssertEqual(BufferbloatGrade.b.downgraded(), .c)
        XCTAssertEqual(BufferbloatGrade.c.downgraded(), .d)
        XCTAssertEqual(BufferbloatGrade.d.downgraded(), .f)
        XCTAssertEqual(BufferbloatGrade.f.downgraded(), .f)
    }

    func testReportWithoutLoadedMeasurementsHasNoGrade() {
        let report = BufferbloatReport(unloadedPingMs: 20, loadedDownloadPingMs: nil, loadedUploadPingMs: nil)
        XCTAssertNil(report.grade, "Без замера под нагрузкой оценки быть не должно")
        XCTAssertNil(report.maxDeltaMs)
        XCTAssertEqual(report.dynamicVerdictTitle, "Недостаточно данных для оценки")
    }

    func testReportUsesWorstDirection() {
        let report = BufferbloatReport(unloadedPingMs: 20, loadedDownloadPingMs: 30, loadedUploadPingMs: 80)
        XCTAssertEqual(report.downloadDeltaMs ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(report.uploadDeltaMs ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(report.maxDeltaMs ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(report.grade, .c)
    }

    func testDelayBelowBaselineDoesNotProduceNegativeDelta() {
        let report = BufferbloatReport(unloadedPingMs: 50, loadedDownloadPingMs: 40, loadedUploadPingMs: nil)
        XCTAssertEqual(report.downloadDeltaMs ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(report.grade, .aPlus)
    }

    /// Потери проб под нагрузкой — признак переполненной очереди: оценка падает на ступень.
    func testHeavyLossDowngradesGrade() {
        let lossy = BufferbloatReport(
            unloadedPingMs: 20,
            loadedDownloadPingMs: 30,
            loadedUploadPingMs: nil,
            downloadLossPercent: 25
        )
        XCTAssertEqual(lossy.grade, .b, "Рост задержки 10 мс даёт A, потери ≥ 20 % понижают оценку до B")

        let clean = BufferbloatReport(
            unloadedPingMs: 20,
            loadedDownloadPingMs: 30,
            loadedUploadPingMs: nil,
            downloadLossPercent: 5
        )
        XCTAssertEqual(clean.grade, .a)
    }

    func testErrorsHaveUserFacingDescriptions() {
        XCTAssertFalse((BufferbloatError.noConnection.errorDescription ?? "").isEmpty)
        XCTAssertFalse((BufferbloatError.cancelled.errorDescription ?? "").isEmpty)
    }
}

// MARK: - Сканер локальной сети

final class LANTests: XCTestCase {

    private func address(_ text: String) throws -> UInt32 {
        try XCTUnwrap(LANSubnet.address(from: text), "Адрес «\(text)» не разобран")
    }

    func testAddressConversionRoundTrip() throws {
        XCTAssertEqual(try address("192.168.1.10"), 0xC0A8010A)
        XCTAssertEqual(LANSubnet.string(from: 0xC0A8010A), "192.168.1.10")
        XCTAssertEqual(LANSubnet.string(from: try address("10.0.0.1")), "10.0.0.1")
    }

    func testMalformedAddressesAreRejected() {
        XCTAssertNil(LANSubnet.address(from: ""))
        XCTAssertNil(LANSubnet.address(from: "192.168.1"))
        XCTAssertNil(LANSubnet.address(from: "192.168.1.256"))
        XCTAssertNil(LANSubnet.address(from: "192.168.1.1.1"))
        XCTAssertNil(LANSubnet.address(from: "a.b.c.d"))
    }

    /// Сканировать имеет смысл только частные сети RFC 1918, чужую сеть оператора — нельзя.
    func testOnlyRFC1918RangesArePrivate() throws {
        for text in ["10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.0.1", "192.168.255.254"] {
            XCTAssertTrue(LANSubnet.isPrivate(try address(text)), "\(text) должен считаться частным")
        }
        for text in ["8.8.8.8", "172.15.255.255", "172.32.0.1", "192.169.0.1", "100.64.0.1", "169.254.1.1", "1.1.1.1"] {
            XCTAssertFalse(LANSubnet.isPrivate(try address(text)), "\(text) не должен считаться частным")
        }
    }

    /// Адрес из TEST-NET-1 есть не на любой машине, поэтому маска берётся по умолчанию (/24).
    func testSubnetForUnknownInterfaceFallsBackToSlash24() throws {
        let local = try address("192.0.2.77")
        let network = try address("192.0.2.0")
        let broadcast = try address("192.0.2.255")

        let subnet = try XCTUnwrap(LANScannerEngine.makeSubnet(localAddress: local))
        XCTAssertEqual(subnet.prefixLength, 24)
        XCTAssertEqual(subnet.networkAddress, network)
        XCTAssertEqual(subnet.cidrDescription, "192.0.2.0/24")
        XCTAssertFalse(subnet.isTruncated)

        // 254 адреса сети минус адрес самого устройства
        XCTAssertEqual(subnet.hostAddresses.count, 253)
        XCTAssertFalse(subnet.hostAddresses.contains(local), "Собственный адрес не сканируется")
        XCTAssertFalse(subnet.hostAddresses.contains(network), "Адрес сети не сканируется")
        XCTAssertFalse(subnet.hostAddresses.contains(broadcast), "Широковещательный адрес не сканируется")
    }

    func testScanErrorsHaveUserFacingDescriptions() {
        for error in [LANScanError.notOnLocalNetwork, .localNetworkAccessDenied, .cancelled] {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
    }
}

// MARK: - DNS-запросы

/// Бенчмарк DNS отправляет настоящие запросы: проверяем сборку пакета (RFC 1035) и разбор ответа.
final class DNSPacketTests: XCTestCase {

    func testQueryPacketLayout() throws {
        let packet = try XCTUnwrap(DNSQueryProbe.makeQuery(id: 0xABCD, domain: "example.com"))
        let bytes = [UInt8](packet)

        XCTAssertEqual(Array(bytes[0..<2]), [0xAB, 0xCD], "Идентификатор запроса")
        XCTAssertEqual(Array(bytes[2..<4]), [0x01, 0x00], "Флаги: стандартный запрос, рекурсия желательна")
        XCTAssertEqual(Array(bytes[4..<6]), [0x00, 0x01], "Один вопрос")
        XCTAssertEqual(Array(bytes[6..<12]), [0, 0, 0, 0, 0, 0], "Записей в ответе, полномочиях и дополнениях нет")

        var expectedName: [UInt8] = [7]
        expectedName += Array("example".utf8)
        expectedName += [3]
        expectedName += Array("com".utf8)
        expectedName += [0]
        XCTAssertEqual(Array(bytes[12..<(12 + expectedName.count)]), expectedName, "Имя в формате «длина + метка»")
        XCTAssertEqual(Array(bytes.suffix(4)), [0, 1, 0, 1], "Тип A, класс IN")
        XCTAssertEqual(bytes.count, 12 + expectedName.count + 4)
    }

    func testOverlongLabelIsRejected() {
        let tooLong = String(repeating: "a", count: 64) + ".com"
        XCTAssertNil(DNSQueryProbe.makeQuery(id: 1, domain: tooLong))
    }

    private func responseHeader(id: UInt16, flags: UInt16, answers: UInt16) -> Data {
        var bytes: [UInt8] = []
        bytes.append(UInt8(id >> 8))
        bytes.append(UInt8(id & 0xFF))
        bytes.append(UInt8(flags >> 8))
        bytes.append(UInt8(flags & 0xFF))
        bytes.append(contentsOf: [0, 1])            // один вопрос
        bytes.append(UInt8(answers >> 8))
        bytes.append(UInt8(answers & 0xFF))
        bytes.append(contentsOf: [0, 0, 0, 0])      // полномочия и дополнения
        return Data(bytes)
    }

    func testValidAnswerIsAccepted() {
        let data = responseHeader(id: 0x1234, flags: 0x8180, answers: 1)
        XCTAssertTrue(DNSQueryProbe.isValidAnswer(data, expectedID: 0x1234))
    }

    func testForeignOrBrokenAnswersAreRejected() {
        // Чужой идентификатор
        XCTAssertFalse(DNSQueryProbe.isValidAnswer(responseHeader(id: 0x1234, flags: 0x8180, answers: 1), expectedID: 0x9999))
        // Это запрос, а не ответ
        XCTAssertFalse(DNSQueryProbe.isValidAnswer(responseHeader(id: 0x1234, flags: 0x0100, answers: 1), expectedID: 0x1234))
        // Ошибка NXDOMAIN
        XCTAssertFalse(DNSQueryProbe.isValidAnswer(responseHeader(id: 0x1234, flags: 0x8183, answers: 0), expectedID: 0x1234))
        // Ответ без записей
        XCTAssertFalse(DNSQueryProbe.isValidAnswer(responseHeader(id: 0x1234, flags: 0x8180, answers: 0), expectedID: 0x1234))
        // Обрезанный пакет
        XCTAssertFalse(DNSQueryProbe.isValidAnswer(Data([1, 2, 3]), expectedID: 1))
    }
}
