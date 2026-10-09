//
//  AlertNotifier.swift
//  NetPulse
//
//  Оповещения о проблемах сети (подписка PRO): уведомление, когда связь пропала или стала плохой, и напоминание,
//  если запись маршрута идёт слишком долго. Уведомления приходят, только пока приложение не на экране, но работает
//  (идёт запись маршрута или включён остров): iOS не даёт следить за сетью в закрытом приложении.
//

import Foundation
import UIKit
import UserNotifications

@MainActor
final class AlertNotifier {
    static let shared = AlertNotifier()

    /// Не чаще одного уведомления об одной и той же проблеме за это время, секунд
    static let minimumInterval: TimeInterval = 300
    /// Через сколько секунд записи напоминать, что она идёт
    static let recordingReminderDelay: TimeInterval = 60 * 60

    private static let enabledKey = "netpulse_alerts_enabled"
    private static let reminderID = "netpulse.recording.reminder"

    private let defaults: UserDefaults
    private var lastPosted: [String: Date] = [:]
    private var reminderScheduled = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Выбор пользователя: нужны ли оповещения (по умолчанию нет)
    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    // MARK: - Включение

    /// Просит у iOS разрешение на уведомления (окно появляется только здесь, по действию пользователя).
    /// Возвращает `true`, если оповещения включены.
    func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        isEnabled = granted
        return granted
    }

    func disable() {
        isEnabled = false
        cancelRecordingReminder()
    }

    // MARK: - Правила

    /// Нужно ли сейчас слать уведомление: есть подписка, оповещения включены, приложение не на экране
    /// (на экране проблема и так видна)
    var shouldNotify: Bool {
        ProStore.shared.isPro && isEnabled && UIApplication.shared.applicationState != .active
    }

    /// Можно ли слать уведомление об этой проблеме: не слали ли такое только что
    func isThrottled(key: String, now: Date = Date()) -> Bool {
        if let last = lastPosted[key], now.timeIntervalSince(last) < Self.minimumInterval {
            return true
        }
        return false
    }

    // MARK: - Уведомления

    /// Уведомление о проблеме сети (узел не отвечает, потери пакетов)
    func notifyProblem(key: String, title: String, body: String, now: Date = Date()) {
        guard shouldNotify, !isThrottled(key: key, now: now) else { return }
        lastPosted[key] = now
        post(id: "netpulse.alert.\(key)", title: title, body: body, delay: nil)
    }

    /// Напоминание: запись маршрута идёт уже час. Ставится при старте записи, снимается при остановке.
    func scheduleRecordingReminder() {
        guard ProStore.shared.isPro, isEnabled else { return }
        reminderScheduled = true
        post(
            id: Self.reminderID,
            title: "Запись маршрута идёт уже час",
            body: "Если вы закончили, откройте NetPulse и остановите запись: она тратит заряд.",
            delay: Self.recordingReminderDelay
        )
    }

    /// При запуске приложения: напоминание о записи, оставшееся от прошлого запуска, больше не верно
    /// (запись после закрытия приложения сама не продолжается)
    func clearStaleReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
    }

    func cancelRecordingReminder() {
        guard reminderScheduled else { return }
        reminderScheduled = false
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
    }

    private func post(id: String, title: String, body: String, delay: TimeInterval?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = delay.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}
