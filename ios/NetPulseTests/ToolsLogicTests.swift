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

// MARK: - Доступность сервисов (PRO)

final class ServiceCheckTests: XCTestCase {
    private func result(_ id: String, _ state: ServiceState) -> ServiceCheckResult {
        ServiceCheckResult(targetID: id, state: state, latencyMs: state == .down ? nil : 100, detail: "")
    }

    func testStateDependsOnlyOnLatency() {
        XCTAssertEqual(ServiceCheckEngine.classify(latencyMs: nil), .down, "Нет ответа — сервис не отвечает")
        XCTAssertEqual(ServiceCheckEngine.classify(latencyMs: 80), .ok)
        XCTAssertEqual(ServiceCheckEngine.classify(latencyMs: 1_499), .ok)
        XCTAssertEqual(ServiceCheckEngine.classify(latencyMs: 1_500), .slow)
        XCTAssertEqual(ServiceCheckEngine.classify(latencyMs: 9_000), .slow)
    }

    func testEveryServiceHasASecureURLAndUniqueID() {
        let ids = ServiceCheckEngine.targets.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Идентификаторы сервисов не повторяются")
        for target in ServiceCheckEngine.targets {
            XCTAssertEqual(target.url.scheme, "https", "\(target.name): запросы только по HTTPS")
            XCTAssertNotNil(target.url.host)
        }
    }

    func testFailureReasonsAreHumanReadable() {
        XCTAssertTrue(ServiceCheckEngine.describe(.timedOut).contains("Нет ответа"))
        XCTAssertTrue(ServiceCheckEngine.describe(.notConnectedToInternet).contains("интернет"))
        XCTAssertTrue(ServiceCheckEngine.describe(.cannotFindHost).contains("DNS"))
        XCTAssertFalse(ServiceCheckEngine.describe(.badServerResponse).isEmpty)
    }

    func testVerdictBlamesTheNetworkWhenNothingAnswers() {
        let all = ServiceCheckEngine.targets.map { result($0.id, .down) }
        XCTAssertTrue(ServiceCheckEngine.verdict(all).contains("нет подключения"), "Если не отвечает всё, дело не в сервисах")
    }

    func testVerdictNamesTheFailingAndSlowServices() {
        let results = [result("telegram", .down), result("youtube", .slow), result("google", .ok)]
        let verdict = ServiceCheckEngine.verdict(results)
        XCTAssertTrue(verdict.contains("Не отвечают: Telegram"))
        XCTAssertTrue(verdict.contains("Медленно отвечают: YouTube"))
        XCTAssertFalse(verdict.contains("Google"), "Работающие сервисы в вывод не попадают")
    }

    func testVerdictForHealthyNetwork() {
        let results = [result("telegram", .ok), result("google", .ok)]
        XCTAssertEqual(ServiceCheckEngine.verdict(results), "Все проверенные сервисы отвечают.")
    }

    func testLatencyFormatting() {
        XCTAssertEqual(ServiceCheckEngine.formatLatency(240), "240 мс")
        XCTAssertEqual(ServiceCheckEngine.formatLatency(1_800), "1.8 с")
    }

    @MainActor
    func testHistoryKeepsTheLatestRunsPerService() throws {
        let suite = "netpulse.test.services.\(UUID().uuidString)"
        let store = ServiceHistoryStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        for index in 0..<40 {
            store.record([result("telegram", index % 2 == 0 ? .ok : .down)])
        }
        XCTAssertEqual(store.runs.count, 30, "Помним только последние 30 проверок")
        XCTAssertEqual(store.recentStates(for: "telegram").count, 12)
        XCTAssertTrue(store.recentStates(for: "unknown").isEmpty)
        store.clear()
        XCTAssertTrue(store.runs.isEmpty)
    }
}

// MARK: - История замеров (PRO)

@MainActor
final class SpeedHistoryTests: XCTestCase {
    private func entry(_ down: Double, _ up: Double = 10, ping: Double? = 20, connection: String = "Wi-Fi", minutesAgo: Double = 0) -> SpeedHistoryEntry {
        SpeedHistoryEntry(
            date: Date().addingTimeInterval(-minutesAgo * 60),
            downloadMbps: down,
            uploadMbps: up,
            pingMs: ping,
            connection: connection
        )
    }

    func testNewestEntryComesFirstAndEmptyOnesAreSkipped() {
        let store = SpeedHistoryStore(fileURL: nil)
        store.add(entry(50, minutesAgo: 5))
        store.add(entry(80))
        store.add(entry(0))
        XCTAssertEqual(store.entries.count, 2, "Замер с нулевой скоростью в историю не попадает")
        XCTAssertEqual(store.entries.first?.downloadMbps, 80)
    }

    func testHistoryIsLimited() {
        let store = SpeedHistoryStore(fileURL: nil)
        for index in 0..<(SpeedHistoryStore.maxEntries + 25) {
            store.add(entry(Double(index + 1)))
        }
        XCTAssertEqual(store.entries.count, SpeedHistoryStore.maxEntries)
    }

    func testFilterByConnection() {
        let store = SpeedHistoryStore(fileURL: nil)
        store.add(entry(40, connection: "Wi-Fi"))
        store.add(entry(25, connection: "Сотовая"))
        store.add(entry(60, connection: "Wi-Fi"))
        XCTAssertEqual(store.entries(connection: "Wi-Fi").count, 2)
        XCTAssertEqual(store.entries(connection: "Сотовая").count, 1)
        XCTAssertEqual(store.entries(connection: nil).count, 3)
    }

    func testSummary() throws {
        XCTAssertNil(SpeedHistorySummary.make(from: []))
        let summary = try XCTUnwrap(SpeedHistorySummary.make(from: [entry(20, 4, ping: 30), entry(60, 8, ping: 10)]))
        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(summary.averageDownloadMbps, 40, accuracy: 0.001)
        XCTAssertEqual(summary.averageUploadMbps, 6, accuracy: 0.001)
        XCTAssertEqual(summary.bestDownloadMbps, 60)
        XCTAssertEqual(summary.worstDownloadMbps, 20)
        XCTAssertEqual(try XCTUnwrap(summary.averagePingMs), 20, accuracy: 0.001)
    }

    func testHistorySurvivesRestart() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("np-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let first = SpeedHistoryStore(fileURL: file)
        first.add(entry(75))
        // Запись идёт в фоне: ждём файл
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: file.path), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let second = SpeedHistoryStore(fileURL: file)
        XCTAssertEqual(second.entries.first?.downloadMbps, 75, "Замеры переживают перезапуск приложения")
    }

    func testConnectionLabelsAreShort() {
        XCTAssertEqual(SpeedHistoryEntry.label(for: .wifi), "Wi-Fi")
        XCTAssertEqual(SpeedHistoryEntry.label(for: .cellular), "Сотовая")
        XCTAssertEqual(SpeedHistoryEntry.label(for: .ethernet), "Ethernet")
        XCTAssertEqual(SpeedHistoryEntry.label(for: .unavailable), "Другое")
    }
}

// MARK: - Отчёт, экспорт, оповещения, команда (PRO)

final class ProFeatureSupportTests: XCTestCase {
    private func sampleReport() -> ProReportData {
        ProReportData(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            appVersion: "1.0.1",
            connection: "Wi-Fi",
            provider: "Тестовый провайдер",
            publicIP: "203.0.113.5",
            periodText: "Задержка, потери и оповещения за текущий сеанс работы приложения.",
            speedSummary: SpeedHistorySummary(
                count: 3, averageDownloadMbps: 40, averageUploadMbps: 8, bestDownloadMbps: 60, worstDownloadMbps: 20, averagePingMs: 25
            ),
            speedSeries: [20, 60, 40],
            hosts: [
                ReportHostLine(name: "Cloudflare", address: "1.1.1.1", averageLatencyMs: 24, jitterMs: 2.5, lossPct: 0, status: "норма")
            ],
            problems: ["8 окт. · Cloudflare: Узел недоступен"],
            routes: [
                ReportRouteLine(title: "Сегодня", summary: "1,2 км · 14 мин", problems: "Мест без связи: 1.", quality: "Качество связи: Хорошо 80 %")
            ],
            complaint: "Прошу проверить качество связи на моей линии."
        )
    }

    func testReportIsARealPDF() {
        let pdf = ReportBuilder.makePDF(sampleReport())
        XCTAssertGreaterThan(pdf.count, 1_500)
        XCTAssertEqual(String(data: pdf.prefix(5), encoding: .ascii), "%PDF-", "Файл должен быть PDF")
    }

    func testReportWithoutDataStillBuilds() {
        var empty = sampleReport()
        empty.speedSummary = nil
        empty.speedSeries = []
        empty.hosts = []
        empty.problems = []
        empty.routes = []
        XCTAssertGreaterThan(ReportBuilder.makePDF(empty).count, 1_000, "Пустой отчёт тоже собирается")
    }

    func testLongReportMovesToNextPage() {
        var long = sampleReport()
        long.problems = (0..<120).map { "Строка \($0): узел не отвечал, потери пакетов выше порога" }
        let short = ReportBuilder.makePDF(sampleReport())
        let big = ReportBuilder.makePDF(long)
        XCTAssertGreaterThan(big.count, short.count, "Длинный отчёт занимает больше страниц")
    }

    func testGPXContainsPointsTimesAndEscapedText() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let route = RouteRecord(
            startedAt: start,
            points: [
                RoutePoint(time: start, latitude: 55.75, longitude: 37.62, latencyMs: 40),
                RoutePoint(time: start.addingTimeInterval(30), latitude: 55.7512, longitude: 37.6234, latencyMs: 55)
            ]
        )
        let gpx = RouteExport.gpx(for: route, appVersion: "1.0 & <1>")
        XCTAssertTrue(gpx.hasPrefix("<?xml"))
        XCTAssertTrue(gpx.contains("<trkpt lat=\"55.7500000\" lon=\"37.6200000\">"))
        XCTAssertEqual(gpx.components(separatedBy: "<trkpt ").count - 1, 2)
        XCTAssertTrue(gpx.contains("<time>"))
        XCTAssertTrue(gpx.contains("1.0 &amp; &lt;1&gt;"), "Спецсимволы в GPX экранируются")
        XCTAssertTrue(gpx.hasSuffix("</gpx>\n"))
    }

    func testPointDescriptionMentionsLatencyAndSilence() {
        let start = Date()
        let good = RoutePoint(time: start, latitude: 55, longitude: 37, latencyMs: 42)
        XCTAssertTrue(RouteExport.description(of: good).contains("задержка 42 мс"))
        let silent = RoutePoint(time: start, latitude: 55, longitude: 37, reachable: false)
        XCTAssertTrue(RouteExport.description(of: silent).contains("нет ответа сети"))
    }

    func testSpeedTestRequestIsConsumedOnceAndExpires() throws {
        let suite = "netpulse.test.intent.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertFalse(SpeedTestRequest.consume(defaults: defaults, now: now), "Просьбы нет — замера нет")
        SpeedTestRequest.request(defaults: defaults, now: now)
        XCTAssertTrue(SpeedTestRequest.consume(defaults: defaults, now: now.addingTimeInterval(5)))
        XCTAssertFalse(SpeedTestRequest.consume(defaults: defaults, now: now.addingTimeInterval(6)), "Просьба забирается один раз")

        SpeedTestRequest.request(defaults: defaults, now: now)
        XCTAssertFalse(
            SpeedTestRequest.consume(defaults: defaults, now: now.addingTimeInterval(SpeedTestRequest.lifetime + 1)),
            "Забытая просьба не запускает замер через час"
        )
    }

    @MainActor
    func testAlertsAreOffByDefaultAndNeverNotifyFreeUsers() throws {
        let suite = "netpulse.test.alerts.\(UUID().uuidString)"
        let notifier = AlertNotifier(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertFalse(notifier.isEnabled, "Оповещения включает только пользователь")
        notifier.isEnabled = true
        XCTAssertTrue(notifier.isEnabled)
        notifier.disable()
        XCTAssertFalse(notifier.isEnabled)
        XCTAssertFalse(notifier.isThrottled(key: "host|availability"))
    }
}
