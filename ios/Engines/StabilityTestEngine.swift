//
//  StabilityTestEngine.swift
//  NetPulse
//
//  Тест стабильности: несколько минут подряд раз в секунду опрашивает узлы и копит потери, задержку, джиттер
//  и обрывы. Это не замер скорости, а проверка, насколько ровно держится связь.
//

import Foundation
import Observation
import UIKit

// MARK: - Опрос узлов

public protocol StabilityProbing: Sendable {
    /// Опрашивает все узлы одновременно; ответ — по одному результату на узел
    func probe(hosts: [StabilityHost]) async -> [StabilityProbe]
}

/// Настоящий опрос: время TCP-соединения с узлом (как в мониторинге), таймаут 1,5 секунды
public final class LiveStabilityProber: StabilityProbing, @unchecked Sendable {
    private let engine: PingEngine

    public init(timeout: TimeInterval = 1.5) {
        engine = PingEngine(timeout: timeout)
    }

    public func probe(hosts: [StabilityHost]) async -> [StabilityProbe] {
        await withTaskGroup(of: StabilityProbe.self, returning: [StabilityProbe].self) { group in
            for (index, host) in hosts.enumerated() {
                let target = HostTarget(
                    name: host.name,
                    address: host.address,
                    tcpPort: host.port,
                    isGateway: host.isGateway
                )
                group.addTask { [engine] in
                    let record = await engine.pingTarget(target)
                    return StabilityProbe(host: index, latencyMs: record.isSuccess ? record.latencyMs : nil)
                }
            }
            var all: [StabilityProbe] = []
            for await probe in group {
                all.append(probe)
            }
            return all
        }
    }
}

// MARK: - Работа в фоне

/// Системная фоновая задача, которая не даёт iOS усыпить приложение, пока идёт тест (iOS 26 и новее).
/// Здесь только то, что нужно прогону; настоящая реализация — `ContinuedProcessingHost`, в тестах — подставная.
@MainActor
public protocol StabilityBackgroundHosting: AnyObject {
    /// Идёт ли тест под защитой системной задачи
    var isActive: Bool { get }
    /// Просит у системы время на работу в фоне. `false` — просьбу не приняли (тест идёт, пока приложение открыто).
    /// `onExpire` вызывается, если система или пользователь (кнопкой в системном окне) прекратили задачу.
    func begin(totalSeconds: Int, title: String, subtitle: String, onExpire: @escaping @MainActor () -> Void) -> Bool
    func update(completedSeconds: Int, subtitle: String)
    func end(success: Bool)
}

// MARK: - Прогон теста

@MainActor
@Observable
public final class StabilityTestRunner {
    public static let shared = StabilityTestRunner(
        prober: LiveStabilityProber(),
        history: StabilityHistoryStore.shared,
        background: ContinuedProcessingHost.shared
    )

    public enum State: Equatable, Sendable {
        case idle
        case running
        case finished
    }

    public enum StopReason: Sendable {
        case completed
        case userStopped
        case systemStopped
    }

    /// Длительности на выбор, секунды
    public static let durationOptions: [Int] = [300, 900, 1_800, 3_600]
    /// Шаг теста по умолчанию, секунд
    public static let defaultTickSeconds: TimeInterval = 1
    /// Тест короче этого не сохраняется в историю
    public static let minSavedSeconds: TimeInterval = 10

    public private(set) var state: State = .idle
    public private(set) var plannedSeconds: TimeInterval = 0
    /// Сколько секунд замеры реально шли (без пауз)
    public private(set) var activeSeconds: TimeInterval = 0
    /// Сколько секунд приложение не работало (его усыпила система)
    public private(set) var pausedSeconds: TimeInterval = 0
    public private(set) var currentLatencyMs: Double?
    public private(set) var lossPercent: Double = 0
    public private(set) var outageCount = 0
    public private(set) var isDownNow = false
    public private(set) var liveBuckets: [StabilityBucket] = []
    public private(set) var hosts: [StabilityHost] = []
    public private(set) var connection = ""
    public private(set) var result: StabilityResult?

    @ObservationIgnored private let prober: any StabilityProbing
    @ObservationIgnored private let history: StabilityHistoryStore
    @ObservationIgnored private let background: (any StabilityBackgroundHosting)?
    @ObservationIgnored private let tickSeconds: TimeInterval
    @ObservationIgnored private let minSavedSeconds: TimeInterval
    @ObservationIgnored private let setScreenAwake: @MainActor (Bool) -> Void
    @ObservationIgnored private var accumulator = StabilityAccumulator(hosts: [], plannedSeconds: 0)
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var startedAt = Date()

    public init(
        prober: any StabilityProbing,
        history: StabilityHistoryStore,
        background: (any StabilityBackgroundHosting)? = nil,
        tickSeconds: TimeInterval = StabilityTestRunner.defaultTickSeconds,
        minSavedSeconds: TimeInterval = StabilityTestRunner.minSavedSeconds,
        setScreenAwake: @escaping @MainActor (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }
    ) {
        self.prober = prober
        self.history = history
        self.background = background
        self.tickSeconds = max(0.001, tickSeconds)
        self.minSavedSeconds = minSavedSeconds
        self.setScreenAwake = setScreenAwake
    }

    public var isRunning: Bool {
        state == .running
    }

    /// Доля пройденного, 0…1
    public var progress: Double {
        plannedSeconds > 0 ? min(1, activeSeconds / plannedSeconds) : 0
    }

    public var remainingSeconds: TimeInterval {
        max(0, plannedSeconds - activeSeconds)
    }

    /// Тест идёт под защитой системной фоновой задачи: приложение можно свернуть
    public var runsInBackground: Bool {
        background?.isActive ?? false
    }

    /// Что тест знает о связи прямо сейчас. Нужно острову: пока приложение свёрнуто, узлы мониторинга не опрашиваются
    /// и остров остался бы без пинга и потерь, а тест их измеряет каждую секунду. `nil` — тест не идёт или данных ещё нет.
    public var islandSnapshot: (pingMs: Double?, lossPercent: Double)? {
        guard state == .running, accumulatorHasData else { return nil }
        return (currentLatencyMs, lossPercent)
    }

    private var accumulatorHasData: Bool {
        accumulator.tickCount >= 2
    }

    // MARK: - Управление

    /// Начинает тест. Вызывать при открытом приложении: системная фоновая задача запрашивается только отсюда.
    public func start(durationSeconds: TimeInterval, hosts: [StabilityHost], connection: String) {
        guard state != .running, durationSeconds > 0, !hosts.isEmpty else { return }

        self.hosts = hosts
        self.connection = connection
        plannedSeconds = durationSeconds
        activeSeconds = 0
        pausedSeconds = 0
        currentLatencyMs = nil
        lossPercent = 0
        outageCount = 0
        isDownNow = false
        liveBuckets = []
        result = nil
        accumulator = StabilityAccumulator(hosts: hosts, plannedSeconds: durationSeconds, tickSeconds: tickSeconds)
        startedAt = Date()
        state = .running
        setScreenAwake(true)
        IslandDiagnostics.shared.log("Тест стабильности начат: \(Int(durationSeconds)) с, узлов: \(hosts.count)", .island)

        let accepted = background?.begin(
            totalSeconds: Int(durationSeconds.rounded()),
            title: "Тест стабильности сети",
            subtitle: "Идёт тест",
            onExpire: { [weak self] in
                self?.finish(.systemStopped)
            }
        ) ?? false
        if !accepted {
            IslandDiagnostics.shared.log("Тест стабильности идёт без системной фоновой задачи: пока приложение открыто", .info)
        }

        runTask = Task { [weak self] in
            await self?.run()
        }
    }

    /// Останавливает тест; уже набранное сохраняется как неполный итог
    public func stop() {
        finish(.userStopped)
    }

    /// Возвращает экран к началу после просмотра итога
    public func reset() {
        guard state != .running else { return }
        state = .idle
        result = nil
    }

    // MARK: - Цикл

    private func run() async {
        var previousTickStart: Date?
        let pauseThreshold = max(3, tickSeconds * 4)

        while !Task.isCancelled, state == .running {
            let tickStart = Date()
            if let previous = previousTickStart {
                let gap = tickStart.timeIntervalSince(previous)
                if gap > pauseThreshold {
                    // Приложение спало: эти секунды не засчитываются, иначе тишину приняли бы за потерю связи
                    pausedSeconds += gap - tickSeconds
                    activeSeconds += tickSeconds
                } else {
                    activeSeconds += max(0, gap)
                }
            }
            previousTickStart = tickStart
            if activeSeconds >= plannedSeconds { break }

            let probes = await prober.probe(hosts: hosts)
            // Пока шёл опрос, тест могли остановить
            guard !Task.isCancelled, state == .running else { return }

            accumulator.add(StabilityTick(offset: activeSeconds, probes: probes))
            publishLiveState()

            let spent = Date().timeIntervalSince(tickStart)
            let wait = max(0.01, tickSeconds - spent)
            try? await Task.sleep(for: .seconds(wait))
        }

        if state == .running {
            finish(.completed)
        }
    }

    private func publishLiveState() {
        currentLatencyMs = accumulator.lastLatencyMs
        lossPercent = accumulator.liveLossPercent
        outageCount = accumulator.liveOutageCount
        isDownNow = accumulator.isDownNow
        liveBuckets = accumulator.liveBuckets

        let remaining = Int(remainingSeconds.rounded(.up))
        let subtitle = remaining >= 60
            ? "Осталось около \(Int((Double(remaining) / 60).rounded(.up))) мин · потери \(StabilityAnalyzer.format(lossPercent)) %"
            : "Осталось \(remaining) с · потери \(StabilityAnalyzer.format(lossPercent)) %"
        background?.update(completedSeconds: Int(activeSeconds), subtitle: subtitle)
    }

    private func finish(_ reason: StopReason) {
        guard state == .running else { return }
        runTask?.cancel()
        runTask = nil

        let finished = accumulator.makeResult(
            startedAt: startedAt,
            connection: connection,
            finishedEarly: reason != .completed,
            pausedSeconds: pausedSeconds
        )
        result = finished
        state = .finished
        activeSeconds = min(max(activeSeconds, finished.activeSeconds), plannedSeconds)
        setScreenAwake(false)
        background?.end(success: reason != .systemStopped)

        if finished.activeSeconds >= minSavedSeconds {
            history.add(finished)
        }
        IslandDiagnostics.shared.log(
            "Тест стабильности завершён (\(reason)): \(finished.verdict.title), потери \(StabilityAnalyzer.format(finished.lossPercent)) %",
            .info
        )
        if reason == .completed {
            HapticManager.shared.notificationSuccess()
        }
    }
}
