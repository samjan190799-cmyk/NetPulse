//
//  MorningSummary.swift
//  NetPulse
//
//  Утренняя сводка: одно уведомление в день с итогами связи за сутки («Средний пинг 32 мс. Обрывов не было. Хуже
//  всего было около 21:00»). Уведомление ставится заранее, потому что iOS не даёт приложению выполнять код в момент
//  показа; его текст пересчитывается при каждом запуске приложения и при каждом обновлении виджета (общий журнал
//  замеров лежит в App Group). Данные не покидают устройство. Файл входит и в приложение, и в расширение виджетов.
//

import Foundation
import UserNotifications

// MARK: - Текст

enum MorningSummaryText {
    /// В журнале должно быть хотя бы столько замеров, иначе сводка была бы догадкой
    static let minimumChecks = 3

    /// Заголовок и текст сводки; `nil` — данных мало, уведомление не ставится
    static func make(from summary: DailySummary) -> (title: String, body: String)? {
        guard summary.checks >= minimumChecks else { return nil }

        let title: String
        if summary.outages > 0 {
            title = "Связь за сутки: были обрывы"
        } else if let average = summary.averagePingMs, average >= QuickCheckVerdict.goodPingMs {
            title = "Связь за сутки: было медленно"
        } else {
            title = "Связь за сутки: всё ровно"
        }

        var parts: [String] = []
        if let average = summary.averagePingMs {
            parts.append("Средний пинг \(Int(average.rounded())) мс.")
        }
        parts.append(summary.outages == 0 ? "Обрывов не было." : "Обрывов: \(summary.outages).")
        if let hour = summary.worstHour {
            parts.append("Хуже всего было около \(String(format: "%02d", hour)):00.")
        }
        return (title, parts.joined(separator: " "))
    }
}

// MARK: - Настройки

/// Настройки сводки лежат в общих данных App Group: их читает и приложение, и расширение виджетов
final class MorningSummarySettings: @unchecked Sendable {
    static let shared = MorningSummarySettings()

    static let enabledKey = "netpulse_morning_summary_enabled"
    static let hourKey = "netpulse_morning_summary_hour"
    static let minuteKey = "netpulse_morning_summary_minute"
    static let defaultHour = 8
    static let defaultMinute = 30

    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: QuickCheckLog.groupIdentifier) ?? .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    var hour: Int {
        get {
            guard let stored = defaults.object(forKey: Self.hourKey) as? Int else { return Self.defaultHour }
            return min(max(stored, 0), 23)
        }
        set { defaults.set(min(max(newValue, 0), 23), forKey: Self.hourKey) }
    }

    var minute: Int {
        get {
            guard let stored = defaults.object(forKey: Self.minuteKey) as? Int else { return Self.defaultMinute }
            return min(max(stored, 0), 59)
        }
        set { defaults.set(min(max(newValue, 0), 59), forKey: Self.minuteKey) }
    }
}

// MARK: - Уведомления

protocol NotificationScheduling: Sendable {
    /// Разрешил ли пользователь уведомления
    func isAuthorized() async -> Bool
    /// Ставит (или заменяет) уведомление на заданное время
    func schedule(identifier: String, title: String, body: String, at components: DateComponents) async
    func removePending(identifiers: [String])
}

struct SystemNotificationScheduler: NotificationScheduling {
    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    func schedule(identifier: String, title: String, body: String, at components: DateComponents) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.interruptionLevel = .passive
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func removePending(identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

// MARK: - Планировщик

enum MorningSummaryScheduler {
    static let identifier = "netpulse.morning.summary"
    /// Сводка охватывает последние сутки
    static let window: TimeInterval = 24 * 60 * 60

    /// Ближайшее утро: сегодня в указанное время, если оно ещё не прошло, иначе завтра
    static func nextFireDate(after now: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> Date? {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
    }

    /// Просит у iOS разрешение на уведомления (окно появляется только здесь, по действию пользователя) и включает сводку
    @MainActor
    static func enable(
        settings: MorningSummarySettings = .shared,
        center: UNUserNotificationCenter = .current()
    ) async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
        settings.isEnabled = granted
        if granted {
            await reschedule()
        }
        return granted
    }

    static func disable(
        settings: MorningSummarySettings = .shared,
        scheduler: any NotificationScheduling = SystemNotificationScheduler()
    ) {
        settings.isEnabled = false
        scheduler.removePending(identifiers: [identifier])
    }

    /// Пересчитывает текст и ставит уведомление на ближайшее утро. Вызывается при запуске приложения, при выходе
    /// на экран и после каждого замера, в том числе из виджета. Если сводка выключена, уведомления нет или данных
    /// мало, ожидающее уведомление снимается.
    static func reschedule(
        now: Date = Date(),
        settings: MorningSummarySettings = .shared,
        log: QuickCheckLog = .shared,
        scheduler: any NotificationScheduling = SystemNotificationScheduler(),
        calendar: Calendar = .current
    ) async {
        guard settings.isEnabled else {
            scheduler.removePending(identifiers: [identifier])
            return
        }
        guard await scheduler.isAuthorized() else {
            scheduler.removePending(identifiers: [identifier])
            return
        }

        let samples = log.samples(since: now.addingTimeInterval(-window))
        let summary = DailySummary.make(samples: samples, calendar: calendar)
        guard let text = MorningSummaryText.make(from: summary),
              let fire = nextFireDate(after: now, hour: settings.hour, minute: settings.minute, calendar: calendar) else {
            scheduler.removePending(identifiers: [identifier])
            return
        }

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        await scheduler.schedule(identifier: identifier, title: text.title, body: text.body, at: components)
    }
}
