//
//  QuickCheck.swift
//  NetPulse
//
//  Быстрая проверка связи, которой не нужно открывать приложение: кнопка в Пункте управления, виджеты, Siri и
//  Команды. Три узла опрашиваются одновременно по TCP (время установки соединения), из ответов получается вердикт
//  «Отлично / Нормально / Плохо / Нет связи». Каждый замер попадает в общий журнал, из которого строится утренняя
//  сводка. Файл входит и в приложение, и в расширение виджетов, поэтому зависит только от Foundation и Network.
//

import Foundation
import Network

// MARK: - Узлы

struct QuickCheckHost: Sendable, Equatable {
    let name: String
    let host: String
    let port: UInt16

    /// Три независимых узла: если отвечает один, а два молчат, виновата связь, а не узел
    static let defaults: [QuickCheckHost] = [
        QuickCheckHost(name: "Cloudflare", host: "1.1.1.1", port: 443),
        QuickCheckHost(name: "Google", host: "8.8.8.8", port: 443),
        QuickCheckHost(name: "Quad9", host: "9.9.9.9", port: 443)
    ]
}

// MARK: - Вердикт

enum QuickCheckVerdict: String, Codable, Sendable, Equatable {
    case excellent
    case good
    case poor
    case offline

    /// Быстрее — «отлично», быстрее второго порога — «нормально», дальше — «плохо»
    static let excellentPingMs = 60.0
    static let goodPingMs = 150.0

    /// По итогам проверки: ответили `reached` узлов из `total`, средний (медианный) пинг `medianMs`.
    /// Половина узлов и меньше — «плохо»: один молчащий узел из трёх беды не значит, два — значит.
    static func classify(medianMs: Double?, reached: Int, total: Int) -> QuickCheckVerdict {
        guard total > 0, reached > 0, let medianMs else { return .offline }
        if reached * 2 <= total { return .poor }
        if medianMs < excellentPingMs { return .excellent }
        if medianMs < goodPingMs { return .good }
        return .poor
    }

    /// По снимку виджета (там только пинг и доля потерь). `nil` — вывода нет: замеров не было.
    static func fromSnapshot(pingMs: Double?, lossPercent: Double) -> QuickCheckVerdict? {
        if lossPercent >= 100 { return .offline }
        guard let pingMs else { return nil }
        if lossPercent > 50 { return .poor }
        if pingMs < excellentPingMs { return .excellent }
        if pingMs < goodPingMs { return .good }
        return .poor
    }

    var title: String {
        switch self {
        case .excellent: return "Отлично"
        case .good: return "Нормально"
        case .poor: return "Плохо"
        case .offline: return "Нет связи"
        }
    }

    var symbolName: String {
        switch self {
        case .excellent: return "checkmark.circle.fill"
        case .good: return "checkmark.circle"
        case .poor: return "exclamationmark.triangle.fill"
        case .offline: return "wifi.slash"
        }
    }

    /// Оценка 0...100 для снимка виджета (полный индекс здоровья считает приложение)
    var healthScore: Int {
        switch self {
        case .excellent: return 95
        case .good: return 75
        case .poor: return 40
        case .offline: return 0
        }
    }
}

// MARK: - Итог проверки

struct QuickCheckProbe: Sendable, Equatable {
    let host: QuickCheckHost
    /// Время установки соединения; `nil` — узел не ответил
    let latencyMs: Double?
}

struct QuickCheckResult: Sendable, Equatable {
    let time: Date
    let probes: [QuickCheckProbe]
    /// «Wi-Fi», «Мобильная сеть», «Ethernet», «Сеть» или «Нет сети»
    let connection: String

    var total: Int { probes.count }
    var reached: Int { probes.filter { $0.latencyMs != nil }.count }

    var lossPercent: Double {
        total == 0 ? 100 : Double(total - reached) / Double(total) * 100
    }

    /// Медиана пинга по ответившим узлам
    var medianMs: Double? {
        Self.median(probes.compactMap(\.latencyMs))
    }

    var verdict: QuickCheckVerdict {
        .classify(medianMs: medianMs, reached: reached, total: total)
    }

    var sample: QuickCheckSample {
        QuickCheckSample(time: time, pingMs: medianMs, reached: reached, total: total, connection: connection)
    }

    private var pingText: String {
        medianMs.map { "\(Int($0.rounded())) мс" } ?? "—"
    }

    /// Фраза для Siri, Команд и кнопки Action Button
    var spokenText: String {
        switch verdict {
        case .excellent:
            return "Связь отличная: пинг \(pingText). \(connection)."
        case .good:
            return "Связь нормальная: пинг \(pingText). \(connection)."
        case .poor:
            if reached < total {
                return "Связь плохая: ответили \(reached) из \(total) узлов, пинг \(pingText). \(connection)."
            }
            return "Связь медленная: пинг \(pingText). \(connection)."
        case .offline:
            return "Нет связи: ни один из \(total) узлов не отвечает. \(connection)."
        }
    }

    /// Заголовок и текст уведомления с результатом (кнопка в Пункте управления)
    var notificationTitle: String { "Связь: \(verdict.title.lowercased())" }

    var notificationBody: String {
        verdict == .offline ? "Ни один узел не отвечает · \(connection)" : "Пинг \(pingText) · \(connection)"
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
}

// MARK: - Замер

protocol QuickCheckConnecting: Sendable {
    /// Время установки TCP-соединения с узлом в миллисекундах; `nil` — не удалось за `timeout` секунд
    func connect(to host: QuickCheckHost, timeout: TimeInterval) async -> Double?
}

enum QuickCheck {
    /// На ответ узла отводится столько секунд: проверка должна уложиться в лимит расширения и в терпение человека
    static let timeout: TimeInterval = 2.0

    /// Опрашивает узлы одновременно и собирает итог. `connection` подставляется в тестах; обычно определяется по системе.
    static func run(
        hosts: [QuickCheckHost] = QuickCheckHost.defaults,
        connector: any QuickCheckConnecting = TCPQuickCheckConnector(),
        connection: String? = nil,
        timeout: TimeInterval = QuickCheck.timeout,
        now: Date = Date()
    ) async -> QuickCheckResult {
        let probes = await withTaskGroup(of: (Int, QuickCheckProbe).self) { group in
            for (index, host) in hosts.enumerated() {
                group.addTask {
                    let latency = await connector.connect(to: host, timeout: timeout)
                    return (index, QuickCheckProbe(host: host, latencyMs: latency))
                }
            }
            var collected: [(Int, QuickCheckProbe)] = []
            for await item in group {
                collected.append(item)
            }
            // Порядок узлов — как в списке, а не как они ответили
            return collected.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        let label: String
        if let connection {
            label = connection
        } else {
            label = await QuickCheckNetwork.currentLabel()
        }
        return QuickCheckResult(time: now, probes: probes, connection: label)
    }
}

// MARK: - Настоящее соединение

/// Одна попытка соединения: ответ приходит из обработчика состояния, срок — из таймера; сработать должен ровно один
private final class TCPAttempt: @unchecked Sendable {
    private let connection: NWConnection
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Double?, Never>?
    private var finished = false
    private var startedAt: UInt64 = 0

    init?(host: QuickCheckHost) {
        guard let port = NWEndpoint.Port(rawValue: host.port) else { return nil }
        connection = NWConnection(host: NWEndpoint.Host(host.host), port: port, using: .tcp)
    }

    func run(timeout: TimeInterval) async -> Double? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            lock.lock()
            self.continuation = continuation
            startedAt = DispatchTime.now().uptimeNanoseconds
            lock.unlock()

            connection.stateUpdateHandler = { [weak self] state in
                self?.handle(state)
            }
            connection.start(queue: DispatchQueue.global(qos: .userInitiated))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(nil)
            }
        }
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            lock.lock()
            let started = startedAt
            lock.unlock()
            let elapsed = DispatchTime.now().uptimeNanoseconds &- started
            finish(Double(elapsed) / 1_000_000)
        case .failed, .cancelled:
            finish(nil)
        default:
            break
        }
    }

    private func finish(_ value: Double?) {
        lock.lock()
        guard !finished, let continuation else {
            lock.unlock()
            return
        }
        finished = true
        self.continuation = nil
        lock.unlock()
        connection.cancel()
        continuation.resume(returning: value)
    }
}

struct TCPQuickCheckConnector: QuickCheckConnecting {
    func connect(to host: QuickCheckHost, timeout: TimeInterval) async -> Double? {
        guard let attempt = TCPAttempt(host: host) else { return nil }
        return await attempt.run(timeout: timeout)
    }
}

// MARK: - Тип подключения

enum QuickCheckNetwork {
    /// Подпись для интерфейса: слова совпадают с теми, по которым виджет выбирает значок
    static func label(for path: NWPath) -> String {
        guard path.status == .satisfied else { return "Нет сети" }
        if path.usesInterfaceType(.wifi) { return "Wi-Fi" }
        if path.usesInterfaceType(.cellular) { return "Мобильная сеть" }
        if path.usesInterfaceType(.wiredEthernet) { return "Ethernet" }
        return "Сеть"
    }

    /// Текущее подключение: первое сообщение монитора пути приходит сразу; если нет, через секунду отдаём «Сеть»
    static func currentLabel() async -> String {
        await PathSnapshot().read()
    }
}

private final class PathSnapshot: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Never>?
    private var finished = false

    func read() async -> String {
        await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            monitor.pathUpdateHandler = { [weak self] path in
                self?.finish(QuickCheckNetwork.label(for: path))
            }
            monitor.start(queue: DispatchQueue.global(qos: .userInitiated))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.finish("Сеть")
            }
        }
    }

    private func finish(_ label: String) {
        lock.lock()
        guard !finished, let continuation else {
            lock.unlock()
            return
        }
        finished = true
        self.continuation = nil
        lock.unlock()
        monitor.cancel()
        continuation.resume(returning: label)
    }
}

// MARK: - Журнал замеров

struct QuickCheckSample: Codable, Sendable, Equatable {
    let time: Date
    /// Медианный пинг; `nil` — не ответил ни один узел
    let pingMs: Double?
    let reached: Int
    let total: Int
    let connection: String

    /// Ни один узел не ответил
    var isDown: Bool { total > 0 && reached == 0 }
    /// Хотя бы один узел не ответил
    var hasFailures: Bool { total > 0 && reached < total }
}

/// Общий журнал замеров в контейнере App Group: пишут приложение, виджеты и кнопка проверки, читает утренняя сводка.
/// Хранится не больше `maxSamples` последних замеров (при замере раз в 5–15 минут это несколько суток).
final class QuickCheckLog: @unchecked Sendable {
    static let maxSamples = 800
    static let groupIdentifier = "group.com.samvel.netpulse"

    static let shared = QuickCheckLog(fileURL: QuickCheckLog.defaultFileURL())

    private let fileURL: URL?
    private let lock = NSLock()

    init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    static func defaultFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent("netpulse_quick_samples.json")
    }

    /// Замеры не старше `since`, старые первыми
    func samples(since: Date = .distantPast) -> [QuickCheckSample] {
        lock.lock()
        defer { lock.unlock() }
        return load().filter { $0.time >= since }
    }

    func append(_ sample: QuickCheckSample) {
        lock.lock()
        defer { lock.unlock() }
        store(load() + [sample])
    }

    /// Для замеров приложения, которые идут каждые несколько секунд: в журнал попадает не чаще одного раза
    /// в `minInterval` секунд. Возвращает `true`, если замер записан.
    @discardableResult
    func appendIfDue(_ sample: QuickCheckSample, minInterval: TimeInterval = 300) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let existing = load()
        if let last = existing.last, sample.time.timeIntervalSince(last.time) < minInterval {
            return false
        }
        store(existing + [sample])
        return true
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    private func load() -> [QuickCheckSample] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return ((try? decoder.decode([QuickCheckSample].self, from: data)) ?? []).sorted { $0.time < $1.time }
    }

    private func store(_ samples: [QuickCheckSample]) {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let kept = Array(samples.sorted { $0.time < $1.time }.suffix(Self.maxSamples))
        if let data = try? encoder.encode(kept) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - Итоги за сутки

struct DailySummary: Equatable, Sendable {
    let checks: Int
    let averagePingMs: Double?
    /// Обрывы: серии подряд идущих замеров, где не ответил ни один узел
    let outages: Int
    /// Час суток (0...23), в который связь была хуже всего; `nil` — хуже других часов не было
    let worstHour: Int?

    /// Слабый час называется, если в нём были сбои или средний пинг не меньше этого значения
    static let slowHourPingMs = 100.0

    static func make(samples: [QuickCheckSample], calendar: Calendar = .current) -> DailySummary {
        let ordered = samples.sorted { $0.time < $1.time }
        let pings = ordered.compactMap(\.pingMs)
        let average = pings.isEmpty ? nil : pings.reduce(0, +) / Double(pings.count)

        var outages = 0
        var inOutage = false
        for sample in ordered {
            let down = sample.isDown
            if down && !inOutage { outages += 1 }
            inOutage = down
        }

        var failures: [Int: Int] = [:]
        var pingSums: [Int: Double] = [:]
        var pingCounts: [Int: Int] = [:]
        for sample in ordered {
            let hour = calendar.component(.hour, from: sample.time)
            if sample.hasFailures { failures[hour, default: 0] += 1 }
            if let ping = sample.pingMs {
                pingSums[hour, default: 0] += ping
                pingCounts[hour, default: 0] += 1
            }
        }
        func averagePing(_ hour: Int) -> Double {
            guard let count = pingCounts[hour], count > 0 else { return 0 }
            return (pingSums[hour] ?? 0) / Double(count)
        }

        var worst: Int?
        if let top = failures.values.max() {
            // Больше всего сбоев; при равенстве — где пинг выше, затем более ранний час
            worst = failures.filter { $0.value == top }.keys.sorted { lhs, rhs in
                let (a, b) = (averagePing(lhs), averagePing(rhs))
                return a != b ? a > b : lhs < rhs
            }.first
        } else if let slowest = pingCounts.keys.sorted(by: { lhs, rhs in
            let (a, b) = (averagePing(lhs), averagePing(rhs))
            return a != b ? a > b : lhs < rhs
        }).first, averagePing(slowest) >= slowHourPingMs {
            worst = slowest
        }

        return DailySummary(checks: ordered.count, averagePingMs: average, outages: outages, worstHour: worst)
    }
}
