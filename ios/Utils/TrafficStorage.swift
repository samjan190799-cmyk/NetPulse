//
//  TrafficStorage.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Постоянное хранилище истории трафика, аналитики сессий и квот
public actor TrafficStorage {
    public static let shared = TrafficStorage()

    private var sessions: [TrafficSession] = []
    private var dataPoints: [TrafficDataPoint] = []
    private var budget: TrafficBudget = TrafficBudget()

    private var currentActiveSessionId: UUID?
    private let fileManager = FileManager.default
    private let storageQueue = DispatchQueue(label: "com.samvel.netpulse.trafficstorage", qos: .utility)

    private var sessionsFileURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("netpulse_traffic_sessions.json")
    }

    private var dataPointsFileURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("netpulse_traffic_datapoints.json")
    }

    private var budgetFileURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("netpulse_traffic_budget.json")
    }

    public init() {
        loadData()
    }

    // MARK: - Инициализация и загрузка данных

    private func loadData() {
        // Загрузка сессий
        if let data = try? Data(contentsOf: sessionsFileURL),
           let decoded = try? JSONDecoder().decode([TrafficSession].self, from: data) {
            self.sessions = decoded
        }

        // Загрузка точек графиков
        if let data = try? Data(contentsOf: dataPointsFileURL),
           let decoded = try? JSONDecoder().decode([TrafficDataPoint].self, from: data) {
            self.dataPoints = decoded
        }

        // Загрузка бюджета
        if let data = try? Data(contentsOf: budgetFileURL),
           let decoded = try? JSONDecoder().decode(TrafficBudget.self, from: data) {
            self.budget = decoded
        }

        // Если данных нет, генерируем базовую структуру для демонстрации реальных срезов
        if sessions.isEmpty {
            seedInitialDemoSessionsIfNeeded()
        }
    }

    private func saveData() {
        do {
            let sData = try JSONEncoder().encode(sessions)
            try sData.write(to: sessionsFileURL, options: .atomic)

            let pData = try JSONEncoder().encode(dataPoints)
            try pData.write(to: dataPointsFileURL, options: .atomic)

            let bData = try JSONEncoder().encode(budget)
            try bData.write(to: budgetFileURL, options: .atomic)
        } catch {
            print("⚠️ Ошибка сохранения данных трафика: \(error.localizedDescription)")
        }
    }

    // MARK: - Управление активной сессией сети

    /// Обновление или запуск новой сессии при смене сети / типа подключения
    public func recordTrafficSample(
        snapshot: BandwidthSnapshot,
        networkName: String,
        connectionType: String,
        interfaceName: String
    ) {
        let now = Date()

        // 1. Проверяем, изменилась ли сеть
        if let activeId = currentActiveSessionId,
           let index = sessions.firstIndex(where: { $0.id == activeId }) {
            let active = sessions[index]
            if active.networkName != networkName || active.connectionType != connectionType {
                // Закрываем предыдущую сессию
                sessions[index].endDate = now
                sessions[index].isActive = false
                currentActiveSessionId = nil
            }
        }

        // 2. Создаем новую активную сессию, если ее нет
        if currentActiveSessionId == nil {
            let newSession = TrafficSession(
                networkName: networkName,
                connectionType: connectionType,
                interfaceName: interfaceName,
                startDate: now,
                downloadedBytes: snapshot.deltaDownloadBytes,
                uploadedBytes: snapshot.deltaUploadBytes,
                peakDownloadBps: snapshot.downloadBytesPerSec,
                peakUploadBps: snapshot.uploadBytesPerSec,
                isActive: true
            )
            sessions.insert(newSession, at: 0)
            currentActiveSessionId = newSession.id
        } else if let activeId = currentActiveSessionId,
                  let index = sessions.firstIndex(where: { $0.id == activeId }) {
            // Обновляем текущую сессию
            sessions[index].downloadedBytes += snapshot.deltaDownloadBytes
            sessions[index].uploadedBytes += snapshot.deltaUploadBytes
            sessions[index].peakDownloadBps = max(sessions[index].peakDownloadBps, snapshot.downloadBytesPerSec)
            sessions[index].peakUploadBps = max(sessions[index].peakUploadBps, snapshot.uploadBytesPerSec)
            sessions[index].endDate = now
        }

        // 3. Записываем точку графика расхода, если был реальный расход
        if snapshot.deltaDownloadBytes > 0 || snapshot.deltaUploadBytes > 0 || dataPoints.isEmpty {
            let isWifi = connectionType.contains("Wi-Fi")
            let point = TrafficDataPoint(
                timestamp: now,
                downloadBytes: snapshot.deltaDownloadBytes,
                uploadBytes: snapshot.deltaUploadBytes,
                wifiBytes: isWifi ? (snapshot.deltaDownloadBytes + snapshot.deltaUploadBytes) : 0,
                cellularBytes: !isWifi ? (snapshot.deltaDownloadBytes + snapshot.deltaUploadBytes) : 0
            )
            dataPoints.append(point)

            // Храним максимум 500 последних точек в памяти
            if dataPoints.count > 500 {
                dataPoints.removeFirst(dataPoints.count - 500)
            }
        }

        // Сохраняем раз в 30 секунд или периодически
        saveData()
    }

    // MARK: - Запросы и агрегация статистики

    public func getSummary(for period: TrafficPeriod) -> TrafficSummary {
        let cutoffDate = cutoffDate(for: period)
        let filteredSessions = sessions.filter { $0.startDate >= cutoffDate }

        var summary = TrafficSummary()
        summary.totalSessionsCount = filteredSessions.count
        summary.activeSessionsCount = filteredSessions.filter { $0.isActive }.count

        for s in filteredSessions {
            summary.totalDownload += s.downloadedBytes
            summary.totalUpload += s.uploadedBytes

            if s.connectionType.contains("Wi-Fi") {
                summary.wifiDownload += s.downloadedBytes
                summary.wifiUpload += s.uploadedBytes
            } else {
                summary.cellularDownload += s.downloadedBytes
                summary.cellularUpload += s.uploadedBytes
            }
        }

        return summary
    }

    public func getSessions(for period: TrafficPeriod) -> [TrafficSession] {
        let cutoffDate = cutoffDate(for: period)
        return sessions.filter { $0.startDate >= cutoffDate }
    }

    public func getDataPoints(for period: TrafficPeriod) -> [TrafficDataPoint] {
        let cutoffDate = cutoffDate(for: period)
        return dataPoints.filter { $0.timestamp >= cutoffDate }
    }

    public func getBudget() -> TrafficBudget {
        return budget
    }

    public func updateBudget(_ newBudget: TrafficBudget) {
        self.budget = newBudget
        saveData()
    }

    public func resetAllData() {
        sessions.removeAll()
        dataPoints.removeAll()
        currentActiveSessionId = nil
        saveData()
    }

    private func cutoffDate(for period: TrafficPeriod) -> Date {
        let calendar = Calendar.current
        let now = Date()

        switch period {
        case .today:
            return calendar.startOfDay(for: now)
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .month:
            return calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .allTime:
            return Date.distantPast
        }
    }

    // MARK: - Экспорт отчетов расхода трафика

    public func exportTrafficCSV() throws -> URL {
        var csv = "SessionID,NetworkName,ConnectionType,Interface,StartDate,EndDate,DurationSec,DownloadedBytes,UploadedBytes,TotalBytes,PeakDownloadBps\n"
        let df = ISO8601DateFormatter()

        for s in sessions {
            let endStr = s.endDate != nil ? df.string(from: s.endDate!) : "Active"
            let line = "\(s.id.uuidString),\"\(s.networkName)\",\"\(s.connectionType)\",\(s.interfaceName),\(df.string(from: s.startDate)),\(endStr),\(Int(s.duration)),\(s.downloadedBytes),\(s.uploadedBytes),\(s.totalBytes),\(Int(s.peakDownloadBps))\n"
            csv.append(line)
        }

        let tempDir = fileManager.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("NetPulse_Traffic_Report_\(UUID().uuidString.prefix(6)).csv")
        try csv.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    public func exportTrafficJSON() throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        let exportPayload = TrafficExportPayload(
            exportDate: Date(),
            summary: getSummary(for: .allTime),
            budget: budget,
            sessions: sessions
        )

        let data = try encoder.encode(exportPayload)
        let tempDir = fileManager.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("NetPulse_Traffic_Report_\(UUID().uuidString.prefix(6)).json")
        try data.write(to: fileURL)
        return fileURL
    }

    // MARK: - Демо-данные для визуализации при первом запуске
    private func seedInitialDemoSessionsIfNeeded() {
        let now = Date()
        let cal = Calendar.current

        let demoSessions: [TrafficSession] = [
            TrafficSession(
                networkName: "Домашний Wi-Fi (5 GHz)",
                connectionType: "Wi-Fi",
                interfaceName: "en0",
                startDate: cal.date(byAdding: .hour, value: -3, to: now) ?? now,
                endDate: now,
                downloadedBytes: 1_420_000_000, // 1.42 GB
                uploadedBytes: 310_000_000,    // 310 MB
                peakDownloadBps: 18_500_000,
                peakUploadBps: 4_200_000,
                isActive: true
            ),
            TrafficSession(
                networkName: "Мобильная сеть (5G/LTE)",
                connectionType: "Cellular (5G/LTE)",
                interfaceName: "pdp_ip0",
                startDate: cal.date(byAdding: .hour, value: -8, to: now) ?? now,
                endDate: cal.date(byAdding: .hour, value: -3, to: now) ?? now,
                downloadedBytes: 480_000_000,  // 480 MB
                uploadedBytes: 95_000_000,     // 95 MB
                peakDownloadBps: 9_200_000,
                peakUploadBps: 1_800_000,
                isActive: false
            ),
            TrafficSession(
                networkName: "Офисный Wi-Fi (Корпоративный)",
                connectionType: "Wi-Fi",
                interfaceName: "en0",
                startDate: cal.date(byAdding: .day, value: -1, to: now) ?? now,
                endDate: cal.date(byAdding: .day, value: -1, to: now)?.addingTimeInterval(28800),
                downloadedBytes: 3_150_000_000, // 3.15 GB
                uploadedBytes: 890_000_000,    // 890 MB
                peakDownloadBps: 45_000_000,
                peakUploadBps: 22_000_000,
                isActive: false
            ),
            TrafficSession(
                networkName: "Публичный Wi-Fi Кафе",
                connectionType: "Wi-Fi",
                interfaceName: "en0",
                startDate: cal.date(byAdding: .day, value: -2, to: now) ?? now,
                endDate: cal.date(byAdding: .day, value: -2, to: now)?.addingTimeInterval(7200),
                downloadedBytes: 320_000_000,  // 320 MB
                uploadedBytes: 42_000_000,     // 42 MB
                peakDownloadBps: 4_500_000,
                peakUploadBps: 800_000,
                isActive: false
            )
        ]

        self.sessions = demoSessions
        self.currentActiveSessionId = demoSessions.first?.id

        // Генерируем точки графиков
        var pts: [TrafficDataPoint] = []
        for i in (0..<24).reversed() {
            if let d = cal.date(byAdding: .hour, value: -i, to: now) {
                let dl = UInt64.random(in: 10_000_000...150_000_000)
                let ul = UInt64.random(in: 2_000_000...40_000_000)
                let isW = i % 3 != 0
                pts.append(TrafficDataPoint(
                    timestamp: d,
                    downloadBytes: dl,
                    uploadBytes: ul,
                    wifiBytes: isW ? (dl + ul) : 0,
                    cellularBytes: !isW ? (dl + ul) : 0
                ))
            }
        }
        self.dataPoints = pts
        saveData()
    }
}

/// Структура для экспорта в JSON
private struct TrafficExportPayload: Codable {
    let exportDate: Date
    let summary: TrafficSummary
    let budget: TrafficBudget
    let sessions: [TrafficSession]
}
