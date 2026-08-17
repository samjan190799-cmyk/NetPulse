//
//  TrafficStorage.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Постоянное хранилище истории РЕАЛЬНОГО трафика, аналитики сессий и квот с поддержкой фоновой синхронизации и защитой от дискового троттлинга
public actor TrafficStorage {
    public static let shared = TrafficStorage()

    private var sessions: [TrafficSession]
    private var dataPoints: [TrafficDataPoint]
    private var budget: TrafficBudget
    private var currentActiveSessionId: UUID?

    private var hasUnsavedChanges: Bool = false
    private var lastSavedDate: Date = Date()
    private var saveTask: Task<Void, Never>?

    private static let kLastHardwareCountersKey = "netpulse_last_hardware_counters"

    private static var sessionsFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("netpulse_traffic_sessions.json")
    }

    private static var dataPointsFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("netpulse_traffic_datapoints.json")
    }

    private static var budgetFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("netpulse_traffic_budget.json")
    }

    public init() {
        let (initialSessions, initialPoints, initialBudget) = Self.loadInitialData()
        self.sessions = initialSessions
        self.dataPoints = initialPoints
        self.budget = initialBudget
        self.currentActiveSessionId = initialSessions.first(where: { $0.isActive })?.id
    }

    // MARK: - Инициализация и загрузка только реальных данных

    private static func loadInitialData() -> ([TrafficSession], [TrafficDataPoint], TrafficBudget) {
        var loadedSessions: [TrafficSession] = []
        var loadedPoints: [TrafficDataPoint] = []
        var loadedBudget: TrafficBudget = TrafficBudget()

        // Загрузка сохраненных сессий
        if let data = try? Data(contentsOf: sessionsFileURL),
           let decoded = try? JSONDecoder().decode([TrafficSession].self, from: data) {
            loadedSessions = decoded
        }

        // Загрузка точек графиков
        if let data = try? Data(contentsOf: dataPointsFileURL),
           let decoded = try? JSONDecoder().decode([TrafficDataPoint].self, from: data) {
            loadedPoints = decoded
        }

        // Загрузка квоты
        if let data = try? Data(contentsOf: budgetFileURL),
           let decoded = try? JSONDecoder().decode(TrafficBudget.self, from: data) {
            loadedBudget = decoded
        }

        return (loadedSessions, loadedPoints, loadedBudget)
    }

    /// Прямая запись на диск без блокировок
    private func performDiskSave() {
        do {
            let sData = try JSONEncoder().encode(sessions)
            try sData.write(to: Self.sessionsFileURL, options: .atomic)

            let pData = try JSONEncoder().encode(dataPoints)
            try pData.write(to: Self.dataPointsFileURL, options: .atomic)

            let bData = try JSONEncoder().encode(budget)
            try bData.write(to: Self.budgetFileURL, options: .atomic)

            self.hasUnsavedChanges = false
            self.lastSavedDate = Date()
        } catch {
            print("⚠️ Ошибка сохранения данных трафика: \(error.localizedDescription)")
        }
    }

    /// Дебаунсинг дисковой записи: предотвращает 1 запись/сек и исключает разряд батареи и перегрузку I/O
    private func scheduleDebouncedSave() {
        hasUnsavedChanges = true
        let timeSinceLastSave = Date().timeIntervalSince(lastSavedDate)

        // Если прошло более 20 секунд с последнего сохранения, сохраняем сразу
        if timeSinceLastSave >= 20.0 {
            saveTask?.cancel()
            saveTask = nil
            performDiskSave()
            return
        }

        // Иначе планируем сохранение через 15 секунд, если задача еще не висит
        if saveTask == nil {
            saveTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.flush()
            }
        }
    }

    /// Принудительный сброс буфера на диск (при сворачивании, закрытии приложения или изменении квоты)
    public func flush() {
        saveTask?.cancel()
        saveTask = nil
        if hasUnsavedChanges {
            performDiskSave()
        }
    }

    // MARK: - Фоновая синхронизация с аппаратными счетчиками ядра Darwin BSD (Zero-Loss)

    /// Синхронизация трафика, потраченного пока приложение было свернуто, спало или было закрыто
    public func reconcileBackgroundHardwareTraffic(
        currentConnectionType: String,
        currentNetworkName: String
    ) {
        let currentCounters = BandwidthEngine.fetchDetailedInterfaceBytes()
        let now = Date()

        // 1. Считываем сохраненный срез при предыдущей активности
        if let savedData = UserDefaults.standard.data(forKey: Self.kLastHardwareCountersKey),
           let saved = try? JSONDecoder().decode(InterfaceByteCounters.self, from: savedData) {
            
            // Вычисляем пропущенные дельты на уровне сетевых интерфейсов ядра
            let missingTotalIn = BandwidthEngine.computeDelta(prev: saved.totalIn, current: currentCounters.totalIn)
            let missingTotalOut = BandwidthEngine.computeDelta(prev: saved.totalOut, current: currentCounters.totalOut)
            
            let missingWifiIn = BandwidthEngine.computeDelta(prev: saved.wifiIn, current: currentCounters.wifiIn)
            let missingWifiOut = BandwidthEngine.computeDelta(prev: saved.wifiOut, current: currentCounters.wifiOut)
            let missingWifiTotal = missingWifiIn + missingWifiOut
            
            let missingCellIn = BandwidthEngine.computeDelta(prev: saved.cellularIn, current: currentCounters.cellularIn)
            let missingCellOut = BandwidthEngine.computeDelta(prev: saved.cellularOut, current: currentCounters.cellularOut)
            let missingCellTotal = missingCellIn + missingCellOut

            if missingTotalIn > 0 || missingTotalOut > 0 {
                let isWifi = currentConnectionType.contains("Wi-Fi")
                let ifName = isWifi ? "en0" : "pdp_ip0"

                if let activeId = currentActiveSessionId,
                   let index = sessions.firstIndex(where: { $0.id == activeId }) {
                    sessions[index].downloadedBytes += missingTotalIn
                    sessions[index].uploadedBytes += missingTotalOut
                    sessions[index].endDate = now
                } else {
                    let backgroundSession = TrafficSession(
                        networkName: currentNetworkName.isEmpty ? (isWifi ? "Wi-Fi Сеть" : "Мобильный интернет (5G/LTE)") : currentNetworkName,
                        connectionType: currentConnectionType.isEmpty ? (isWifi ? "Wi-Fi" : "Сотовая связь") : currentConnectionType,
                        interfaceName: ifName,
                        startDate: now.addingTimeInterval(-60),
                        endDate: now,
                        downloadedBytes: missingTotalIn,
                        uploadedBytes: missingTotalOut,
                        peakDownloadBps: Double(missingTotalIn),
                        peakUploadBps: Double(missingTotalOut),
                        isActive: true
                    )
                    sessions.insert(backgroundSession, at: 0)
                    currentActiveSessionId = backgroundSession.id
                }

                // Добавляем точку на график
                let point = TrafficDataPoint(
                    timestamp: now,
                    downloadBytes: missingTotalIn,
                    uploadBytes: missingTotalOut,
                    wifiBytes: missingWifiTotal,
                    cellularBytes: missingCellTotal
                )
                dataPoints.append(point)
                if dataPoints.count > 500 {
                    dataPoints.removeFirst(dataPoints.count - 500)
                }

                scheduleDebouncedSave()
            }
        }

        // 2. Обновляем контрольную точку аппаратного счетчика
        persistHardwareCounters(currentCounters)
    }

    private func persistHardwareCounters(_ counters: InterfaceByteCounters) {
        if let encoded = try? JSONEncoder().encode(counters) {
            UserDefaults.standard.set(encoded, forKey: Self.kLastHardwareCountersKey)
        }
    }

    // MARK: - Управление активной сессией сети (Реальный замер дельты)

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
            // Обновляем текущую сессию реальными переданными байтами
            sessions[index].downloadedBytes += snapshot.deltaDownloadBytes
            sessions[index].uploadedBytes += snapshot.deltaUploadBytes
            sessions[index].peakDownloadBps = max(sessions[index].peakDownloadBps, snapshot.downloadBytesPerSec)
            sessions[index].peakUploadBps = max(sessions[index].peakUploadBps, snapshot.uploadBytesPerSec)
            sessions[index].endDate = now
        }

        // 3. Записываем реальную точку графика расхода, если была активность
        if snapshot.deltaDownloadBytes > 0 || snapshot.deltaUploadBytes > 0 {
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

        // Сохраняем с дебаунсом и обновляем контрольную точку
        scheduleDebouncedSave()
        persistHardwareCounters(BandwidthEngine.fetchDetailedInterfaceBytes())
    }

    // MARK: - Запросы и агрегация статистики

    public func getCurrentActiveSession() -> TrafficSession? {
        if let activeId = currentActiveSessionId {
            return sessions.first(where: { $0.id == activeId })
        }
        return sessions.first(where: { $0.isActive })
    }

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
        hasUnsavedChanges = true
        performDiskSave()
    }

    public func resetAllData() {
        sessions.removeAll()
        dataPoints.removeAll()
        currentActiveSessionId = nil
        UserDefaults.standard.removeObject(forKey: Self.kLastHardwareCountersKey)
        hasUnsavedChanges = true
        performDiskSave()
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

        let tempDir = FileManager.default.temporaryDirectory
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
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("NetPulse_Traffic_Report_\(UUID().uuidString.prefix(6)).json")
        try data.write(to: fileURL)
        return fileURL
    }
}

/// Структура для экспорта в JSON
private struct TrafficExportPayload: Codable {
    let exportDate: Date
    let summary: TrafficSummary
    let budget: TrafficBudget
    let sessions: [TrafficSession]
}
