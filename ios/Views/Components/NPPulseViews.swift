//
//  NPPulseViews.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import Foundation

// MARK: - Линия-кардиограмма

/// Линия «пульса»: повторяющийся удар, как на кардиограмме. Из неё сделаны и бегущая линия на главном экране,
/// и заставка при запуске.
struct ECGShape: Shape {
    /// Сколько ударов помещается по ширине
    var cycles: Double = 2.5
    /// Сдвиг волны в долях периода: растёт со временем, и линия бежит вправо
    var phase: Double = 0
    /// Размах ударов, 0...1 (1 — почти до верхнего края)
    var amplitude: Double = 1
    /// Какая часть линии нарисована слева направо, 0...1 (для заставки)
    var drawn: Double = 1

    var animatableData: Double {
        get { drawn }
        set { drawn = newValue }
    }

    /// Форма одного удара: небольшой зубец, острый пик с провалами по бокам и пологая волна
    nonisolated static func wave(_ position: Double) -> Double {
        func bump(_ center: Double, _ width: Double, _ height: Double) -> Double {
            let distance = (position - center) / width
            return height * exp(-distance * distance)
        }
        return bump(0.18, 0.045, 0.14)
            + bump(0.31, 0.012, -0.16)
            + bump(0.345, 0.014, 1.0)
            + bump(0.385, 0.014, -0.3)
            + bump(0.62, 0.07, 0.22)
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 1, rect.height > 1 else { return path }

        let steps = max(2, Int(rect.width / 2))
        let lastStep = Int((Double(steps) * min(max(drawn, 0), 1)).rounded())
        guard lastStep >= 1 else { return path }

        let baseline = rect.minY + rect.height * 0.68
        let reach = rect.height * 0.62 * CGFloat(min(max(amplitude, 0), 1))

        for step in 0...lastStep {
            let fraction = Double(step) / Double(steps)
            var position = fraction * cycles - phase
            position -= floor(position)
            let x = rect.minX + rect.width * CGFloat(fraction)
            let y = baseline - CGFloat(Self.wave(position)) * reach
            if step == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

// MARK: - Пульс сети на главном экране

/// «Пульс сети»: тонкая бегущая линия-кардиограмма за цифрами скорости. Цвет — качество связи, размах — скорость,
/// без связи — ровная красная линия. Пока идёт замер, линия ярче. Бежит только когда бесконечное движение
/// разрешено (нет «Уменьшения движения» и энергосбережения, приложение на экране); иначе стоит на месте.
struct NetworkPulseLine: View {
    let color: Color
    /// Размах ударов, 0...1
    let intensity: Double
    /// Нет связи: линия ровная
    var isFlat = false
    /// Идёт замер скорости: линия ярче и толще
    var isBusy = false

    @Environment(\.npContinuousMotion) private var continuous

    /// Скорость бега: ударов в секунду. Постоянная, чтобы при смене состояния волна не прыгала.
    private static let beatsPerSecond = 0.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !continuous)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let phase = continuous ? seconds * Self.beatsPerSecond : 0
            line(phase: phase)
        }
        .mask(edgeFade)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func line(phase: Double) -> some View {
        let amplitude = isFlat ? 0.02 : 0.35 + 0.65 * min(max(intensity, 0), 1)
        return ZStack {
            ECGShape(cycles: 2.5, phase: phase, amplitude: amplitude)
                .stroke(color.opacity(isBusy ? 0.4 : 0.22), style: StrokeStyle(lineWidth: isBusy ? 7 : 5, lineCap: .round, lineJoin: .round))
                .blur(radius: 3)
            ECGShape(cycles: 2.5, phase: phase, amplitude: amplitude)
                .stroke(color.opacity(isBusy ? 0.95 : 0.7), style: StrokeStyle(lineWidth: isBusy ? 2.5 : 2, lineCap: .round, lineJoin: .round))
        }
    }

    /// Края линии растворяются, чтобы она не упиралась в границы панели
    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.15),
                .init(color: .black, location: 0.85),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Заставка при запуске

/// Было ли уже показано вступление в этом запуске приложения: корневой экран может пересоздаваться
@MainActor
private enum NPIntroState {
    static var played = false
}

/// Короткая заставка: линия-пульс рисуется слева направо и проявляется название. Не мешает: касания проходят
/// сквозь неё к приложению, сама она занимает около секунды и один раз за запуск. При «Уменьшении движения» не
/// показывается.
@MainActor
struct NPIntroOverlay: View {
    @Environment(\.npOneShotMotion) private var oneShot
    @State private var isActive = !NPIntroState.played && !NPMotionSwitches.allOff
    @State private var drawn = 0.0
    @State private var titleOpacity = 0.0

    var body: some View {
        if isActive && oneShot {
            ZStack {
                NPTheme.backgroundDeep.ignoresSafeArea()
                VStack(spacing: 18) {
                    ECGShape(cycles: 1.6, phase: 0.05, amplitude: 1, drawn: drawn)
                        .stroke(
                            LinearGradient(
                                colors: [NPTheme.accentPrimary, NPTheme.accentSoft],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 220, height: 70)
                    Text("NetPulse")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(NPTheme.textPrimary)
                        .opacity(titleOpacity)
                }
            }
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                await play()
            }
        }
    }

    private func play() async {
        NPIntroState.played = true
        withAnimation(.easeInOut(duration: 0.75)) {
            drawn = 1
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
            titleOpacity = 1
        }
        try? await Task.sleep(for: .milliseconds(1100))
        withAnimation(.easeIn(duration: 0.3)) {
            isActive = false
        }
    }
}
