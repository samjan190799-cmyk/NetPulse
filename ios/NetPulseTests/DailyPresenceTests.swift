//
//  DailyPresenceTests.swift
//  NetPulseTests
//
//  Быстрая проверка связи, журнал замеров, утренняя сводка и снимок для виджетов.
//

import XCTest
@testable import NetPulse

// MARK: - Общее

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 3
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = 0
    components.timeZone = TimeZone(secondsFromGMT: 0)
    return utc.date(from: components)!
}

private func sample(_ time: Date, ping: Double?, reached: Int = 3, total: Int = 3, connection: String = "Wi-Fi") -> QuickCheckSample {
    QuickCheckSample(time: time, pingMs: ping, reached: reached, total: total, connection: connection)
}

private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("netpulse-quick-\(UUID().uuidString).json")
}

/// Подставной замер: время ответа по адресу узла; нет в словаре — узел молчит
private struct FakeConnector: QuickCheckConnecting {
    let latencies: [String: Double]

    func connect(to host: QuickCheckHost, timeout: TimeInterval) async -> Double? {
        // Разное время «ответа», чтобы порядок ответов не совпадал с порядком узлов
        let delay: UInt64 = host.host == "1.1.1.1" ? 30_000_000 : 1_000_000
        try? await Task.sleep(nanoseconds: delay)
        return latencies[host.host]
    }
}

// MARK: - Вердикт

final class QuickCheckVerdictTests: XCTestCase {

    func testNothingAnswersMeansNoConnection() {
        XCTAssertEqual(QuickCheckVerdict.classify(medianMs: nil, reached: 0, total: 3), .offline)
        XCTAssertEqual(QuickCheckVerdict.classify(medianMs: 20, reached: 0, total: 3), .offline)
        XCTAssertEqual(QuickCheckVerdict.classify(medianMs: 20, reached: 0, total: 0), .offline)
    }

    func testOneNodeOfThreeIsNotEnoughButTwoAreFine() {
        XCTAssertEqual(QuickCheckVerdict.classify(medianMs: 20, reached: 1, total: 3), .poor)
        XCTAssertEqual(QuickCheckVerdict.classify(medianMs: 20, reached: 2, total: 3), .excellent)
        XCTAssertEqual(QuickCheckVerdict.classify(medianMs: 20, reached: 1, total: 2), .poor)
    }

    func testPingThresholds() {
        XCTAssertEqual(QuickCheckVerdict.classify(medianMs: 59.9, reached: 3, total: 3), .excellent)
        XCTAssertEqual(QuickCheckVerdict.classify(medianMs: 60, reached: 3, total: 3), .good)
        XCTAssertEqual(QuickCheckVerdict.classify(medianMs: 149.9, reached: 3, total: 3), .good)
        XCTAssertEqual(QuickCheckVerdict.classify(medianMs: 150, reached: 3, total: 3), .poor)
    }

    func testSnapshotVerdictNeedsAPingOrFullLoss() {
        XCTAssertNil(QuickCheckVerdict.fromSnapshot(pingMs: nil, lossPercent: 0))
        XCTAssertEqual(QuickCheckVerdict.fromSnapshot(pingMs: nil, lossPercent: 100), .offline)
        XCTAssertEqual(QuickCheckVerdict.fromSnapshot(pingMs: 30, lossPercent: 0), .excellent)
        XCTAssertEqual(QuickCheckVerdict.fromSnapshot(pingMs: 90, lossPercent: 0), .good)
        XCTAssertEqual(QuickCheckVerdict.fromSnapshot(pingMs: 30, lossPercent: 60), .poor)
        XCTAssertEqual(QuickCheckVerdict.fromSnapshot(pingMs: 300, lossPercent: 0), .poor)
    }

    func testEveryVerdictHasATitleSymbolAndScore() {
        let all: [QuickCheckVerdict] = [.excellent, .good, .poor, .offline]
        XCTAssertEqual(Set(all.map(\.title)).count, 4)
        XCTAssertEqual(Set(all.map(\.symbolName)).count, 4)
        XCTAssertEqual(all.map(\.healthScore), [95, 75, 40, 0])
    }
}

// MARK: - Проверка

final class QuickCheckRunTests: XCTestCase {

    func testRunCollectsAllNodesInListOrderAndComputesTheNumbers() async {
        let connector = FakeConnector(latencies: ["1.1.1.1": 30, "8.8.8.8": 20, "9.9.9.9": 50])
        let result = await QuickCheck.run(connector: connector, connection: "Wi-Fi", now: date(10, 12))

        XCTAssertEqual(result.probes.map(\.host.host), ["1.1.1.1", "8.8.8.8", "9.9.9.9"])
        XCTAssertEqual(result.reached, 3)
        XCTAssertEqual(result.total, 3)
        XCTAssertEqual(result.medianMs, 30)
        XCTAssertEqual(result.lossPercent, 0)
        XCTAssertEqual(result.verdict, .excellent)
        XCTAssertEqual(result.connection, "Wi-Fi")
        XCTAssertEqual(result.time, date(10, 12))
    }

    func testSilentNodesCountAsLoss() async {
        let connector = FakeConnector(latencies: ["8.8.8.8": 40])
        let result = await QuickCheck.run(connector: connector, connection: "Мобильная сеть")

        XCTAssertEqual(result.reached, 1)
        XCTAssertEqual(result.lossPercent, 200.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(result.verdict, .poor)
        XCTAssertEqual(result.medianMs, 40)
    }

    func testNoAnswersMeansOffline() async {
        let result = await QuickCheck.run(connector: FakeConnector(latencies: [:]), connection: "Нет сети")
        XCTAssertNil(result.medianMs)
        XCTAssertEqual(result.lossPercent, 100)
        XCTAssertEqual(result.verdict, .offline)
        XCTAssertTrue(result.sample.isDown)
    }

    func testMedianOfOddAndEvenLists() {
        XCTAssertNil(QuickCheckResult.median([]))
        XCTAssertEqual(QuickCheckResult.median([50, 10, 30]), 30)
        XCTAssertEqual(QuickCheckResult.median([10, 20, 30, 40]), 25)
    }

    func testTextsNameTheVerdictAndTheNumbers() async {
        let fast = await QuickCheck.run(connector: FakeConnector(latencies: ["1.1.1.1": 24, "8.8.8.8": 24, "9.9.9.9": 24]), connection: "Wi-Fi")
        XCTAssertEqual(fast.spokenText, "Связь отличная: пинг 24 мс. Wi-Fi.")
        XCTAssertEqual(fast.notificationTitle, "Связь: отлично")
        XCTAssertEqual(fast.notificationBody, "Пинг 24 мс · Wi-Fi")

        let normal = await QuickCheck.run(connector: FakeConnector(latencies: ["1.1.1.1": 90, "8.8.8.8": 90, "9.9.9.9": 90]), connection: "Wi-Fi")
        XCTAssertTrue(normal.spokenText.hasPrefix("Связь нормальная: пинг 90 мс"))

        let slow = await QuickCheck.run(connector: FakeConnector(latencies: ["1.1.1.1": 300, "8.8.8.8": 300, "9.9.9.9": 300]), connection: "Wi-Fi")
        XCTAssertTrue(slow.spokenText.hasPrefix("Связь медленная"))

        let partial = await QuickCheck.run(connector: FakeConnector(latencies: ["8.8.8.8": 40]), connection: "Wi-Fi")
        XCTAssertTrue(partial.spokenText.contains("ответили 1 из 3 узлов"))

        let offline = await QuickCheck.run(connector: FakeConnector(latencies: [:]), connection: "Нет сети")
        XCTAssertTrue(offline.spokenText.hasPrefix("Нет связи"))
        XCTAssertEqual(offline.notificationBody, "Ни один узел не отвечает · Нет сети")
    }

    func testDefaultHostsAreThreeIndependentServices() {
        let hosts = QuickCheckHost.defaults
        XCTAssertEqual(hosts.count, 3)
        XCTAssertEqual(Set(hosts.map(\.host)).count, 3)
        XCTAssertTrue(hosts.allSatisfy { $0.port == 443 })
    }
}

// MARK: - Журнал

final class QuickCheckLogTests: XCTestCase {

    func testSamplesComeBackOldestFirstAndSurviveARestart() {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let log = QuickCheckLog(fileURL: url)
        log.append(sample(date(10, 9), ping: 30))
        log.append(sample(date(10, 8), ping: 20))

        let again = QuickCheckLog(fileURL: url)
        XCTAssertEqual(again.samples().map(\.pingMs), [20, 30])
        XCTAssertEqual(again.samples(since: date(10, 9)).map(\.pingMs), [30])
    }

    func testOnlyTheNewestSamplesAreKept() {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let log = QuickCheckLog(fileURL: url)
        let total = QuickCheckLog.maxSamples + 5
        for index in 0..<total {
            log.append(sample(Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 60), ping: Double(index)))
        }
        let kept = log.samples()
        XCTAssertEqual(kept.count, QuickCheckLog.maxSamples)
        XCTAssertEqual(kept.last?.pingMs, Double(total - 1))
        XCTAssertEqual(kept.first?.pingMs, 5)
    }

    func testFrequentAppSamplesAreThinnedOut() {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let log = QuickCheckLog(fileURL: url)
        XCTAssertTrue(log.appendIfDue(sample(date(10, 9, 0), ping: 10), minInterval: 300))
        XCTAssertFalse(log.appendIfDue(sample(date(10, 9, 3), ping: 11), minInterval: 300), "Прошло 3 минуты из 5")
        XCTAssertTrue(log.appendIfDue(sample(date(10, 9, 5), ping: 12), minInterval: 300))
        XCTAssertEqual(log.samples().map(\.pingMs), [10, 12])
    }

    func testClearAndMissingFile() {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let log = QuickCheckLog(fileURL: url)
        XCTAssertTrue(log.samples().isEmpty)
        log.append(sample(date(10, 9), ping: 30))
        log.clear()
        XCTAssertTrue(log.samples().isEmpty)

        let withoutStorage = QuickCheckLog(fileURL: nil)
        withoutStorage.append(sample(date(10, 9), ping: 30))
        XCTAssertTrue(withoutStorage.samples().isEmpty, "Без хранилища журнал пуст и не падает")
    }

    func testBrokenFileIsTreatedAsEmpty() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("не json".utf8).write(to: url)

        let log = QuickCheckLog(fileURL: url)
        XCTAssertTrue(log.samples().isEmpty)
        log.append(sample(date(10, 9), ping: 30))
        XCTAssertEqual(log.samples().count, 1)
    }
}

// MARK: - Сводка за сутки

final class DailySummaryTests: XCTestCase {

    func testAveragePingAndCheckCount() {
        let summary = DailySummary.make(samples: [
            sample(date(10, 9), ping: 20),
            sample(date(10, 10), ping: 40),
            sample(date(10, 11), ping: nil, reached: 0)
        ], calendar: utc)
        XCTAssertEqual(summary.checks, 3)
        XCTAssertEqual(summary.averagePingMs, 30)
    }

    func testSeveralSilentChecksInARowAreOneOutage() {
        let summary = DailySummary.make(samples: [
            sample(date(10, 9), ping: 20),
            sample(date(10, 10), ping: nil, reached: 0),
            sample(date(10, 11), ping: nil, reached: 0),
            sample(date(10, 12), ping: 25),
            sample(date(10, 13), ping: nil, reached: 0)
        ], calendar: utc)
        XCTAssertEqual(summary.outages, 2)
    }

    func testPartialFailureIsNotAnOutage() {
        let summary = DailySummary.make(samples: [
            sample(date(10, 9), ping: 20, reached: 2),
            sample(date(10, 10), ping: 25, reached: 1)
        ], calendar: utc)
        XCTAssertEqual(summary.outages, 0)
    }

    func testWorstHourIsWhereMostChecksFailed() {
        let summary = DailySummary.make(samples: [
            sample(date(10, 9), ping: 20),
            sample(date(10, 21, 5), ping: 30, reached: 2),
            sample(date(10, 21, 35), ping: nil, reached: 0),
            sample(date(10, 22), ping: 40, reached: 2)
        ], calendar: utc)
        XCTAssertEqual(summary.worstHour, 21)
    }

    func testWithoutFailuresASlowHourIsNamedOnlyWhenItIsReallySlow() {
        let calm = DailySummary.make(samples: [
            sample(date(10, 9), ping: 20),
            sample(date(10, 10), ping: 60)
        ], calendar: utc)
        XCTAssertNil(calm.worstHour)

        let slow = DailySummary.make(samples: [
            sample(date(10, 9), ping: 20),
            sample(date(10, 18), ping: 130)
        ], calendar: utc)
        XCTAssertEqual(slow.worstHour, 18)
    }

    func testEmptyLogGivesAnEmptySummary() {
        let summary = DailySummary.make(samples: [], calendar: utc)
        XCTAssertEqual(summary.checks, 0)
        XCTAssertNil(summary.averagePingMs)
        XCTAssertEqual(summary.outages, 0)
        XCTAssertNil(summary.worstHour)
    }
}

// MARK: - Текст сводки

final class MorningSummaryTextTests: XCTestCase {

    func testTooFewChecksGiveNoSummary() {
        let summary = DailySummary(checks: 2, averagePingMs: 30, outages: 0, worstHour: nil)
        XCTAssertNil(MorningSummaryText.make(from: summary))
    }

    func testCalmDay() throws {
        let summary = DailySummary(checks: 20, averagePingMs: 32.4, outages: 0, worstHour: nil)
        let text = try XCTUnwrap(MorningSummaryText.make(from: summary))
        XCTAssertEqual(text.title, "Связь за сутки: всё ровно")
        XCTAssertEqual(text.body, "Средний пинг 32 мс. Обрывов не было.")
    }

    func testDayWithOutagesNamesTheWorstHour() throws {
        let summary = DailySummary(checks: 20, averagePingMs: 48, outages: 2, worstHour: 9)
        let text = try XCTUnwrap(MorningSummaryText.make(from: summary))
        XCTAssertEqual(text.title, "Связь за сутки: были обрывы")
        XCTAssertEqual(text.body, "Средний пинг 48 мс. Обрывов: 2. Хуже всего было около 09:00.")
    }

    func testSlowDayWithoutOutages() throws {
        let summary = DailySummary(checks: 20, averagePingMs: 180, outages: 0, worstHour: 21)
        let text = try XCTUnwrap(MorningSummaryText.make(from: summary))
        XCTAssertEqual(text.title, "Связь за сутки: было медленно")
        XCTAssertTrue(text.body.contains("около 21:00"))
    }
}

// MARK: - Планировщик

private final class FakeNotifications: NotificationScheduling, @unchecked Sendable {
    struct Scheduled: Equatable {
        let identifier: String
        let title: String
        let body: String
        let components: DateComponents
    }

    private let lock = NSLock()
    private var _authorized: Bool
    private var _scheduled: [Scheduled] = []
    private var _removed: [[String]] = []

    init(authorized: Bool) {
        _authorized = authorized
    }

    var scheduled: [Scheduled] { lock.lock(); defer { lock.unlock() }; return _scheduled }
    var removed: [[String]] { lock.lock(); defer { lock.unlock() }; return _removed }

    func isAuthorized() async -> Bool { _authorized }

    func schedule(identifier: String, title: String, body: String, at components: DateComponents) async {
        lock.lock()
        _scheduled.append(Scheduled(identifier: identifier, title: title, body: body, components: components))
        lock.unlock()
    }

    func removePending(identifiers: [String]) {
        lock.lock()
        _removed.append(identifiers)
        lock.unlock()
    }
}

final class MorningSummarySchedulerTests: XCTestCase {

    private func makeSettings(enabled: Bool, hour: Int? = nil, minute: Int? = nil) -> MorningSummarySettings {
        let suite = "netpulse.morning-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = MorningSummarySettings(defaults: defaults)
        settings.isEnabled = enabled
        if let hour { settings.hour = hour }
        if let minute { settings.minute = minute }
        return settings
    }

    private func makeLog(_ samples: [QuickCheckSample]) -> (QuickCheckLog, URL) {
        let url = temporaryFile()
        let log = QuickCheckLog(fileURL: url)
        samples.forEach { log.append($0) }
        return (log, url)
    }

    private var daySamples: [QuickCheckSample] {
        [
            sample(date(10, 9), ping: 30),
            sample(date(10, 14), ping: 40),
            sample(date(10, 20), ping: 50)
        ]
    }

    func testNextFireDateIsTodayIfTheTimeHasNotComeAndTomorrowIfItHas() throws {
        let before = try XCTUnwrap(MorningSummaryScheduler.nextFireDate(after: date(10, 7), hour: 8, minute: 30, calendar: utc))
        XCTAssertEqual(before, date(10, 8, 30))

        let after = try XCTUnwrap(MorningSummaryScheduler.nextFireDate(after: date(10, 22), hour: 8, minute: 30, calendar: utc))
        XCTAssertEqual(after, date(11, 8, 30))

        let exactly = try XCTUnwrap(MorningSummaryScheduler.nextFireDate(after: date(10, 8, 30), hour: 8, minute: 30, calendar: utc))
        XCTAssertEqual(exactly, date(11, 8, 30), "Если время уже наступило, берётся следующий день")
    }

    func testSchedulesTheNextMorningWithTheTextFromTheLog() async throws {
        let settings = makeSettings(enabled: true, hour: 8, minute: 30)
        let (log, url) = makeLog(daySamples)
        defer { try? FileManager.default.removeItem(at: url) }
        let notifications = FakeNotifications(authorized: true)

        await MorningSummaryScheduler.reschedule(
            now: date(10, 22), settings: settings, log: log, scheduler: notifications, calendar: utc
        )

        let scheduled = try XCTUnwrap(notifications.scheduled.first)
        XCTAssertEqual(notifications.scheduled.count, 1)
        XCTAssertEqual(scheduled.identifier, MorningSummaryScheduler.identifier)
        XCTAssertEqual(scheduled.title, "Связь за сутки: всё ровно")
        XCTAssertEqual(scheduled.body, "Средний пинг 40 мс. Обрывов не было.")
        XCTAssertEqual(scheduled.components.year, 2026)
        XCTAssertEqual(scheduled.components.month, 3)
        XCTAssertEqual(scheduled.components.day, 11)
        XCTAssertEqual(scheduled.components.hour, 8)
        XCTAssertEqual(scheduled.components.minute, 30)
    }

    func testOldSamplesDoNotCount() async {
        let settings = makeSettings(enabled: true)
        let stale = [
            sample(date(5, 9), ping: 30),
            sample(date(5, 10), ping: 30),
            sample(date(5, 11), ping: 30)
        ]
        let (log, url) = makeLog(stale)
        defer { try? FileManager.default.removeItem(at: url) }
        let notifications = FakeNotifications(authorized: true)

        await MorningSummaryScheduler.reschedule(
            now: date(10, 22), settings: settings, log: log, scheduler: notifications, calendar: utc
        )

        XCTAssertTrue(notifications.scheduled.isEmpty, "Замеры пятидневной давности в сводку за сутки не входят")
        XCTAssertEqual(notifications.removed.last, [MorningSummaryScheduler.identifier])
    }

    func testDisabledOrNotAllowedOrEmptyRemovesThePendingNotification() async {
        let (log, url) = makeLog(daySamples)
        defer { try? FileManager.default.removeItem(at: url) }

        let off = FakeNotifications(authorized: true)
        await MorningSummaryScheduler.reschedule(
            now: date(10, 22), settings: makeSettings(enabled: false), log: log, scheduler: off, calendar: utc
        )
        XCTAssertTrue(off.scheduled.isEmpty)
        XCTAssertEqual(off.removed.last, [MorningSummaryScheduler.identifier])

        let denied = FakeNotifications(authorized: false)
        await MorningSummaryScheduler.reschedule(
            now: date(10, 22), settings: makeSettings(enabled: true), log: log, scheduler: denied, calendar: utc
        )
        XCTAssertTrue(denied.scheduled.isEmpty)
        XCTAssertEqual(denied.removed.last, [MorningSummaryScheduler.identifier])

        let (emptyLog, emptyURL) = makeLog([])
        defer { try? FileManager.default.removeItem(at: emptyURL) }
        let nothing = FakeNotifications(authorized: true)
        await MorningSummaryScheduler.reschedule(
            now: date(10, 22), settings: makeSettings(enabled: true), log: emptyLog, scheduler: nothing, calendar: utc
        )
        XCTAssertTrue(nothing.scheduled.isEmpty)
        XCTAssertEqual(nothing.removed.last, [MorningSummaryScheduler.identifier])
    }

    func testSettingsDefaultsAndLimits() {
        let settings = makeSettings(enabled: false)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.hour, 8)
        XCTAssertEqual(settings.minute, 30)

        settings.hour = 40
        settings.minute = -5
        XCTAssertEqual(settings.hour, 23)
        XCTAssertEqual(settings.minute, 0)
    }
}

// MARK: - Снимок для виджетов

final class QuickCheckSnapshotTests: XCTestCase {

    private func result(_ latencies: [String: Double], connection: String = "Wi-Fi") async -> QuickCheckResult {
        await QuickCheck.run(connector: FakeConnector(latencies: latencies), connection: connection, now: date(10, 12))
    }

    func testCheckUpdatesPingLossAndNodesButKeepsSpeedAndTraffic() async {
        let old = NetPulseWidgetData(
            downloadSpeedMbps: 250,
            uploadSpeedMbps: 80,
            pingMs: 99,
            jitterMs: 5,
            lossPercent: 0,
            ispName: "Домашний Wi-Fi",
            connectionType: "Wi-Fi",
            todayTrafficBytes: 1_000,
            budgetTotalBytes: 5_000,
            budgetUsedBytes: 2_000,
            healthScore: 50,
            dnsHosts: [],
            lastUpdated: date(10, 8)
        )
        let merged = QuickCheckService.merged(await result(["1.1.1.1": 20, "8.8.8.8": 30, "9.9.9.9": 40]), into: old)

        XCTAssertEqual(merged.pingMs, 30)
        XCTAssertNil(merged.jitterMs)
        XCTAssertEqual(merged.lossPercent, 0)
        XCTAssertEqual(merged.healthScore, 95)
        XCTAssertEqual(merged.downloadSpeedMbps, 250)
        XCTAssertEqual(merged.uploadSpeedMbps, 80)
        XCTAssertEqual(merged.todayTrafficBytes, 1_000)
        XCTAssertEqual(merged.budgetTotalBytes, 5_000)
        XCTAssertEqual(merged.budgetUsedBytes, 2_000)
        XCTAssertEqual(merged.ispName, "Домашний Wi-Fi")
        XCTAssertEqual(merged.lastUpdated, date(10, 12))
        XCTAssertEqual(merged.dnsHosts.map(\.name), ["Cloudflare", "Google", "Quad9"])
        XCTAssertTrue(merged.dnsHosts.allSatisfy(\.isOK))
    }

    func testFirstCheckWithoutAppDataNamesTheConnection() async {
        let merged = QuickCheckService.merged(await result(["8.8.8.8": 30], connection: "Мобильная сеть"), into: .empty)
        XCTAssertEqual(merged.ispName, "Мобильная сеть")
        XCTAssertEqual(merged.connectionType, "Мобильная сеть")
        XCTAssertEqual(merged.healthScore, 40)
        XCTAssertEqual(merged.dnsHosts.filter(\.isOK).count, 1)
    }

    func testOfflineCheckShowsFullLossAndNoPing() async {
        let merged = QuickCheckService.merged(await result([:], connection: "Нет сети"), into: .empty)
        XCTAssertNil(merged.pingMs)
        XCTAssertEqual(merged.lossPercent, 100)
        XCTAssertEqual(merged.healthScore, 0)
        XCTAssertEqual(QuickCheckVerdict.fromSnapshot(pingMs: merged.pingMs, lossPercent: merged.lossPercent), .offline)
    }
}
