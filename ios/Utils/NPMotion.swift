//
//  NPMotion.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

// MARK: - Выключатели для тестов

/// Аргументы запуска, которыми UI-тесты выключают движение: снимки экрана должны быть одинаковыми, а бесконечные
/// анимации не дают XCUITest дождаться покоя приложения.
/// - `-netpulse_motion_off YES` — никакого движения (заставка, «рисование» маршрута, появление экранов, пульс);
/// - `-netpulse_continuous_off YES` — только бесконечное движение выключено (пульс, дыхание свечения, волна точки).
enum NPMotionSwitches {
    nonisolated static var allOff: Bool {
        UserDefaults.standard.bool(forKey: "netpulse_motion_off")
    }

    nonisolated static var continuousOff: Bool {
        allOff || UserDefaults.standard.bool(forKey: "netpulse_continuous_off")
    }
}

// MARK: - Что разрешено двигать

private struct NPContinuousMotionKey: EnvironmentKey {
    static let defaultValue = true
}

private struct NPOneShotMotionKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Можно ли бесконечное движение (пульс, дыхание, волна): оно выключается при «Уменьшении движения», в режиме
    /// энергосбережения и пока приложение не на экране, чтобы не тратить заряд
    var npContinuousMotion: Bool {
        get { self[NPContinuousMotionKey.self] }
        set { self[NPContinuousMotionKey.self] = newValue }
    }

    /// Можно ли разовое движение (заставка, появление, «рисование» маршрута): его выключает только
    /// «Уменьшение движения» в настройках iOS
    var npOneShotMotion: Bool {
        get { self[NPOneShotMotionKey.self] }
        set { self[NPOneShotMotionKey.self] = newValue }
    }
}

/// Выставляет в окружение правила движения. Накладывается один раз на корень приложения.
struct NPMotionPolicyModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    func body(content: Content) -> some View {
        content
            .environment(\.npOneShotMotion, !reduceMotion && !NPMotionSwitches.allOff)
            .environment(
                \.npContinuousMotion,
                !reduceMotion && !lowPower && scenePhase == .active && !NPMotionSwitches.continuousOff
            )
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }
}

// MARK: - Общие приёмы

/// Единые кривые движения: пружины одинаковой «упругости» по всему приложению
enum NPMotion {
    static var spring: Animation {
        .spring(response: 0.42, dampingFraction: 0.82)
    }

    static var pop: Animation {
        .spring(response: 0.4, dampingFraction: 0.55)
    }
}

/// Анимация по значению, которая молчит при «Уменьшении движения»
struct NPAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.npOneShotMotion) private var oneShot
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(oneShot ? animation : nil, value: value)
    }
}

/// Экран плавно проявляется и чуть поднимается, когда его открывают
struct NPAppearModifier: ViewModifier {
    @Environment(\.npOneShotMotion) private var oneShot
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || !oneShot ? 1 : 0)
            .offset(y: shown || !oneShot ? 0 : 10)
            .onAppear {
                guard oneShot else {
                    shown = true
                    return
                }
                shown = false
                withAnimation(.easeOut(duration: 0.32)) {
                    shown = true
                }
            }
    }
}

/// Значок подпрыгивает, когда меняется значение (например, оценка связи)
struct NPBounceModifier<Value: Equatable>: ViewModifier {
    @Environment(\.npOneShotMotion) private var oneShot
    let value: Value

    func body(content: Content) -> some View {
        if oneShot {
            content.symbolEffect(.bounce, value: value)
        } else {
            content
        }
    }
}

/// Свечение, которое «дышит», пока `active` и бесконечное движение разрешено
struct NPBreathingGlowModifier: ViewModifier {
    @Environment(\.npContinuousMotion) private var continuous
    let color: Color
    let active: Bool

    func body(content: Content) -> some View {
        if active && continuous {
            content.phaseAnimator([0.12, 0.6]) { view, glow in
                view.shadow(color: color.opacity(glow), radius: 14)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
        } else {
            content
        }
    }
}

extension View {
    func npMotionPolicy() -> some View {
        modifier(NPMotionPolicyModifier())
    }

    func npAnimation<Value: Equatable>(_ animation: Animation = NPMotion.spring, value: Value) -> some View {
        modifier(NPAnimationModifier(animation: animation, value: value))
    }

    func npAppear() -> some View {
        modifier(NPAppearModifier())
    }

    func npBounce<Value: Equatable>(value: Value) -> some View {
        modifier(NPBounceModifier(value: value))
    }

    func npBreathingGlow(color: Color, active: Bool) -> some View {
        modifier(NPBreathingGlowModifier(color: color, active: active))
    }
}

// MARK: - Мигающая точка записи

/// Красная точка записи маршрута: мягко мигает, пока запись идёт и бесконечное движение разрешено
struct NPRecordingDot: View {
    @Environment(\.npContinuousMotion) private var continuous
    let color: Color

    var body: some View {
        if continuous {
            dot.phaseAnimator([1.0, 0.4]) { view, level in
                view
                    .opacity(level)
                    .scaleEffect(0.82 + 0.18 * level)
            } animation: { _ in
                .easeInOut(duration: 0.8)
            }
        } else {
            dot
        }
    }

    private var dot: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .shadow(color: color.opacity(0.6), radius: 4)
    }
}
