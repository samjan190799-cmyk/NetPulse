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

    /// Дано ли разрешение «Всегда»: тест выставляет сам
    var hasAlwaysAuthorization = false

    private(set) var permissionRequests = 0
    private(set) var alwaysRequests = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    /// Все значения, с которыми запись просила разрешить или запретить фон
    private(set) var backgroundAllowed: [Bool] = []
    /// Все значения режима экономии заряда, которые запись передала источнику
    private(set) var powerSavingValues: [Bool] = []
    /// Следит ли источник за значительными перемещениями (как настоящий: остановка источника это выключает)
    private(set) var watchingMoves = false

    init(authorization: LocationAuthorization) {
        self.authorization = authorization
    }

    func requestPermission() { permissionRequests += 1 }
    func requestAlwaysPermission() { alwaysRequests += 1 }
    func setBackgroundUpdates(allowed: Bool) { backgroundAllowed.append(allowed) }
    func setPowerSaving(_ enabled: Bool) { powerSavingValues.append(enabled) }
    func setRelaunchOnMove(enabled: Bool) { watchingMoves = enabled }
    func start() { startCount += 1 }
    func stop() {
        stopCount += 1
        watchingMoves = false
    }

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

/// Переключатель «включено энергосбережение» для теста
@MainActor
private final class LowPowerFlag {
    var isOn = false
}

/// Переключатель «включён режим экономии заряда» для теста
@MainActor
private final class PowerSaverFlag {
    var isOn = false
}

/// Всё, что нужно тесту записи маршрута, в одном месте
@MainActor
private struct Rig {
    let recorder: RouteRecorder
    let session: FakeLocationSession
    let probe: FakeProbe
    let storage: RouteStorage
    let directory: URL
    let defaults: UserDefaults
    let lowPower: LowPowerFlag
    let powerSaver: PowerSaverFlag
}

@MainActor
private func makeRig(
    authorization: LocationAuthorization,
    alwaysGranted: Bool = false,
    probe: FakeProbe = FakeProbe(),
    directory: URL? = nil,
    defaults existingDefaults: UserDefaults? = nil
) throws -> Rig {
    let dir = directory ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("netpulse-recorder-\(UUID().uuidString)", isDirectory: true)
    let defaults: UserDefaults
    if let existingDefaults {
        defaults = existingDefaults
    } else {
        let suite = "netpulse.route-tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    let session = FakeLocationSession(authorization: authorization)
    session.hasAlwaysAuthorization = alwaysGranted
    let storage = RouteStorage(directory: dir)
    let lowPower = LowPowerFlag()
    let powerSaver = PowerSaverFlag()
    let recorder = RouteRecorder(
        session: session,
        probe: probe,
        storage: storage,
        defaults: defaults,
        startsLoop: false,
        isLowPowerMode: { lowPower.isOn },
        isPowerSaver: { powerSaver.isOn }
    )
    return Rig(recorder: recorder, session: session, probe: probe, storage: storage, directory: dir, defaults: defaults, lowPower: lowPower, powerSaver: powerSaver)
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

// MARK: - Фон, экономия заряда, автоостановка

final class RouteRecorderBatteryTests: XCTestCase {
    /// Широта, на которую сдвигается телефон на ~20 м (между порогами обычного режима, 15 м, и экономного, 30 м)
    private let twentyMeters = 0.00018

    @MainActor
    func testBackgroundRecordingIsOnByDefaultAndRemembered() throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        XCTAssertTrue(rig.recorder.recordsInBackground, "Раньше запись всегда шла в фоне: по умолчанию так и остаётся")
        XCTAssertTrue(rig.recorder.stopsWhenIdle)

        rig.recorder.recordsInBackground = false
        rig.recorder.stopsWhenIdle = false

        let second = try makeRig(authorization: .authorized, defaults: rig.defaults)
        defer { try? FileManager.default.removeItem(at: second.directory) }
        XCTAssertFalse(second.recorder.recordsInBackground, "Выбор пользователя сохраняется между запусками")
        XCTAssertFalse(second.recorder.stopsWhenIdle)
    }

    @MainActor
    func testSessionIsToldWhetherBackgroundUpdatesAreAllowed() throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.recorder.recordsInBackground = false

        rig.recorder.start()
        XCTAssertEqual(rig.session.backgroundAllowed.last, false, "Запись началась при выключенной фоновой записи")
        XCTAssertEqual(rig.session.startCount, 1)

        // Переключатель в настройках действует сразу, без перезапуска записи
        rig.recorder.recordsInBackground = true
        XCTAssertEqual(rig.session.backgroundAllowed.last, true)
        rig.recorder.recordsInBackground = false
        XCTAssertEqual(rig.session.backgroundAllowed.last, false)

        rig.recorder.stop()
    }

    @MainActor
    func testRecordingWaitsInBackgroundWhenBackgroundRecordingIsOff() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.recorder.recordsInBackground = false

        rig.recorder.start()
        let t0 = Date()
        rig.session.emit(fix(55.0, at: t0))
        await rig.recorder.tick(now: t0)
        XCTAssertEqual(rig.recorder.pointCount, 1)

        rig.recorder.appDidEnterBackground()
        let t1 = t0.addingTimeInterval(30)
        rig.session.emit(fix(55.0 + twentyMeters * 10, at: t1))
        await rig.recorder.tick(now: t1)
        XCTAssertEqual(rig.recorder.pointCount, 1, "В фоне запись на паузе: новых точек нет")
        let callsInBackground = await rig.probe.calls
        XCTAssertEqual(callsInBackground, 1, "В фоне сеть не проверяется")

        let startsBefore = rig.session.startCount
        rig.recorder.appDidBecomeActive()
        XCTAssertGreaterThan(rig.session.startCount, startsBefore, "При возвращении геолокация запускается заново")
        let notice = try XCTUnwrap(rig.recorder.notice)
        XCTAssertTrue(notice.contains("на паузе"), notice)
        XCTAssertTrue(rig.recorder.isActive, "Запись не прервалась, а только ждала")

        let t2 = t1.addingTimeInterval(10)
        rig.session.emit(fix(55.0 + twentyMeters * 10, at: t2))
        await rig.recorder.tick(now: t2)
        XCTAssertEqual(rig.recorder.pointCount, 2, "После возвращения запись снова пишет точки")

        rig.recorder.stop()
    }

    @MainActor
    func testRecordingContinuesInBackgroundWhenAllowed() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        rig.recorder.start()
        let t0 = Date()
        rig.session.emit(fix(55.0, at: t0))
        await rig.recorder.tick(now: t0)

        rig.recorder.appDidEnterBackground()
        let t1 = t0.addingTimeInterval(20)
        rig.session.emit(fix(55.0 + twentyMeters * 3, at: t1))   // около 60 м: больше порога экономного режима
        await rig.recorder.tick(now: t1)

        XCTAssertEqual(rig.recorder.pointCount, 2, "Фоновая запись включена: точки в фоне пишутся")
        XCTAssertNil(rig.recorder.notice)

        rig.recorder.stop()
    }

    @MainActor
    func testBackgroundAndLowPowerModeUseTheEconomyPolicy() async throws {
        // Сдвиг на ~20 м за 5 секунд: в обычном режиме это движение, в экономном — ещё нет
        func secondPoint(prepare: (Rig) -> Void) async throws -> Int {
            let rig = try makeRig(authorization: .authorized)
            defer { try? FileManager.default.removeItem(at: rig.directory) }
            rig.recorder.start()
            prepare(rig)
            let t0 = Date()
            rig.session.emit(fix(55.0, at: t0))
            await rig.recorder.tick(now: t0)
            let t1 = t0.addingTimeInterval(5)
            rig.session.emit(fix(55.0 + twentyMeters, at: t1))
            await rig.recorder.tick(now: t1)
            let count = rig.recorder.pointCount
            rig.recorder.stop()
            return count
        }

        let standard = try await secondPoint { _ in }
        let background = try await secondPoint { $0.recorder.appDidEnterBackground() }
        let lowPower = try await secondPoint { $0.lowPower.isOn = true }

        XCTAssertEqual(standard, 2, "Обычный режим: 20 м больше порога в 15 м")
        XCTAssertEqual(background, 1, "В фоне порог выше (30 м): лишняя точка и проверка сети не нужны")
        XCTAssertEqual(lowPower, 1, "При включённом энергосбережении точки тоже пишутся реже")
    }

    func testEconomyPolicyWakesTheAppLessOften() {
        let standard = RouteSamplingPolicy.standard
        let economy = RouteSamplingPolicy.economy
        XCTAssertEqual(standard, RouteSamplingPolicy())
        XCTAssertGreaterThanOrEqual(economy.tickInterval, standard.tickInterval * 2)
        XCTAssertGreaterThanOrEqual(economy.stationaryInterval, standard.stationaryInterval * 2)
        XCTAssertGreaterThan(economy.minMoveMeters, standard.minMoveMeters)
        XCTAssertGreaterThan(economy.maxFixAge, economy.tickInterval, "Положение не должно устаревать быстрее, чем идёт цикл")
    }

    @MainActor
    func testRecordingStopsItselfWhenThePhoneStandsStill() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        rig.recorder.start()
        let t0 = Date()
        rig.session.emit(fix(55.0, at: t0))
        await rig.recorder.tick(now: t0)
        let t1 = t0.addingTimeInterval(5)
        rig.session.emit(fix(55.0 + twentyMeters, at: t1))
        await rig.recorder.tick(now: t1)
        XCTAssertEqual(rig.recorder.pointCount, 2)

        // Прошло больше срока автоостановки, телефон всё это время на месте
        let late = t1.addingTimeInterval(RouteRecorder.idleStopSeconds + 60)
        rig.session.emit(fix(55.0 + twentyMeters, at: late))
        await rig.recorder.tick(now: late)

        XCTAssertFalse(rig.recorder.isActive, "Запись остановилась сама")
        XCTAssertEqual(rig.recorder.state, .idle)
        XCTAssertEqual(rig.recorder.history.count, 1, "Записанный маршрут сохранён, а не потерян")
        let notice = try XCTUnwrap(rig.recorder.notice)
        XCTAssertTrue(notice.contains("простоял"), notice)
    }

    @MainActor
    func testIdleStopCanBeSwitchedOff() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.recorder.stopsWhenIdle = false

        rig.recorder.start()
        let t0 = Date()
        rig.session.emit(fix(55.0, at: t0))
        await rig.recorder.tick(now: t0)

        let late = t0.addingTimeInterval(RouteRecorder.idleStopSeconds + 60)
        rig.session.emit(fix(55.0, at: late))
        await rig.recorder.tick(now: late)

        XCTAssertTrue(rig.recorder.isActive, "Автоостановка выключена: запись продолжается")
        XCTAssertEqual(rig.recorder.state, .recording)

        rig.recorder.stop()
    }

    @MainActor
    func testMovementKeepsTheRecordingGoing() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        rig.recorder.start()
        var now = Date()
        var latitude = 55.0
        // Час пути с остановками по минуте: движения хватает, запись не прерывается
        for step in 0..<40 {
            rig.session.emit(fix(latitude, at: now))
            await rig.recorder.tick(now: now)
            latitude += twentyMeters * 2
            now = now.addingTimeInterval(step % 2 == 0 ? 90 : 60)
        }
        XCTAssertTrue(rig.recorder.isActive)
        XCTAssertGreaterThan(rig.recorder.pointCount, 20)

        rig.recorder.stop()
    }

    @MainActor
    func testDiagnosticContextMentionsTheBackgroundSetting() throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        XCTAssertTrue(rig.recorder.diagnosticContext().contains("фоновая запись: вкл"))
        rig.recorder.recordsInBackground = false
        XCTAssertTrue(rig.recorder.diagnosticContext().contains("фоновая запись: выкл"))
    }
}

// MARK: - Режим экономии заряда

final class RouteRecorderPowerSaverTests: XCTestCase {
    /// Широта, на которую сдвигается телефон на ~20 м
    private let twentyMeters = 0.00018

    @MainActor
    func testSessionIsToldWhetherPowerSavingIsOn() throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        rig.recorder.start()
        XCTAssertEqual(rig.session.powerSavingValues.last, false, "Без режима экономии геолокация работает как раньше")

        rig.powerSaver.isOn = true
        let startsBefore = rig.session.startCount
        rig.recorder.powerSaverChanged()
        XCTAssertEqual(rig.session.powerSavingValues.last, true)
        XCTAssertGreaterThan(rig.session.startCount, startsBefore, "Геолокация перезапускается с новой точностью")

        rig.powerSaver.isOn = false
        rig.recorder.powerSaverChanged()
        XCTAssertEqual(rig.session.powerSavingValues.last, false)

        rig.recorder.stop()
    }

    @MainActor
    func testSwitchingPowerSaverWithoutRecordingTouchesNothing() throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        rig.powerSaver.isOn = true
        rig.recorder.powerSaverChanged()

        XCTAssertEqual(rig.session.startCount, 0, "Записи нет: геолокацию запускать незачем")
        XCTAssertTrue(rig.session.powerSavingValues.isEmpty)
        XCTAssertFalse(rig.recorder.isActive)
    }

    @MainActor
    func testSaverWritesPointsLessOftenThanTheStandardMode() async throws {
        // 20 м за 5 секунд: обычный режим пишет точку, режим экономии (порог 50 м) ещё нет
        func pointsAfterShortMove(saver: Bool) async throws -> Int {
            let rig = try makeRig(authorization: .authorized)
            defer { try? FileManager.default.removeItem(at: rig.directory) }
            rig.powerSaver.isOn = saver
            rig.recorder.start()
            let t0 = Date()
            rig.session.emit(fix(55.0, at: t0))
            await rig.recorder.tick(now: t0)
            let t1 = t0.addingTimeInterval(5)
            rig.session.emit(fix(55.0 + twentyMeters, at: t1))
            await rig.recorder.tick(now: t1)
            let count = rig.recorder.pointCount
            rig.recorder.stop()
            return count
        }

        let standard = try await pointsAfterShortMove(saver: false)
        let saver = try await pointsAfterShortMove(saver: true)

        XCTAssertEqual(standard, 2)
        XCTAssertEqual(saver, 1, "В режиме экономии 20 м ещё не движение")
    }

    @MainActor
    func testSaverStillFollowsRealMovement() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.powerSaver.isOn = true

        rig.recorder.start()
        var now = Date()
        var latitude = 55.0
        // Около 80 м за шаг проверки (15 секунд): телефон едет, значит, каждая проверка добавляет точку
        for _ in 0..<5 {
            rig.session.emit(fix(latitude, at: now))
            await rig.recorder.tick(now: now)
            latitude += twentyMeters * 4
            now = now.addingTimeInterval(15)
        }

        XCTAssertEqual(rig.recorder.pointCount, 5, "Пока телефон движется, режим экономии маршрут не теряет")
        rig.recorder.stop()
    }

    @MainActor
    func testStandingPhoneGetsOnePointPerMinuteInSaverMode() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.powerSaver.isOn = true

        rig.recorder.start()
        let t0 = Date()
        rig.session.emit(fix(55.0, at: t0))
        await rig.recorder.tick(now: t0)

        // Шаг проверки 15 секунд: на 15, 30 и 45-й секундах точка не нужна, на 60-й нужна, на 75 и 90-й снова нет
        for step in 1...6 {
            let time = t0.addingTimeInterval(Double(step) * 15)
            rig.session.emit(fix(55.0, at: time))
            await rig.recorder.tick(now: time)
        }

        XCTAssertEqual(rig.recorder.pointCount, 2)
        rig.recorder.stop()
    }

    @MainActor
    func testSaverDoesNotMeasureSpeedOnTheRoute() async throws {
        func speedRequests(saver: Bool) async throws -> Int {
            let rig = try makeRig(authorization: .authorized)
            defer { try? FileManager.default.removeItem(at: rig.directory) }
            rig.recorder.measuresSpeed = true
            rig.powerSaver.isOn = saver
            rig.recorder.start()
            let now = Date()
            rig.session.emit(fix(55.0, at: now))
            await rig.recorder.tick(now: now)
            let requests = await rig.probe.speedRequests
            rig.recorder.stop()
            return requests
        }

        let normal = try await speedRequests(saver: false)
        let saver = try await speedRequests(saver: true)

        XCTAssertEqual(normal, 1, "Замер скорости включён: на первой точке скорость измеряется")
        XCTAssertEqual(saver, 0, "В режиме экономии скорость не качается, хотя замер включён: это до 1,5 МБ каждые 30 секунд")
    }

    @MainActor
    func testRouteStartedInSaverModeIsNotMarkedAsSpeedMeasured() throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.recorder.measuresSpeed = true
        rig.powerSaver.isOn = true

        rig.recorder.start()
        XCTAssertEqual(rig.recorder.current?.measuredSpeed, false)
        rig.recorder.stop()
    }

    @MainActor
    func testSaverStopsTheRecordingAfterTenIdleMinutes() async throws {
        func isStillRecording(afterIdleMinutes minutes: Double, saver: Bool) async throws -> Bool {
            let rig = try makeRig(authorization: .authorized)
            defer { try? FileManager.default.removeItem(at: rig.directory) }
            rig.powerSaver.isOn = saver
            rig.recorder.start()
            let t0 = Date()
            rig.session.emit(fix(55.0, at: t0))
            await rig.recorder.tick(now: t0)
            let later = t0.addingTimeInterval(minutes * 60)
            rig.session.emit(fix(55.0, at: later))
            await rig.recorder.tick(now: later)
            let active = rig.recorder.isActive
            rig.recorder.stop()
            return active
        }

        let normalAfterEleven = try await isStillRecording(afterIdleMinutes: 11, saver: false)
        let saverAfterEleven = try await isStillRecording(afterIdleMinutes: 11, saver: true)
        let saverAfterNine = try await isStillRecording(afterIdleMinutes: 9, saver: true)

        XCTAssertTrue(normalAfterEleven, "Обычный режим ждёт 20 минут")
        XCTAssertFalse(saverAfterEleven, "Режим экономии останавливает забытую запись после 10 минут простоя")
        XCTAssertTrue(saverAfterNine)
    }

    @MainActor
    func testSaverExplainsWhyNoNewPositionArrives() async throws {
        func lineAfterSilence(saver: Bool) async throws -> String {
            let rig = try makeRig(authorization: .authorized)
            defer { try? FileManager.default.removeItem(at: rig.directory) }
            rig.powerSaver.isOn = saver
            rig.recorder.start()
            let t0 = Date()
            rig.session.emit(fix(55.0, at: t0))
            await rig.recorder.tick(now: t0)
            // Положение больше не приходит: у стоящего телефона в режиме экономии это обычное дело
            await rig.recorder.tick(now: t0.addingTimeInterval(200))
            let line = rig.recorder.progressLine
            rig.recorder.stop()
            return line
        }

        let standard = try await lineAfterSilence(saver: false)
        let saver = try await lineAfterSilence(saver: true)

        XCTAssertEqual(standard, "Ждём сигнал GPS…")
        XCTAssertTrue(saver.contains("Новых данных о положении нет"), saver)
    }

    @MainActor
    func testWaitingForTheFirstPositionStaysAGpsHintInSaverMode() async throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.powerSaver.isOn = true

        rig.recorder.start()
        await rig.recorder.tick(now: Date())

        XCTAssertEqual(rig.recorder.progressLine, "Ждём сигнал GPS…", "Положения ещё не было ни разу: это ожидание GPS")
        rig.recorder.stop()
    }

    @MainActor
    func testDiagnosticContextMentionsSaverAndAfterCloseSettings() throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        var context = rig.recorder.diagnosticContext()
        XCTAssertTrue(context.contains("экономия заряда: выкл"), context)
        XCTAssertTrue(context.contains("после закрытия: выкл"), context)

        rig.powerSaver.isOn = true
        rig.recorder.continuesAfterClose = true
        context = rig.recorder.diagnosticContext()
        XCTAssertTrue(context.contains("экономия заряда: вкл"), context)
        XCTAssertTrue(context.contains("после закрытия: вкл"), context)
    }
}

// MARK: - Правила записи: инварианты

final class SamplingPolicyInvariantTests: XCTestCase {
    func testSaverPolicyIsSparserThanEconomy() {
        let economy = RouteSamplingPolicy.economy
        let saver = RouteSamplingPolicy.saver
        XCTAssertGreaterThan(saver.tickInterval, economy.tickInterval)
        XCTAssertGreaterThanOrEqual(saver.stationaryInterval, economy.stationaryInterval)
        XCTAssertGreaterThan(saver.minMoveMeters, economy.minMoveMeters)
        XCTAssertGreaterThan(saver.maxAccuracyMeters, economy.maxAccuracyMeters, "Положение в режиме экономии грубее (около 100 м)")
        XCTAssertGreaterThan(saver.maxFixAge, saver.tickInterval, "Положение не должно устаревать быстрее, чем идёт цикл")
    }

    /// Пока телефон стоит, точки идут с паузой; если пауза длиннее порога разрыва, линия маршрута рвётся там,
    /// где никто никуда не ехал, и расстояние считается неверно.
    func testStandingStillNeverBreaksTheRouteLine() {
        let policies: [(String, RouteSamplingPolicy)] = [
            ("обычный", .standard),
            ("экономный", .economy),
            ("экономия заряда", .saver)
        ]
        for (name, policy) in policies {
            XCTAssertLessThan(
                policy.worstCaseStationaryGap,
                RouteAnalyzer.maxGapSeconds,
                "Режим «\(name)»: между точками стоящего телефона может пройти \(policy.worstCaseStationaryGap) с, а линия рвётся после \(RouteAnalyzer.maxGapSeconds) с"
            )
        }
    }
}

// MARK: - Запись после закрытия приложения

final class RouteRecorderAfterCloseTests: XCTestCase {

    /// Недописанный маршрут на диске, как его оставляет закрытое приложение
    private func unfinishedRoute() -> RouteRecord {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return RouteRecord(
            startedAt: start,
            points: [
                RoutePoint(time: start, latitude: 55.0, longitude: 37.0, latencyMs: 40),
                RoutePoint(time: start.addingTimeInterval(15), latitude: 55.0005, longitude: 37.0, latencyMs: 45),
                RoutePoint(time: start.addingTimeInterval(30), latitude: 55.001, longitude: 37.0, latencyMs: 50)
            ]
        )
    }

    @MainActor
    func testItIsOffByDefaultAndRemembered() throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        XCTAssertFalse(rig.recorder.continuesAfterClose, "Продолжение после закрытия просит доступ «Всегда»: по умолчанию выключено")

        rig.recorder.continuesAfterClose = true

        let second = try makeRig(authorization: .authorized, defaults: rig.defaults)
        defer { try? FileManager.default.removeItem(at: second.directory) }
        XCTAssertTrue(second.recorder.continuesAfterClose, "Выбор пользователя сохраняется между запусками")
    }

    @MainActor
    func testTurningItOnAsksForAlwaysAccessOnlyWhenItIsMissing() throws {
        let without = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: without.directory) }
        without.recorder.continuesAfterClose = true
        XCTAssertEqual(without.session.alwaysRequests, 1)
        without.recorder.continuesAfterClose = true
        XCTAssertEqual(without.session.alwaysRequests, 1, "Тот же выбор повторно окно не открывает")

        let granted = try makeRig(authorization: .authorized, alwaysGranted: true)
        defer { try? FileManager.default.removeItem(at: granted.directory) }
        granted.recorder.continuesAfterClose = true
        XCTAssertEqual(granted.session.alwaysRequests, 0, "«Всегда» уже есть: просить нечего")
        XCTAssertFalse(granted.session.watchingMoves, "Записи нет: следить за перемещениями незачем")
    }

    @MainActor
    func testRecordingWatchesBigMovesOnlyWhenEverythingIsAllowed() throws {
        let rig = try makeRig(authorization: .authorized, alwaysGranted: true)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        rig.recorder.start()
        XCTAssertFalse(rig.session.watchingMoves, "Продолжение после закрытия выключено")

        rig.recorder.continuesAfterClose = true
        XCTAssertTrue(rig.session.watchingMoves, "Включили во время записи: слежение началось сразу")

        rig.recorder.continuesAfterClose = false
        XCTAssertFalse(rig.session.watchingMoves)

        rig.recorder.continuesAfterClose = true
        rig.recorder.recordsInBackground = false
        XCTAssertFalse(rig.session.watchingMoves, "Закрытое приложение работает только в фоне: без фоновой записи следить не нужно")
        rig.recorder.recordsInBackground = true
        XCTAssertTrue(rig.session.watchingMoves)

        rig.recorder.stop()
        XCTAssertFalse(rig.session.watchingMoves, "Запись закончена: iOS больше не нужно запускать приложение")
    }

    @MainActor
    func testWithoutAlwaysAccessNothingIsWatchedUntilItIsGranted() throws {
        let rig = try makeRig(authorization: .authorized)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.recorder.continuesAfterClose = true

        rig.recorder.start()
        XCTAssertFalse(rig.session.watchingMoves, "Без «Всегда» iOS всё равно не запустит закрытое приложение")
        XCTAssertFalse(rig.recorder.hasAlwaysAuthorization)

        // Пользователь согласился на «Всегда», пока шла запись
        rig.session.hasAlwaysAuthorization = true
        rig.session.changeAuthorization(to: .authorized)
        XCTAssertTrue(rig.recorder.hasAlwaysAuthorization)
        XCTAssertTrue(rig.session.watchingMoves)

        rig.recorder.stop()
    }

    @MainActor
    func testRelaunchContinuesTheSameRoute() async throws {
        let rig = try makeRig(authorization: .authorized, alwaysGranted: true)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.recorder.continuesAfterClose = true
        let unfinished = unfinishedRoute()
        try await rig.storage.saveActive(unfinished)

        let resumed = await rig.recorder.resumeAfterRelaunch()

        XCTAssertTrue(resumed)
        XCTAssertTrue(rig.recorder.isActive)
        XCTAssertEqual(rig.recorder.state, .recording)
        XCTAssertEqual(rig.recorder.current?.id, unfinished.id, "Запись дописывается в тот же маршрут, а не начинает новый")
        XCTAssertEqual(rig.recorder.pointCount, 3)
        XCTAssertEqual(rig.recorder.recordingSince, unfinished.startedAt)
        XCTAssertEqual(rig.session.startCount, 1)
        XCTAssertTrue(rig.session.watchingMoves, "Слежение за перемещениями продолжается")
        XCTAssertTrue(rig.recorder.history.isEmpty, "Маршрут не сохраняется как прерванный: он продолжается")
        let notice = try XCTUnwrap(rig.recorder.notice)
        XCTAssertTrue(notice.contains("продолжена"), notice)

        // Новая точка ложится после пропуска, а линия через пропуск не проводится
        let now = Date()
        rig.session.emit(fix(55.2, at: now))
        await rig.recorder.tick(now: now)
        let points = try XCTUnwrap(rig.recorder.current).points
        XCTAssertEqual(points.count, 4)
        XCTAssertEqual(
            RouteAnalyzer.distanceMeters(of: points),
            RouteAnalyzer.distanceMeters(of: Array(points.prefix(3))),
            accuracy: 0.001,
            "Между закрытием и запуском пропуск: 22 км по прямой в длину пути не входят"
        )

        rig.recorder.stop()
    }

    @MainActor
    func testRelaunchDoesNotResumeWhenSomethingIsNotAllowed() async throws {
        func attempt(
            _ name: String,
            authorization: LocationAuthorization = .authorized,
            always: Bool = true,
            continues: Bool = true,
            background: Bool = true,
            file: StaticString = #filePath,
            line: UInt = #line
        ) async throws {
            let rig = try makeRig(authorization: authorization, alwaysGranted: always)
            defer { try? FileManager.default.removeItem(at: rig.directory) }
            rig.recorder.continuesAfterClose = continues
            rig.recorder.recordsInBackground = background
            rig.session.setRelaunchOnMove(enabled: true)   // iOS ещё помнит подписку на перемещения
            try await rig.storage.saveActive(unfinishedRoute())

            let resumed = await rig.recorder.resumeAfterRelaunch()

            XCTAssertFalse(resumed, name, file: file, line: line)
            XCTAssertFalse(rig.recorder.isActive, name, file: file, line: line)
            XCTAssertEqual(rig.session.startCount, 0, name, file: file, line: line)
            XCTAssertFalse(rig.session.watchingMoves, "\(name): подписку на перемещения нужно снять", file: file, line: line)
            let stillThere = await rig.storage.loadActive()
            XCTAssertNotNil(stillThere, "\(name): недописанный маршрут остаётся на диске до открытия приложения", file: file, line: line)
        }

        try await attempt("продолжение после закрытия выключено", continues: false)
        try await attempt("нет доступа «Всегда»", always: false)
        try await attempt("геолокация запрещена", authorization: .denied)
        try await attempt("фоновая запись выключена", background: false)
    }

    @MainActor
    func testRelaunchWithoutUnfinishedRouteDoesNothing() async throws {
        let rig = try makeRig(authorization: .authorized, alwaysGranted: true)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.recorder.continuesAfterClose = true
        rig.session.setRelaunchOnMove(enabled: true)

        let resumed = await rig.recorder.resumeAfterRelaunch()

        XCTAssertFalse(resumed)
        XCTAssertFalse(rig.recorder.isActive)
        XCTAssertFalse(rig.session.watchingMoves, "Дописывать нечего: iOS больше не нужно запускать приложение")
    }

    @MainActor
    func testRelaunchDoesNotTouchARecordingThatIsAlreadyRunning() async throws {
        let rig = try makeRig(authorization: .authorized, alwaysGranted: true)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.recorder.continuesAfterClose = true
        rig.recorder.start()
        let runningID = try XCTUnwrap(rig.recorder.current).id
        try await rig.storage.saveActive(unfinishedRoute())

        let resumed = await rig.recorder.resumeAfterRelaunch()

        XCTAssertFalse(resumed)
        XCTAssertEqual(rig.recorder.current?.id, runningID)
        XCTAssertTrue(rig.session.watchingMoves, "Идущая запись продолжает следить за перемещениями")
        rig.recorder.stop()
    }

    @MainActor
    func testOpeningTheAppByHandSavesTheRouteAndDropsTheSubscription() async throws {
        let rig = try makeRig(authorization: .authorized, alwaysGranted: true)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.recorder.continuesAfterClose = true
        rig.session.setRelaunchOnMove(enabled: true)
        try await rig.storage.saveActive(unfinishedRoute())

        await rig.recorder.recoverInterruptedRoute()

        XCTAssertFalse(rig.session.watchingMoves, "Приложение открыли сами: подписка на перемещения от прежней записи не нужна")
        XCTAssertEqual(rig.recorder.history.count, 1)
        XCTAssertEqual(rig.recorder.history.first?.interrupted, true)
        XCTAssertFalse(rig.recorder.isActive)
    }

    @MainActor
    func testRecoveryLeavesAResumedRecordingAlone() async throws {
        let rig = try makeRig(authorization: .authorized, alwaysGranted: true)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.recorder.continuesAfterClose = true
        let unfinished = unfinishedRoute()
        try await rig.storage.saveActive(unfinished)
        let resumed = await rig.recorder.resumeAfterRelaunch()
        XCTAssertTrue(resumed)

        // Пользователь открыл приложение: обычный запуск не должен «закрыть» маршрут, который снова пишется
        await rig.recorder.recoverInterruptedRoute()

        XCTAssertTrue(rig.recorder.isActive)
        XCTAssertTrue(rig.recorder.history.isEmpty)
        XCTAssertEqual(rig.recorder.current?.id, unfinished.id)
        XCTAssertTrue(rig.session.watchingMoves)
        rig.recorder.stop()
    }

    @MainActor
    func testReturningToTheAppKeepsTheResumedRoute() async throws {
        let rig = try makeRig(authorization: .authorized, alwaysGranted: true)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.recorder.continuesAfterClose = true
        let unfinished = unfinishedRoute()
        try await rig.storage.saveActive(unfinished)
        let resumed = await rig.recorder.resumeAfterRelaunch()
        XCTAssertTrue(resumed)

        let startsBefore = rig.session.startCount
        rig.recorder.appDidBecomeActive()

        XCTAssertEqual(rig.recorder.current?.id, unfinished.id)
        XCTAssertEqual(rig.recorder.state, .recording)
        XCTAssertGreaterThan(rig.session.startCount, startsBefore, "При возвращении геолокация запускается заново, как и раньше")
        XCTAssertTrue(rig.session.watchingMoves)
        rig.recorder.stop()
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
