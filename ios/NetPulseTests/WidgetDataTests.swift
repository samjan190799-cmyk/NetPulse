//
//  WidgetDataTests.swift
//  NetPulseTests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest
@testable import NetPulse

/// Снимок данных для виджетов и острова: никаких выдуманных значений, устаревшие данные не выдаются за живые.
final class WidgetDataTests: XCTestCase {

    // MARK: - Пустой снимок

    /// Раньше без данных виджет показывал демо «285 Мбит/с, здоровье 98» как реальные значения.
    func testEmptySnapshotContainsNoDemoValues() {
        let empty = NetPulseWidgetData.empty
        XCTAssertNil(empty.pingMs)
        XCTAssertNil(empty.jitterMs)
        XCTAssertNil(empty.healthScore)
        XCTAssertEqual(empty.downloadSpeedMbps, 0)
        XCTAssertEqual(empty.uploadSpeedMbps, 0)
        XCTAssertTrue(empty.dnsHosts.isEmpty)
        XCTAssertTrue(empty.isStale)
        XCTAssertEqual(empty.pingValueText, "—")
        XCTAssertEqual(empty.jitterValueText, "—")
    }

    // MARK: - Свежесть данных

    func testFreshValuesAreShown() {
        let fresh = NetPulseWidgetData(pingMs: 24.6, jitterMs: 1.26, lastUpdated: Date())
        XCTAssertFalse(fresh.isStale)
        XCTAssertEqual(fresh.pingValueText, "25")
        XCTAssertEqual(fresh.jitterValueText, "1.3")
        XCTAssertEqual(fresh.formattedPing, "25 мс")
        XCTAssertEqual(fresh.formattedJitter, "1.3 мс")
    }

    /// В фоне приложение пинг не измеряет, поэтому «замороженное» значение старше 10 минут показывать нельзя.
    func testStaleValuesAreHidden() {
        let old = NetPulseWidgetData(pingMs: 24.6, jitterMs: 1.26, lastUpdated: Date().addingTimeInterval(-601))
        XCTAssertTrue(old.isStale)
        XCTAssertEqual(old.pingValueText, "—")
        XCTAssertEqual(old.jitterValueText, "—")
        XCTAssertEqual(old.formattedPing, "—")
        XCTAssertEqual(old.formattedJitter, "—")

        let almostStale = NetPulseWidgetData(pingMs: 10, lastUpdated: Date().addingTimeInterval(-590))
        XCTAssertFalse(almostStale.isStale)
    }

    func testMissingPingIsDashEvenWhenFresh() {
        let noPing = NetPulseWidgetData(pingMs: nil, lastUpdated: Date())
        XCTAssertEqual(noPing.pingValueText, "—")
        XCTAssertEqual(noPing.formattedPing, "—")
    }

    // MARK: - Скорость

    func testUnmeasuredSpeedIsDash() {
        XCTAssertEqual(NetPulseWidgetData.speedText(0), "—")
        XCTAssertEqual(NetPulseWidgetData.speedText(-1), "—")
        XCTAssertEqual(NetPulseWidgetData.speedText(12.34), "12.3")
        XCTAssertEqual(NetPulseWidgetData.speedText(12.34, decimals: 0), "12")
        XCTAssertEqual(NetPulseWidgetData.speedText(12.34, decimals: 2), "12.34")
    }

    // MARK: - Лимит трафика

    func testBudgetProgress() {
        // Лимит не задан: прогресса нет (раньше по умолчанию подставлялись «5 ГБ»)
        let noLimit = NetPulseWidgetData(todayTrafficBytes: 500, budgetTotalBytes: 0)
        XCTAssertEqual(noLimit.budgetProgress, 0)

        // Расход считается за период квоты, а не «за сегодня»
        let half = NetPulseWidgetData(todayTrafficBytes: 10, budgetTotalBytes: 100, budgetUsedBytes: 50)
        XCTAssertEqual(half.budgetProgress, 0.5, accuracy: 0.0001)

        // Снимок старого формата: расход периода неизвестен — используется трафик за сегодня
        let legacy = NetPulseWidgetData(todayTrafficBytes: 25, budgetTotalBytes: 100)
        XCTAssertEqual(legacy.budgetProgress, 0.25, accuracy: 0.0001)

        // Перерасход не выходит за 100 %
        let over = NetPulseWidgetData(todayTrafficBytes: 0, budgetTotalBytes: 100, budgetUsedBytes: 400)
        XCTAssertEqual(over.budgetProgress, 1.0, accuracy: 0.0001)
    }

    // MARK: - Сохранение и чтение

    func testSnapshotSurvivesJSONRoundTrip() throws {
        let original = NetPulseWidgetData(
            downloadSpeedMbps: 42.5,
            uploadSpeedMbps: 7.5,
            pingMs: 31,
            jitterMs: nil,
            ispName: "Тестовая сеть",
            connectionType: "Wi-Fi",
            budgetTotalBytes: 1_000,
            budgetUsedBytes: 250,
            healthScore: nil,
            dnsHosts: [WidgetDNSHost(name: "Cloudflare", address: "1.1.1.1", latencyMs: 14.2, isOK: true)],
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NetPulseWidgetData.self, from: data)

        XCTAssertEqual(decoded.downloadSpeedMbps, 42.5)
        XCTAssertEqual(decoded.pingMs, 31)
        XCTAssertNil(decoded.jitterMs, "Неизмеренный джиттер не должен превращаться в число")
        XCTAssertNil(decoded.healthScore, "Отсутствие индекса здоровья не должно превращаться в 100")
        XCTAssertEqual(decoded.budgetUsedBytes, 250)
        XCTAssertEqual(decoded.dnsHosts.count, 1)
        XCTAssertEqual(decoded.dnsHosts.first?.address, "1.1.1.1")
        XCTAssertEqual(decoded.lastUpdated, original.lastUpdated)
    }

    /// Запись и чтение через общее хранилище. Оба вызова синхронны и идут на главном потоке, как и записи ViewModel,
    /// поэтому между ними ничто не может перезаписать снимок.
    @MainActor
    func testManagerSavesAndLoadsLatestSnapshot() {
        let snapshot = NetPulseWidgetData(
            downloadSpeedMbps: 42.5,
            uploadSpeedMbps: 7.5,
            pingMs: 31,
            ispName: "Проверка менеджера",
            connectionType: "Wi-Fi",
            healthScore: 87,
            lastUpdated: Date()
        )
        WidgetDataManager.shared.saveSnapshot(snapshot, reloadTimelines: false)
        let loaded = WidgetDataManager.shared.loadLatestSnapshot()

        XCTAssertEqual(loaded.ispName, "Проверка менеджера")
        XCTAssertEqual(loaded.downloadSpeedMbps, 42.5)
        XCTAssertEqual(loaded.pingMs, 31)
        XCTAssertEqual(loaded.healthScore, 87)
    }
}
