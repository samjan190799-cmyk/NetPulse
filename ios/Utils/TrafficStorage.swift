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
            // Санация данных: фильтруем микро-сессии с 0 байт и аномальные дубликаты
            let sanitized = decoded.filter { session in
                let total = session.downloadedBytes + session.uploadedBytes
                // Исключаем пустые артефактные сессии
                return total > 1024 || session.isActive
            }
            // Ограничиваем историю максимум 100 наиболее актуальными сессиями
            loadedSessions = Array(sanitized.prefix(100))
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

    /// Дебаунсинг дисковой записи: предотвращает частую запись и исключает разряд батареи и перегрузку I/O
    private func scheduleDebouncedSave() {
        hasUnsavedChanges = true
        let timeSinceLastSave = Date().timeIntervalSince(lastSavedDate)

        // Сохраняем не чаще чем раз в 30 секунд для сбережения аккумулятора
        if timeSinceLastSave >= 30.0 {
            saveTask?.cancel()
            saveTask = nil
            performDiskSave()
            return
        }

        if saveTask == nil {
            saveTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 25_000_000_000)
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
        guard let savedData = UserDefaults.standard.data(forKey: Self.kLastHardwareCountersKey),
              let saved = try? JSONDecoder().decode(InterfaceByteCounters.self, from: savedData),
              (saved.totalIn > 0 || saved.totalOut > 0) else {
            // Первичная точка отсчета: фиксируем текущее состояние ядра БЕЗ начисления дельты
            persistHardwareCounters(currentCounters)
            return
        }

        let isWifi = currentConnectionType.contains("Wi-Fi") || currentConnectionType.lowercased().contains("wifi")
        let normConnType = isWifi ? "Wi-Fi" : "Сотовая связь"
        let normNetName = isWifi ? "Wi-Fi Подключение" : "Мобильная сеть (LTE/5G)"
        let ifName = isWifi ? "en0" : "pdp_ip0"

        // Вычисляем пропущенные дельты на уровне сетевых интерфейсов ядра
        let missingWifiIn = BandwidthEngine.computeDelta(prev: saved.wifiIn, current: currentCounters.wifiIn)
        let missingWifiOut = BandwidthEngine.computeDelta(prev: saved.wifiOut, current: currentCounters.wifiOut)
        let missingWifiTotal = missingWifiIn + missingWifiOut

        let missingCellIn = BandwidthEngine.computeDelta(prev: saved.cellularIn, current: currentCounters.cellularIn)
        let missingCellOut = BandwidthEngine.computeDelta(prev: saved.cellularOut, current: currentCounters.cellularOut)
        let missingCellTotal = missingCellIn + missingCellOut

        let missingTotalIn = isWifi ? missingWifiIn : missingCellIn
        let missingTotalOut = isWifi ? missingWifiOut : missingCellOut

        // Обновляем контрольную точку аппаратного счетчика
        persistHardwareCounters(currentCounters)

        if missingTotalIn > 0 || missingTotalOut > 0 {
            let bgDistribution = TrafficClassifier.shared.distributeSample(
                deltaDownload: missingTotalIn,
                deltaUpload: missingTotalOut,
                speedBps: Double(missingTotalIn + missingTotalOut),
                isSpeedtestActive: false,
                isBackground: true
            )

            if let activeId = currentActiveSessionId,
               let index = sessions.firstIndex(where: { $0.id == activeId }),
               sessions[index].connectionType == normConnType {
                sessions[index].downloadedBytes += missingTotalIn
                sessions[index].uploadedBytes += missingTotalOut
                sessions[index].endDate = now
                sessions[index].categoryUsages = TrafficClassifier.shared.mergeCategoryUsages(
                    existing: sessions[index].categoryUsages,
                    additions: bgDistribution
                )
            } else {
                // Закрываем предыдущую активную сессию если сменился тип сети
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
                    downloadedBytes: missingTotalIn,
                    uploadedBytes: missingTotalOut,
                    peakDownloadBps: Double(missingTotalIn),
                    peakUploadBps: Double(missingTotalOut),
                    isActive: true,
                    categoryUsages: initialCategories
                )
                sessions.insert(backgroundSession, at: 0)
                currentActiveSessionId = backgroundSession.id
            }

            // Добавляем точку на график
            let point = TrafficDataPoint(
                timestamp: now,
                downloadBytes: missingTotalIn,
                uploadBytes: missingTotalOut,
                wifiBytes: isWifi ? (missingTotalIn + missingTotalOut) : 0,
                cellularBytes: !isWifi ? (missingTotalIn + missingTotalOut) : 0
            )
            dataPoints.append(point)
            if dataPoints.count > 300 {
                dataPoints.removeFirst(dataPoints.count - 300)
            }

            scheduleDebouncedSave()
        }
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
        interfaceName: String,
        isSpeedtestActive: Bool = false
    ) {
        let now = Date()
        let isWifi = connectionType.contains("Wi-Fi") || connectionType.lowercased().contains("wifi")
        let normConnType = isWifi ? "Wi-Fi" : "Сотовая связь"
        let normNetName = isWifi ? "Wi-Fi Подключение" : "Мобильная сеть (LTE/5G)"

        // 1. Проверяем, изменился ли физический тип сети (Wi-Fi <-> Cellular)
        if let activeId = currentActiveSessionId,
           let index = sessions.firstIndex(where: { $0.id == activeId }) {
            let active = sessions[index]
            // Сессия меняется ТОЛЬКО если произошел реальный переход между Wi-Fi и Cellular
            // или текущая сессия длится уже более 24 часов
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

            // Храним максимум 300 последних точек в памяти
            if dataPoints.count > 300 {
                dataPoints.removeFirst(dataPoints.count - 300)
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

        summary.categoryBreakdown = TrafficClassifier.shared.aggregateCategoryBreakdown(
            from: filteredSessions,
            totalTraffic: summary.totalTraffic
        )

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

