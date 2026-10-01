//
//  IslandUpdatePipeline.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Очередь отправки кадров в Live Activity, которая не может «зависнуть».
///
/// Раньше отправка шла так: флаг «идёт отправка» ставился до `await activity.update(...)` и снимался только после
/// возврата вызова. Если система не отвечала (процесс усыпили посреди вызова, активность завершили, оборвалась связь
/// с системной службой), флаг оставался навсегда, а все следующие кадры молча отбрасывались: остров замирал, даже когда
/// приложение открыто, а кнопка «Перезапустить» не помогала — она упиралась в тот же флаг.
///
/// Теперь у отправки есть срок. По его истечении отправка «забывается», её поздний ответ игнорируется, и уходит
/// самый свежий кадр. Если кадры идут быстрее ответов системы, промежуточные пропускаются: нужен только последний.
///
/// Тип обобщённый и не зависит от ActivityKit, поэтому его логика проверяется юнит-тестами.
@MainActor
public final class IslandUpdatePipeline<State: Sendable> {
    public typealias Sender = @MainActor @Sendable (State) async -> Void

    public struct Stats: Equatable, Sendable {
        /// Сколько отправок начато
        public var started = 0
        /// Сколько отправок завершилось в срок
        public var completed = 0
        /// Сколько отправок забыто по сроку (система не ответила)
        public var abandoned = 0
        /// Сколько ответов пришло уже на забытые отправки
        public var lateReplies = 0
        public var lastStartedAt: Date?
        public var lastCompletedAt: Date?
        public var lastDuration: TimeInterval?
        public var longestDuration: TimeInterval = 0

        public init() {}
    }

    private struct Waiting {
        let state: State
        let send: Sender
    }

    private struct InFlight {
        let token: Int
        let state: State
        let startedAt: Date
    }

    public private(set) var stats = Stats()

    /// Вызывается, когда отправка завершилась в срок (для забытых отправок не вызывается)
    public var onCompleted: (@MainActor (State) -> Void)?
    /// Вызывается, когда отправка забыта по сроку; параметр — сколько секунд она шла
    public var onAbandoned: (@MainActor (TimeInterval) -> Void)?

    private let sendTimeout: TimeInterval
    private let clock: @MainActor () -> Date
    private var waiting: Waiting?
    private var inFlight: InFlight?
    private var generation = 0

    public init(sendTimeout: TimeInterval, clock: @escaping @MainActor () -> Date = { Date() }) {
        self.sendTimeout = sendTimeout
        self.clock = clock
    }

    /// Идёт ли сейчас отправка
    public var isSending: Bool {
        inFlight != nil
    }

    /// Сколько секунд идёт текущая отправка (`nil` — не идёт)
    public var inFlightAge: TimeInterval? {
        inFlight.map { clock().timeIntervalSince($0.startedAt) }
    }

    /// Ставит кадр в очередь; более старый ещё не отправленный кадр заменяется
    public func submit(_ state: State, send: @escaping Sender) {
        waiting = Waiting(state: state, send: send)
        pump()
    }

    /// Двигает очередь: забывает зависшую отправку и запускает следующую. Безопасно вызывать часто —
    /// в том числе и тогда, когда новых кадров нет: зависшая отправка забудется в любом случае.
    public func pump() {
        let now = clock()

        if let current = inFlight {
            let age = now.timeIntervalSince(current.startedAt)
            guard age > sendTimeout else { return }
            // Поздний ответ этой отправки опознаётся по номеру поколения и будет проигнорирован
            inFlight = nil
            generation += 1
            stats.abandoned += 1
            onAbandoned?(age)
        }

        guard let next = waiting else { return }
        waiting = nil

        generation += 1
        let token = generation
        inFlight = InFlight(token: token, state: next.state, startedAt: now)
        stats.started += 1
        stats.lastStartedAt = now

        let sender = next.send
        let state = next.state
        Task { @MainActor [weak self] in
            await sender(state)
            self?.finish(token: token)
        }
    }

    /// Сбрасывает очередь и текущую отправку (например, при перезапуске активности): ответ на старую отправку
    /// после этого игнорируется.
    public func reset() {
        generation += 1
        waiting = nil
        inFlight = nil
    }

    private func finish(token: Int) {
        guard let current = inFlight, current.token == token else {
            stats.lateReplies += 1
            return
        }

        let finishedAt = clock()
        let duration = max(0, finishedAt.timeIntervalSince(current.startedAt))
        inFlight = nil
        stats.completed += 1
        stats.lastCompletedAt = finishedAt
        stats.lastDuration = duration
        stats.longestDuration = max(stats.longestDuration, duration)
        onCompleted?(current.state)

        // Пока шла отправка, мог прийти более свежий кадр — отправляем его сразу
        pump()
    }
}
