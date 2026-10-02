//
//  BufferbloatEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / Network.framework) - 2026.
//

import Foundation
import Network

/// Параметры теста Bufferbloat
public struct BufferbloatConfiguration: Sendable {
    /// Узел для замера задержки (TCP-рукопожатие на порт 443)
    public var probeHost: String = "1.1.1.1"
    /// Число проб без нагрузки (первая — прогревочная и не учитывается)
    public var idleProbeCount: Int = 8
    /// Длительность каждой фазы нагрузки, секунд
    public var loadWindowSeconds: Double = 8.0
    /// Начальный участок фазы, который не учитывается (разгон TCP, наполнение очередей), секунд
    public var rampUpSeconds: Double = 1.0
    /// Пауза между пробами под нагрузкой, миллисекунд
    public var probeIntervalMs: Int = 250
    public var downloadStreams: Int = 4
    public var uploadStreams: Int = 3
    /// Верхняя граница объёма данных за одну фазу: защита мобильного трафика и батареи
    public var maxBytesPerPhase: Int64 = 400_000_000

    public init() {}

    /// Профиль для мобильной сети: меньше трафика за тест
    public static var cellular: BufferbloatConfiguration {
        var configuration = BufferbloatConfiguration()
        configuration.maxBytesPerPhase = 60_000_000
        return configuration
    }
}

/// Асинхронный движок 3-фазного теста задержки под нагрузкой (Bufferbloat).
///
/// Фазы: (1) задержка без нагрузки; (2) задержка при насыщении канала скачиванием; (3) то же при отдаче.
/// Задержка измеряется TCP-рукопожатием до опорного узла каждые ~250 мс, нагрузка создаётся параллельными
/// потоками, которые перезапускаются до конца окна, — иначе на быстром канале передача заканчивалась за доли
/// секунды, а очереди роутера не успевали наполниться.
public actor BufferbloatEngine {
    public static let shared = BufferbloatEngine()

    /// Таймаут одной пробы. Проба, не уложившаяся в него, считается потерянной.
    private static let probeTimeoutSeconds: Double = 2.0
    /// Минимум успешных проб под нагрузкой, достаточный для медианы
    private static let minimumLoadedSamples = 4

    private let pingEngine = PingEngine(timeout: BufferbloatEngine.probeTimeoutSeconds)

    public init() {}

    /// Запуск полного цикла теста.
    ///
    /// - Parameters:
    ///   - isCellular: сеть мобильная — влияет только на текст рекомендаций (настройка роутера там не поможет).
    ///   - onPhaseChange: фаза и последняя измеренная задержка (мс) для интерфейса.
    public func runBufferbloatTest(
        configuration: BufferbloatConfiguration = BufferbloatConfiguration(),
        isCellular: Bool = false,
        onPhaseChange: (@Sendable (BufferbloatPhase, Double) -> Void)? = nil
    ) async -> Result<BufferbloatReport, BufferbloatError> {
        let probeTarget = HostTarget(name: configuration.probeHost, address: configuration.probeHost)
        var notes: [String] = []

        // 1. Задержка без нагрузки
        onPhaseChange?(.unloadedLatency, 0.0)
        let idle = await measureIdle(target: probeTarget, count: configuration.idleProbeCount)
        if Task.isCancelled { return .failure(.cancelled) }
        guard let idleMedian = idle.medianMs else {
            return .failure(.noConnection)
        }
        onPhaseChange?(.unloadedLatency, idleMedian)
        if idle.lossPercent >= 25.0 {
            notes.append("Даже без нагрузки потеряно \(Int(idle.lossPercent.rounded())) % проб — результат менее надёжен.")
        }

        // 2. Насыщение скачиванием
        onPhaseChange?(.downloadSaturation, idleMedian)
        let download = await measureLoadedPhase(
            direction: .download,
            target: probeTarget,
            configuration: configuration
        ) { livePing in
            onPhaseChange?(.downloadSaturation, livePing)
        }
        if Task.isCancelled { return .failure(.cancelled) }

        // 3. Насыщение отдачей
        onPhaseChange?(.uploadSaturation, download.medianPingMs ?? idleMedian)
        let upload = await measureLoadedPhase(
            direction: .upload,
            target: probeTarget,
            configuration: configuration
        ) { livePing in
            onPhaseChange?(.uploadSaturation, livePing)
        }
        if Task.isCancelled { return .failure(.cancelled) }

        notes.append(contentsOf: Self.notes(for: download, phaseName: "скачивании"))
        notes.append(contentsOf: Self.notes(for: upload, phaseName: "отдаче"))

        let measuredDeltas = [download.medianPingMs, upload.medianPingMs]
            .compactMap { $0 }
            .map { max(0, $0 - idleMedian) }
        let recommendations = Self.makeRecommendations(
            maxDelta: measuredDeltas.max(),
            idleMs: idleMedian,
            isCellular: isCellular
        )

        onPhaseChange?(.completed, upload.medianPingMs ?? download.medianPingMs ?? idleMedian)

        return .success(
            BufferbloatReport(
                unloadedPingMs: Self.roundedToTenth(idleMedian),
                loadedDownloadPingMs: download.medianPingMs.map(Self.roundedToTenth),
                loadedUploadPingMs: upload.medianPingMs.map(Self.roundedToTenth),
                downloadSpeedMbps: download.speedMbps.map(Self.roundedToTenth),
                uploadSpeedMbps: upload.speedMbps.map(Self.roundedToTenth),
                downloadLossPercent: download.lossPercent.map(Self.roundedToTenth),
                uploadLossPercent: upload.lossPercent.map(Self.roundedToTenth),
                notes: notes,
                recommendations: recommendations
            )
        )
    }

    // MARK: - Фаза без нагрузки

    private func measureIdle(target: HostTarget, count: Int) async -> (medianMs: Double?, lossPercent: Double) {
        let totalProbes = max(1, count)
        var rtts: [Double] = []
        var lost = 0

        for index in 0..<totalProbes {
            if Task.isCancelled { break }
            let record = await pingEngine.pingTarget(target)

            // Первая проба включает ARP/маршрут и «пробуждение» радиомодуля — в статистику не входит
            let isWarmUp = totalProbes >= 6 && index == 0
            if !isWarmUp {
                if record.isSuccess, let latency = record.latencyMs {
                    rtts.append(latency)
                } else {
                    lost += 1
                }
            }
            if index < totalProbes - 1 {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }

        let counted = rtts.count + lost
        let lossPercent = counted > 0 ? Double(lost) / Double(counted) * 100.0 : 100.0
        return (rtts.isEmpty ? nil : Self.median(rtts), lossPercent)
    }

    // MARK: - Фаза с нагрузкой

    /// Итог одной фазы нагрузки
    private struct LoadedPhaseResult: Sendable {
        /// Медиана задержки под нагрузкой. `nil` — оценить не удалось
        let medianPingMs: Double?
        /// Доля потерянных проб, %. `nil` — проб не было
        let lossPercent: Double?
        /// Скорость передачи за устоявшийся участок. `nil` — данные не передавались
        let speedMbps: Double?
        /// Нагрузку создать не удалось (за первые секунды не передано ни байта)
        let loadFailed: Bool
        /// Медиана — оценка снизу: большинство проб не уложилось в таймаут
        let isLowerBound: Bool
    }

    private func measureLoadedPhase(
        direction: SaturationLoad.Direction,
        target: HostTarget,
        configuration: BufferbloatConfiguration,
        onLivePing: @Sendable (Double) -> Void
    ) async -> LoadedPhaseResult {
        let load = SaturationLoad(
            direction: direction,
            streams: direction == .download ? configuration.downloadStreams : configuration.uploadStreams,
            maxBytes: configuration.maxBytesPerPhase
        )
        load.start()
        defer { load.stop() }

        let start = ContinuousClock().now
        var rtts: [Double] = []
        var lost = 0
        var byteSamples: [(time: Double, bytes: Int64)] = []

        while !Task.isCancelled {
            let now = Self.elapsedSeconds(since: start)
            if now >= configuration.loadWindowSeconds || load.isCapReached { break }
            // За первые 3 секунды не передано ни байта: нагрузку создать не удалось, дальше мерить бессмысленно
            if now >= 3.0 && load.transferredBytes() == 0 { break }

            let record = await pingEngine.pingTarget(target)
            let sampleTime = Self.elapsedSeconds(since: start)
            byteSamples.append((time: sampleTime, bytes: load.transferredBytes()))

            // Начальный участок (разгон TCP) в статистику не входит
            if sampleTime >= configuration.rampUpSeconds {
                if record.isSuccess, let latency = record.latencyMs {
                    rtts.append(latency)
                    onLivePing(latency)
                } else {
                    lost += 1
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(max(50, configuration.probeIntervalMs)) * 1_000_000)
        }

        let totalBytes = load.transferredBytes()
        guard totalBytes > 0 else {
            return LoadedPhaseResult(
                medianPingMs: nil,
                lossPercent: nil,
                speedMbps: nil,
                loadFailed: true,
                isLowerBound: false
            )
        }

        // Скорость — по байтам за устоявшийся участок. Раньше делилось на время цикла пингов, из-за чего
        // 300/600/900 Мбит/с отображались как ≈143 Мбит/с.
        var speedMbps: Double?
        if let first = byteSamples.first(where: { $0.time >= configuration.rampUpSeconds }),
           let last = byteSamples.last,
           last.time - first.time >= 1.0 {
            speedMbps = Double(last.bytes - first.bytes) * 8.0 / ((last.time - first.time) * 1_000_000.0)
        } else if let last = byteSamples.last, last.time >= 0.5 {
            speedMbps = Double(last.bytes) * 8.0 / (last.time * 1_000_000.0)
        }

        let counted = rtts.count + lost
        let lossPercent: Double? = counted > 0 ? Double(lost) / Double(counted) * 100.0 : nil

        if rtts.count >= Self.minimumLoadedSamples {
            return LoadedPhaseResult(
                medianPingMs: Self.median(rtts),
                lossPercent: lossPercent,
                speedMbps: speedMbps,
                loadFailed: false,
                isLowerBound: false
            )
        }

        // Мало успешных проб. Если при этом большинство проб не уложилось в таймаут, задержка под нагрузкой
        // не меньше таймаута (оценка снизу) — тяжёлый bufferbloat нельзя выдавать за «нет данных» или «A+».
        if counted >= Self.minimumLoadedSamples, let lossPercent, lossPercent >= 50.0 {
            return LoadedPhaseResult(
                medianPingMs: Self.probeTimeoutSeconds * 1000.0,
                lossPercent: lossPercent,
                speedMbps: speedMbps,
                loadFailed: false,
                isLowerBound: true
            )
        }

        return LoadedPhaseResult(
            medianPingMs: nil,
            lossPercent: lossPercent,
            speedMbps: speedMbps,
            loadFailed: false,
            isLowerBound: false
        )
    }

    // MARK: - Пояснения и рекомендации

    private static func notes(for phase: LoadedPhaseResult, phaseName: String) -> [String] {
        var result: [String] = []
        if phase.loadFailed {
            result.append("Не удалось создать нагрузку при \(phaseName) (нет данных от сервера speed.cloudflare.com) — эта фаза не оценена.")
            return result
        }
        if phase.isLowerBound {
            let limitMs = Int(probeTimeoutSeconds * 1000.0)
            result.append("При \(phaseName) большинство проб не уложилось в \(Int(probeTimeoutSeconds)) с: реальная задержка не меньше \(limitMs) мс.")
        } else if phase.medianPingMs == nil {
            result.append("При \(phaseName) получено слишком мало ответов на пробы — задержка под нагрузкой не оценена.")
        }
        if let loss = phase.lossPercent, loss >= BufferbloatReport.lossPenaltyThresholdPercent {
            result.append("При \(phaseName) потеряно \(Int(loss.rounded())) % проб — признак переполненной очереди, оценка понижена на ступень.")
        }
        return result
    }

    private static func makeRecommendations(maxDelta: Double?, idleMs: Double, isCellular: Bool) -> [String] {
        guard let maxDelta else {
            return ["Повторите тест позже: под нагрузкой не удалось получить достаточно ответов."]
        }

        var result: [String] = []
        switch maxDelta {
        case ..<5.0:
            result.append("Задержка под нагрузкой почти не растёт — дополнительная настройка не требуется.")
        case ..<15.0:
            result.append("Небольшой рост задержки при полной загрузке канала — для игр и звонков это допустимо.")
        case ..<40.0:
            if isCellular {
                result.append("Рост задержки возникает в сети оператора: настройки роутера здесь ни при чём. Попробуйте другое место или режим сети (LTE/5G).")
            } else {
                result.append("Включите SQM (fq_codel или CAKE) в настройках роутера, если он это поддерживает (OpenWrt, Keenetic, ASUS Merlin и др.).")
                result.append("При подключении по Wi-Fi проверьте уровень сигнала и по возможности используйте диапазон 5 ГГц.")
            }
        default:
            if isCellular {
                result.append("Рост задержки возникает в сети оператора: настройки роутера здесь ни при чём. Попробуйте другое место или режим сети (LTE/5G).")
                result.append("Игры и звонки лучше запускать, когда другие приложения не качают и не загружают большие файлы.")
            } else {
                result.append("Включите SQM (CAKE или fq_codel) в настройках роутера (OpenWrt, Keenetic, ASUS Merlin и др.).")
                result.append("Ограничьте скорость в шейпере SQM на 85–95 % от реальной скорости тарифа: очередь тогда будет копиться в роутере под вашим управлением, а не у провайдера.")
                result.append("Если SQM недоступен, ограничьте скорость на самом «тяжёлом» устройстве (торренты, облачные резервные копии).")
            }
        }

        if idleMs > 75.0 {
            if isCellular {
                result.append("Базовая задержка (\(Int(idleMs.rounded())) мс) определяется самой мобильной сетью, а не буферизацией.")
            } else {
                result.append("Базовая задержка высока (\(Int(idleMs.rounded())) мс) даже без нагрузки: причина в удалённости узла, маршруте или качестве Wi-Fi, а не в буферизации.")
            }
        }
        return result
    }

    // MARK: - Вспомогательные функции

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[middle - 1] + sorted[middle]) / 2.0
        }
        return sorted[middle]
    }

    private static func roundedToTenth(_ value: Double) -> Double {
        (value * 10.0).rounded() / 10.0
    }

    private static func elapsedSeconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock().now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }
}

// MARK: - Генератор нагрузки

/// Нагрузка на канал для Bufferbloat-теста: несколько параллельных потоков, каждый перезапускается после
/// завершения, пока нагрузка не остановлена. Байты считаются по мере приёма/отправки (а не по завершении запроса).
private final class SaturationLoad: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Direction: Sendable {
        case download
        case upload
    }

    private static let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=25000000")!
    private static let uploadURL = URL(string: "https://speed.cloudflare.com/__up")!
    /// Подряд идущие ошибки, после которых потоки больше не перезапускаются (сервер/сеть недоступны)
    private static let maxConsecutiveFailures = 6

    private let direction: Direction
    private let streams: Int
    private let maxBytes: Int64
    private let payload = Data(count: 1_000_000)

    private let lock = NSLock()
    private var session: URLSession?
    private var isStopped = false
    private var bytes: Int64 = 0
    private var consecutiveFailures = 0

    init(direction: Direction, streams: Int, maxBytes: Int64) {
        self.direction = direction
        self.streams = max(1, streams)
        self.maxBytes = maxBytes
        super.init()
    }

    /// Достигнут лимит объёма данных за фазу
    var isCapReached: Bool {
        lock.lock()
        defer { lock.unlock() }
        return bytes >= maxBytes
    }

    func transferredBytes() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return bytes
    }

    func start() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.httpMaximumConnectionsPerHost = max(streams, 2)
        let newSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

        lock.lock()
        session = newSession
        lock.unlock()

        for _ in 0..<streams {
            launchTask()
        }
    }

    func stop() {
        lock.lock()
        isStopped = true
        let current = session
        session = nil
        lock.unlock()
        // Создавать задачи в сессии после invalidate нельзя (исключение), поэтому флаг выставлен до неё
        current?.invalidateAndCancel()
    }

    /// Запуск (или перезапуск) одного потока. Создание задачи выполняется под замком, чтобы `stop()`
    /// не успел отменить сессию между проверкой флага и созданием задачи.
    private func launchTask() {
        lock.lock()
        defer { lock.unlock() }
        guard !isStopped, bytes < maxBytes, let session else { return }

        switch direction {
        case .download:
            var request = URLRequest(url: Self.downloadURL)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            session.dataTask(with: request).resume()
        case .upload:
            var request = URLRequest(url: Self.uploadURL)
            request.httpMethod = "POST"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            session.uploadTask(with: request, from: payload).resume()
        }
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard direction == .download else { return }
        // Тело ответа с ошибкой сервера (например, 429) нагрузкой не считается
        if let http = dataTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            dataTask.cancel()
            return
        }
        lock.lock()
        bytes += Int64(data.count)
        consecutiveFailures = 0
        let capReached = bytes >= maxBytes
        lock.unlock()
        if capReached {
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard direction == .upload else { return }
        lock.lock()
        bytes += bytesSent
        consecutiveFailures = 0
        let capReached = bytes >= maxBytes
        lock.unlock()
        if capReached {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil {
            lock.lock()
            consecutiveFailures += 1
            let tooManyFailures = consecutiveFailures >= Self.maxConsecutiveFailures
            lock.unlock()
            // Сервер или сеть недоступны — не крутим бесконечный цикл перезапусков
            if tooManyFailures { return }
        }
        launchTask()
    }
}
