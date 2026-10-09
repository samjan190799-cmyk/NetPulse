//
//  HapticManager.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import UIKit

/// Менеджер тактильной отдачи (Haptic Feedback) для премиального взаимодействия.
///
/// Переключатель «Тактильный отклик» в настройках гасит всю вибрацию приложения: нажатия кнопок, смену вкладок,
/// замеры и оповещения. Раньше он отключал лишь несколько вызовов в модели, а остальные вибрировали всегда.
@MainActor
public final class HapticManager {
    public static let shared = HapticManager()

    /// Ключ переключателя в `UserDefaults`; тот же ключ пишет настройка «Тактильный отклик»
    nonisolated public static let defaultsKey = "netpulse_haptics_enabled"

    private init() {}

    /// Включён ли тактильный отклик (по умолчанию — да, пока пользователь не выключил его в настройках)
    public var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true
    }

    /// Легкий клик интерфейса
    public func impactLight() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Средний клик интерфейса
    public func impactMedium() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Тяжелый клик (переключение состояния)
    public func impactHeavy() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Смена выбора в переключателях (Segmented Control, Picker)
    public func selectionChanged() {
        guard isEnabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    /// Успешное действие (например, завершение Speedtest)
    public func notificationSuccess() {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    /// Предупреждение (повышенная задержка / джиттер)
    public func notificationWarning() {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }

    /// Критический сбой (потеря пакетов / обрыв связи)
    public func notificationError() {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
    }
}
