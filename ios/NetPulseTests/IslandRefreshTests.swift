//
//  IslandRefreshTests.swift
//  NetPulseTests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest
@testable import NetPulse

// MARK: - Кадр острова по кнопке «Обновить»

final class IslandSnapshotTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func previousState() -> NetPulseAttributes.ContentState {
        NetPulseAttributes.ContentState(
            downloadSpeedText: "45.2 Мбит/с",
            uploadSpeedText: "8.10 Мбит/с",
            compactDownloadText: "45",
            compactUploadText: "8.1",
            pingMs: 31,
            jitterMs: 4.2,
            isTesting: true,
            connectionType: "Wi-Fi",
            ispName: "Ростелеком",
            isGamingMode: true,
            gameTitle: "CS2",
            gameRegion: "Европа",
            packetLossPct: 2,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    func testReachableResultReplacesPingAndDownload() {
        let result = ProbeResult(reachable: true, latencyMs: 23.6, downloadMbps: 41.27, link: .wifi)
        let state = IslandSnapshot.state(from: result, previous: previousState(), now: now)

        XCTAssertEqual(state.pingMs, 24)
        XCTAssertEqual(state.downloadSpeedText, BandwidthSnapshot.formatSpeed(mbps: 41.27))
        XCTAssertEqual(state.compactDownloadText, BandwidthSnapshot.compactSpeed(mbps: 41.27))
        XCTAssertEqual(state.updatedAt, now, "Метка времени кадра нужна, чтобы остров потом честно показал возраст данных")
        XCTAssertFalse(state.isTesting)
        XCTAssertEqual(state.connectionType, "Wi-Fi")
    }

    /// Отдача и джиттер при нажатии кнопки не измеряются: прежнее число рядом со свежим пингом выглядело бы свежим
    func testUnmeasuredValuesBecomeDashesInsteadOfOldNumbers() {
        let result = ProbeResult(reachable: true, latencyMs: 20, downloadMbps: 12, link: .wifi)
        let state = IslandSnapshot.state(from: result, previous: previousState(), now: now)

        XCTAssertEqual(state.uploadSpeedText, "— Мбит/с")
        XCTAssertEqual(state.compactUploadText, "—")
        XCTAssertNil(state.jitterMs)
        XCTAssertNil(state.packetLossPct)
    }

    func testMissingSpeedSampleShowsDashNotZero() {
        let result = ProbeResult(reachable: true, latencyMs: 20, downloadMbps: nil, link: .lte)
        let state = IslandSnapshot.state(from: result, previous: previousState(), now: now)

        XCTAssertEqual(state.downloadSpeedText, "— Мбит/с")
        XCTAssertEqual(state.compactDownloadText, "—")
        XCTAssertEqual(state.pingMs, 20, "Пинг при этом свежий")
        XCTAssertEqual(state.connectionType, "4G (LTE)")
    }

    func testUnreachableNetworkShowsNoConnectionAndFullLoss() {
        let result = ProbeResult(reachable: false, latencyMs: nil, downloadMbps: nil, link: .offline)
        let state = IslandSnapshot.state(from: result, previous: previousState(), now: now)

        XCTAssertNil(state.pingMs)
        XCTAssertEqual(state.packetLossPct, 100)
        XCTAssertEqual(state.downloadSpeedText, "— Мбит/с")
        XCTAssertEqual(state.connectionType, "Нет подключения")
    }

    func testProviderAndGameInfoAreKept() {
        let result = ProbeResult(reachable: true, latencyMs: 20, downloadMbps: 12, link: .wifi)
        let state = IslandSnapshot.state(from: result, previous: previousState(), now: now)

        XCTAssertEqual(state.ispName, "Ростелеком")
        XCTAssertTrue(state.isGamingMode)
        XCTAssertEqual(state.gameTitle, "CS2")
        XCTAssertEqual(state.gameRegion, "Европа")
    }

    func testConnectionLabels() {
        XCTAssertEqual(IslandSnapshot.connectionLabel(for: .wifi, fallback: "x"), "Wi-Fi")
        XCTAssertEqual(IslandSnapshot.connectionLabel(for: .ethernet, fallback: "x"), "Ethernet")
        XCTAssertEqual(IslandSnapshot.connectionLabel(for: .g5, fallback: "x"), "5G")
        XCTAssertEqual(IslandSnapshot.connectionLabel(for: .g3, fallback: "x"), "3G")
        XCTAssertEqual(IslandSnapshot.connectionLabel(for: .cellular, fallback: "x"), "Сотовая")
        XCTAssertEqual(IslandSnapshot.connectionLabel(for: .offline, fallback: "x"), "Нет подключения")
        XCTAssertEqual(IslandSnapshot.connectionLabel(for: .other, fallback: "Ethernet"), "Ethernet", "Неопределённый вид связи не стирает прежнюю подпись")
    }

    @MainActor
    func testManualFrameStaysFreshLongerThanRegularFrames() {
        XCTAssertGreaterThan(IslandSnapshot.staleAfter, ActivityManager.staleAfter)
    }
}

// MARK: - Связка кнопки с приложением

private final class CallFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func set() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}

final class IslandRefreshBridgeTests: XCTestCase {

    override func tearDown() {
        IslandRefreshBridge.uninstall()
        super.tearDown()
    }

    func testRunWithoutHandlerWaitsAndReportsNothingDone() async {
        IslandRefreshBridge.uninstall()
        let ran = await IslandRefreshBridge.run(waitSeconds: 0.2)
        XCTAssertFalse(ran)
    }

    func testRunCallsTheInstalledHandler() async {
        let flag = CallFlag()
        IslandRefreshBridge.install { flag.set() }
        let ran = await IslandRefreshBridge.run(waitSeconds: 0.2)
        XCTAssertTrue(ran)
        XCTAssertTrue(flag.isSet)
    }

    /// При холодном запуске в фоне кнопка может прийти раньше, чем приложение поставит обработчик
    func testHandlerInstalledJustAfterThePressIsStillUsed() async {
        IslandRefreshBridge.uninstall()
        let flag = CallFlag()
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            IslandRefreshBridge.install { flag.set() }
        }
        let ran = await IslandRefreshBridge.run(waitSeconds: 3)
        XCTAssertTrue(ran)
        XCTAssertTrue(flag.isSet)
    }

    func testBridgeWaitIsShortEnoughForABackgroundLaunch() {
        XCTAssertLessThanOrEqual(IslandRefreshBridge.installWaitSeconds, 5)
        XCTAssertGreaterThan(IslandRefreshBridge.installWaitSeconds, 0)
    }
}
