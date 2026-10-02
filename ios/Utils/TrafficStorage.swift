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
    private static let kLastBootTimeKey = "netpulse_last_boot_time"
    private static let kLastCountersTimeKey = "netpulse_last_counters_time"

    /// Максимум сессий на диске (раньше — 100: при смене сетей это ~3 недели, дальше статистика молча терялась)
    private static let maxStoredSessions = 1000
    /// Точки графика: минутные «корзины» за последние сутки, дальше — часовые, не старше 35 дней
    private static let fineRetention: TimeInterval = 24 * 3600
    private static let totalRetention: TimeInterval = 35 * 24 * 3600
    private static let maxStoredDataPoints = 4000

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
            loadedSessions = Array(sanitized.prefix(maxStoredSessions))
        }

        // Загрузка точек графиков (с компактизацией: старые минутные точки сворачиваются в часовые).
        // Прежняя «санация» отдачи в сотовых сессиях (upload = 4 % от скачивания) удалена: она необратимо
        // портила законные данные (выгрузка видео, звонки), а новый учёт больше не считает трафик раздачи дважды.
        if let data = try? Data(contentsOf: dataPointsFileURL),
           let decoded = try? JSONDecoder().decode([TrafficDataPoint].self, from: data) {
            loadedPoints = compactedDataPoints(decoded, now: Date())
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
            let sData = try JSONEncoder().encode(Array(sessions.prefix(Self.maxStoredSessions)))
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

    /// Время последней перезагрузки устройства (kern.boottime). Счётчики интерфейсов при перезагрузке обнуляются.
    private static func currentBootTime() -> TimeInterval? {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0 else { return nil }
        return TimeInterval(bootTime.tv_sec)
    }

    /// Синхронизация трафика, потраченного строго пока приложение спало или было закрыто.
    ///
    /// Дельта считается по КАЖДОМУ типу сети отдельно и записывается в сессию своего типа независимо от текущего
    /// подключения: раньше учитывалась только текущая сеть, и трафик другой (например, сотовой после ухода
    /// с Wi-Fi в фоне) терялся. После перезагрузки счётчики начинаются с нуля, и раньше это принималось за
    /// 32-битное переполнение (фантомные сотни мегабайт).
    public func reconcileBackgroundHardwareTraffic(
        currentConnectionType: String,
        currentNetworkName: String
    ) {
        let currentCounters = BandwidthEngine.fetchDetailedInterfaceBytes()
        let now = Date()
        let bootNow = Self.currentBootTime()

        // 1. Считываем сохраненную базовую точку при уходе в фон
        guard let savedData = UserDefaults.standard.data(forKey: Self.kLastHardwareCountersKey),
              let saved = try? JSONDecoder().decode(InterfaceByteCounters.self, from: savedData),
              (saved.totalIn > 0 || saved.totalOut > 0) else {
            // Первичная точка отсчета: фиксируем текущее состояние ядра БЕЗ начисления дельты
            persistHardwareCounters(currentCounters)
            BandwidthEngine.shared.resetBaseline(to: currentCounters)
            return
        }

        // 2. Что изменилось с момента сохранения: перезагрузка и прошедшее время
        let savedBoot = UserDefaults.standard.object(forKey: Self.kLastBootTimeKey) as? Double
        let rebooted: Bool
        if let boot = bootNow, let previous = savedBoot {
            rebooted = abs(boot - previous) > 5.0
        } else {
            rebooted = false
        }
        let savedTime = UserDefaults.standard.object(forKey: Self.kLastCountersTimeKey) as? Double
        let elapsed: TimeInterval? = savedTime.map { max(now.timeIntervalSince1970 - $0, 1.0) }
        // Правдоподобный максимум за прошедшее время (250 МБ/с): всё, что больше, — сброс счётчика, а не трафик
        let plausibleCap: UInt64 = elapsed.map { UInt64(min($0 * 250_000_000.0, 4_000_000_000.0)) } ?? 2_000_000_000

        func missing(_ previous: UInt64, _ current: UInt64) -> UInt64 {
            if rebooted {
                return current   // счётчики обнулились при перезагрузке: всё накопленное — трафик без нашего учёта
            }
            return BandwidthEngine.computeDelta(prev: previous, current: current, maxPlausibleDelta: plausibleCap)
        }

        let wifiIn = missing(saved.wifiIn, currentCounters.wifiIn)
        let wifiOut = missing(saved.wifiOut, currentCounters.wifiOut)
        let cellIn = missing(saved.cellularIn, currentCounters.cellularIn)
        let cellOut = missing(saved.cellularOut, currentCounters.cellularOut)

        // 3. НЕМЕДЛЕННО обновляем базовую точку в UserDefaults и в BandwidthEngine,
        // чтобы активный цикл не посчитал эти байты второй раз!
        persistHardwareCounters(currentCounters)
        BandwidthEngine.shared.resetBaseline(to: currentCounters)

        // Окно, в течение которого трафик не наблюдался (для границ сессии)
        var windowStart = now.addingTimeInterval(-60)
        if let elapsedSeconds = elapsed, elapsedSeconds < 7 * 86400 {
            windowStart = now.addingTimeInterval(-elapsedSeconds)
        }

        var added = false
        if wifiIn > 0 || wifiOut > 0 {
            addBackgroundTraffic(isWifi: true, download: wifiIn, upload: wifiOut, windowStart: windowStart, now: now)
            added = true
        }
        if cellIn > 0 || cellOut > 0 {
            addBackgroundTraffic(isWifi: false, download: cellIn, upload: cellOut, windowStart: windowStart, now: now)
            added = true
        }
        if added {
            scheduleDebouncedSave()
        }
    }

    /// Начисление трафика, прошедшего в фоне, в сессию соответствующего типа сети
    private func addBackgroundTraffic(isWifi: Bool, download: UInt64, upload: UInt64, windowStart: Date, now: Date) {
        let normConnType = isWifi ? "Wi-Fi" : "Сотовая связь"
        let normNetName = isWifi ? "Wi-Fi Подключение" : "Мобильная сеть (LTE/5G)"
        let ifName = isWifi ? "en0" : "pdp_ip0"

        let bgDistribution = TrafficClassifier.shared.distributeSample(
            deltaDownload: download,
            deltaUpload: upload,
            speedBps: Double(download + upload),
            isSpeedtestActive: false,
            isBackground: true
        )

        if let activeId = currentActiveSessionId,
           let index = sessions.firstIndex(where: { $0.id == activeId }),
           sessions[index].connectionType == normConnType {
            sessions[index].downloadedBytes += download
            sessions[index].uploadedBytes += upload
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
                startDate: windowStart,
                endDate: now,
                downloadedBytes: download,
                uploadedBytes: upload,
                peakDownloadBps: Double(download),
                peakUploadBps: Double(upload),
                isActive: true,
                categoryUsages: initialCategories
            )
            sessions.insert(backgroundSession, at: 0)
            currentActiveSessionId = backgroundSession.id
        }

        appendToDataPoints(
            timestamp: now,
            download: download,
            upload: upload,
            wifi: isWifi ? (download + upload) : 0,
            cellular: isWifi ? 0 : (download + upload)
        )
    }

    public func persistHardwareCounters(_ counters: InterfaceByteCounters) {
        if let encoded = try? JSONEncoder().encode(counters) {
            UserDefaults.standard.set(encoded, forKey: Self.kLastHardwareCountersKey)
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.kLastCountersTimeKey)
        if let boot = Self.currentBootTime() {
            let saved = UserDefaults.standard.object(forKey: Self.kLastBootTimeKey) as? Double
            if saved != boot {
                UserDefaults.standard.set(boot, forKey: Self.kLastBootTimeKey)
            }
        }
    }

    // MARK: - Точки графика: минутные корзины с компактизацией

    /// Добавляет байты в минутную «корзину». Раньше каждая секунда активности была отдельной точкой при лимите
    /// в 300 точек, и графики «24 часа / 7 / 30 дней» охватывали лишь последние ~5 минут.
    private func appendToDataPoints(timestamp: Date, download: UInt64, upload: UInt64, wifi: UInt64, cellular: UInt64) {
        let bucketStart = Date(timeIntervalSince1970: (timestamp.timeIntervalSince1970 / 60.0).rounded(.down) * 60.0)
        if let last = dataPoints.last, last.timestamp == bucketStart {
            dataPoints[dataPoints.count - 1] = TrafficDataPoint(
                id: last.id,
                timestamp: bucketStart,
                downloadBytes: last.downloadBytes + download,
                uploadBytes: last.uploadBytes + upload,
                wifiBytes: last.wifiBytes + wifi,
                cellularBytes: last.cellularBytes + cellular
            )
        } else {
            dataPoints.append(TrafficDataPoint(
                timestamp: bucketStart,
                downloadBytes: download,
                uploadBytes: upload,
                wifiBytes: wifi,
                cellularBytes: cellular
            ))
            // Новая минута — подходящий момент свернуть старые точки (не каждую секунду)
            dataPoints = Self.compactedDataPoints(dataPoints, now: timestamp)
        }
    }

    /// Минутные точки старше суток сворачиваются в часовые, точки старше 35 дней отбрасываются.
    /// Предполагает хронологический порядок точек (они только добавляются в конец).
    private static func compactedDataPoints(_ points: [TrafficDataPoint], now: Date) -> [TrafficDataPoint] {
        let fineCutoff = now.addingTimeInterval(-fineRetention)
        let dropCutoff = now.addingTimeInterval(-totalRetention)

        var result: [TrafficDataPoint] = []
        result.reserveCapacity(points.count)

        for point in points {
            if point.timestamp < dropCutoff {
                continue
            }
            if point.timestamp >= fineCutoff {
                result.append(point)
                continue
            }
            let hourStart = Date(timeIntervalSince1970: (point.timestamp.timeIntervalSince1970 / 3600.0).rounded(.down) * 3600.0)
            if let last = result.last, last.timestamp == hourStart {
                result[result.count - 1] = TrafficDataPoint(
                    id: last.id,
                    timestamp: hourStart,
                    downloadBytes: last.downloadBytes + point.downloadBytes,
                    uploadBytes: last.uploadBytes + point.uploadBytes,
                    wifiBytes: last.wifiBytes + point.wifiBytes,
                    cellularBytes: last.cellularBytes + point.cellularBytes
                )
            } else {
                result.append(TrafficDataPoint(
                    id: point.id,
                    timestamp: hourStart,
                    downloadBytes: point.downloadBytes,
                    uploadBytes: point.uploadBytes,
                    wifiBytes: point.wifiBytes,
                    cellularBytes: point.cellularBytes
                ))
            }
        }

        if result.count > maxStoredDataPoints {
            result.removeFirst(result.count - maxStoredDataPoints)
        }
        return result
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
        // Пропускаем тяжелую классификацию и работу с массивами, если нет сетевого трафика (в покое)
        if snapshot.deltaDownloadBytes == 0 && snapshot.deltaUploadBytes == 0 {
            return
        }

        let now = Date()
        // Тип сети — по тому, какой интерфейс реально передавал байты. Раньше брался `connectionType`, который
        // обновляется раз в ~20 секунд: при переходе Wi-Fi → LTE первые секунды записывались не в ту сеть.
        let isWifi: Bool
        if snapshot.deltaWifiBytes > 0 || snapshot.deltaCellularBytes > 0 {
            isWifi = snapshot.deltaWifiBytes >= snapshot.deltaCellularBytes
        } else {
            isWifi = connectionType.contains("Wi-Fi") || connectionType.lowercased().contains("wifi")
        }
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

        // 3. Записываем реальный расход в минутную «корзину» графика, если была активность
        if snapshot.deltaDownloadBytes > 0 || snapshot.deltaUploadBytes > 0 {
            appendToDataPoints(
                timestamp: now,
                download: snapshot.deltaDownloadBytes,
                upload: snapshot.deltaUploadBytes,
                wifi: isWifi ? (snapshot.deltaDownloadBytes + snapshot.deltaUploadBytes) : 0,
                cellular: isWifi ? 0 : (snapshot.deltaDownloadBytes + snapshot.deltaUploadBytes)
            )
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

    /// Доля байт сессии, относящаяся к периоду, начинающемуся в `cutoff` (пропорционально времени пересечения).
    /// Раньше сессия, пересекающая границу периода, учитывалась ЦЕЛИКОМ: начатая вчера в 07:00 в 00:30 попадала
    /// в «Сегодня» вся (≈ 17,5 ч вместо 0,5 ч), что искажало и квоту, и предупреждения.
    private static func periodFraction(of session: TrafficSession, cutoff: Date, now: Date) -> Double {
        if session.startDate >= cutoff {
            return 1.0
        }
        let end = min(session.endDate ?? now, now)
        guard end > cutoff else { return 0.0 }
        let total = end.timeIntervalSince(session.startDate)
        guard total > 0 else { return 1.0 }
        return min(1.0, max(0.0, end.timeIntervalSince(cutoff) / total))
    }

    private static func scaled(_ value: UInt64, by fraction: Double) -> UInt64 {
        if fraction >= 1.0 { return value }
        return UInt64((Double(value) * fraction).rounded())
    }

    /// Копия сессии с байтами, отнесёнными к периоду (для суммирования и разбивки по категориям)
    private static func session(_ session: TrafficSession, scaledBy fraction: Double) -> TrafficSession {
        if fraction >= 1.0 { return session }
        var copy = session
        copy.downloadedBytes = scaled(session.downloadedBytes, by: fraction)
        copy.uploadedBytes = scaled(session.uploadedBytes, by: fraction)
        copy.categoryUsages = session.categoryUsages.map { usage in
            var u = usage
            u.downloadBytes = scaled(usage.downloadBytes, by: fraction)
            u.uploadBytes = scaled(usage.uploadBytes, by: fraction)
            return u
        }
        return copy
    }

    public func getSummary(for period: TrafficPeriod) -> TrafficSummary {
        let now = Date()
        let cutoff = cutoffDate(for: period)

        var summary = TrafficSummary()
        var inPeriod: [TrafficSession] = []

        for original in sessions {
            let fraction = Self.periodFraction(of: original, cutoff: cutoff, now: now)
            guard fraction > 0 else { continue }
            let s = Self.session(original, scaledBy: fraction)
            inPeriod.append(s)

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

        summary.totalSessionsCount = inPeriod.count
        summary.activeSessionsCount = inPeriod.filter { $0.isActive }.count
        summary.categoryBreakdown = TrafficClassifier.shared.aggregateCategoryBreakdown(
            from: inPeriod,
            totalTraffic: summary.totalTraffic
        )

        return summary
    }

    public func getSessions(for period: TrafficPeriod) -> [TrafficSession] {
        let now = Date()
        let cutoff = cutoffDate(for: period)
        return sessions.filter { Self.periodFraction(of: $0, cutoff: cutoff, now: now) > 0 }
    }

    public func getDataPoints(for period: TrafficPeriod) -> [TrafficDataPoint] {
        let cutoff = cutoffDate(for: period)
        return dataPoints.filter { $0.timestamp >= cutoff }
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
            let endStr = s.endDate.map { df.string(from: $0) } ?? "Active"
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
