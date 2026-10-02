//
//  ModesAndPrivacyTests.swift
//  NetPulseTests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest
@testable import NetPulse

// MARK: - Непрерывный режим

final class ContinuousModeStateTests: XCTestCase {
    private typealias State = ContinuousModeManager.State

    func testEveryActiveStateHasUserFacingText() {
        XCTAssertEqual(State.off.statusText, "")
        for state in [State.waitingForPermission, .running, .denied, .restricted, .unavailable] {
            XCTAssertFalse(state.statusText.isEmpty, "У состояния \(state) нет подписи для экрана настроек")
        }
    }

    func testOnlyProblemStatesNeedAttention() {
        XCTAssertTrue(State.denied.needsAttention)
        XCTAssertTrue(State.restricted.needsAttention)
        XCTAssertTrue(State.unavailable.needsAttention)
        XCTAssertFalse(State.off.needsAttention)
        XCTAssertFalse(State.waitingForPermission.needsAttention)
        XCTAssertFalse(State.running.needsAttention)
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

// MARK: - Что уходит в облачный AI

/// В сторонний сервис не должны попадать IP-адреса и название провайдера, а отсутствие данных не маскируется.
final class CloudPrivacyTests: XCTestCase {

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

    func testCloudSummaryOmitsIdentifyingData() {
        let summary = context(hasLiveData: true, averagePingMs: 23.4, speedtestDownloadMbps: 90).summaryForCloudAI

        for secret in ["192.168.7.23", "192.168.7.1", "203.0.113.77", "Секретный Провайдер", "10.9.8.7"] {
            XCTAssertFalse(summary.contains(secret), "В облачную сводку попало: \(secret)")
        }
        XCTAssertTrue(summary.contains("23.4"), "Измеренный пинг должен быть в сводке")
        XCTAssertTrue(summary.contains("отдача не измерена"), "Неизмеренная отдача не должна выдаваться за нуль")
    }

    func testSummaryAdmitsMissingData() {
        let summary = context(hasLiveData: false, averagePingMs: nil, speedtestDownloadMbps: nil).summaryForCloudAI

        XCTAssertTrue(summary.contains("свежих данных нет"))
        XCTAssertTrue(summary.contains("Замер скорости не выполнялся"))
        XCTAssertFalse(summary.contains("Средний пинг"), "Без данных мониторинга пинга в сводке быть не должно")
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

    func testProvidersHaveUniqueStorageKeysAndDefaultModels() {
        XCTAssertFalse(AIProviderType.offlineSmart.isCloud)

        for provider in AIProviderType.allCases where provider != .offlineSmart {
            XCTAssertTrue(provider.isCloud, "\(provider.rawValue) должен считаться облачным")
            XCTAssertFalse(provider.defaultModelName.isEmpty)
        }

        let keys = AIProviderType.allCases.map { $0.storageKey }
        XCTAssertEqual(Set(keys).count, keys.count, "Ключи хранилища (Keychain) должны быть уникальны")
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
