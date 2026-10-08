//
//  ModesAndPrivacyTests.swift
//  NetPulseTests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest
@testable import NetPulse

// MARK: - Запись маршрута: состояния и сборка

final class RouteRecorderStateTests: XCTestCase {
    private typealias State = RouteRecorder.State

    func testEveryActiveStateHasUserFacingText() {
        XCTAssertEqual(State.idle.statusText, "")
        for state in [State.waitingForPermission, .recording, .denied, .restricted, .unavailable] {
            XCTAssertFalse(state.statusText.isEmpty, "У состояния \(state) нет подписи для экрана «Карта сети»")
            XCTAssertFalse(state.logLabel.isEmpty)
        }
    }

    func testOnlyProblemStatesNeedAttention() {
        XCTAssertTrue(State.denied.needsAttention)
        XCTAssertTrue(State.restricted.needsAttention)
        XCTAssertTrue(State.unavailable.needsAttention)
        XCTAssertFalse(State.idle.needsAttention)
        XCTAssertFalse(State.waitingForPermission.needsAttention)
        XCTAssertFalse(State.recording.needsAttention)
    }

    /// Состояния, при которых нужны действия пользователя, должны объяснять, что делать
    func testPermissionStatesExplainWhatToDo() {
        XCTAssertTrue(State.denied.statusText.contains("Настройках"))
        XCTAssertTrue(State.waitingForPermission.statusText.contains("При использовании"))
        XCTAssertTrue(State.waitingForPermission.statusText.contains("Однократно"), "Название кнопки должно совпадать с тем, что показывает iOS")
    }

    /// Фоновая геолокация без записи `location` в UIBackgroundModes роняет приложение исключением CoreLocation,
    /// поэтому менеджер перед включением проверяет Info.plist. Тест гарантирует, что запись на месте.
    func testInfoPlistDeclaresLocationBackgroundMode() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        XCTAssertTrue(modes.contains("location"), "В Info.plist нет UIBackgroundModes = location: режим не сможет работать")

        let purpose = Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String
        XCTAssertFalse((purpose ?? "").isEmpty, "В Info.plist нет текста запроса геолокации")
    }

    /// Длинный текст запроса делает системное окно выше экрана: видна только первая кнопка («Однократно»), а нужная
    /// «При использовании приложения» уезжает вниз (так было при 307 символах). Текст — одно короткое предложение.
    func testLocationPromptTextIsShortEnoughForAllButtonsToFit() {
        let purpose = Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String ?? ""
        XCTAssertFalse(purpose.isEmpty)
        XCTAssertLessThanOrEqual(purpose.count, 140, "Текст запроса геолокации слишком длинный (\(purpose.count) символов): кнопки не поместятся в окне")
    }

    /// Аудио-режим убран из-за правила App Store 2.5.4 и не должен вернуться незаметно.
    func testInfoPlistHasNoAudioBackgroundMode() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        XCTAssertFalse(modes.contains("audio"))
    }
}

// MARK: - Обращение провайдеру

/// Обращение провайдеру содержит только измеренное, а отсутствие данных не маскируется.
final class ISPReportTests: XCTestCase {

    private func context(
        hasLiveData: Bool,
        averagePingMs: Double?,
        speedtestDownloadMbps: Double?
    ) -> NetworkDiagnosticsContext {
        NetworkDiagnosticsContext(
            connectionType: "Wi-Fi",
            localIP: "192.168.7.23",
            gatewayIP: "192.168.7.1",
            publicIP: "203.0.113.77",
            ispName: "Секретный Провайдер",
            dnsServers: ["10.9.8.7"],
            averagePingMs: averagePingMs,
            jitterMs: 1.5,
            packetLossPct: 0,
            hasLiveData: hasLiveData,
            liveDownloadMbps: 5,
            liveUploadMbps: 1,
            speedtestDownloadMbps: speedtestDownloadMbps,
            speedtestUploadMbps: nil,
            recentAlertsCount: 0,
            tracerouteHopsCount: 0
        )
    }

    func testUnmeasuredUploadStaysNil() {
        XCTAssertNil(context(hasLiveData: true, averagePingMs: 10, speedtestDownloadMbps: 50).measuredUploadMbps)
    }

    /// Обращение провайдеру содержит только измеренное: раньше шаблон подставлял шлюз 192.168.1.1 и «систематические потери».
    func testSupportReportDoesNotInventMeasurements() {
        let report = context(hasLiveData: false, averagePingMs: nil, speedtestDownloadMbps: nil).generateISPSupportReport()

        XCTAssertTrue(report.contains("не измерялась (мониторинг не работал)"))
        XCTAssertTrue(report.contains("Скорость загрузки (замер): не измерялась"))
        XCTAssertFalse(report.contains("192.168.1.1"))
        XCTAssertFalse(report.localizedCaseInsensitiveContains("систематическ"))
    }
}

/// Приложение не просит доступ к микрофону и распознаванию речи: голосового ввода больше нет.
final class NoVoicePermissionsTests: XCTestCase {
    func testInfoPlistHasNoMicrophoneOrSpeechKeys() {
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription"))
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription"))
    }
}

// MARK: - Оценка возможностей сети

final class CapabilityTests: XCTestCase {

    /// Без замера скорости ни один сценарий не получает оценку.
    func testNoSpeedMeasurementMeansNoVerdicts() {
        let items = NetworkCapabilityEvaluator(downloadMbps: 0, uploadMbps: 0, pingMs: 20, jitterMs: 1).evaluateAll()
        XCTAssertEqual(items.count, 4)
        XCTAssertTrue(items.allSatisfy { $0.level == .unknown })
    }

    /// Раньше без пинга подставлялись «50 мс, джиттер 5 мс» и игры получали оценку.
    func testGamingNeedsMeasuredPing() throws {
        let items = NetworkCapabilityEvaluator(downloadMbps: 100, uploadMbps: 50, pingMs: nil, jitterMs: nil).evaluateAll()

        let gaming = try XCTUnwrap(items.first { $0.category == "Гейминг" })
        XCTAssertEqual(gaming.level, .unknown)

        let streaming = try XCTUnwrap(items.first { $0.category == "Медиа" })
        XCTAssertEqual(streaming.level, .excellent)
    }

    /// Видеозвонки зависят от отдачи: без её замера оценки нет.
    func testVideoCallsNeedMeasuredUpload() throws {
        let items = NetworkCapabilityEvaluator(downloadMbps: 100, uploadMbps: 0, pingMs: 20, jitterMs: 2).evaluateAll()
        let calls = try XCTUnwrap(items.first { $0.category == "Связь" })
        XCTAssertEqual(calls.level, .unknown)
    }
}

// MARK: - История и экспорт

final class HistoryExportTests: XCTestCase {

    func testRecordsAreCounted() async {
        let storage = HistoryStorage()
        await storage.recordPing(PingRecord(host: "1.1.1.1", targetName: "Cloudflare", isSuccess: true, latencyMs: 12.5))
        await storage.recordPing(PingRecord(host: "8.8.8.8", targetName: "Google", isSuccess: false))

        let counts = await storage.counts()
        XCTAssertEqual(counts.pings, 2)
        XCTAssertEqual(counts.alerts, 0)
        XCTAssertEqual(counts.speedtests, 0)
    }

    /// История не растёт бесконечно: старые записи вытесняются.
    func testHistoryIsBounded() async {
        let storage = HistoryStorage()
        for index in 0..<20_700 {
            await storage.recordPing(PingRecord(host: "1.1.1.1", targetName: "Узел \(index)", isSuccess: true, latencyMs: 10))
        }
        let pings = await storage.counts().pings
        XCTAssertTrue((20_000...20_500).contains(pings), "В памяти \(pings) записей: ограничение не работает")
    }

    /// Имя узла вводит пользователь: значение, начинающееся с «=», Excel выполнил бы как формулу.
    func testCSVNeutralizesFormulasAndQuotesSeparators() async throws {
        let storage = HistoryStorage()
        await storage.recordPing(PingRecord(host: "1.1.1.1", targetName: "=HYPERLINK(\"http://evil\")", isSuccess: true, latencyMs: 12.5))
        await storage.recordPing(PingRecord(host: "8.8.8.8", targetName: "Узел, с запятой", isSuccess: false, errorMessage: "таймаут"))

        let url = try await storage.exportSessionToCSV()
        defer { try? FileManager.default.removeItem(at: url) }
        let csv = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(csv.hasPrefix("Timestamp,TargetName,Host,Success,Latency_ms,Protocol,Error\n"))
        XCTAssertTrue(csv.contains("\"'=HYPERLINK(\"\"http://evil\"\")\""), "Формула должна получить префикс и экранирование кавычек:\n\(csv)")
        XCTAssertTrue(csv.contains("\"Узел, с запятой\""), "Поле с запятой должно быть в кавычках:\n\(csv)")
        XCTAssertFalse(csv.contains(",=HYPERLINK"), "Ячейка не должна начинаться с «=»")
    }
}

// MARK: - Ссылки на политику конфиденциальности и поддержку

final class AppLinksTests: XCTestCase {
    /// Правило App Store 5.1.1: политика конфиденциальности доступна по ссылке из приложения
    func testPrivacyAndSupportLinksAreSecureWebPages() {
        for url in [AppLinks.privacyPolicy, AppLinks.support] {
            XCTAssertEqual(url.scheme, "https", "Ссылка должна быть защищённой: \(url)")
            XCTAssertFalse((url.host ?? "").isEmpty, "У ссылки нет хоста: \(url)")
        }
        XCTAssertNotEqual(AppLinks.privacyPolicy, AppLinks.support)
    }
}

// MARK: - Подписка PRO

final class ProEntitlementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testActiveMonthlySubscriptionGrantsPro() {
        XCTAssertTrue(ProEntitlement.grantsPro(
            productID: ProEntitlement.monthlyID, revocationDate: nil,
            expirationDate: now.addingTimeInterval(86_400), now: now
        ))
    }

    func testSubscriptionWithoutExpirationDateGrantsPro() {
        XCTAssertTrue(ProEntitlement.grantsPro(productID: ProEntitlement.monthlyID, revocationDate: nil, expirationDate: nil, now: now))
    }

    func testExpiredSubscriptionDoesNotGrantPro() {
        XCTAssertFalse(ProEntitlement.grantsPro(
            productID: ProEntitlement.monthlyID, revocationDate: nil,
            expirationDate: now.addingTimeInterval(-1), now: now
        ))
    }

    func testRevokedSubscriptionDoesNotGrantPro() {
        XCTAssertFalse(ProEntitlement.grantsPro(
            productID: ProEntitlement.monthlyID, revocationDate: now.addingTimeInterval(-3_600),
            expirationDate: now.addingTimeInterval(86_400), now: now
        ))
    }

    func testOtherProductDoesNotGrantPro() {
        XCTAssertFalse(ProEntitlement.grantsPro(productID: "com.example.other", revocationDate: nil, expirationDate: nil, now: now))
    }

    func testPaidFeaturesAreIslandHudAndAIAudit() {
        XCTAssertEqual(ProFeature.included, [.island, .hud, .aiAudit])
        for feature in ProFeature.allCases {
            XCTAssertFalse(feature.title.isEmpty)
            XCTAssertFalse(feature.summary.isEmpty)
            XCTAssertFalse(feature.icon.isEmpty)
        }
    }
}

@MainActor
final class ProStoreTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "netpulse.test.pro.\(UUID().uuidString)"
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    func testFreeUserIsRefusedAndPaywallOpens() throws {
        let store = ProStore(defaults: try makeDefaults())
        XCTAssertFalse(store.isPro)
        XCTAssertNil(store.paywall)
        XCTAssertFalse(store.requirePro(.island))
        XCTAssertEqual(store.paywall, .island, "Окно подписки подсвечивает возможность, с которой его открыли")
    }

    func testSubscriberPassesWithoutPaywall() throws {
        let store = ProStore(defaults: try makeDefaults())
        store.apply(isActive: true)
        XCTAssertTrue(store.isPro)
        XCTAssertTrue(store.requirePro(.hud))
        XCTAssertNil(store.paywall)
    }

    func testBecomingProClosesPaywallAndNotifiesOnce() throws {
        let store = ProStore(defaults: try makeDefaults())
        var notifications = 0
        store.onChange = { notifications += 1 }
        store.paywall = .aiAudit

        store.apply(isActive: true)
        XCTAssertEqual(notifications, 1)
        XCTAssertNil(store.paywall, "После покупки окно подписки закрывается")

        store.apply(isActive: true)
        XCTAssertEqual(notifications, 1, "Тот же статус повторно никого не будит")
    }

    func testLosingSubscriptionNotifiesAndLocksFeatures() throws {
        let store = ProStore(defaults: try makeDefaults())
        store.apply(isActive: true)
        var notifications = 0
        store.onChange = { notifications += 1 }

        store.apply(isActive: false)
        XCTAssertFalse(store.isPro)
        XCTAssertEqual(notifications, 1, "Остров должен погаснуть сразу, а не после перезапуска")
        XCTAssertFalse(store.requirePro(.island))
    }

    func testStatusIsRememberedBetweenLaunches() throws {
        let defaults = try makeDefaults()
        let first = ProStore(defaults: defaults)
        first.apply(isActive: true)

        let second = ProStore(defaults: defaults)
        XCTAssertTrue(second.isPro, "Подписчик не должен видеть замок до ответа StoreKit")

        second.apply(isActive: false)
        XCTAssertFalse(ProStore(defaults: defaults).isPro, "Отозванная подписка не должна вернуться из памяти")
    }
}
