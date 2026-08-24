//
//  SpeedtestHeroView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Премиальный блок замера скорости (Speedtest) 2026 с потоком световых частиц (Data Stream Particles),
/// зеркальным ободом и кинетической типографикой.
public struct SpeedtestHeroView: View {
    public let isRunning: Bool
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let pingMs: Double?
    public let jitterMs: Double?
    public let onStartSpeedtest: () -> Void

    @State private var isPulseActive: Bool = false
    @State private var isButtonPressed: Bool = false
    @State private var particleRotation: Double = 0.0

    private var currentDisplaySpeed: Double {
        if isRunning {
            return uploadMbps > 0 ? uploadMbps : downloadMbps
        }
        return downloadMbps > 0 ? downloadMbps : 0.0
    }

    private var gaugeProgress: Double {
        // Плавная шкала до 500 Мбит/с с логарифмической мягкостью
        min(max(currentDisplaySpeed / 500.0, 0.0), 1.0)
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Верхняя плашка с заголовком и живым индикатором фазы
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NPTheme.accentPrimary)
                        .symbolEffect(.pulse, isActive: isRunning)
                    Text("СКОРОСТЬ СОЕДИНЕНИЯ")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(NPTheme.textSecondary)
                        .tracking(0.5)
                }

                Spacer()

                if isRunning {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(uploadMbps > 0 ? NPTheme.upload : NPTheme.download)
                            .frame(width: 6, height: 6)
                            .scaleEffect(isPulseActive ? 1.4 : 0.8)
                            .opacity(isPulseActive ? 1.0 : 0.4)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isPulseActive)

                        Text(uploadMbps > 0 ? "ОТДАЧА" : "СКАЧИВАНИЕ")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(uploadMbps > 0 ? NPTheme.upload : NPTheme.download)
                            .contentTransition(.opacity)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background((uploadMbps > 0 ? NPTheme.upload : NPTheme.download).opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke((uploadMbps > 0 ? NPTheme.upload : NPTheme.download).opacity(0.25), lineWidth: 1)
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }

            // Центральный спидометр с частицами данных и белым/неоновым свечением
            ZStack {
                // 1. Внешняя пульсирующая волна при замере
                if isRunning {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [NPTheme.accentPrimary.opacity(0.35), NPTheme.accentPrimary.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2
                        )
                        .frame(width: isPulseActive ? 220 : 185, height: isPulseActive ? 220 : 185)
                        .opacity(isPulseActive ? 0.0 : 0.9)
                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: isPulseActive)
                }

                // 2. Фоновая направляющая дуга с разметкой
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(
                        NPTheme.cardBackgroundTertiary,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: 185, height: 185)

                // 3. Зеркальный внутренний обод (Specular Inner Ring)
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.15), location: 0.0),
                                .init(color: Color.clear, location: 0.5),
                                .init(color: Color.white.opacity(0.08), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: 172, height: 172)

                // 4. Активная дуга скорости с ярким градиентом и свечением
                Circle()
                    .trim(from: 0.15, to: 0.15 + (0.70 * gaugeProgress))
                    .stroke(
                        NPTheme.accentGradient,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: 185, height: 185)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: gaugeProgress)
                    .shadow(color: isRunning ? NPTheme.glowActive : Color.clear, radius: 14, x: 0, y: 0)

                // 5. Поток световых частиц данных (Data Stream Particles) при замере
                if isRunning {
                    DataStreamParticlesRing(speed: currentDisplaySpeed)
                        .frame(width: 185, height: 185)
                }

                // 6. Центральные цифровые показатели
                VStack(spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", currentDisplaySpeed))
                            .font(.system(size: 48, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(NPTheme.textPrimary)
                            .contentTransition(.numericText(value: currentDisplaySpeed))
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentDisplaySpeed)
                            .shadow(color: NPTheme.glowActive, radius: isRunning ? 8 : 0)
                    }

                    Text("Мбит/с")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NPTheme.textSecondary)

                    Text(statusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isRunning ? NPTheme.accentPrimary : NPTheme.textTertiary)
                        .padding(.top, 4)
                        .contentTransition(.opacity)
                }
            }
            .frame(height: 180)
            .onAppear {
                isPulseActive = true
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Текущая скорость соединения")
            .accessibilityValue("\(String(format: "%.1f", currentDisplaySpeed)) Мегабит в секунду, статус: \(statusText)")

            // Сетка 4 метрик со стеклянным фоном
            HStack(spacing: 8) {
                AnimatedMetricItemBox(
                    title: "Скачивание",
                    value: downloadMbps > 0 ? String(format: "%.1f", downloadMbps) : "—",
                    numericValue: downloadMbps,
                    unit: "Мбит/с",
                    icon: "arrow.down",
                    isActive: isRunning && uploadMbps == 0
                )

                AnimatedMetricItemBox(
                    title: "Отдача",
                    value: uploadMbps > 0 ? String(format: "%.1f", uploadMbps) : "—",
                    numericValue: uploadMbps,
                    unit: "Мбит/с",
                    icon: "arrow.up",
                    isActive: isRunning && uploadMbps > 0
                )

                AnimatedMetricItemBox(
                    title: "Пинг",
                    value: pingMs != nil ? String(format: "%.0f", pingMs!) : "—",
                    numericValue: pingMs ?? 0,
                    unit: "мс",
                    icon: "network",
                    isActive: false
                )

                AnimatedMetricItemBox(
                    title: "Джиттер",
                    value: jitterMs != nil ? String(format: "%.1f", jitterMs!) : "—",
                    numericValue: jitterMs ?? 0,
                    unit: "мс",
                    icon: "waveform.path.ecg",
                    isActive: false
                )
            }

            // Кнопка запуска с виброоткликом и пружинной физикой Apple HIG
            Button(action: {
                HapticManager.shared.impactMedium()
                onStartSpeedtest()
            }) {
                HStack(spacing: 8) {
                    if isRunning {
                        ProgressView()
                            .tint(NPTheme.backgroundDeep)
                            .scaleEffect(0.9)
                        Text("Измерение скорости...")
                            .font(.system(size: 15, weight: .bold))
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(downloadMbps > 0 ? "Повторить замер" : "Начать тест скорости")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(isRunning ? NPTheme.buttonDisabledGradient : NPTheme.buttonGradient)
                .foregroundStyle(isRunning ? NPTheme.textSecondary : NPTheme.backgroundDeep)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: NPTheme.glowActive, radius: isRunning ? 4 : 12, x: 0, y: 4)
            }
            .buttonStyle(NPPressableButtonStyle(scale: 0.96))
            .disabled(isRunning)
            .accessibilityLabel(downloadMbps > 0 ? "Повторить замер скорости" : "Начать тест скорости")
        }
        .padding(18)
        .npGlassCard(cornerRadius: 20)
    }

    private var statusText: String {
        if isRunning {
            return uploadMbps > 0 ? "Замер отдачи..." : "Замер скачивания..."
        }
        if downloadMbps > 0 {
            return "Замер завершен"
        }
        return "Нажмите для замера"
    }
}

/// Анимированное кольцо световых частиц данных
private struct DataStreamParticlesRing: View {
    let speed: Double

    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = size.width / 2
                let now = timeline.date.timeIntervalSinceReferenceDate
                let speedFactor = max(1.0, min(speed / 30.0, 10.0))

                for i in 0..<8 {
                    let angleOffset = Double(i) * (.pi / 4.0)
                    let currentAngle = (now * speedFactor + angleOffset).truncatingRemainder(dividingBy: .pi * 2)

                    // Ограничиваем сектор только рабочей дугой спидометра (от 0.15*2pi до 0.85*2pi)
                    let normalizedAngle = currentAngle
                    let x = center.x + CGFloat(cos(normalizedAngle)) * radius
                    let y = center.y + CGFloat(sin(normalizedAngle)) * radius

                    let particleSize: CGFloat = 3.5
                    let rect = CGRect(x: x - particleSize / 2, y: y - particleSize / 2, width: particleSize, height: particleSize)

                    context.fill(
                        Circle().path(in: rect),
                        with: .color(.white.opacity(0.85))
                    )
                }
            }
        }
    }
}

/// Анимированная плашка отдельной метрики в стеклянном стиле 2026
private struct AnimatedMetricItemBox: View {
    let title: String
    let value: String
    let numericValue: Double
    let unit: String
    let icon: String
    let isActive: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isActive ? NPTheme.accentPrimary : NPTheme.textSecondary)
                .symbolEffect(.bounce, value: isActive)
                .scaleEffect(isActive ? 1.15 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)

            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isActive ? NPTheme.accentPrimary : NPTheme.textPrimary)
                .contentTransition(.numericText(value: numericValue))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: numericValue)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(unit)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(NPTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? NPTheme.accentPrimary.opacity(0.10) : NPTheme.cardBackgroundTertiary.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? NPTheme.accentPrimary.opacity(0.3) : NPTheme.border, lineWidth: 1)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
}

