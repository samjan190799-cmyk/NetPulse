//
//  HistoryStorage.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Менеджер долговременного хранения истории измерений и экспорта отчетов.
public actor HistoryStorage {
    private var pingRecords: [PingRecord] = []
    private var speedtests: [SpeedtestResult] = []
    private var alerts: [NetworkAlert] = []
    private let sessionId: String

    public init() {
        self.sessionId = UUID().uuidString.prefix(8).lowercased()
    }

    public func recordPing(_ record: PingRecord) {
        pingRecords.append(record)
    }

    public func recordSpeedtest(_ result: SpeedtestResult) {
        speedtests.append(result)
    }

    public func recordAlert(_ alert: NetworkAlert) {
        alerts.append(alert)
    }

    /// Экспорт данных текущей сессии в JSON-файл для ShareLink
    public func exportSessionToJSON() throws -> URL {
        let report: [String: Any] = [
            "netpulse_ios_version": "1.0.0",
            "session_id": sessionId,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "total_pings": pingRecords.count,
            "total_alerts": alerts.count,
            "total_speedtests": speedtests.count,
            "ping_records": pingRecords.map { r in
                [
                    "host": r.host,
                    "target_name": r.targetName,
                    "timestamp": ISO8601DateFormatter().string(from: r.timestamp),
                    "is_success": r.isSuccess,
                    "latency_ms": r.latencyMs as Any,
                    "protocol": r.protocolType
                ]
            }
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted])
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("NetPulse_Report_\(sessionId).json")
        try jsonData.write(to: fileURL)
        return fileURL
    }

    /// Экспорт измерений в CSV-файл для ShareLink
    public func exportSessionToCSV() throws -> URL {
        var csvString = "Timestamp,TargetName,Host,Success,Latency_ms,Protocol\n"
        let df = ISO8601DateFormatter()

        for r in pingRecords {
            let latStr = r.latencyMs.map { String(format: "%.1f", $0) } ?? ""
            let line = "\(df.string(from: r.timestamp)),\(r.targetName),\(r.host),\(r.isSuccess ? "1" : "0"),\(latStr),\(r.protocolType)\n"
            csvString.append(line)
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("NetPulse_Metrics_\(sessionId).csv")
        try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
