//
//  StabilityTests.swift
//  NetPulseTests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest
@testable import NetPulse

// MARK: - Подготовка данных

private let now = Date(timeIntervalSince1970: 1_800_000_000)

/// Два узла интернета и роутер: ответы в шагах идут в этом же порядке
private func hostsWithGateway() -> [StabilityHost] {
    [
        StabilityHost(name: "A", address: "1.1.1.1"),
        StabilityHost(name: "B", address: "2.2.2.2"),
        StabilityHost(name: "Роутер", address: "192.168.1.1", port: 53, isGateway: true)
    ]
}

private func hostsWithoutGateway() -> [StabilityHost] {
    [
        StabilityHost(name: "A", address: "1.1.1.1"),
        StabilityHost(name: "B", address: "2.2.2.2"),
        StabilityHost(name: "C", address: "3.3.3.3")
    ]
}

private func tick(_ offset: Double, _ latencies: [Double?]) -> StabilityTick {
    StabilityTick(
        offset: offset,
        probes: latencies.enumerated().map { StabilityProbe(host: $0.offset, latencyMs: $0.element) }
    )
}

private func finish(_ accumulator: StabilityAccumulator, early: Bool = false) -> StabilityResult {
    accumulator.makeResult(startedAt: now, connection: "Wi-Fi", finishedEarly: early, pausedSeconds: 0)
}

// MARK: - Накопление шагов

final class StabilityAccumulatorTests: XCTestCase {

    func testLossAndLatencyAreCountedOverAllInternetHosts() throws {
        var accumulator = StabilityAccumulator(hosts: hostsWithoutGateway(), plannedSeconds: 300)
        for index in 0..<10 {
            accumulator.add(tick(Double(index), [20, 30, index == 4 ? nil : 40]))
        }
        let result = finish(accumulator)

        XCTAssertEqual(result.sent, 30)
        XCTAssertEqual(result.lost, 1)
        XCTAssertEqual(result.lossPercent, 100.0 / 30.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.averageMs), 860.0 / 29.0, accuracy: 0.001)
        XCTAssertEqual(result.minMs, 20)
        XCTAssertEqual(result.maxMs, 40)
        XCTAssertEqual(result.p95Ms, 40)
        XCTAssertEqual(result.activeSeconds, 10, accuracy: 0.001, "Последний шаг на 9-й секунде плюс его длительность")

        let third = result.hosts[2]
        XCTAssertEqual(third.sent, 10)
        XCTAssertEqual(third.lost, 1)
        XCTAssertEqual(try XCTUnwrap(third.averageMs), 40, accuracy: 0.001)
    }

    func testGatewayIsReportedSeparatelyAndDoesNotCountAsInternetLoss() {
        var accumulator = StabilityAccumulator(hosts: hostsWithGateway(), plannedSeconds: 300)
        for index in 0..<10 {
            accumulator.add(tick(Double(index), [20, 20, nil]))
        }
        let result = finish(accumulator)

        XCTAssertEqual(result.lossPercent, 0, "Роутер не отвечает, а интернет в порядке: потерь интернета нет")
        XCTAssertEqual(result.sent, 20)
        let gateway = try? XCTUnwrap(result.gateway)
        XCTAssertEqual(gateway?.lossPercent, 100)
        XCTAssertTrue(result.outages.isEmpty, "Обрыв — это когда не отвечает интернет, а не роутер")
    }

    func testJitterIsTheAverageStepBetweenNeighbouringAnswers() throws {
        var accumulator = StabilityAccumulator(hosts: [StabilityHost(name: "A", address: "1.1.1.1")], plannedSeconds: 300)
        for (index, value) in [10.0, 20, 10, 20].enumerated() {
            accumulator.add(tick(Double(index), [value]))
        }
        XCTAssertEqual(try XCTUnwrap(finish(accumulator).jitterMs), 10, accuracy: 0.001)
    }

    func testPercentileUsesNearestRank() throws {
        var accumulator = StabilityAccumulator(hosts: [StabilityHost(name: "A", address: "1.1.1.1")], plannedSeconds: 300)
        for index in 0..<100 {
            accumulator.add(tick(Double(index), [Double(index + 1)]))
        }
        let result = finish(accumulator)
        XCTAssertEqual(result.p95Ms, 95)
        XCTAssertEqual(result.minMs, 1)
        XCTAssertEqual(result.maxMs, 100)
        XCTAssertEqual(try XCTUnwrap(result.averageMs), 50.5, accuracy: 0.001)
    }

    func testBrokenLatenciesCountAsLostAndUnknownHostsAreIgnored() {
        var accumulator = StabilityAccumulator(hosts: [StabilityHost(name: "A", address: "1.1.1.1")], plannedSeconds: 300)
        accumulator.add(tick(0, [.nan]))
        accumulator.add(tick(1, [-5]))
        accumulator.add(tick(2, [10]))
        accumulator.add(StabilityTick(offset: 3, probes: [StabilityProbe(host: 7, latencyMs: 10)]))
        let result = finish(accumulator)

        XCTAssertEqual(result.sent, 3)
        XCTAssertEqual(result.lost, 2)
    }

    func testEmptyTestHasNoNumbersAndNoDuration() {
        let result = finish(StabilityAccumulator(hosts: hostsWithoutGateway(), plannedSeconds: 300))
        XCTAssertEqual(result.sent, 0)
        XCTAssertEqual(result.lossPercent, 0)
        XCTAssertNil(result.averageMs)
        XCTAssertNil(result.p95Ms)
        XCTAssertEqual(result.activeSeconds, 0)
        XCTAssertTrue(result.buckets.isEmpty)
    }

    // MARK: Обрывы

    func testSeveralSilentStepsInARowAreAnOutage() {
        var accumulator = StabilityAccumulator(hosts: hostsWithGateway(), plannedSeconds: 300)
        for index in 0..<15 {
            let down = (5..<10).contains(index)
            accumulator.add(tick(Double(index), [down ? nil : 20, down ? nil : 20, 2]))
        }
        let result = finish(accumulator)

        XCTAssertEqual(result.outages.count, 1)
        XCTAssertEqual(result.outages[0].start, 5, accuracy: 0.001)
        XCTAssertEqual(result.outages[0].duration, 5, accuracy: 0.001)
        XCTAssertEqual(result.outages[0].gatewayAnswered, true, "Роутер отвечал: рвётся дальше роутера")
        XCTAssertEqual(result.lossPercent, 100.0 / 3.0, accuracy: 0.001)
    }

    func testOutageWhereTheRouterIsSilentToo() {
        var accumulator = StabilityAccumulator(hosts: hostsWithGateway(), plannedSeconds: 300)
        for index in 0..<10 {
            let down = (3..<7).contains(index)
            accumulator.add(tick(Double(index), [down ? nil : 20, down ? nil : 20, down ? nil : 2]))
        }
        XCTAssertEqual(finish(accumulator).outages.first?.gatewayAnswered, false)
    }

    func testOutageWithoutARouterHostHasNoRouterVerdict() {
        var accumulator = StabilityAccumulator(hosts: hostsWithoutGateway(), plannedSeconds: 300)
        for index in 0..<10 {
            let down = (3..<7).contains(index)
            accumulator.add(tick(Double(index), [down ? nil : 20, down ? nil : 20, down ? nil : 20]))
        }
        let outages = finish(accumulator).outages
        XCTAssertEqual(outages.count, 1)
        XCTAssertNil(outages[0].gatewayAnswered)
    }

    func testOneSilentStepIsAGlitchNotAnOutage() {
        var accumulator = StabilityAccumulator(hosts: hostsWithGateway(), plannedSeconds: 300)
        for index in 0..<10 {
            let down = index == 5
            accumulator.add(tick(Double(index), [down ? nil : 20, down ? nil : 20, 2]))
        }
        XCTAssertTrue(finish(accumulator).outages.isEmpty)
    }

    func testOutageStillGoingAtTheEndIsCounted() {
        var accumulator = StabilityAccumulator(hosts: hostsWithGateway(), plannedSeconds: 300)
        for index in 0..<9 {
            let down = index >= 5
            accumulator.add(tick(Double(index), [down ? nil : 20, down ? nil : 20, 2]))
        }
        XCTAssertEqual(accumulator.liveOutageCount, 1)
        XCTAssertTrue(accumulator.isDownNow)
        let outages = finish(accumulator).outages
        XCTAssertEqual(outages.count, 1)
        XCTAssertEqual(outages[0].duration, 4, accuracy: 0.001)
    }

    func testLiveNumbersFollowTheLastStep() throws {
        var accumulator = StabilityAccumulator(hosts: hostsWithGateway(), plannedSeconds: 300)
        accumulator.add(tick(0, [20, 40, 2]))
        XCTAssertEqual(try XCTUnwrap(accumulator.lastLatencyMs), 30, accuracy: 0.001, "Среднее по узлам интернета, роутер не в счёте")
        accumulator.add(tick(1, [nil, nil, 2]))
        XCTAssertNil(accumulator.lastLatencyMs)
        XCTAssertEqual(accumulator.liveLossPercent, 50, accuracy: 0.001)
    }

    // MARK: График

    func testBucketsGroupStepsAndMarkTheSilentOnes() throws {
        var accumulator = StabilityAccumulator(hosts: hostsWithGateway(), plannedSeconds: 300)
        for index in 0..<10 {
            let down = index >= 5
            accumulator.add(tick(Double(index), [down ? nil : 20, down ? nil : 20, 2]))
        }
        let buckets = finish(accumulator).buckets

        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets[0].start, 0)
        XCTAssertEqual(try XCTUnwrap(buckets[0].averageMs), 20, accuracy: 0.001)
        XCTAssertEqual(buckets[0].lossPercent, 0)
        XCTAssertFalse(buckets[0].isDown)
        XCTAssertEqual(buckets[1].start, 5)
        XCTAssertNil(buckets[1].averageMs)
        XCTAssertEqual(buckets[1].lossPercent, 100)
        XCTAssertTrue(buckets[1].isDown)
    }

    func testBucketWidthKeepsTheGraphUnderAboutOneHundredTwentyPoints() {
        XCTAssertEqual(StabilityAccumulator.bucketSeconds(forPlanned: 300), 5)
        XCTAssertEqual(StabilityAccumulator.bucketSeconds(forPlanned: 900), 8)
        XCTAssertEqual(StabilityAccumulator.bucketSeconds(forPlanned: 1_800), 15)
        XCTAssertEqual(StabilityAccumulator.bucketSeconds(forPlanned: 3_600), 30)
        XCTAssertEqual(StabilityAccumulator.bucketSeconds(forPlanned: 0), 5)
        XCTAssertEqual(StabilityAccumulator.bucketSeconds(forPlanned: .nan), 5)
    }
}

// MARK: - Узлы

final class StabilityHostTests: XCTestCase {

    func testRouterIsAddedOnlyWithAUsableAddress() {
        XCTAssertEqual(StabilityHost.defaults(gateway: nil).count, 3)
        XCTAssertEqual(StabilityHost.defaults(gateway: "192.168.1.1").count, 4)
        XCTAssertTrue(StabilityHost.defaults(gateway: "192.168.1.1").last?.isGateway ?? false)
        for bad in ["gateway", "", "—", "1.2.3", "300.1.1.1", "1.2.3.4.5", "a.b.c.d", "-1.2.3.4", "1..3.4", "1.2.3.+4"] {
            XCTAssertEqual(StabilityHost.defaults(gateway: bad).count, 3, "Адрес «\(bad)» не годится для роутера")
        }
    }

    func testInternetHostsComeFirstAndAreNotGateways() {
        let hosts = StabilityHost.defaults(gateway: "10.0.0.1")
        XCTAssertEqual(hosts.filter { !$0.isGateway }.map(\.address), ["1.1.1.1", "8.8.8.8", "9.9.9.9"])
    }
}

// MARK: - Вывод

final class StabilityVerdictTests: XCTestCase {

    private func result(
        active: Double = 600,
        sent: Int = 1_800,
        lost: Int = 0,
        p95: Double? = 40,
        jitter: Double? = 5,
        outages: [StabilityOutage] = [],
        gateway: StabilityHostSummary? = nil
    ) -> StabilityResult {
        var hosts = [StabilityHostSummary(
            name: "Cloudflare", address: "1.1.1.1", isGateway: false, sent: sent, lost: lost,
            averageMs: 30, maxMs: 60, jitterMs: jitter
        )]
        if let gateway { hosts.append(gateway) }
        return StabilityResult(
            startedAt: now, plannedSeconds: 600, activeSeconds: active, pausedSeconds: 0, finishedEarly: false,
            connection: "Wi-Fi", hosts: hosts, sent: sent, lost: lost, averageMs: 30, minMs: 10, maxMs: 80,
            p95Ms: p95, jitterMs: jitter, outages: outages, buckets: [], bucketSeconds: 5
        )
    }

    private func router(sent: Int = 600, lost: Int = 0) -> StabilityHostSummary {
        StabilityHostSummary(name: "Роутер", address: "192.168.1.1", isGateway: true, sent: sent, lost: lost, averageMs: 3, maxMs: 10, jitterMs: 1)
    }

    func testSteadyConnectionIsExcellent() {
        let verdict = result().verdict
        XCTAssertEqual(verdict.level, .excellent)
        XCTAssertEqual(verdict.title, "Связь стабильная")
        XCTAssertEqual(verdict.summary, "Потеряно 0 % запросов, обрывов не было, в 95 % случаев ответ быстрее 40 мс.")
        XCTAssertNil(verdict.cause)
    }

    func testSmallWobblesAreGoodNotExcellent() {
        XCTAssertEqual(result(lost: 9).verdict.level, .good, "0,5 % потерь")
        XCTAssertEqual(result(p95: 120).verdict.level, .good)
        XCTAssertEqual(result(jitter: 25).verdict.level, .good)
        XCTAssertNil(result(lost: 9).verdict.cause, "Причину называем только когда есть что чинить")
    }

    func testLossesOutagesOrSlowAnswersMakeItUnstable() {
        XCTAssertEqual(result(lost: 36).verdict.level, .unstable, "2 % потерь")
        XCTAssertEqual(result(outages: [StabilityOutage(start: 100, duration: 3)]).verdict.level, .unstable)
        XCTAssertEqual(result(p95: 250).verdict.level, .unstable)
        XCTAssertEqual(result(jitter: 45).verdict.level, .unstable)
    }

    func testHeavyLossesLongOrFrequentOutagesMakeItBad() {
        XCTAssertEqual(result(lost: 100).verdict.level, .bad, "Больше 5 % потерь")
        XCTAssertEqual(result(outages: [StabilityOutage(start: 100, duration: 12)]).verdict.level, .bad)
        XCTAssertEqual(
            result(outages: (0..<3).map { StabilityOutage(start: Double($0) * 100, duration: 3) }).verdict.level,
            .bad
        )
        XCTAssertEqual(result(p95: 450).verdict.level, .bad)
    }

    func testTooShortTestSaysSoInsteadOfGuessing() {
        let short = result(active: 20).verdict
        XCTAssertEqual(short.level, .insufficient)
        XCTAssertEqual(short.title, "Мало данных")
        XCTAssertEqual(result(sent: 50).verdict.level, .insufficient)
        XCTAssertNil(short.cause)
    }

    func testSummaryNamesOutagesAndTheLongestOne() {
        let outages = [StabilityOutage(start: 10, duration: 4), StabilityOutage(start: 100, duration: 12.4)]
        let summary = result(lost: 36, outages: outages).verdict.summary
        XCTAssertTrue(summary.contains("обрывов: 2, самый долгий 12 с"))
        XCTAssertTrue(summary.contains("Потеряно 2 % запросов"))
    }

    // MARK: Причина

    func testLossesAlreadyBeforeTheRouterPointToWiFi() throws {
        let verdict = result(lost: 36, gateway: router(lost: 30)).verdict
        XCTAssertTrue(try XCTUnwrap(verdict.cause).contains("до роутера"))
    }

    func testQuietRouterAndBrokenInternetPointToTheProvider() throws {
        let verdict = result(lost: 36, gateway: router(lost: 0)).verdict
        XCTAssertTrue(try XCTUnwrap(verdict.cause).contains("провайдер"))
    }

    func testAnOutageWithASilentRouterPointsToWiFiEvenWithLowOverallLoss() throws {
        let outage = StabilityOutage(start: 100, duration: 3, gatewayAnswered: false)
        let verdict = result(outages: [outage], gateway: router(lost: 2)).verdict
        XCTAssertTrue(try XCTUnwrap(verdict.cause).contains("до роутера"))
    }

    func testWithoutARouterTheAppAdmitsItCannotTellSignalFromTheOperator() throws {
        let verdict = result(lost: 36).verdict
        XCTAssertTrue(try XCTUnwrap(verdict.cause).contains("мобильной сети"))
    }

    func testNumberFormatting() {
        XCTAssertEqual(StabilityAnalyzer.format(0), "0")
        XCTAssertEqual(StabilityAnalyzer.format(0.45), "0.5")
        XCTAssertEqual(StabilityAnalyzer.format(12.04), "12")
        XCTAssertEqual(StabilityAnalyzer.format(33.333), "33.3")
    }
}

// MARK: - Текст итога

final class StabilityReportTextTests: XCTestCase {

    private func sampleResult() -> StabilityResult {
        StabilityResult(
            startedAt: now, plannedSeconds: 900, activeSeconds: 600, pausedSeconds: 30, finishedEarly: true,
            connection: "Wi-Fi",
            hosts: [
                StabilityHostSummary(name: "Cloudflare", address: "1.1.1.1", isGateway: false, sent: 600, lost: 12, averageMs: 31, maxMs: 90, jitterMs: 6),
                StabilityHostSummary(name: "Роутер", address: "192.168.1.1", isGateway: true, sent: 600, lost: 0, averageMs: 3, maxMs: 8, jitterMs: 1)
            ],
            sent: 600, lost: 12, averageMs: 31, minMs: 12, maxMs: 90, p95Ms: 70, jitterMs: 6,
            outages: [StabilityOutage(start: 125, duration: 8, gatewayAnswered: true)],
            buckets: [], bucketSeconds: 5
        )
    }

    func testFullTextHasTheNumbersAProviderWouldAskFor() {
        let text = StabilityReportText.text(for: sampleResult())
        XCTAssertTrue(text.contains("Подключение: Wi-Fi"))
        XCTAssertTrue(text.contains("остановлен до конца, планировалось 15 мин"))
        XCTAssertTrue(text.contains("Приложение не работало 30 с"))
        XCTAssertTrue(text.contains("Итог: Связь нестабильная"))
        XCTAssertTrue(text.contains("в среднем 31 мс"))
        XCTAssertTrue(text.contains("95 % ответов быстрее 70 мс"))
        XCTAssertTrue(text.contains("• Cloudflare: потери 2 %"))
        XCTAssertTrue(text.contains("на 2:05 от начала, 8 с (роутер отвечал)"))
        XCTAssertTrue(text.contains("провайдер"))
    }

    func testOneLineForThePdfReport() {
        let line = StabilityReportText.line(for: sampleResult())
        XCTAssertTrue(line.contains("Wi-Fi"))
        XCTAssertTrue(line.contains("потери 2 %"))
        XCTAssertTrue(line.contains("обрывов: 1, самый долгий 8 с"))
        XCTAssertTrue(line.hasSuffix("Связь нестабильная."))
    }

    func testDurationAndClockFormats() {
        XCTAssertEqual(StabilityReportText.duration(40), "40 с")
        XCTAssertEqual(StabilityReportText.duration(600), "10 мин")
        XCTAssertEqual(StabilityReportText.duration(.nan), "—")
        XCTAssertEqual(StabilityReportText.clock(125), "2:05")
        XCTAssertEqual(StabilityReportText.clock(-3), "0:00")
    }
}

// MARK: - Прогон теста

private struct FixedProber: StabilityProbing {
    let latency: Double?

    func probe(hosts: [StabilityHost]) async -> [StabilityProbe] {
        hosts.indices.map { StabilityProbe(host: $0, latencyMs: latency) }
    }
}

@MainActor
private final class FakeBackground: StabilityBackgroundHosting {
    var isActive = false
    var accept = true
    private(set) var beginCount = 0
    private(set) var endResults: [Bool] = []
    private(set) var updates = 0
    private var expire: (@MainActor () -> Void)?

    func begin(totalSeconds: Int, title: String, subtitle: String, onExpire: @escaping @MainActor () -> Void) -> Bool {
        beginCount += 1
        guard accept else { return false }
        expire = onExpire
        isActive = true
        return true
    }

    func update(completedSeconds: Int, subtitle: String) {
        updates += 1
    }

    func end(success: Bool) {
        endResults.append(success)
        isActive = false
    }

    func systemExpires() {
        expire?()
    }
}

@MainActor
private final class AwakeLog {
    var values: [Bool] = []
}

@MainActor
private func waitUntil(timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}

final class StabilityTestRunnerTests: XCTestCase {

    @MainActor
    private func makeRunner(
        latency: Double? = 25,
        background: FakeBackground? = nil,
        awake: AwakeLog = AwakeLog(),
        minSavedSeconds: TimeInterval = StabilityTestRunner.minSavedSeconds
    ) -> (runner: StabilityTestRunner, history: StabilityHistoryStore) {
        let history = StabilityHistoryStore(fileURL: nil)
        let runner = StabilityTestRunner(
            prober: FixedProber(latency: latency),
            history: history,
            background: background,
            tickSeconds: 0.01,
            minSavedSeconds: minSavedSeconds,
            setScreenAwake: { awake.values.append($0) }
        )
        return (runner, history)
    }

    @MainActor
    func testTestRunsToTheEndAndProducesAResult() async throws {
        let background = FakeBackground()
        let awake = AwakeLog()
        let (runner, history) = makeRunner(background: background, awake: awake, minSavedSeconds: 0.05)

        runner.start(durationSeconds: 0.3, hosts: hostsWithoutGateway(), connection: "Wi-Fi")
        XCTAssertEqual(runner.state, .running)
        XCTAssertTrue(runner.isRunning)

        let done = await waitUntil { runner.state == .finished }
        XCTAssertTrue(done, "Тест должен закончиться сам")

        let result = try XCTUnwrap(runner.result)
        XCTAssertFalse(result.finishedEarly)
        XCTAssertEqual(result.lossPercent, 0)
        XCTAssertGreaterThan(result.sent, 20)
        XCTAssertEqual(result.connection, "Wi-Fi")
        XCTAssertEqual(runner.progress, 1, accuracy: 0.001)

        XCTAssertEqual(background.beginCount, 1)
        XCTAssertEqual(background.endResults, [true])
        XCTAssertGreaterThan(background.updates, 5, "Системное окно получает ход теста каждую секунду")
        XCTAssertEqual(awake.values, [true, false], "Экран не гаснет, пока идёт тест, и освобождается в конце")
        XCTAssertEqual(history.results.map(\.id), [result.id], "Законченный тест попадает в историю")
    }

    @MainActor
    func testUserCanStopTheTestAndKeepsWhatWasCollected() async throws {
        let background = FakeBackground()
        let (runner, history) = makeRunner(background: background)

        runner.start(durationSeconds: 60, hosts: hostsWithoutGateway(), connection: "Wi-Fi")
        let collected = await waitUntil { runner.activeSeconds > 0.1 }
        XCTAssertTrue(collected)

        runner.stop()
        XCTAssertEqual(runner.state, .finished)
        let result = try XCTUnwrap(runner.result)
        XCTAssertTrue(result.finishedEarly)
        XCTAssertGreaterThan(result.sent, 0)
        XCTAssertEqual(background.endResults, [true], "Пользователь остановил сам: для системы это обычное завершение")
        XCTAssertTrue(history.results.isEmpty, "Тест короче 10 секунд в историю не попадает")
    }

    @MainActor
    func testTooShortTestIsNotSavedButAnyLongerOneIs() async throws {
        let (strict, strictHistory) = makeRunner(minSavedSeconds: 10)
        strict.start(durationSeconds: 0.2, hosts: hostsWithoutGateway(), connection: "Wi-Fi")
        _ = await waitUntil { strict.state == .finished }
        XCTAssertTrue(strictHistory.results.isEmpty, "Тест короче 10 секунд в историю не попадает")

        let (lenient, lenientHistory) = makeRunner(minSavedSeconds: 0.05)
        lenient.start(durationSeconds: 0.2, hosts: hostsWithoutGateway(), connection: "Wi-Fi")
        _ = await waitUntil { lenient.state == .finished }
        XCTAssertEqual(lenientHistory.results.count, 1)
    }

    @MainActor
    func testSystemEndingTheBackgroundTaskStopsTheTest() async throws {
        let background = FakeBackground()
        let (runner, _) = makeRunner(background: background)

        runner.start(durationSeconds: 60, hosts: hostsWithoutGateway(), connection: "Wi-Fi")
        _ = await waitUntil { runner.activeSeconds > 0.05 }
        background.systemExpires()

        XCTAssertEqual(runner.state, .finished)
        XCTAssertEqual(runner.result?.finishedEarly, true)
        XCTAssertEqual(background.endResults, [false], "Систему тест не дожидался: это неудачное завершение")
    }

    @MainActor
    func testRefusedBackgroundTaskStillLetsTheTestRun() async throws {
        let background = FakeBackground()
        background.accept = false
        let (runner, _) = makeRunner(background: background)

        runner.start(durationSeconds: 0.2, hosts: hostsWithoutGateway(), connection: "Wi-Fi")
        XCTAssertFalse(runner.runsInBackground)
        let done = await waitUntil { runner.state == .finished }
        XCTAssertTrue(done)
    }

    @MainActor
    func testIslandGetsThePingAndLossOnlyWhileTheTestRuns() async throws {
        let (runner, _) = makeRunner(latency: 25)
        XCTAssertNil(runner.islandSnapshot, "Теста нет: острову нечего брать")

        runner.start(durationSeconds: 60, hosts: hostsWithoutGateway(), connection: "Wi-Fi")
        let ready = await waitUntil { runner.islandSnapshot != nil }
        XCTAssertTrue(ready)
        XCTAssertEqual(try XCTUnwrap(runner.islandSnapshot?.pingMs), 25, accuracy: 0.001)
        XCTAssertEqual(runner.islandSnapshot?.lossPercent, 0)

        runner.stop()
        XCTAssertNil(runner.islandSnapshot, "Тест закончился: пинг теста больше не выдаётся за живой")
    }

    @MainActor
    func testSilentNetworkIsRecordedAsAnOutageNotAsAnEndlessWait() async throws {
        let (runner, _) = makeRunner(latency: nil)

        runner.start(durationSeconds: 0.3, hosts: hostsWithoutGateway(), connection: "Wi-Fi")
        _ = await waitUntil { runner.state == .finished }
        let result = try XCTUnwrap(runner.result)

        XCTAssertEqual(result.lossPercent, 100)
        XCTAssertEqual(result.outages.count, 1)
        XCTAssertNil(result.averageMs)
    }

    @MainActor
    func testSecondStartWhileRunningIsIgnoredAndBadInputIsRefused() async throws {
        let (runner, _) = makeRunner()
        runner.start(durationSeconds: 0, hosts: hostsWithoutGateway(), connection: "Wi-Fi")
        XCTAssertEqual(runner.state, .idle)
        runner.start(durationSeconds: 60, hosts: [], connection: "Wi-Fi")
        XCTAssertEqual(runner.state, .idle)

        runner.start(durationSeconds: 60, hosts: hostsWithoutGateway(), connection: "Wi-Fi")
        runner.start(durationSeconds: 5, hosts: hostsWithoutGateway(), connection: "Сотовая")
        XCTAssertEqual(runner.plannedSeconds, 60)
        XCTAssertEqual(runner.connection, "Wi-Fi")
        runner.stop()
    }

    @MainActor
    func testResetReturnsToTheStartScreenOnlyAfterTheTest() async throws {
        let (runner, _) = makeRunner()
        runner.start(durationSeconds: 60, hosts: hostsWithoutGateway(), connection: "Wi-Fi")
        runner.reset()
        XCTAssertEqual(runner.state, .running, "Во время теста сбросить нельзя")

        runner.stop()
        runner.reset()
        XCTAssertEqual(runner.state, .idle)
        XCTAssertNil(runner.result)
    }

    @MainActor
    func testDurationOptionsAreFiveFifteenThirtyAndSixtyMinutes() {
        XCTAssertEqual(StabilityTestRunner.durationOptions, [300, 900, 1_800, 3_600])
    }
}

// MARK: - История тестов

final class StabilityHistoryStoreTests: XCTestCase {

    private func sample(_ offset: TimeInterval, lost: Int = 0) -> StabilityResult {
        StabilityResult(
            startedAt: now.addingTimeInterval(offset), plannedSeconds: 300, activeSeconds: 300, pausedSeconds: 0,
            finishedEarly: false, connection: "Wi-Fi", hosts: [], sent: 900, lost: lost, averageMs: 30, minMs: 10,
            maxMs: 80, p95Ms: 50, jitterMs: 5, outages: [], buckets: [], bucketSeconds: 5
        )
    }

    @MainActor
    func testNewestTestsComeFirstAndTheListIsLimited() {
        let store = StabilityHistoryStore(fileURL: nil)
        for index in 0..<(StabilityHistoryStore.maxEntries + 3) {
            store.add(sample(Double(index)))
        }
        XCTAssertEqual(store.results.count, StabilityHistoryStore.maxEntries)
        XCTAssertEqual(store.results.first?.startedAt, now.addingTimeInterval(Double(StabilityHistoryStore.maxEntries + 2)))
    }

    @MainActor
    func testAddingTheSameResultTwiceKeepsOneCopy() {
        let store = StabilityHistoryStore(fileURL: nil)
        let result = sample(0)
        store.add(result)
        store.add(result)
        XCTAssertEqual(store.results.count, 1)
    }

    @MainActor
    func testRemoveAndClear() {
        let store = StabilityHistoryStore(fileURL: nil)
        let first = sample(0)
        let second = sample(10)
        store.add(first)
        store.add(second)
        store.remove(id: first.id)
        XCTAssertEqual(store.results.map(\.id), [second.id])
        store.clear()
        XCTAssertTrue(store.results.isEmpty)
    }

    @MainActor
    func testResultsSurviveARestart() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("netpulse-stability-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = StabilityHistoryStore(fileURL: url)
        let result = sample(0, lost: 7)
        store.add(result)

        // Запись идёт в фоне: ждём файл
        let written = await waitUntil { FileManager.default.fileExists(atPath: url.path) }
        XCTAssertTrue(written)

        let reopened = StabilityHistoryStore(fileURL: url)
        XCTAssertEqual(reopened.results.count, 1)
        XCTAssertEqual(reopened.results.first?.id, result.id)
        XCTAssertEqual(reopened.results.first?.lost, 7)
    }
}
