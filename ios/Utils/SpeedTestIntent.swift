//
//  SpeedTestIntent.swift
//  NetPulse
//
//  «Замерить скорость» для Siri, Команд (Shortcuts) и кнопки Action Button: открывает приложение и сразу запускает
//  замер. Доступно всем пользователям, без подписки.
//

import AppIntents
import Foundation

extension Notification.Name {
    /// Просьба открыть главный экран («Сеть»): после команды замера
    static let netPulseShowHome = Notification.Name("netpulse.show_home")
}

/// Просьба запустить замер после открытия приложения. Команда только оставляет отметку, а замер запускает само
/// приложение, когда окажется на экране: так он стартует и при холодном запуске.
enum SpeedTestRequest {
    static let key = "netpulse_pending_speedtest"
    /// Отметка живёт столько секунд: забытая просьба не должна запустить замер через час
    static let lifetime: TimeInterval = 60

    static func request(defaults: UserDefaults = .standard, now: Date = Date()) {
        defaults.set(now.timeIntervalSince1970, forKey: key)
    }

    /// Забирает просьбу, если она свежая. Возвращает `true`, когда замер нужно запустить.
    static func consume(defaults: UserDefaults = .standard, now: Date = Date()) -> Bool {
        let stamp = defaults.double(forKey: key)
        defaults.removeObject(forKey: key)
        guard stamp > 0 else { return false }
        return now.timeIntervalSince1970 - stamp < lifetime
    }
}

struct StartSpeedTestIntent: AppIntent {
    static let title: LocalizedStringResource = "Замерить скорость"
    static let description = IntentDescription("Открывает NetPulse и сразу запускает замер скорости интернета.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        SpeedTestRequest.request()
        return .result()
    }
}

struct NetPulseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSpeedTestIntent(),
            phrases: [
                "Замерить скорость в \(.applicationName)",
                "Проверить интернет в \(.applicationName)"
            ],
            shortTitle: "Замер скорости",
            systemImageName: "speedometer"
        )
    }
}
