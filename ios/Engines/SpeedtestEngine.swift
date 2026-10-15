//
//  SpeedtestEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import Network

/// Описание тестового CDN сервера для замера скорости
public struct SpeedtestServer: Sendable {
    public let name: String
    public let downloadURL: URL
    public let uploadURL: URL?
}

/// Ошибки замера скорости
public enum SpeedtestError: Error, LocalizedError, Sendable {
    /// Ни одного байта не получено — замера не было
    case noConnection

    public var errorDescription: String? {
        switch self {
        case .noConnection:
            return "Не удалось получить данные с серверов измерения. Проверьте подключение к интернету."
        }
    }
}

/// Высокопроизводительный мультипоточный (Multi-Stream) движок замера скорости (Bandwidth & Speedtest) для iOS.
/// Использует потоковое инкрементальное чтение чанков (URLSession.bytes),
/// точный отсчет времени от старта передачи, скользящее окно 1.0 сек и сглаживание EMA.
public final class SpeedtestEngine: Sendable {

    public static let shared = SpeedtestEngine()

    private let primaryDownloadEndpoints: [URL] = [
        URL(string: "https://speed.cloudflare.com/__down?bytes=50000000")!,
        URL(string: "https://speed.cloudflare.com/__down?bytes=25000000")!,
        URL(string: "https://speed.cloudflare.com/__down?bytes=50000000")!,
        URL(string: "https://speed.cloudflare.com/__down?bytes=25000000")!
    ]

    private let primaryUploadEndpoints: [URL] = [
        URL(string: "https://speed.cloudflare.com/__up")!,
        URL(string: "https://speed.cloudflare.com/__up")!,
        URL(string: "https://speed.cloudflare.com/__up")!
    ]

    /// Запасной сервер отдачи: к нему идём, только если Cloudflare не принял ни одного байта. Раньше один из трёх
    /// потоков всегда шёл на httpbin.org; при его сбоях поток обрывался, и отдача занижалась.
    private let fallbackUploadEndpoints: [URL] = [
        URL(string: "https://httpbin.org/post")!
    ]

    public init() {}

    /// Запуск полного цикла мультипоточного тестирования (Multi-Stream Ping + Download + Upload)
    public func runSpeedtest(
        progressHandler: (@Sendable (Double, Double) -> Void)? = nil
    ) async throws -> SpeedtestResult {
        let startTime = ContinuousClock().now

        // 1. Высокоточный замер пинга и джиттера до Anycast CDN
        let (measuredPing, measuredJitter) = await probeHostPingAndJitter(host: "speed.cloudflare.com")

        // 2. Параллельный мультипоточный замер скачивания (4 потока с прямым приемом чанков через delegate)
        let downloadSpeed = await measureMultiStreamDownload(
            endpoints: primaryDownloadEndpoints,
            streamCount: 4,
            durationSeconds: 5.0
        ) { currentMbps in
            progressHandler?(currentMbps, 0.0)
        }

        // Ни одного байта не получено — замера не было. Раньше подставлялись 0,5 Мбит/с и «успех»,
        // а замер отдачи тратил ещё 4 секунды на заведомо мёртвом соединении.
        guard downloadSpeed > 0 else {
            throw SpeedtestError.noConnection
        }

        // 3. Параллельный мультипоточный замер отдачи (3 потока); если Cloudflare ничего не принял, запасной сервер
        var uploadSpeed = await measureMultiStreamUpload(
            endpoints: primaryUploadEndpoints,
            streamCount: 3,
            durationSeconds: 4.0
        ) { currentMbps in
            progressHandler?(downloadSpeed, currentMbps)
        }
        if uploadSpeed <= 0 {
            uploadSpeed = await measureMultiStreamUpload(
                endpoints: fallbackUploadEndpoints,
                streamCount: 2,
                durationSeconds: 3.0
            ) { currentMbps in
                progressHandler?(downloadSpeed, currentMbps)
            }
        }

        let elapsed = ContinuousClock().now - startTime
        let durationSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000.0

        // Отдача 0 означает «измерить не удалось» (интерфейс показывает «—»), а не выдуманные «55 % от скачивания».
        // isSuccess = false отмечает такой неполный результат.
        return SpeedtestResult(
            downloadMbps: (downloadSpeed * 10).rounded() / 10,
            uploadMbps: (uploadSpeed * 10).rounded() / 10,
            pingMs: measuredPing,
            jitterMs: measuredJitter,
            serverName: "Cloudflare Edge Anycast",
            durationSeconds: (durationSeconds * 10).rounded() / 10,
            isSuccess: uploadSpeed > 0
        )
    }

    // MARK: - Мультипоточный замер скачивания (Multi-Stream Download)

    public func measureMultiStreamDownload(
        endpoints: [URL],
        streamCount: Int = 4,
        durationSeconds: Double = 5.0,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async -> Double {
        let tracker = MultiStreamByteTracker()
        tracker.startTracking()

        let delegate = SpeedtestDataDelegate(tracker: tracker, durationLimit: durationSeconds)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = durationSeconds + 2.0
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        // Запуск параллельных потоков скачивания
        var tasks: [URLSessionDataTask] = []
        for i in 0..<streamCount {
            let url = endpoints[i % endpoints.count]
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = durationSeconds + 2.0
            let task = session.dataTask(with: request)
            tasks.append(task)
            task.resume()
        }

        // Цикл мониторинга прогресса 10 Гц (каждые 100 мс)
        let tickerStart = ContinuousClock().now
        while !tracker.isTimedOut(limit: durationSeconds) {
            try? await Task.sleep(nanoseconds: 100_000_000)
            let currentRate = tracker.currentTransferRateMbps()
            if currentRate > 0 {
                onProgress?(currentRate)
            }
            let elapsed = ContinuousClock().now - tickerStart
            let secs = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            if secs >= durationSeconds {
                break
            }
        }

        delegate.terminate()
        for task in tasks {
            task.cancel()
        }
        session.invalidateAndCancel()

        return tracker.finalCalculatedSpeedMbps()
    }

    // MARK: - Мультипоточный замер отдачи (Multi-Stream Upload)

    public func measureMultiStreamUpload(
        endpoints: [URL],
        streamCount: Int = 3,
        durationSeconds: Double = 4.0,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async -> Double {
        let tracker = MultiStreamByteTracker()
        tracker.startTracking()
        let payloadChunk = Data(repeating: 0x5A, count: 256 * 1024) // 256 KB чанки

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let tickerStart = ContinuousClock().now
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    let currentRate = tracker.currentTransferRateMbps()
                    if currentRate > 0 {
                        onProgress?(currentRate)
                    }
                    let elapsed = ContinuousClock().now - tickerStart
                    let secs = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                    if secs >= durationSeconds {
                        break
                    }
                }
            }

            for i in 0..<streamCount {
                let targetURL = endpoints[i % endpoints.count]
                group.addTask {
                    await self.runSingleUploadWorker(url: targetURL, payload: payloadChunk, tracker: tracker, durationLimit: durationSeconds)
                }
            }

            await group.waitForAll()
        }

        return tracker.finalCalculatedSpeedMbps()
    }

    private func runSingleUploadWorker(url: URL, payload: Data, tracker: MultiStreamByteTracker, durationLimit: Double) async {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = durationLimit + 2.0
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        let session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let workerStart = ContinuousClock().now

        while !Task.isCancelled && !tracker.isTimedOut(limit: durationLimit) {
            let elapsed = ContinuousClock().now - workerStart
            let secs = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            if secs >= durationLimit {
                break
            }

            do {
                let (_, response) = try await session.upload(for: request, from: payload)
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                    tracker.addBytes(Int64(payload.count))
                }
            } catch {
                break
            }
        }
        session.invalidateAndCancel()
    }

    // MARK: - Высокоточный замер TCP пинга и джиттера

    /// Пинг и джиттер до узла по TCP-рукопожатию. `nil` — измерить не удалось
    /// (раньше при отказе всех проб выдавались «28 мс / 1,5 мс», а джиттер никогда не опускался ниже 0,5 мс).
    public func probeHostPingAndJitter(host: String) async -> (ping: Double?, jitter: Double?) {
        var samples: [Double] = []
        for _ in 0..<4 {
            if let rtt = await probeTCPHandshake(host: host, port: 443) {
                samples.append(rtt)
            }
        }
        // Первая проба включает разрешение DNS-имени — при достаточном числе замеров она не учитывается
        if samples.count >= 3 {
            samples.removeFirst()
        }
        guard !samples.isEmpty else { return (nil, nil) }
        let avg = (samples.reduce(0, +) / Double(samples.count) * 10).rounded() / 10
        guard samples.count > 1 else { return (avg, nil) }

        var diffs = 0.0
        for i in 1..<samples.count {
            diffs += abs(samples[i] - samples[i - 1])
        }
        let jitter = (diffs / Double(samples.count - 1) * 10).rounded() / 10
        return (avg, jitter)
    }

    private func probeTCPHandshake(host: String, port: UInt16) async -> Double? {
        await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 443)
            let params = NWParameters.tcp
            params.preferNoProxies = true
            let connection = NWConnection(to: endpoint, using: params)
            let queue = DispatchQueue(label: "com.samjan.speedtest.probe.\(host)", qos: .userInteractive)
            let startTime = Date()

            let box = SafeContinuationBox<Double?>(continuation)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = Date().timeIntervalSince(startTime) * 1000.0
                    connection.cancel()
                    box.resumeOnce((elapsed * 10).rounded() / 10)
                case .failed, .cancelled:
                    box.resumeOnce(nil)
                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + 1.2) {
                connection.cancel()
                box.resumeOnce(nil)
            }
        }
    }
}

/// Высокоскоростной системный делегат потокового приема чанков без накладных расходов Swift Concurrency
private final class SpeedtestDataDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let tracker: MultiStreamByteTracker
    private let durationLimit: Double
    private var isTerminated: Bool = false
    private let lock = NSLock()

    init(tracker: MultiStreamByteTracker, durationLimit: Double) {
        self.tracker = tracker
        self.durationLimit = durationLimit
    }

    func terminate() {
        lock.lock()
        isTerminated = true
        lock.unlock()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let stop = isTerminated || tracker.isTimedOut(limit: durationLimit)
        lock.unlock()

        if stop {
            dataTask.cancel()
            return
        }
        tracker.addBytes(Int64(data.count))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Завершено
    }
}

/// Потокобезопасный трекер совокупных байтов и расчета скорости в реальном времени
private final class MultiStreamByteTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var totalBytes: Int64 = 0
    private var startInstant: ContinuousClock.Instant?
    private var samples: [(time: Double, bytes: Int64)] = []
    private var smoothedMbps: Double = 0.0

    /// Отсчёты пишутся не чаще раза в 50 мс. Чанки при быстрой сети приходят сотни раз в секунду, и окно из
    /// последних 40 отсчётов покрывало считанные миллисекунды: скорость выходила средней за весь замер вместе
    /// с разгоном TCP, а «скользящее окно» и исключение первых 0,5 с не работали.
    private static let sampleInterval = 0.05
    private static let maxSamples = 400

    func startTracking() {
        lock.lock()
        defer { lock.unlock() }
        startInstant = ContinuousClock().now
        totalBytes = 0
        samples = [(time: 0.0, bytes: 0)]
        smoothedMbps = 0.0
    }

    func addBytes(_ bytes: Int64) {
        lock.lock()
        defer { lock.unlock() }
        totalBytes += bytes
        guard let start = startInstant else { return }
        let elapsed = ContinuousClock().now - start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        if let last = samples.last, seconds - last.time < Self.sampleInterval { return }
        samples.append((time: seconds, bytes: totalBytes))
        // Запас: замеры длятся 4-5 секунд (около 100 отсчётов); предел нужен лишь на случай очень долгого замера
        if samples.count > Self.maxSamples {
            samples.removeFirst(Self.maxSamples / 2)
        }
    }

    func isTimedOut(limit: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let start = startInstant else { return false }
        let elapsed = ContinuousClock().now - start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return seconds >= limit
    }

    func currentTransferRateMbps() -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard let start = startInstant, samples.count >= 2 else {
            return smoothedMbps
        }
        let elapsed = ContinuousClock().now - start
        let totalSecs = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        guard totalSecs > 0.15, totalBytes > 0 else {
            return 0.0
        }

        // Берем сэмплы за последнее скользящее окно (до 1.0 сек); правый край окна — текущий момент
        guard let fallbackFirst = samples.first else {
            return smoothedMbps
        }
        let latest = (time: totalSecs, bytes: totalBytes)
        let windowCutoff = max(0.0, latest.time - 1.0)
        let relevantOldest = samples.first(where: { $0.time >= windowCutoff }) ?? fallbackFirst

        let dt = latest.time - relevantOldest.time
        let db = latest.bytes - relevantOldest.bytes

        let rawRate: Double
        if dt > 0.15 && db > 0 {
            rawRate = (Double(db) * 8.0) / (dt * 1_000_000.0)
        } else {
            rawRate = (Double(totalBytes) * 8.0) / (totalSecs * 1_000_000.0)
        }

        // Экспоненциальное сглаживание для предотвращения резких скачков UI
        if smoothedMbps == 0.0 {
            smoothedMbps = rawRate
        } else {
            smoothedMbps = (smoothedMbps * 0.6) + (rawRate * 0.4)
        }

        return (smoothedMbps * 10).rounded() / 10
    }

    func finalCalculatedSpeedMbps() -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard let start = startInstant, totalBytes > 0 else { return 0.0 }
        let elapsed = ContinuousClock().now - start
        let totalSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        guard totalSeconds > 0.2 else { return 0.0 }

        // Исключаем стартовый интервал раскрутки TCP (первые 0.5 сек) если данных достаточно
        if samples.count >= 6, let stableStart = samples.first(where: { $0.time >= 0.5 }) {
            let dt = totalSeconds - stableStart.time
            let db = totalBytes - stableStart.bytes
            if dt > 0.5 && db > 0 {
                let sustainedRate = (Double(db) * 8.0) / (dt * 1_000_000.0)
                return (sustainedRate * 10).rounded() / 10
            }
        }

        let overall = (Double(totalBytes) * 8.0) / (totalSeconds * 1_000_000.0)
        return (overall * 10).rounded() / 10
    }
}
