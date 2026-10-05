//
//  HistoryStorage.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Менеджер хранения измерений текущего сеанса и экспорта отчётов.
///
/// Данные живут в памяти до закрытия приложения; чтобы сеанс не рос бесконечно, число записей ограничено
/// (старые вытесняются). Раньше экспорт был всегда пустым: пинги и оповещения никто не записывал,
/// а в JSON не попадали результаты замеров скорости.
public actor HistoryStorage {
    private static let maxPingRecords = 20_000
    private static let maxAlerts = 500
    private static let maxSpeedtests = 100
    /// Запас перед обрезкой: удаление начала массива делается пачкой, а не на каждую запись
    private static let trimSlack = 500

    private var pingRecords: [PingRecord] = []
    private var speedtests: [SpeedtestResult] = []
    private var alerts: [NetworkAlert] = []
    private let sessionId: String

    public init() {
        self.sessionId = UUID().uuidString.prefix(8).lowercased()
    }

    public func recordPing(_ record: PingRecord) {
        pingRecords.append(record)
        if pingRecords.count > Self.maxPingRecords + Self.trimSlack {
            pingRecords.removeFirst(pingRecords.count - Self.maxPingRecords)
        }
    }

    public func recordSpeedtest(_ result: SpeedtestResult) {
        speedtests.append(result)
        if speedtests.count > Self.maxSpeedtests {
            speedtests.removeFirst(speedtests.count - Self.maxSpeedtests)
        }
    }

    public func recordAlert(_ alert: NetworkAlert) {
        alerts.append(alert)
        if alerts.count > Self.maxAlerts {
            alerts.removeFirst(alerts.count - Self.maxAlerts)
        }
    }

    /// Сведения об экспорте: сколько записей сейчас в памяти (для интерфейса)
    public func counts() -> (pings: Int, alerts: Int, speedtests: Int) {
        (pingRecords.count, alerts.count, speedtests.count)
    }

    // MARK: - Экспорт

    private struct ExportReport: Encodable {
        let appVersion: String
        let sessionId: String
        let generatedAt: Date
        let totalPings: Int
        let totalAlerts: Int
        let totalSpeedtests: Int
        let speedtests: [SpeedtestResult]
        let alerts: [NetworkAlert]
        let pings: [PingRecord]
    }

    /// Экспорт данных текущего сеанса в JSON-файл для ShareLink
    public func exportSessionToJSON() throws -> URL {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let report = ExportReport(
            appVersion: version,
            sessionId: sessionId,
            generatedAt: Date(),
            totalPings: pingRecords.count,
            totalAlerts: alerts.count,
            totalSpeedtests: speedtests.count,
            speedtests: speedtests,
            alerts: alerts,
            pings: pingRecords
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(report)

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("NetPulse_Report_\(sessionId).json")
        try jsonData.write(to: fileURL, options: .atomic)
        return fileURL
    }

    /// Экспорт измерений в CSV-файл для ShareLink
    public func exportSessionToCSV() throws -> URL {
        var rows: [String] = ["Timestamp,TargetName,Host,Success,Latency_ms,Protocol,Error"]
        let df = ISO8601DateFormatter()

        for r in pingRecords {
            let latency = r.latencyMs.map { String(format: "%.1f", $0) } ?? ""
            let fields = [
                df.string(from: r.timestamp),
                Self.csvField(r.targetName),
                Self.csvField(r.host),
                r.isSuccess ? "1" : "0",
                latency,
                Self.csvField(r.protocolType),
                Self.csvField(r.errorMessage ?? "")
            ]
            rows.append(fields.joined(separator: ","))
        }

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("NetPulse_Metrics_\(sessionId).csv")
        try (rows.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Поле CSV: кавычки и разделители экранируются, а значения, начинающиеся с «=», «+», «-», «@», получают
    /// префикс — иначе Excel выполнит их как формулу (имя узла вводит пользователь).
    private static func csvField(_ value: String) -> String {
        var text = value
        if let first = text.first, "=+-@\t\r".contains(first) {
            text = "'" + text
        }
        if text.contains(",") || text.contains("\"") || text.contains("\n") || text.contains("\r") {
            return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return text
    }
}
