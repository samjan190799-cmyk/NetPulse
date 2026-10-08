//
//  IslandTests.swift
//  NetPulseTests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest
@testable import NetPulse

// MARK: - Вспомогательные типы

/// Часы, которыми управляет тест
@MainActor
private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_000_000)

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

/// Отправитель, который «не отвечает», пока тест его не отпустит: так моделируется зависший вызов `activity.update`
@MainActor
private final class ManualSender {
    private(set) var started: [Int] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var waitingCount: Int { continuations.count }

    func send(_ value: Int) async {
        started.append(value)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    /// Отпускает отправку с заданным порядковым номером среди ещё не отпущенных
    func release(at index: Int) {
        guard continuations.indices.contains(index) else { return }
        let continuation = continuations.remove(at: index)
        continuation.resume()
    }

    func releaseAll() {
        let all = continuations
        continuations.removeAll()
        for continuation in all {
            continuation.resume()
        }
    }
}

/// Собирает значения, пришедшие в обратные вызовы
@MainActor
private final class ValueRecorder {
    var values: [Int] = []
}

/// Ждёт выполнения условия, опрашивая его каждые 10 мс
@MainActor
private func waitUntil(
    timeout: TimeInterval = 3,
    _ description: String = "условие",
    _ condition: @MainActor () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            XCTFail("За \(timeout) с не выполнилось: \(description)")
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

// MARK: - Конвейер обновления острова

/// Раньше один «зависший» вызов `activity.update` блокировал все следующие обновления навсегда: остров замирал
/// даже при открытом приложении, а кнопка «Перезапустить» упиралась в тот же флаг.
final class IslandPipelineTests: XCTestCase {

    /// Пока идёт отправка, промежуточные кадры пропускаются: после ответа уходит только самый свежий.
    @MainActor
    func testOnlyNewestWaitingFrameGoesOutAfterCurrentFinishes() async throws {
        let pipeline = IslandUpdatePipeline<Int>(sendTimeout: 5)
        let sender = ManualSender()
        let send: IslandUpdatePipeline<Int>.Sender = { value in await sender.send(value) }

        pipeline.submit(1, send: send)
        pipeline.submit(2, send: send)
        pipeline.submit(3, send: send)
        pipeline.submit(4, send: send)
        try await waitUntil("первая отправка началась") { sender.started == [1] }
        XCTAssertTrue(pipeline.isSending)

        sender.release(at: 0)
        try await waitUntil("ушёл самый свежий кадр") { sender.started == [1, 4] }

        sender.release(at: 0)
        try await waitUntil("обе отправки завершены") { pipeline.stats.completed == 2 }
        XCTAssertEqual(pipeline.stats.started, 2)
        XCTAssertEqual(pipeline.stats.abandoned, 0)
        XCTAssertFalse(pipeline.isSending)
    }

    /// Главный сценарий: отправка не отвечает, по сроку она забывается, и остров продолжает обновляться.
    @MainActor
    func testHungSendIsAbandonedAndNewestFrameGoesOut() async throws {
        let clock = TestClock()
        let pipeline = IslandUpdatePipeline<Int>(sendTimeout: 5, clock: { clock.now })
        let sender = ManualSender()
        let send: IslandUpdatePipeline<Int>.Sender = { value in await sender.send(value) }

        pipeline.submit(1, send: send)
        try await waitUntil("первая отправка началась") { sender.started == [1] }

        // Прошло 3 секунды: отправка ещё считается живой, новый кадр ждёт
        clock.advance(3)
        pipeline.submit(2, send: send)
        XCTAssertEqual(sender.started, [1])
        XCTAssertEqual(pipeline.stats.abandoned, 0)

        // Прошло ещё 3 секунды (всего 6 > 5): зависшая отправка забыта, кадр 2 уходит
        clock.advance(3)
        pipeline.pump()
        XCTAssertEqual(pipeline.stats.abandoned, 1)
        try await waitUntil("кадр 2 отправлен") { sender.started == [1, 2] }
        XCTAssertTrue(pipeline.isSending)

        // Ответ на забытую отправку приходит поздно: он не считается успехом и не снимает «занятость» кадра 2
        sender.release(at: 0)
        try await waitUntil("поздний ответ учтён") { pipeline.stats.lateReplies == 1 }
        XCTAssertEqual(pipeline.stats.completed, 0)
        XCTAssertTrue(pipeline.isSending)

        sender.release(at: 0)
        try await waitUntil("кадр 2 завершён") { pipeline.stats.completed == 1 }
        XCTAssertFalse(pipeline.isSending)

        // Конвейер жив: следующий кадр уходит сразу
        pipeline.submit(3, send: send)
        try await waitUntil("кадр 3 отправлен") { sender.started == [1, 2, 3] }
        sender.releaseAll()
        try await waitUntil("кадр 3 завершён") { pipeline.stats.completed == 2 }
    }

    /// Зависшая отправка забывается и тогда, когда новых кадров нет (вызов `pump()` из цикла обновления)
    @MainActor
    func testPumpAbandonsHungSendEvenWithoutNewFrames() async throws {
        let clock = TestClock()
        let pipeline = IslandUpdatePipeline<Int>(sendTimeout: 5, clock: { clock.now })
        let sender = ManualSender()

        pipeline.submit(1, send: { value in await sender.send(value) })
        try await waitUntil("отправка началась") { sender.started == [1] }
        XCTAssertEqual(pipeline.inFlightAge ?? -1, 0, accuracy: 0.001)

        clock.advance(4.9)
        pipeline.pump()
        XCTAssertTrue(pipeline.isSending, "До срока отправка ещё считается живой")

        clock.advance(0.2)
        pipeline.pump()
        XCTAssertFalse(pipeline.isSending)
        XCTAssertEqual(pipeline.stats.abandoned, 1)
    }

    /// Сброс (например, при перезапуске активности) отбрасывает очередь и игнорирует ответ на старую отправку
    @MainActor
    func testResetDropsQueueAndIgnoresReplyToOldSend() async throws {
        let pipeline = IslandUpdatePipeline<Int>(sendTimeout: 5)
        let sender = ManualSender()
        let send: IslandUpdatePipeline<Int>.Sender = { value in await sender.send(value) }

        pipeline.submit(1, send: send)
        pipeline.submit(2, send: send)
        try await waitUntil("отправка началась") { sender.started == [1] }

        pipeline.reset()
        XCTAssertFalse(pipeline.isSending)

        sender.release(at: 0)
        try await waitUntil("ответ на старую отправку проигнорирован") { pipeline.stats.lateReplies == 1 }
        XCTAssertEqual(pipeline.stats.completed, 0)
        XCTAssertEqual(sender.started, [1], "Кадр 2 после сброса отправляться не должен")

        pipeline.submit(3, send: send)
        try await waitUntil("после сброса кадры снова уходят") { sender.started == [1, 3] }
        sender.releaseAll()
    }

    /// Обратный вызов `onCompleted` приходит только для отправок, завершённых в срок
    @MainActor
    func testCompletionCallbackIgnoresAbandonedSends() async throws {
        let clock = TestClock()
        let pipeline = IslandUpdatePipeline<Int>(sendTimeout: 5, clock: { clock.now })
        let sender = ManualSender()
        let recorder = ValueRecorder()
        pipeline.onCompleted = { value in recorder.values.append(value) }
        let abandonedRecorder = ValueRecorder()
        pipeline.onAbandoned = { age in abandonedRecorder.values.append(Int(age.rounded())) }
        let send: IslandUpdatePipeline<Int>.Sender = { value in await sender.send(value) }

        pipeline.submit(1, send: send)
        try await waitUntil("отправка началась") { sender.started == [1] }
        clock.advance(7)
        pipeline.submit(2, send: send)
        try await waitUntil("кадр 2 отправлен") { sender.started == [1, 2] }
        XCTAssertEqual(abandonedRecorder.values, [7])

        sender.release(at: 0)
        sender.release(at: 0)
        try await waitUntil("кадр 2 завершён") { recorder.values == [2] }
    }

    /// Длительность отправок попадает в статистику
    @MainActor
    func testStatsRecordSendDuration() async throws {
        let clock = TestClock()
        let pipeline = IslandUpdatePipeline<Int>(sendTimeout: 10, clock: { clock.now })
        let sender = ManualSender()

        pipeline.submit(1, send: { value in await sender.send(value) })
        try await waitUntil("отправка началась") { sender.started == [1] }
        clock.advance(2)
        sender.release(at: 0)
        try await waitUntil("отправка завершена") { pipeline.stats.completed == 1 }

        XCTAssertEqual(pipeline.stats.lastDuration ?? -1, 2, accuracy: 0.001)
        XCTAssertEqual(pipeline.stats.longestDuration, 2, accuracy: 0.001)
        XCTAssertNotNil(pipeline.stats.lastCompletedAt)
    }

    /// Сроки согласованы: зависшая отправка забывается раньше, чем iOS пометит остров устаревшим,
    /// а повторная отправка не реже, чем нужно для свежести
    @MainActor
    func testTimingConstantsAreConsistent() {
        XCTAssertLessThan(ActivityManager.sendTimeout, ActivityManager.staleAfter)
        XCTAssertGreaterThan(ActivityManager.staleAfter, ActivityManager.unchangedResendInterval * 4)
    }
}

// MARK: - Паузы цикла

final class LoopTimingTests: XCTestCase {
    func testNormalTicksAreNotPauses() {
        XCTAssertEqual(LoopTiming.classify(gap: 1.0, previousTickWasBackground: true), .normal)
        XCTAssertEqual(LoopTiming.classify(gap: LoopTiming.pauseThreshold, previousTickWasBackground: false), .normal)
    }

    func testPauseAfterBackgroundTickMeansSuspension() {
        XCTAssertEqual(
            LoopTiming.classify(gap: 120, previousTickWasBackground: true),
            .suspendedInBackground(seconds: 120)
        )
    }

    func testPauseAfterForegroundTickMeansBusyMainThread() {
        XCTAssertEqual(
            LoopTiming.classify(gap: 9, previousTickWasBackground: false),
            .stalledInForeground(seconds: 9)
        )
    }
}

// MARK: - Журнал острова

final class IslandDiagnosticsTests: XCTestCase {

    @MainActor
    private func makeDefaults() throws -> UserDefaults {
        let name = "netpulse.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @MainActor
    func testJournalKeepsOnlyNewestEntries() throws {
        let journal = IslandDiagnostics(defaults: try makeDefaults(), fileURL: nil)
        let total = IslandDiagnostics.maxEntries + 50
        for index in 0..<total {
            journal.log("событие \(index)")
        }
        XCTAssertEqual(journal.entries.count, IslandDiagnostics.maxEntries)
        XCTAssertEqual(journal.entries.first?.text, "событие 50")
        XCTAssertEqual(journal.entries.last?.text, "событие \(total - 1)")
    }

    /// Приложение, которое система закрыла в фоне, не получает уведомления о завершении: единственный след —
    /// «открытый сеанс» и время последнего сигнала жизни.
    @MainActor
    func testPreviousSessionWithoutCleanExitIsDetected() throws {
        let defaults = try makeDefaults()
        let start = Date(timeIntervalSince1970: 2_000_000)

        let first = IslandDiagnostics(defaults: defaults, fileURL: nil)
        let firstReport = first.beginSession(now: start)
        XCTAssertFalse(firstReport.previousEndedUncleanly)
        first.heartbeat(isBackground: true, now: start.addingTimeInterval(100))
        // Приложение закрыли без штатного выхода

        let second = IslandDiagnostics(defaults: defaults, fileURL: nil)
        let secondReport = second.beginSession(now: start.addingTimeInterval(500))
        XCTAssertTrue(secondReport.previousEndedUncleanly)
        XCTAssertTrue(secondReport.lastHeartbeatWasBackground)
        XCTAssertEqual(secondReport.lastHeartbeat?.timeIntervalSince1970 ?? 0, start.timeIntervalSince1970 + 100, accuracy: 1)
        XCTAssertEqual(second.uncleanSessionCount, 1)
        XCTAssertTrue(second.entries.contains { $0.kind == .warning && $0.text.contains("без штатного выхода") })

        // Штатное завершение считается нормальным
        second.endSession()
        let third = IslandDiagnostics(defaults: defaults, fileURL: nil)
        XCTAssertFalse(third.beginSession(now: start.addingTimeInterval(900)).previousEndedUncleanly)
        XCTAssertEqual(third.uncleanSessionCount, 1)
    }

    @MainActor
    func testHeartbeatIsWrittenNoMoreOftenThanEveryFiveSeconds() throws {
        let defaults = try makeDefaults()
        let start = Date(timeIntervalSince1970: 3_000_000)

        let first = IslandDiagnostics(defaults: defaults, fileURL: nil)
        first.beginSession(now: start)
        first.heartbeat(isBackground: false, now: start)
        first.heartbeat(isBackground: true, now: start.addingTimeInterval(1))   // слишком рано — игнорируется

        let second = IslandDiagnostics(defaults: defaults, fileURL: nil)
        XCTAssertFalse(second.beginSession(now: start.addingTimeInterval(2)).lastHeartbeatWasBackground)

        second.heartbeat(isBackground: true, now: start.addingTimeInterval(10))
        let third = IslandDiagnostics(defaults: defaults, fileURL: nil)
        XCTAssertTrue(third.beginSession(now: start.addingTimeInterval(11)).lastHeartbeatWasBackground)
    }

    @MainActor
    func testOnlyBackgroundPausesAreCountedAndTheyPersist() throws {
        let defaults = try makeDefaults()
        let journal = IslandDiagnostics(defaults: defaults, fileURL: nil)

        journal.recordPause(seconds: 30, inBackground: true, context: "режим работает")
        journal.recordPause(seconds: 10, inBackground: false, context: "")
        journal.recordPause(seconds: 50, inBackground: true, context: "")

        XCTAssertEqual(journal.backgroundPauseCount, 2)
        XCTAssertEqual(journal.longestBackgroundPause, 50, accuracy: 0.001)

        let reopened = IslandDiagnostics(defaults: defaults, fileURL: nil)
        XCTAssertEqual(reopened.backgroundPauseCount, 2)
        XCTAssertEqual(reopened.longestBackgroundPause, 50, accuracy: 0.001)
    }

    @MainActor
    func testJournalSurvivesRestartThroughFile() throws {
        let defaults = try makeDefaults()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("island-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = IslandDiagnostics(defaults: defaults, fileURL: url)
        first.log("первое событие", .island)
        first.log("второе событие", .warning)
        first.saveNow()

        let second = IslandDiagnostics(defaults: defaults, fileURL: url)
        XCTAssertEqual(second.entries.map(\.text), ["первое событие", "второе событие"])
        XCTAssertEqual(second.entries.last?.kind, .warning)
    }

    @MainActor
    func testClearResetsEntriesAndCounters() throws {
        let defaults = try makeDefaults()
        let journal = IslandDiagnostics(defaults: defaults, fileURL: nil)
        journal.log("событие")
        journal.recordPause(seconds: 20, inBackground: true, context: "")

        journal.clear()
        XCTAssertTrue(journal.entries.isEmpty)
        XCTAssertEqual(journal.backgroundPauseCount, 0)
        XCTAssertEqual(IslandDiagnostics(defaults: defaults, fileURL: nil).backgroundPauseCount, 0)
    }

    @MainActor
    func testSummaryDescribesHealthHonestly() throws {
        let journal = IslandDiagnostics(defaults: try makeDefaults(), fileURL: nil)
        let health = IslandHealthSnapshot(
            activityText: "активна",
            secondsSinceLastUpdate: 3,
            sent: 120,
            abandoned: 2,
            lateReplies: 1,
            longestSendSeconds: 5.5,
            inFlightSeconds: nil
        )
        let summary = journal.summaryText(health: health, recording: "идёт, точек: 12")

        XCTAssertTrue(summary.contains("Остров: активна"))
        XCTAssertTrue(summary.contains("Последнее обновление: 3 с назад"))
        XCTAssertTrue(summary.contains("Отправлено кадров: 120"))
        XCTAssertTrue(summary.contains("Зависших отправок: 2 (поздних ответов: 1)"))
        XCTAssertTrue(summary.contains("Запись маршрута: идёт, точек: 12"))
        XCTAssertTrue(summary.contains("Паузы приложения в фоне: 0"))

        let never = journal.summaryText(health: IslandHealthSnapshot(), recording: "не идёт")
        XCTAssertTrue(never.contains("Последнее обновление: ещё не было"))
    }

    @MainActor
    func testExportContainsSummaryAndEntriesInOrder() throws {
        let journal = IslandDiagnostics(defaults: try makeDefaults(), fileURL: nil)
        journal.log("раньше")
        journal.log("позже")

        let text = journal.exportText(summary: "СВОДКА")
        XCTAssertTrue(text.contains("СВОДКА"))
        XCTAssertTrue(text.contains("События:"))
        let earlier = try XCTUnwrap(text.range(of: "раньше"))
        let later = try XCTUnwrap(text.range(of: "позже"))
        XCTAssertLessThan(earlier.lowerBound, later.lowerBound, "В файле события идут от старых к новым")

        let lines = journal.displayLines()
        XCTAssertTrue(lines.first?.contains("позже") == true, "На экране новые события сверху")
    }

    func testAgeFormatting() {
        XCTAssertEqual(IslandDiagnostics.formatAge(5), "5 с")
        XCTAssertEqual(IslandDiagnostics.formatAge(59), "59 с")
        XCTAssertEqual(IslandDiagnostics.formatAge(61), "1 мин")
        XCTAssertEqual(IslandDiagnostics.formatAge(3_700), "1 ч")
        XCTAssertEqual(IslandDiagnostics.formatAge(-3), "0 с")
    }
}

// MARK: - Трафик, прошедший, пока приложение спало

final class SleepTrafficTests: XCTestCase {
    func testNoteIsMadeWhenAwayLongEnoughAndTrafficIsNoticeable() throws {
        let summary = SleepTrafficSummary(downloadBytes: 120_000_000, uploadBytes: 8_000_000)
        let note = try XCTUnwrap(SleepTrafficNote.make(summary: summary, awaySeconds: 180))
        XCTAssertEqual(note.downloadBytes, 120_000_000)
        XCTAssertEqual(note.uploadBytes, 8_000_000)
        XCTAssertEqual(note.awaySeconds, 180)
    }

    func testShortAbsenceIsNotSleep() {
        let summary = SleepTrafficSummary(downloadBytes: 5_000_000, uploadBytes: 1_000_000)
        XCTAssertNil(SleepTrafficNote.make(summary: summary, awaySeconds: SleepTrafficNote.minAwaySeconds - 1),
                     "Обычное переключение между приложениями не считается сном")
        XCTAssertNotNil(SleepTrafficNote.make(summary: summary, awaySeconds: SleepTrafficNote.minAwaySeconds))
    }

    func testBackgroundNoiseIsNotShown() {
        let noise = SleepTrafficSummary(downloadBytes: 10_000, uploadBytes: 5_000)
        XCTAssertNil(SleepTrafficNote.make(summary: noise, awaySeconds: 600))
        let enough = SleepTrafficSummary(downloadBytes: SleepTrafficNote.minBytes, uploadBytes: 0)
        XCTAssertNotNil(SleepTrafficNote.make(summary: enough, awaySeconds: 600))
    }

    func testMissingDataGivesNoNote() {
        XCTAssertNil(SleepTrafficNote.make(summary: nil, awaySeconds: 600), "Первой сверки счётчиков ещё не было")
        XCTAssertNil(SleepTrafficNote.make(summary: SleepTrafficSummary(downloadBytes: 9_000_000, uploadBytes: 0), awaySeconds: nil),
                     "Неизвестно, когда приложение свернули")
    }

    func testNoteTextShowsDurationAndBothDirections() {
        let note = SleepTrafficNote(downloadBytes: 120 * 1_048_576, uploadBytes: 8 * 1_048_576, awaySeconds: 180)
        XCTAssertTrue(note.text.contains("3 мин"), note.text)
        XCTAssertTrue(note.text.contains("↓ 120.0 МБ"), note.text)
        XCTAssertTrue(note.text.contains("↑ 8.0 МБ"), note.text)
    }

    func testTotalBytesAddsBothDirections() {
        XCTAssertEqual(SleepTrafficSummary(downloadBytes: 3, uploadBytes: 4).totalBytes, 7)
    }
}

#if canImport(ActivityKit)
// MARK: - Состояние острова: метка времени кадра

final class IslandContentStateTests: XCTestCase {
    func testUpdatedAtSurvivesEncodingRoundTrip() throws {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let state = NetPulseAttributes.ContentState(compactDownloadText: "12", updatedAt: stamp)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(NetPulseAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded.updatedAt, stamp)
        XCTAssertEqual(decoded.compactDownloadText, "12")
    }

    /// Остров, созданный прежней версией приложения, не знает про `updatedAt`: такой кадр должен читаться
    func testStateWithoutUpdatedAtStillDecodes() throws {
        let old = NetPulseAttributes.ContentState(compactDownloadText: "7")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        object.removeValue(forKey: "updatedAt")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(NetPulseAttributes.ContentState.self, from: data)
        XCTAssertNil(decoded.updatedAt)
        XCTAssertEqual(decoded.compactDownloadText, "7")
    }
}
#endif
