//
//  TrafficStorage.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Постоянное хранилище истории РЕАЛЬНОГО трафика, аналитики сессий и квот с защитой от повторного/двойного учета
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

    // MARK: - Инициализация и санация сохраненных данных

    private static func loadInitialData() -> ([TrafficSession], [TrafficDataPoint], TrafficBudget) {
        var loadedSessions: [TrafficSession] = []
        var loadedPoints: [TrafficDataPoint] = []
        var loadedBudget: TrafficBudget = TrafficBudget()

        // Загрузка сохраненных сессий с фильтрацией аномалий
        if let data = try? Data(contentsOf: sessionsFileURL),
           let decoded = try? JSONDecoder().decode([TrafficSession].self, from: data) {
            let sanitized = decoded.compactMap { session -> TrafficSession? in
                var s = session
                // Санация аномальных выбросов (защита от багов с переполнением)
                if s.downloadedBytes > 200_000_000_000 || s.uploadedBytes > 200_000_000_000 {
                    return nil
                }
                let total = s.downloadedBytes + s.uploadedBytes
                if total > 1024 || s.isActive {
                    return s
                }
                return nil
            }
            loadedSessions = Array(sanitized.prefix(100))
        }

        // Однократная автоматическая санация ложной отдачи при раздаче интернета на ноутбук (Hotspot)
        let kHotspotSanitizedKey = "netpulse_hotspot_v3_recalibrated"
        if !UserDefaults.standard.bool(forKey: kHotspotSanitizedKey) {
            UserDefaults.standard.set(true, forKey: kHotspotSanitizedKey)
            loadedSessions = loadedSessions.map { session in
                var s = session
                // Если отдача в сотовой сети была ошибочно начислена из-за Wi-Fi моста на ноутбук (почти равна объему скачивания)
                if s.connectionType.contains("Сотовая") && s.uploadedBytes > 10_000_000 && s.uploadedBytes >= (s.downloadedBytes / 2) {
                    s.uploadedBytes = (s.downloadedBytes * 4) / 100 // Реальный TCP ACK трафик ~4%
                }
                return s
            }
        }

        // Загрузка точек графиков
        if let data = try? Data(contentsOf: dataPointsFileURL),
           let decoded = try? JSONDecoder().decode([TrafficDataPoint].self, from: data) {
            loadedPoints = Array(decoded.suffix(300))
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
            let sData = try JSONEncoder().encode(Array(sessions.prefix(100)))
            try sData.write(to: Self.sessionsFileURL, options: .atomic)

            let pData = try JSONEncoder().encode(Array(dataPoints.suffix(300)))
            try pData.write(to: Self.dataPointsFileURL, options: .atomic)

            let bData = try JSONEncoder().encode(budget)
            try bData.write(to: Self.budgetFileURL, options: .atomic)

            self.hasUnsavedChanges = false
            self.lastSavedDate = Date()
        } catch {
            print("⚠️ Ошибка сохранения данных трафика: \(error.localizedDescription)")
        }
    }

    /// Дебаунсинг дисковой записи
    private func scheduleDebouncedSave() {
        hasUnsavedChanges = true
        let timeSinceLastSave = Date().timeIntervalSince(lastSavedDate)

        if timeSinceLastSave >= 20.0 {
            saveTask?.cancel()
            saveTask = nil
            performDiskSave()
            return
        }

        if saveTask == nil {
            saveTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.flush()
            }
        }
    }

    /// Принудительный сброс буфера на диск
    public func flush() {
        saveTask?.cancel()
        saveTask = nil
        if hasUnsavedChanges {
            performDiskSave()
        }
    }

    // MARK: - Фоновая синхронизация с аппаратными счетчиками ядра Darwin BSD (Zero-Loss)

    /// Синхронизация трафика, потраченного строго пока приложение спало или было закрыто
    public func reconcileBackgroundHardwareTraffic(
        currentConnectionType: String,
        currentNetworkName: String
    ) {
        let currentCounters = BandwidthEngine.fetchDetailedInterfaceBytes()
        let now = Date()

        // 1. Считываем сохраненную базовую точку при уходе в фон
        guard let savedData = UserDefaults.standard.data(forKey: Self.kLastHardwareCountersKey),
              let saved = try? JSONDecoder().decode(InterfaceByteCounters.self, from: savedData),
              (saved.totalIn > 0 || saved.totalOut > 0) else {
            // Первичная точка отсчета: фиксируем текущее состояние ядра БЕЗ начисления дельты
            persistHardwareCounters(currentCounters)
            BandwidthEngine.shared.resetBaseline(to: currentCounters)
            return
        }

        // 2. Вычисляем пропущенные дельты физических интерфейсов
        let missingWifiIn = BandwidthEngine.computeDelta(prev: saved.wifiIn, current: currentCounters.wifiIn)
        let missingWifiOut = BandwidthEngine.computeDelta(prev: saved.wifiOut, current: currentCounters.wifiOut)

        let missingCellIn = BandwidthEngine.computeDelta(prev: saved.cellularIn, current: currentCounters.cellularIn)
        let missingCellOut = BandwidthEngine.computeDelta(prev: saved.cellularOut, current: currentCounters.cellularOut)

        let isWifi = currentConnectionType.contains("Wi-Fi") || currentConnectionType.lowercased().contains("wifi")
        let normConnType = isWifi ? "Wi-Fi" : "Сотовая связь"
        let normNetName = isWifi ? "Wi-Fi Подключение" : "Мобильная сеть (LTE/5G)"
        let ifName = isWifi ? "en0" : "pdp_ip0"

        let totalMissingIn = isWifi ? missingWifiIn : missingCellIn
        let totalMissingOut = isWifi ? missingWifiOut : missingCellOut

        // 3. НЕМЕДЛЕННО обновляем базовую точку в UserDefaults и в BandwidthEngine,
        // чтобы активный цикл не посчитал эти байты второй раз!
        persistHardwareCounters(currentCounters)
        BandwidthEngine.shared.resetBaseline(to: currentCounters)

        if totalMissingIn > 0 || totalMissingOut > 0 {
            let bgDistribution = TrafficClassifier.shared.distributeSample(
                deltaDownload: totalMissingIn,
                deltaUpload: totalMissingOut,
                speedBps: Double(totalMissingIn + totalMissingOut),
                isSpeedtestActive: false,
                isBackground: true
            )

            if let activeId = currentActiveSessionId,
               let index = sessions.firstIndex(where: { $0.id == activeId }),
               sessions[index].connectionType == normConnType {
                sessions[index].downloadedBytes += totalMissingIn
                sessions[index].uploadedBytes += totalMissingOut
                sessions[index].endDate = now
                sessions[index].categoryUsages = TrafficClassifier.shared.mergeCategoryUsages(
                    existing: sessions[index].categoryUsages,
                    additions: bgDistribution
                )
            } else {
                if let activeId = currentActiveSessionId,
                   let index = sessions.firstIndex(where: { $0.id == activeId }) {
                    sessions[index].isActive = false
                    sessions[index].endDate = now
                }

                let initialCategories = TrafficClassifier.shared.mergeCategoryUsages(
                    existing: [],
                    additions: bgDistribution
                )
                let backgroundSession = TrafficSession(
                    networkName: normNetName,
                    connectionType: normConnType,
                    interfaceName: ifName,
                    startDate: now.addingTimeInterval(-60),
                    endDate: now,
                    downloadedBytes: totalMissingIn,
                    uploadedBytes: totalMissingOut,
                    peakDownloadBps: Double(totalMissingIn),
                    peakUploadBps: Double(totalMissingOut),
                    isActive: true,
                    categoryUsages: initialCategories
                )
                sessions.insert(backgroundSession, at: 0)
                currentActiveSessionId = backgroundSession.id
            }

            // Добавляем точку на график
            let point = TrafficDataPoint(
                timestamp: now,
                downloadBytes: totalMissingIn,
                uploadBytes: totalMissingOut,
                wifiBytes: isWifi ? (totalMissingIn + totalMissingOut) : 0,
                cellularBytes: !isWifi ? (totalMissingIn + totalMissingOut) : 0
            )
            dataPoints.append(point)
            if dataPoints.count > 300 {
                dataPoints.removeFirst(dataPoints.count - 300)
            }

            scheduleDebouncedSave()
        }
    }

    public func persistHardwareCounters(_ counters: InterfaceByteCounters) {
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
        interfaceName: String,
        isSpeedtestActive: Bool = false
    ) {
        let now = Date()
        let isWifi = connectionType.contains("Wi-Fi") || connectionType.lowercased().contains("wifi")
        let normConnType = isWifi ? "Wi-Fi" : "Сотовая связь"
        let normNetName = isWifi ? "Wi-Fi Подключение" : "Мобильная сеть (LTE/5G)"

        // 1. Проверяем смену физического типа сети (Wi-Fi <-> Cellular)
        if let activeId = currentActiveSessionId,
           let index = sessions.firstIndex(where: { $0.id == activeId }) {
            let active = sessions[index]
            if active.connectionType != normConnType || now.timeIntervalSince(active.startDate) > 86400 {
                sessions[index].endDate = now
                sessions[index].isActive = false
                currentActiveSessionId = nil
            }
        }

        let sampleDistribution = TrafficClassifier.shared.distributeSample(
            deltaDownload: snapshot.deltaDownloadBytes,
            deltaUpload: snapshot.deltaUploadBytes,
            speedBps: snapshot.downloadBytesPerSec + snapshot.uploadBytesPerSec,
            isSpeedtestActive: isSpeedtestActive,
            isBackground: false
        )

        // 2. Создаем новую активную сессию, если ее нет
        if currentActiveSessionId == nil {
            let initialCategories = TrafficClassifier.shared.mergeCategoryUsages(
                existing: [],
                additions: sampleDistribution
            )
            let newSession = TrafficSession(
                networkName: normNetName,
                connectionType: normConnType,
                interfaceName: isWifi ? "en0" : "pdp_ip0",
                startDate: now,
                downloadedBytes: snapshot.deltaDownloadBytes,
                uploadedBytes: snapshot.deltaUploadBytes,
                peakDownloadBps: snapshot.downloadBytesPerSec,
                peakUploadBps: snapshot.uploadBytesPerSec,
                isActive: true,
                categoryUsages: initialCategories
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
            if snapshot.deltaDownloadBytes > 0 || snapshot.deltaUploadBytes > 0 {
                sessions[index].categoryUsages = TrafficClassifier.shared.mergeCategoryUsages(
                    existing: sessions[index].categoryUsages,
                    additions: sampleDistribution
                )
            }
        }

        // 3. Записываем реальную точку графика расхода, если была активность
        if snapshot.deltaDownloadBytes > 0 || snapshot.deltaUploadBytes > 0 {
            let point = TrafficDataPoint(
                timestamp: now,
                downloadBytes: snapshot.deltaDownloadBytes,
                uploadBytes: snapshot.deltaUploadBytes,
                wifiBytes: isWifi ? (snapshot.deltaDownloadBytes + snapshot.deltaUploadBytes) : 0,
                cellularBytes: !isWifi ? (snapshot.deltaDownloadBytes + snapshot.deltaUploadBytes) : 0
            )
            dataPoints.append(point)

            if dataPoints.count > 300 {
                dataPoints.removeFirst(dataPoints.count - 300)
            }
        }

        // 4. Синхронизируем базовую точку счетчиков в UserDefaults, исключая двойной подсчет при переходе в фон
        let currentCounters = InterfaceByteCounters(
            totalIn: snapshot.totalReceivedBytes,
            totalOut: snapshot.totalSentBytes,
            wifiIn: snapshot.wifiReceivedBytes,
            wifiOut: snapshot.wifiSentBytes,
            cellularIn: snapshot.cellularReceivedBytes,
            cellularOut: snapshot.cellularSentBytes
        )
        persistHardwareCounters(currentCounters)
        scheduleDebouncedSave()
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
        let filteredSessions = sessions.filter { $0.startDate >= cutoffDate || ($0.endDate != nil && $0.endDate! >= cutoffDate) || $0.isActive }

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

        summary.categoryBreakdown = TrafficClassifier.shared.aggregateCategoryBreakdown(
            from: filteredSessions,
            totalTraffic: summary.totalTraffic
        )

        return summary
    }

    public func getSessions(for period: TrafficPeriod) -> [TrafficSession] {
        let cutoffDate = cutoffDate(for: period)
        return sessions.filter { $0.startDate >= cutoffDate || ($0.endDate != nil && $0.endDate! >= cutoffDate) || $0.isActive }
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
        let current = BandwidthEngine.fetchDetailedInterfaceBytes()
        persistHardwareCounters(current)
        BandwidthEngine.shared.resetBaseline(to: current)
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
        var csv = "SessionID,NetworkName,ConnectionType,Interface,StartDate,EndDate,DurationSec,DownloadedBytes,UploadedBytes,TotalBytes,DominantCategory,PeakDownloadBps\n"
        let df = ISO8601DateFormatter()

        for s in sessions {
            let endStr = s.endDate != nil ? df.string(from: s.endDate!) : "Active"
            let dominant = s.dominantCategory?.rawValue ?? "Не определено"
            let line = "\(s.id.uuidString),\"\(s.networkName)\",\"\(s.connectionType)\",\(s.interfaceName),\(df.string(from: s.startDate)),\(endStr),\(Int(s.duration)),\(s.downloadedBytes),\(s.uploadedBytes),\(s.totalBytes),\"\(dominant)\",\(Int(s.peakDownloadBps))\n"
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
