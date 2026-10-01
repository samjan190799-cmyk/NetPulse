//
//  IslandDiagnostics.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import UIKit
#if canImport(os)
import os
#endif

// MARK: - Классификация пауз цикла обновления

/// Разбор пауз в цикле обновления острова. Цикл тикает раз в секунду: если между двумя тиками прошло заметно больше,
/// значит, код не выполнялся. В фоне это означает, что iOS приостановила приложение (остров замирает именно поэтому).
public enum LoopTiming {
    /// Порог паузы в секундах: тик занимает около секунды, всё, что дольше, — остановка
    public static let pauseThreshold: TimeInterval = 4

    public enum Verdict: Equatable, Sendable {
        case normal
        /// Предыдущий тик был в фоне: приложение приостановили (или завершили и снова запустили)
        case suspendedInBackground(seconds: TimeInterval)
        /// Предыдущий тик был при открытом приложении: остановка главного потока, а не приостановка системой
        case stalledInForeground(seconds: TimeInterval)
    }

    public static func classify(gap: TimeInterval, previousTickWasBackground: Bool) -> Verdict {
        guard gap > pauseThreshold else { return .normal }
        return previousTickWasBackground ? .suspendedInBackground(seconds: gap) : .stalledInForeground(seconds: gap)
    }
}

// MARK: - Сведения о здоровье острова

/// Снимок состояния конвейера обновления острова для экрана диагностики
public struct IslandHealthSnapshot: Equatable, Sendable {
    /// Состояние активности в iOS: активна, устарела, завершена и т. д.
    public var activityText: String
    /// Сколько секунд назад остров успешно обновился (`nil` — ещё ни разу)
    public var secondsSinceLastUpdate: TimeInterval?
    /// Сколько кадров отправлено успешно
    public var sent: Int
    /// Сколько отправок забыто, потому что система не ответила
    public var abandoned: Int
    /// Сколько ответов пришло на уже забытые отправки
    public var lateReplies: Int
    public var longestSendSeconds: TimeInterval
    /// Сколько секунд идёт текущая отправка (`nil` — не идёт)
    public var inFlightSeconds: TimeInterval?

    public init(
        activityText: String = "нет",
        secondsSinceLastUpdate: TimeInterval? = nil,
        sent: Int = 0,
        abandoned: Int = 0,
        lateReplies: Int = 0,
        longestSendSeconds: TimeInterval = 0,
        inFlightSeconds: TimeInterval? = nil
    ) {
        self.activityText = activityText
        self.secondsSinceLastUpdate = secondsSinceLastUpdate
        self.sent = sent
        self.abandoned = abandoned
        self.lateReplies = lateReplies
        self.longestSendSeconds = longestSendSeconds
        self.inFlightSeconds = inFlightSeconds
    }
}

// MARK: - Журнал

/// Журнал событий острова и фонового режима.
///
/// Остров замирает по причинам, которые снаружи не видно: приложение усыпили, его закрыла система, обновление
/// «зависло», активность завершена. Журнал записывает именно эти события и переживает перезапуск приложения, поэтому
/// после замирания можно открыть «Диагностику острова» и увидеть, что произошло и когда. Координаты и сетевые адреса
/// в журнал не попадают.
@MainActor
public final class IslandDiagnostics {
    public static let shared = IslandDiagnostics(defaults: .standard, fileURL: IslandDiagnostics.defaultLogURL)

    public enum Kind: String, Codable, Sendable {
        case info = "инфо"
        case warning = "внимание"
        case error = "ошибка"
        case lifecycle = "жизненный цикл"
        case location = "геолокация"
        case island = "остров"
    }

    public struct Entry: Codable, Equatable, Sendable {
        public let time: Date
        public let kind: Kind
        public let text: String
    }

    /// Итог проверки предыдущего запуска
    public struct SessionReport: Equatable, Sendable {
        /// Предыдущий запуск закончился без штатного выхода (приложение закрыла система, оно упало или его смахнули)
        public var previousEndedUncleanly: Bool
        public var lastHeartbeat: Date?
        public var lastHeartbeatWasBackground: Bool
    }

    public static let maxEntries = 400

    private enum Key {
        static let sessionOpen = "netpulse_island_session_open"
        static let lastHeartbeat = "netpulse_island_last_heartbeat"
        static let lastHeartbeatBackground = "netpulse_island_last_heartbeat_background"
        static let pauseCount = "netpulse_island_pause_count"
        static let longestPause = "netpulse_island_longest_pause"
        static let uncleanCount = "netpulse_island_unclean_count"
    }

    public private(set) var entries: [Entry] = []
    /// Сколько раз цикл обнаруживал, что приложение приостанавливали в фоне
    public private(set) var backgroundPauseCount: Int
    public private(set) var longestBackgroundPause: TimeInterval
    /// Сколько запусков закончилось без штатного выхода
    public private(set) var uncleanSessionCount: Int

    private let defaults: UserDefaults
    private let fileURL: URL?
    private let timeFormatter: DateFormatter
    private var lastHeartbeatWrite = Date.distantPast
    private var saveTask: Task<Void, Never>?

    public init(defaults: UserDefaults, fileURL: URL?) {
        self.defaults = defaults
        self.fileURL = fileURL
        self.backgroundPauseCount = defaults.integer(forKey: Key.pauseCount)
        self.longestBackgroundPause = defaults.double(forKey: Key.longestPause)
        self.uncleanSessionCount = defaults.integer(forKey: Key.uncleanCount)

        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM HH:mm:ss"
        self.timeFormatter = formatter

        if let url = fileURL,
           let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            self.entries = Array(saved.suffix(Self.maxEntries))
        }
    }

    nonisolated static var defaultLogURL: URL? {
        guard let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return directory.appendingPathComponent("netpulse_island_log.json")
    }

    // MARK: Запись событий

    public func log(_ text: String, _ kind: Kind = .info, now: Date = Date()) {
        entries.append(Entry(time: now, kind: kind, text: text))
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        scheduleSave()
    }

    public func clear() {
        entries.removeAll()
        backgroundPauseCount = 0
        longestBackgroundPause = 0
        uncleanSessionCount = 0
        defaults.set(0, forKey: Key.pauseCount)
        defaults.set(0.0, forKey: Key.longestPause)
        defaults.set(0, forKey: Key.uncleanCount)
        saveNow()
    }

    // MARK: Сеанс и сигналы жизни

    /// Отмечает начало запуска и проверяет, как закончился предыдущий. Приложение, которое система закрыла в фоне,
    /// не получает уведомления о завершении — единственный след остаётся в «флаге открытого сеанса» и времени
    /// последнего сигнала жизни.
    @discardableResult
    public func beginSession(now: Date = Date()) -> SessionReport {
        let wasOpen = defaults.bool(forKey: Key.sessionOpen)
        let beat = defaults.object(forKey: Key.lastHeartbeat) as? Double
        let wasBackground = defaults.bool(forKey: Key.lastHeartbeatBackground)
        let lastBeat = beat.map { Date(timeIntervalSince1970: $0) }

        if wasOpen {
            uncleanSessionCount += 1
            defaults.set(uncleanSessionCount, forKey: Key.uncleanCount)
            let when = lastBeat.map { timeFormatter.string(from: $0) } ?? "неизвестно"
            let state = wasBackground ? "приложение было в фоне" : "приложение было на экране"
            log(
                "Предыдущий запуск завершился без штатного выхода. Последний сигнал жизни: \(when) (\(state)). "
                + "Возможные причины: систему не устроил расход памяти в фоне, сбой или закрытие из переключателя приложений.",
                .warning,
                now: now
            )
        }

        defaults.set(true, forKey: Key.sessionOpen)
        log("Запуск приложения. \(Self.environmentSummary())", .lifecycle, now: now)
        return SessionReport(
            previousEndedUncleanly: wasOpen,
            lastHeartbeat: lastBeat,
            lastHeartbeatWasBackground: wasBackground
        )
    }

    /// Штатное завершение: следующий запуск не будет считать это аварией
    public func endSession() {
        defaults.set(false, forKey: Key.sessionOpen)
        saveNow()
    }

    /// Сигнал жизни. Записывается не чаще раза в 5 секунд, чтобы не нагружать хранилище.
    public func heartbeat(isBackground: Bool, now: Date = Date()) {
        guard now.timeIntervalSince(lastHeartbeatWrite) >= 5 else { return }
        lastHeartbeatWrite = now
        defaults.set(now.timeIntervalSince1970, forKey: Key.lastHeartbeat)
        defaults.set(isBackground, forKey: Key.lastHeartbeatBackground)
    }

    // MARK: Паузы цикла

    /// Фиксирует паузу цикла обновления.
    /// В фоне это значит, что iOS приостановила приложение; при открытом приложении — что главный поток был занят.
    public func recordPause(seconds: TimeInterval, inBackground: Bool, context: String, now: Date = Date()) {
        let rounded = Int(seconds.rounded())
        if inBackground {
            backgroundPauseCount += 1
            longestBackgroundPause = max(longestBackgroundPause, seconds)
            defaults.set(backgroundPauseCount, forKey: Key.pauseCount)
            defaults.set(longestBackgroundPause, forKey: Key.longestPause)
            let suffix = context.isEmpty ? "" : " \(context)"
            log("Приложение было приостановлено системой в фоне примерно на \(rounded) с.\(suffix)", .warning, now: now)
        } else {
            log("Цикл обновления простоял \(rounded) с при открытом приложении (главный поток был занят).", .warning, now: now)
        }
    }

    /// Фиксирует, сколько памяти осталось до лимита, после которого система закрывает приложение
    public func sampleMemory(isBackground: Bool, now: Date = Date()) {
        guard let megabytes = Self.availableMemoryMB() else { return }
        let place = isBackground ? " (в фоне)" : ""
        log(
            "Доступно памяти до лимита системы: \(megabytes) МБ\(place)",
            megabytes < 80 ? .warning : .info,
            now: now
        )
    }

    public static func availableMemoryMB() -> Int? {
        #if os(iOS)
        let bytes = Int(os_proc_available_memory())
        guard bytes > 0 else { return nil }
        return bytes / 1_048_576
        #else
        return nil
        #endif
    }

    // MARK: Текст для экрана и обмена

    public static func environmentSummary() -> String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        let process = ProcessInfo.processInfo
        return "Версия \(version) (\(build)), iOS \(UIDevice.current.systemVersion), \(UIDevice.current.model), "
            + "энергосбережение: \(process.isLowPowerModeEnabled ? "вкл" : "выкл")."
    }

    /// Краткая сводка состояния острова для экрана диагностики
    public func summaryText(health: IslandHealthSnapshot, continuousMode: String) -> String {
        var lines: [String] = []
        lines.append("Остров: \(health.activityText)")

        if let age = health.secondsSinceLastUpdate {
            lines.append("Последнее обновление: \(Self.formatAge(age)) назад")
        } else {
            lines.append("Последнее обновление: ещё не было")
        }

        lines.append("Отправлено кадров: \(health.sent)")
        lines.append("Зависших отправок: \(health.abandoned) (поздних ответов: \(health.lateReplies))")
        lines.append(String(format: "Самая долгая отправка: %.1f с", health.longestSendSeconds))
        if let inFlight = health.inFlightSeconds {
            lines.append(String(format: "Сейчас отправка идёт уже %.1f с", inFlight))
        }

        lines.append("Непрерывный режим: \(continuousMode)")

        var pauses = "Паузы приложения в фоне: \(backgroundPauseCount)"
        if backgroundPauseCount > 0 {
            pauses += ", самая долгая ≈ \(Int(longestBackgroundPause.rounded())) с"
        }
        lines.append(pauses)
        lines.append("Запусков без штатного выхода: \(uncleanSessionCount)")
        return lines.joined(separator: "\n")
    }

    /// Журнал текстом: сверху заголовок со сводкой, дальше события от старых к новым
    public func exportText(summary: String) -> String {
        var lines = ["NetPulse — журнал острова", Self.environmentSummary(), "", summary, "", "События:"]
        for entry in entries {
            lines.append("\(timeFormatter.string(from: entry.time)) [\(entry.kind.rawValue)] \(entry.text)")
        }
        return lines.joined(separator: "\n")
    }

    /// События для экрана: самые новые сверху
    public func displayLines() -> [String] {
        entries.reversed().map { entry in
            "\(timeFormatter.string(from: entry.time)) [\(entry.kind.rawValue)] \(entry.text)"
        }
    }

    /// Чистая функция форматирования; не привязана к главному потоку, чтобы её можно было вызывать откуда угодно
    public nonisolated static func formatAge(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        if value < 60 { return "\(value) с" }
        if value < 3_600 { return "\(value / 60) мин" }
        return "\(value / 3_600) ч"
    }

    // MARK: Сохранение

    private func scheduleSave() {
        guard fileURL != nil, saveTask == nil else { return }
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            self?.saveNow()
            self?.saveTask = nil
        }
    }

    public func saveNow() {
        guard let url = fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
