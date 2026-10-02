//
//  RouteRecorderTests.swift
//  NetPulseTests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest
@testable import NetPulse

// MARK: - Подставные зависимости

/// Источник положения, которым управляет тест: разрешение, вызовы запуска и остановки, поступающие положения
@MainActor
private final class FakeLocationSession: LocationSessionProviding {
    var authorization: LocationAuthorization
    var onFix: (@MainActor (LocationFix) -> Void)?
    var onAuthorizationChange: (@MainActor () -> Void)?

    private(set) var permissionRequests = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(authorization: LocationAuthorization) {
        self.authorization = authorization
    }

    func requestPermission() { permissionRequests += 1 }
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }

    func changeAuthorization(to value: LocationAuthorization) {
        authorization = value
        onAuthorizationChange?()
    }

    func emit(_ fix: LocationFix) {
        onFix?(fix)
    }
}

/// Проверка сети с заранее заданными ответами; когда они кончаются, отвечает запасным результатом
private actor FakeProbe: NetworkProbing {
    private var queue: [ProbeResult]
    private let fallback: ProbeResult
    private(set) var calls = 0
    private(set) var speedRequests = 0

    init(
        results: [ProbeResult] = [],
        fallback: ProbeResult = ProbeResult(reachable: true, latencyMs: 40, downloadMbps: nil, link: .lte)
    ) {
        self.queue = results
        self.fallback = fallback
    }

    func measure(withSpeed: Bool) async -> ProbeResult {
        calls += 1
        if withSpeed { speedRequests += 1 }
        return queue.isEmpty ? fallback : queue.removeFirst()
    }
}

/// Всё, что нужно тесту записи маршрута, в одном месте
@MainActor
private struct Rig {
    let recorder: RouteRecorder
    let session: FakeLocationSession
    let probe: FakeProbe
    let storage: RouteStorage
    let directory: URL
}

@MainActor
private func makeRig(
    authorization: LocationAuthorization,
    probe: FakeProbe = FakeProbe(),
    directory: URL? = nil
) throws -> Rig {
    let dir = directory ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("netpulse-recorder-\(UUID().uuidString)", isDirectory: true)
    let suite = "netpulse.route-tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)

    let session = FakeLocationSession(authorization: authorization)
    let storage = RouteStorage(directory: dir)
    let recorder = RouteRecorder(session: session, probe: probe, storage: storage, defaults: defaults, startsLoop: false)
    return Rig(recorder: recorder, session: session, probe: probe, storage: storage, directory: dir)
}

private func fix(_ latitude: Double, at time: Date, accuracy: Double = 5) -> LocationFix {
    LocationFix(latitude: latitude, longitude: 37.0, horizontalAccuracy: accuracy, speed: 10, timestamp: time)
}

// MARK: - Запись маршрута

final class RouteRecorderTests: XCTestCase {

    @MainActor
    func testStartAsksForPermissionAndBeginsAfterItIsGranted() throws {
        let rig = try makeRig(authorization: .notDetermined)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        rig.recorder.start()
        XCTAssertEqual(rig.recorder.state, .waitingForPermission)
        XCTAssertEqual(rig.session.permissionRequests, 1)
        XCTAssertEqual(rig.session.startCount, 0, "Без разрешения геолокация не запускается")
        XCTAssertTrue(rig.recorder.isActive)

        rig.session.changeAuthorization(to: .authorized)
        XCTAssertEqual(rig.recorder.state, .recording)
        XCTAssertEqual(rig.session.startCount, 1)
        XCTAssertNotNil(rig.recorder.current)

        rig.recorder.stop()
        XCTAssertEqual(rig.recorder.state, .idle)
        XCTAssertFalse(rig.recorder.isActive)
    }

    @MainActor
    func testDeniedOrRestrictedAccessRefusesToRecord() throws {
        for authorization in [LocationAuthorization.denied, .restricted] {
            let rig = try makeRig(authorization: authorization)
            defer { try? FileManager.default.removeItem(at: rig.directory) }

            rig.recorder.start()

            XCTAssertEqual(rig.recorder.state, authorization == .denied ? .denied : .restricted)
            XCTAssertTrue(rig.recorder.state.needsAttention)
            XCTAssertNil(rig.recorder.current, "Записи без доступа к геолокации нет")
            XCTAssertFalse(rig.recorder.isActive)
            XCTAssertEqual(rig.session.startCount, 0)
        }
    }

    @MainActor
    func testTickRecordsPointWithResultOfNetworkCheck() async throws {
        let probe = FakeProbe(results: [ProbeResult(reachable: true, latencyMs: 85, downloadMbps: nil, link: .lte)])
        let rig = try makeRig(authorization: .authorized, probe: probe)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        rig.recorder.start()
        let now = Date()
        rig.session.emit(fix(55.0, at: now))
        await rig.recorder.tick(now: now)

        let points = try XCTUnwrap(rig.recorder.current).points
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].latitude, 55.0, accuracy: 0.000_001)
        XCTAssertEqual(points[0].latencyMs, 85)
        XCTAssertEqual(points[0].link, .lte)
        XCTAssertEqual(points[0].quality, .good)
        XCTAssertEqual(rig.recorder.lastQuality, .good)
        XCTAssertEqual(rig.recorder.lastLatencyMs, 85)

        rig.recorder.stop()
    }

    @MainActor
    func testUnansweredCheckMakesDeadPointWithoutInventedLatency() async throws {
        let probe = FakeProbe(results: [ProbeResult(reachable: false, latencyMs: 999, downloadMbps: nil, link: .offline)])
        let rig = try makeRig(authorization: .authorized, probe: probe)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        rig.recorder.start()
        let now = Date()
        rig.session.emit(fix(55.0, at: now))
        await rig.recorder.tick(now: now)

        let point = try XCTUnwrap(rig.recorder.current?.points.first)
        XCTAssertFalse(point.reachable)
        XCTAssertNil(point.latencyMs, "Узел не ответил: задержка не записывается")
        XCTAssertEqual(point.quality, .dead)
        XCTAssertEqual(point.link, .offline)

        rig.recorder.stop()
    }

    @MainActor
    func testNoLocationMeansNoPointAndNoNetworkCheck() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        rig.recorder.start()
        await rig.recorder.tick(now: Date())

        XCTAssertEqual(rig.recorder.pointCount, 0)
        XCTAssertEqual(rig.recorder.progressLine, "Ждём сигнал GPS…")
        let calls = await rig.probe.calls
        XCTAssertEqual(calls, 0, "Без положения сеть не проверяется: нечего привязывать к месту")

        rig.recorder.stop()
    }

    @MainActor
    func testStandingStillDoesNotAddPointsOrSpendNetworkChecks() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        rig.recorder.start()
        let start = Date()
        rig.session.emit(fix(55.0, at: start))
        await rig.recorder.tick(now: start)

        let later = start.addingTimeInterval(5)
        rig.session.emit(fix(55.0, at: later))
        await rig.recorder.tick(now: later)

        XCTAssertEqual(rig.recorder.pointCount, 1)
        let calls = await rig.probe.calls
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(rig.recorder.progressLine.contains("стоит на месте"))

        rig.recorder.stop()
    }

    @MainActor
    func testSpeedIsMeasuredOnlyWhenEnabledAndNotMoreOftenThanEveryThirtySeconds() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.recorder.measuresSpeed = true

        rig.recorder.start()
        XCTAssertEqual(rig.recorder.current?.measuredSpeed, true)

        let t0 = Date()
        // Каждый шаг — около 33 м: точка пишется при каждой проверке
        for (offset, latitude) in [(0.0, 55.0), (10.0, 55.0003), (31.0, 55.0006)] {
            let time = t0.addingTimeInterval(offset)
            rig.session.emit(fix(latitude, at: time))
            await rig.recorder.tick(now: time)
        }

        XCTAssertEqual(rig.recorder.pointCount, 3)
        let speedRequests = await rig.probe.speedRequests
        XCTAssertEqual(speedRequests, 2, "Замер скорости — на первой точке и после 30 секунд, не чаще")

        rig.recorder.stop()
    }

    @MainActor
    func testSpeedIsNotMeasuredByDefault() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        XCTAssertFalse(rig.recorder.measuresSpeed, "Замер скорости расходует трафик и включается только по желанию")

        rig.recorder.start()
        let now = Date()
        rig.session.emit(fix(55.0, at: now))
        await rig.recorder.tick(now: now)

        let speedRequests = await rig.probe.speedRequests
        XCTAssertEqual(speedRequests, 0)
        rig.recorder.stop()
    }

    @MainActor
    func testStopSavesRouteToHistoryAndToDisk() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        rig.recorder.start()
        let t0 = Date()
        rig.session.emit(fix(55.0, at: t0))
        await rig.recorder.tick(now: t0)
        let t1 = t0.addingTimeInterval(5)
        rig.session.emit(fix(55.001, at: t1))
        await rig.recorder.tick(now: t1)

        rig.recorder.stop()

        XCTAssertEqual(rig.recorder.state, .idle)
        XCTAssertNil(rig.recorder.current)
        XCTAssertEqual(rig.recorder.history.count, 1)
        XCTAssertEqual(rig.recorder.lastSaved?.points.count, 2)
        XCTAssertNotNil(rig.recorder.lastSaved?.endedAt)

        var onDisk: [RouteRecord] = []
        for _ in 0..<100 {
            onDisk = await rig.storage.loadAll()
            if !onDisk.isEmpty { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(onDisk.count, 1)
        XCTAssertEqual(onDisk.first?.points.count, 2)
        let active = await rig.storage.loadActive()
        XCTAssertNil(active, "Файл идущей записи после сохранения маршрута не нужен")
    }

    @MainActor
    func testRouteOfOnePointIsNotSaved() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        rig.recorder.start()
        let now = Date()
        rig.session.emit(fix(55.0, at: now))
        await rig.recorder.tick(now: now)
        rig.recorder.stop()

        XCTAssertTrue(rig.recorder.history.isEmpty)
        XCTAssertNil(rig.recorder.lastSaved)
        XCTAssertNotNil(rig.recorder.notice, "Пользователь должен узнать, почему маршрута нет")
        let onDisk = await rig.storage.loadAll()
        XCTAssertTrue(onDisk.isEmpty)
    }

    @MainActor
    func testRevokedPermissionDuringRecordingKeepsRouteAlreadyRecorded() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        rig.recorder.start()
        let t0 = Date()
        rig.session.emit(fix(55.0, at: t0))
        await rig.recorder.tick(now: t0)
        let t1 = t0.addingTimeInterval(5)
        rig.session.emit(fix(55.001, at: t1))
        await rig.recorder.tick(now: t1)

        rig.session.changeAuthorization(to: .denied)

        XCTAssertEqual(rig.recorder.state, .denied)
        XCTAssertNil(rig.recorder.current)
        XCTAssertFalse(rig.recorder.isActive)
        XCTAssertEqual(rig.recorder.history.count, 1, "Записанные точки не теряются")
        XCTAssertEqual(rig.recorder.history.first?.interrupted, true)
    }

    @MainActor
    func testBackgroundPausesAreCountedOnlyDuringRecording() throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        rig.recorder.noteBackgroundPause(seconds: 50, now: Date().addingTimeInterval(100))
        XCTAssertEqual(rig.recorder.pausesWhileRecording, 0, "Запись не идёт — пауза не считается")

        rig.recorder.start()
        // Пауза началась после начала записи
        rig.recorder.noteBackgroundPause(seconds: 50, now: Date().addingTimeInterval(100))
        XCTAssertEqual(rig.recorder.pausesWhileRecording, 1)
        // Пауза началась до начала записи
        rig.recorder.noteBackgroundPause(seconds: 500, now: Date())
        XCTAssertEqual(rig.recorder.pausesWhileRecording, 1)

        rig.recorder.stop()
    }

    @MainActor
    func testInterruptedRecordingIsRecoveredOnNextLaunch() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        // Приложение закрыли посреди записи: на диске остался только файл идущей записи
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let interrupted = RouteRecord(
            startedAt: start,
            points: [
                RoutePoint(time: start, latitude: 55.0, longitude: 37.0, latencyMs: 40),
                RoutePoint(time: start.addingTimeInterval(5), latitude: 55.0005, longitude: 37.0, latencyMs: 45),
                RoutePoint(time: start.addingTimeInterval(10), latitude: 55.001, longitude: 37.0, latencyMs: 50)
            ]
        )
        try await rig.storage.saveActive(interrupted)

        await rig.recorder.recoverInterruptedRoute()

        XCTAssertEqual(rig.recorder.history.count, 1)
        XCTAssertEqual(rig.recorder.history.first?.interrupted, true)
        XCTAssertEqual(rig.recorder.history.first?.points.count, 3)
        XCTAssertEqual(rig.recorder.history.first?.endedAt, start.addingTimeInterval(10))
        XCTAssertNotNil(rig.recorder.notice)
        let active = await rig.storage.loadActive()
        XCTAssertNil(active)
        let saved = await rig.storage.loadAll()
        XCTAssertEqual(saved.count, 1)
    }

    @MainActor
    func testRecoveryDoesNothingWithoutInterruptedRecording() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        await rig.recorder.recoverInterruptedRoute()

        XCTAssertTrue(rig.recorder.history.isEmpty)
        XCTAssertNil(rig.recorder.notice)
    }

    @MainActor
    func testDeletingRoutesRemovesThemFromHistoryAndDisk() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        let first = RouteDemo.sample(startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        var second = RouteDemo.sample(startedAt: Date(timeIntervalSince1970: 1_700_100_000))
        second.id = UUID()
        try await rig.storage.save(first)
        try await rig.storage.save(second)
        await rig.recorder.reloadHistory()
        XCTAssertEqual(rig.recorder.history.count, 2)

        rig.recorder.deleteRoute(id: first.id)
        XCTAssertEqual(rig.recorder.history.map { $0.id }, [second.id])

        rig.recorder.deleteAllRoutes()
        XCTAssertTrue(rig.recorder.history.isEmpty)

        var remaining = 1
        for _ in 0..<100 {
            remaining = await rig.storage.loadAll().count
            if remaining == 0 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(remaining, 0)
    }
}

// MARK: - Хранилище

final class RouteStorageTests: XCTestCase {

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("netpulse-storage-\(UUID().uuidString)", isDirectory: true)
    }

    func testRouteSurvivesSaveAndLoadWithoutChanges() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = RouteStorage(directory: directory)
        let sample = RouteDemo.sample()

        try await storage.save(sample)
        let loaded = await storage.loadAll()

        XCTAssertEqual(loaded, [sample])
    }

    func testRoutesAreReturnedNewestFirst() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = RouteStorage(directory: directory)

        var older = RouteDemo.sample(startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        older.id = UUID()
        var newer = RouteDemo.sample(startedAt: Date(timeIntervalSince1970: 1_700_500_000))
        newer.id = UUID()
        try await storage.save(older)
        try await storage.save(newer)

        let loaded = await storage.loadAll()
        XCTAssertEqual(loaded.map { $0.id }, [newer.id, older.id])
    }

    func testDeleteRemovesOnlyThatRoute() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = RouteStorage(directory: directory)

        var first = RouteDemo.sample(startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        first.id = UUID()
        var second = RouteDemo.sample(startedAt: Date(timeIntervalSince1970: 1_700_500_000))
        second.id = UUID()
        try await storage.save(first)
        try await storage.save(second)

        await storage.delete(id: first.id)

        let loaded = await storage.loadAll()
        XCTAssertEqual(loaded.map { $0.id }, [second.id])
    }

    func testDeleteAllAlsoRemovesUnfinishedRecording() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = RouteStorage(directory: directory)

        try await storage.save(RouteDemo.sample())
        try await storage.saveActive(RouteDemo.sample())

        await storage.deleteAll()

        let routes = await storage.loadAll()
        let active = await storage.loadActive()
        XCTAssertTrue(routes.isEmpty)
        XCTAssertNil(active)
    }

    func testUnfinishedRecordingCanBeSavedLoadedAndCleared() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = RouteStorage(directory: directory)
        let sample = RouteDemo.sample()

        var missing = await storage.loadActive()
        XCTAssertNil(missing)

        try await storage.saveActive(sample)
        let loaded = await storage.loadActive()
        XCTAssertEqual(loaded, sample)
        let routes = await storage.loadAll()
        XCTAssertTrue(routes.isEmpty, "Идущая запись — ещё не маршрут в истории")

        await storage.clearActive()
        missing = await storage.loadActive()
        XCTAssertNil(missing)
    }

    func testBrokenFileIsSkippedAndDoesNotHideOtherRoutes() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = RouteStorage(directory: directory)

        try await storage.save(RouteDemo.sample())
        let broken = directory.appendingPathComponent("route-\(UUID().uuidString).json")
        try Data("{ это не JSON".utf8).write(to: broken)

        let loaded = await storage.loadAll()
        XCTAssertEqual(loaded.count, 1)
    }

    func testOldestRoutesAreDroppedBeyondTheLimit() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = RouteStorage(directory: directory)

        var ids: [UUID] = []
        let total = RouteStorage.maxRoutes + 3
        for index in 0..<total {
            let id = UUID()
            ids.append(id)
            let route = RouteRecord(
                id: id,
                startedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 100),
                points: RouteDemo.sample().points
            )
            try await storage.save(route)
        }

        let loaded = await storage.loadAll()
        XCTAssertEqual(loaded.count, RouteStorage.maxRoutes)
        let loadedIDs = Set(loaded.map { $0.id })
        for dropped in ids.prefix(3) {
            XCTAssertFalse(loadedIDs.contains(dropped), "Три самых старых маршрута должны быть удалены")
        }
        XCTAssertTrue(loadedIDs.contains(ids[total - 1]))
    }
}
