//
//  StabilityModels.swift
//  NetPulse
//
//  Тест стабильности: данные и расчёты. Здесь нет ни сети, ни интерфейса, поэтому всё проверяется юнит-тестами.
//

import Foundation

// MARK: - Узлы теста

/// Узел, который опрашивает тест
public struct StabilityHost: Codable, Sendable, Equatable, Identifiable {
    public var name: String
    public var address: String
    public var port: Int
    /// Домашний роутер. Помогает отличить проблему в Wi-Fi от проблемы у провайдера; в общие потери не входит.
    public var isGateway: Bool

    public var id: String { address }

    public init(name: String, address: String, port: Int = 443, isGateway: Bool = false) {
        self.name = name
        self.address = address
        self.port = port
        self.isGateway = isGateway
    }

    /// Узлы по умолчанию: три публичных DNS-сервера и, если известен, домашний роутер
    public static func defaults(gateway: String?) -> [StabilityHost] {
        var hosts = [
            StabilityHost(name: "Cloudflare", address: "1.1.1.1", port: 443),
            StabilityHost(name: "Google", address: "8.8.8.8", port: 53),
            StabilityHost(name: "Quad9", address: "9.9.9.9", port: 53)
        ]
        if let gateway, isUsableGateway(gateway) {
            hosts.append(StabilityHost(name: "Роутер", address: gateway, port: 53, isGateway: true))
        }
        return hosts
    }

    /// Адрес роутера годится, только если это обычный IPv4-адрес (а не «gateway», не пусто и не прочерк)
    public static func isUsableGateway(_ address: String) -> Bool {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(part) else { return false }
            return value <= 255
        }
    }
}

// MARK: - Результаты опроса

/// Ответ одного узла в одном шаге теста
public struct StabilityProbe: Sendable, Equatable {
    /// Номер узла в списке узлов теста
    public var host: Int
    /// Задержка, мс; `nil` — узел не ответил
    public var latencyMs: Double?

    public init(host: Int, latencyMs: Double?) {
        self.host = host
        self.latencyMs = latencyMs
    }

    public var answered: Bool {
        latencyMs != nil
    }
}

/// Один шаг теста: ответы всех узлов
public struct StabilityTick: Sendable, Equatable {
    /// Сколько секунд работы теста прошло до этого шага (паузы, когда приложение спало, не считаются)
    public var offset: TimeInterval
    public var probes: [StabilityProbe]

    public init(offset: TimeInterval, probes: [StabilityProbe]) {
        self.offset = offset
        self.probes = probes
    }
}

// MARK: - Итог теста

/// Обрыв: интернета не было несколько шагов подряд
public struct StabilityOutage: Codable, Sendable, Equatable {
    /// Секунды от начала теста
    public var start: TimeInterval
    public var duration: TimeInterval
    /// Отвечал ли роутер, пока интернета не было; `nil` — роутер в тесте не участвовал
    public var gatewayAnswered: Bool?

    public init(start: TimeInterval, duration: TimeInterval, gatewayAnswered: Bool? = nil) {
        self.start = start
        self.duration = duration
        self.gatewayAnswered = gatewayAnswered
    }
}

/// Отрезок графика: средняя задержка и потери за несколько секунд
public struct StabilityBucket: Codable, Sendable, Equatable, Identifiable {
    public var start: TimeInterval
    public var averageMs: Double?
    public var lossPercent: Double
    /// Весь отрезок интернета не было
    public var isDown: Bool

    public var id: TimeInterval { start }

    public init(start: TimeInterval, averageMs: Double?, lossPercent: Double, isDown: Bool) {
        self.start = start
        self.averageMs = averageMs
        self.lossPercent = lossPercent
        self.isDown = isDown
    }
}

/// Итог по одному узлу
public struct StabilityHostSummary: Codable, Sendable, Equatable, Identifiable {
    public var name: String
    public var address: String
    public var isGateway: Bool
    public var sent: Int
    public var lost: Int
    public var averageMs: Double?
    public var maxMs: Double?
    public var jitterMs: Double?

    public var id: String { address }

    public var lossPercent: Double {
        sent == 0 ? 0 : Double(lost) / Double(sent) * 100
    }

    public init(
        name: String, address: String, isGateway: Bool, sent: Int, lost: Int,
        averageMs: Double?, maxMs: Double?, jitterMs: Double?
    ) {
        self.name = name
        self.address = address
        self.isGateway = isGateway
        self.sent = sent
        self.lost = lost
        self.averageMs = averageMs
        self.maxMs = maxMs
        self.jitterMs = jitterMs
    }
}

/// Итог теста стабильности
public struct StabilityResult: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    /// На сколько секунд тест был рассчитан
    public var plannedSeconds: Double
    /// Сколько секунд замеры реально шли (без пауз)
    public var activeSeconds: Double
    /// Сколько секунд приложение не работало (свёрнуто и усыплено системой): в замерах эти секунды пусты
    public var pausedSeconds: Double
    /// Тест остановлен до конца (пользователем или системой)
    public var finishedEarly: Bool
    /// «Wi-Fi», «4G (LTE)» и т. п.
    public var connection: String
    public var hosts: [StabilityHostSummary]
    /// Запросов к узлам интернета (без роутера) и сколько из них осталось без ответа
    public var sent: Int
    public var lost: Int
    public var averageMs: Double?
    public var minMs: Double?
    public var maxMs: Double?
    /// Задержка, ниже которой уложились 95 % ответов
    public var p95Ms: Double?
    public var jitterMs: Double?
    public var outages: [StabilityOutage]
    public var buckets: [StabilityBucket]
    public var bucketSeconds: Double

    public init(
        id: UUID = UUID(), startedAt: Date, plannedSeconds: Double, activeSeconds: Double, pausedSeconds: Double,
        finishedEarly: Bool, connection: String, hosts: [StabilityHostSummary], sent: Int, lost: Int,
        averageMs: Double?, minMs: Double?, maxMs: Double?, p95Ms: Double?, jitterMs: Double?,
        outages: [StabilityOutage], buckets: [StabilityBucket], bucketSeconds: Double
    ) {
        self.id = id
        self.startedAt = startedAt
        self.plannedSeconds = plannedSeconds
        self.activeSeconds = activeSeconds
        self.pausedSeconds = pausedSeconds
        self.finishedEarly = finishedEarly
        self.connection = connection
        self.hosts = hosts
        self.sent = sent
        self.lost = lost
        self.averageMs = averageMs
        self.minMs = minMs
        self.maxMs = maxMs
        self.p95Ms = p95Ms
        self.jitterMs = jitterMs
        self.outages = outages
        self.buckets = buckets
        self.bucketSeconds = bucketSeconds
    }

    public var lossPercent: Double {
        sent == 0 ? 0 : Double(lost) / Double(sent) * 100
    }

    public var outageSeconds: Double {
        outages.reduce(0) { $0 + $1.duration }
    }

    public var longestOutageSeconds: Double {
        outages.map(\.duration).max() ?? 0
    }

    public var gateway: StabilityHostSummary? {
        hosts.first { $0.isGateway }
    }

    public var verdict: StabilityVerdict {
        StabilityAnalyzer.verdict(for: self)
    }
}

// MARK: - Накопление шагов

/// Собирает шаги теста в итог. Не знает ни о сети, ни о времени: шаги приходят готовыми, поэтому
/// тесты подают заранее придуманные ответы и проверяют арифметику.
public struct StabilityAccumulator: Sendable {
    /// Столько шагов подряд без ответа интернета считаются обрывом (один шаг — случайный сбой)
    public static let minOutageTicks = 2
    /// Сколько отрезков самое большее на графике
    public static let targetBucketCount = 120
    public static let minBucketSeconds: TimeInterval = 5

    public let hosts: [StabilityHost]
    public let plannedSeconds: TimeInterval
    public let tickSeconds: TimeInterval
    public let bucketSeconds: TimeInterval

    private struct HostTally: Sendable {
        var sent = 0
        var lost = 0
        var sumMs = 0.0
        var answered = 0
        var maxMs: Double?
        var lastMs: Double?
        var jitterSum = 0.0
        var jitterCount = 0
    }

    private struct BucketTally: Sendable {
        var sent = 0
        var lost = 0
        var latencySum = 0.0
        var latencyCount = 0
        var ticks = 0
        var downTicks = 0
    }

    private var tallies: [HostTally]
    private var internetLatencies: [Double] = []
    private var bucketTallies: [Int: BucketTally] = [:]
    private var outages: [StabilityOutage] = []
    private var downStart: TimeInterval?
    private var downLastOffset: TimeInterval = 0
    private var downTicks = 0
    private var downGatewayAnswered = 0
    private var downGatewayTotal = 0
    private var lastOffset: TimeInterval?

    public private(set) var tickCount = 0
    /// Средняя задержка по узлам интернета в последнем шаге; `nil` — никто не ответил
    public private(set) var lastLatencyMs: Double?
    /// Интернета не было в последнем шаге
    public private(set) var isDownNow = false

    public init(hosts: [StabilityHost], plannedSeconds: TimeInterval, tickSeconds: TimeInterval = 1) {
        self.hosts = hosts
        self.plannedSeconds = plannedSeconds
        self.tickSeconds = max(0.001, tickSeconds)
        self.bucketSeconds = Self.bucketSeconds(forPlanned: plannedSeconds)
        self.tallies = Array(repeating: HostTally(), count: hosts.count)
    }

    /// Ширина отрезка графика: чтобы их было не больше 120, но не уже 5 секунд
    public static func bucketSeconds(forPlanned planned: TimeInterval) -> TimeInterval {
        guard planned.isFinite, planned > 0 else { return minBucketSeconds }
        return max(minBucketSeconds, (planned / Double(targetBucketCount)).rounded(.up))
    }

    public mutating func add(_ tick: StabilityTick) {
        tickCount += 1
        lastOffset = tick.offset

        var internetTotal = 0
        var internetAnswered = 0
        var internetLatencySum = 0.0
        var bucket = bucketTallies[bucketIndex(for: tick.offset)] ?? BucketTally()
        var gatewayTotal = 0
        var gatewayAnswered = 0

        for probe in tick.probes where hosts.indices.contains(probe.host) {
            let isGateway = hosts[probe.host].isGateway
            tallies[probe.host].sent += 1

            var answeredMs: Double?
            if let ms = probe.latencyMs, ms.isFinite, ms >= 0 {
                answeredMs = ms
                var tally = tallies[probe.host]
                tally.sumMs += ms
                tally.answered += 1
                tally.maxMs = max(tally.maxMs ?? ms, ms)
                if let previous = tally.lastMs {
                    tally.jitterSum += abs(ms - previous)
                    tally.jitterCount += 1
                }
                tally.lastMs = ms
                tallies[probe.host] = tally
            } else {
                tallies[probe.host].lost += 1
            }

            if isGateway {
                gatewayTotal += 1
                if answeredMs != nil { gatewayAnswered += 1 }
            } else {
                internetTotal += 1
                bucket.sent += 1
                if let ms = answeredMs {
                    internetAnswered += 1
                    internetLatencySum += ms
                    internetLatencies.append(ms)
                    bucket.latencySum += ms
                    bucket.latencyCount += 1
                } else {
                    bucket.lost += 1
                }
            }
        }

        lastLatencyMs = internetAnswered > 0 ? internetLatencySum / Double(internetAnswered) : nil
        let down = internetTotal > 0 && internetAnswered == 0
        isDownNow = down
        bucket.ticks += 1
        if down { bucket.downTicks += 1 }
        bucketTallies[bucketIndex(for: tick.offset)] = bucket

        trackOutage(down: down, offset: tick.offset, gatewayTotal: gatewayTotal, gatewayAnswered: gatewayAnswered)
    }

    /// Живые числа для экрана во время теста
    public var liveLossPercent: Double {
        let internet = tallies.indices.filter { !hosts[$0].isGateway }
        let sent = internet.reduce(0) { $0 + tallies[$1].sent }
        let lost = internet.reduce(0) { $0 + tallies[$1].lost }
        return sent == 0 ? 0 : Double(lost) / Double(sent) * 100
    }

    /// Обрывы, уже завершившиеся, и идущий сейчас (если он уже тянется достаточно долго)
    public var liveOutageCount: Int {
        outages.count + (downTicks >= Self.minOutageTicks ? 1 : 0)
    }

    /// Отрезки графика на сейчас
    public var liveBuckets: [StabilityBucket] {
        makeBuckets()
    }

    // MARK: Итог

    public func makeResult(
        id: UUID = UUID(),
        startedAt: Date,
        connection: String,
        finishedEarly: Bool,
        pausedSeconds: TimeInterval
    ) -> StabilityResult {
        var closed = outages
        if downTicks >= Self.minOutageTicks, let start = downStart {
            closed.append(openOutage(start: start))
        }

        let internet = hosts.indices.filter { !hosts[$0].isGateway }
        let sent = internet.reduce(0) { $0 + tallies[$1].sent }
        let lost = internet.reduce(0) { $0 + tallies[$1].lost }
        let jitterSum = internet.reduce(0.0) { $0 + tallies[$1].jitterSum }
        let jitterCount = internet.reduce(0) { $0 + tallies[$1].jitterCount }
        let sorted = internetLatencies.sorted()
        let active = tickCount == 0 ? 0 : (lastOffset ?? 0) + tickSeconds

        let summaries = hosts.indices.map { index -> StabilityHostSummary in
            let tally = tallies[index]
            let jitter = tally.jitterCount > 0 ? tally.jitterSum / Double(tally.jitterCount) : nil
            return StabilityHostSummary(
                name: hosts[index].name,
                address: hosts[index].address,
                isGateway: hosts[index].isGateway,
                sent: tally.sent,
                lost: tally.lost,
                averageMs: tally.answered > 0 ? tally.sumMs / Double(tally.answered) : nil,
                maxMs: tally.maxMs,
                jitterMs: jitter
            )
        }

        return StabilityResult(
            id: id,
            startedAt: startedAt,
            plannedSeconds: plannedSeconds,
            activeSeconds: active,
            pausedSeconds: pausedSeconds,
            finishedEarly: finishedEarly,
            connection: connection,
            hosts: summaries,
            sent: sent,
            lost: lost,
            averageMs: sorted.isEmpty ? nil : sorted.reduce(0, +) / Double(sorted.count),
            minMs: sorted.first,
            maxMs: sorted.last,
            p95Ms: Self.percentile(0.95, of: sorted),
            jitterMs: jitterCount > 0 ? jitterSum / Double(jitterCount) : nil,
            outages: closed,
            buckets: makeBuckets(),
            bucketSeconds: bucketSeconds
        )
    }

    /// Значение, ниже которого лежит доля `fraction` отсортированных измерений (метод ближайшего ранга)
    static func percentile(_ fraction: Double, of sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[min(sorted.count - 1, max(0, rank - 1))]
    }

    // MARK: Внутреннее

    private func bucketIndex(for offset: TimeInterval) -> Int {
        Int((max(0, offset) / bucketSeconds).rounded(.down))
    }

    private func makeBuckets() -> [StabilityBucket] {
        bucketTallies.keys.sorted().compactMap { key -> StabilityBucket? in
            guard let tally = bucketTallies[key], tally.ticks > 0 else { return nil }
            return StabilityBucket(
                start: Double(key) * bucketSeconds,
                averageMs: tally.latencyCount > 0 ? tally.latencySum / Double(tally.latencyCount) : nil,
                lossPercent: tally.sent == 0 ? 0 : Double(tally.lost) / Double(tally.sent) * 100,
                isDown: tally.downTicks == tally.ticks
            )
        }
    }

    private mutating func trackOutage(down: Bool, offset: TimeInterval, gatewayTotal: Int, gatewayAnswered: Int) {
        if down {
            if downStart == nil {
                downStart = offset
                downTicks = 0
                downGatewayAnswered = 0
                downGatewayTotal = 0
            }
            downTicks += 1
            downLastOffset = offset
            downGatewayAnswered += gatewayAnswered
            downGatewayTotal += gatewayTotal
        } else {
            if downTicks >= Self.minOutageTicks, let start = downStart {
                outages.append(openOutage(start: start))
            }
            downStart = nil
            downTicks = 0
        }
    }

    private func openOutage(start: TimeInterval) -> StabilityOutage {
        var gateway: Bool?
        if downGatewayTotal > 0 {
            gateway = Double(downGatewayAnswered) / Double(downGatewayTotal) >= 0.5
        }
        return StabilityOutage(
            start: start,
            duration: downLastOffset - start + tickSeconds,
            gatewayAnswered: gateway
        )
    }
}

// MARK: - Вывод

public enum StabilityLevel: Int, Sendable, Comparable {
    /// Тест шёл слишком мало, чтобы делать выводы
    case insufficient = 0
    case excellent = 1
    case good = 2
    case unstable = 3
    case bad = 4

    public static func < (lhs: StabilityLevel, rhs: StabilityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct StabilityVerdict: Sendable, Equatable {
    public let level: StabilityLevel
    public let title: String
    /// Цифры, на которых держится вывод
    public let summary: String
    /// Вероятная причина, если связь нестабильна и её можно назвать
    public let cause: String?
}

/// Оценка теста. Пороги подобраны под обычную жизнь: видеозвонок, игра и стриминг страдают при потерях выше
/// процента, при обрывах и при задержке выше 200 мс.
public enum StabilityAnalyzer {
    /// Меньше этого теста не хватает, чтобы судить
    public static let minActiveSeconds: TimeInterval = 30
    public static let minProbes = 60

    public static func verdict(for result: StabilityResult) -> StabilityVerdict {
        guard result.activeSeconds >= minActiveSeconds, result.sent >= minProbes else {
            return StabilityVerdict(
                level: .insufficient,
                title: "Мало данных",
                summary: "Тест шёл \(Int(result.activeSeconds.rounded())) с: для вывода нужно хотя бы \(Int(minActiveSeconds)) секунд. Запустите тест на 5 минут или дольше.",
                cause: nil
            )
        }

        let loss = result.lossPercent
        let longest = result.longestOutageSeconds
        let p95 = result.p95Ms ?? 0
        let jitter = result.jitterMs ?? 0

        let level: StabilityLevel
        if loss > 5 || longest >= 10 || result.outages.count >= 3 || p95 > 400 {
            level = .bad
        } else if loss > 1 || !result.outages.isEmpty || p95 > 200 || jitter > 40 {
            level = .unstable
        } else if loss > 0.3 || p95 > 100 || jitter > 20 {
            level = .good
        } else {
            level = .excellent
        }

        let title: String
        switch level {
        case .excellent: title = "Связь стабильная"
        case .good: title = "Связь хорошая, есть мелкие колебания"
        case .unstable: title = "Связь нестабильная"
        case .bad: title = "Связь плохая"
        case .insufficient: title = "Мало данных"
        }

        return StabilityVerdict(level: level, title: title, summary: summary(for: result), cause: level >= .unstable ? cause(for: result) : nil)
    }

    private static func summary(for result: StabilityResult) -> String {
        var parts = ["Потеряно \(format(result.lossPercent)) % запросов"]
        if result.outages.isEmpty {
            parts.append("обрывов не было")
        } else {
            parts.append("обрывов: \(result.outages.count), самый долгий \(Int(result.longestOutageSeconds.rounded())) с")
        }
        if let p95 = result.p95Ms {
            parts.append("в 95 % случаев ответ быстрее \(Int(p95.rounded())) мс")
        }
        return parts.joined(separator: ", ") + "."
    }

    /// Где искать причину. Роутер отвечает без потерь, а интернет рвётся — вероятно, провайдер. Теряется уже до
    /// роутера — Wi-Fi. Без роутера (мобильная сеть) различить это нельзя, и приложение так и говорит.
    private static func cause(for result: StabilityResult) -> String? {
        guard let gateway = result.gateway, gateway.sent > 0 else {
            return "На мобильной сети приложение не отличит слабый сигнал от проблем оператора. Если обрывы повторяются в одном и том же месте, запишите там маршрут."
        }
        let outagesWithRouterDown = result.outages.filter { $0.gatewayAnswered == false }.count
        if gateway.lossPercent > 1 || outagesWithRouterDown > 0 {
            return "Пакеты теряются уже на пути до роутера (\(format(gateway.lossPercent)) %): проблема в вашей сети Wi-Fi — слабый сигнал, помехи или перегруженный канал. Подойдите ближе к роутеру или проверьте связь по кабелю."
        }
        return "Роутер отвечает без потерь, а до интернета связь рвётся: вероятнее всего, дело в провайдере или в линии до него. Результат теста можно показать провайдеру."
    }

    /// «0.4» или «12»: до десятых, без лишнего нуля
    static func format(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}

// MARK: - Тексты для отчёта

/// Итог теста словами: для строки в PDF-отчёте провайдеру и для «Поделиться»
public enum StabilityReportText {
    /// «15 мин» или «40 с»
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "—" }
        return seconds >= 60 ? "\(Int((seconds / 60).rounded())) мин" : "\(Int(seconds.rounded())) с"
    }

    /// «5:07» — отметка времени от начала теста
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Одна строка для PDF-отчёта: когда, где, что показал тест
    public static func line(for result: StabilityResult) -> String {
        let when = result.startedAt.formatted(date: .abbreviated, time: .shortened)
        var parts = [when, result.connection, duration(result.activeSeconds)]
        parts.append("потери \(StabilityAnalyzer.format(result.lossPercent)) %")
        if result.outages.isEmpty {
            parts.append("обрывов нет")
        } else {
            parts.append("обрывов: \(result.outages.count), самый долгий \(Int(result.longestOutageSeconds.rounded())) с")
        }
        if let average = result.averageMs {
            parts.append("задержка в среднем \(Int(average.rounded())) мс")
        }
        return parts.joined(separator: " · ") + ". " + result.verdict.title + "."
    }

    /// Полный текст итога, которым можно поделиться
    public static func text(for result: StabilityResult) -> String {
        let verdict = result.verdict
        var lines = [
            "Тест стабильности интернета (NetPulse)",
            "Дата: \(result.startedAt.formatted(date: .long, time: .shortened))",
            "Подключение: \(result.connection)"
        ]
        var length = "Длительность: \(duration(result.activeSeconds))"
        if result.finishedEarly {
            length += " (остановлен до конца, планировалось \(duration(result.plannedSeconds)))"
        }
        lines.append(length)
        if result.pausedSeconds >= 5 {
            lines.append("Приложение не работало \(duration(result.pausedSeconds)): в эти секунды замеров нет.")
        }
        lines.append("Итог: \(verdict.title)")
        lines.append(verdict.summary)

        if let average = result.averageMs {
            var latency = "Задержка: в среднем \(Int(average.rounded())) мс"
            if let p95 = result.p95Ms { latency += ", 95 % ответов быстрее \(Int(p95.rounded())) мс" }
            if let maximum = result.maxMs { latency += ", максимум \(Int(maximum.rounded())) мс" }
            if let jitter = result.jitterMs { latency += ", джиттер \(Int(jitter.rounded())) мс" }
            lines.append(latency)
        }

        if !result.hosts.isEmpty {
            lines.append("Узлы:")
            for host in result.hosts {
                var line = "• \(host.name): потери \(StabilityAnalyzer.format(host.lossPercent)) %"
                if let average = host.averageMs { line += ", задержка \(Int(average.rounded())) мс" }
                lines.append(line)
            }
        }

        if !result.outages.isEmpty {
            lines.append("Обрывы:")
            for outage in result.outages {
                var line = "• на \(clock(outage.start)) от начала, \(Int(outage.duration.rounded())) с"
                if let router = outage.gatewayAnswered {
                    line += router ? " (роутер отвечал)" : " (роутер тоже не отвечал)"
                }
                lines.append(line)
            }
        }

        if let cause = verdict.cause {
            lines.append(cause)
        }
        lines.append("Измерено с телефона по времени соединения с узлами; причину приложение определить не может.")
        return lines.joined(separator: "\n")
    }
}
