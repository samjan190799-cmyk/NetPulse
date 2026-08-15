//
//  HapticManager.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import UIKit

/// Менеджер тактильной отдачи (Haptic Feedback) для премиального взаимодействия.
@MainActor
public final class HapticManager {
    public static let shared = HapticManager()

    private init() {}

    /// Легкий клик интерфейса
    public func impactLight() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Средний клик интерфейса
    public func impactMedium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Тяжелый клик (переключение состояния)
    public func impactHeavy() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Успешное действие (например, завершение Speedtest)
    public func notificationSuccess() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    /// Предупреждение (повышенная задержка / джиттер)
    public func notificationWarning() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }

    /// Критический сбой (потеря пакетов / обрыв связи)
    public func notificationError() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
    }
}
