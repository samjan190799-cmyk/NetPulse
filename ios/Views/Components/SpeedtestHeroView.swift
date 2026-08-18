//
//  SpeedtestHeroView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Премиальный блок замера скорости (Speedtest) в монохромном стиле «Obsidian Mono» с белым свечением.
public struct SpeedtestHeroView: View {
    public let isRunning: Bool
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let pingMs: Double?
    public let jitterMs: Double?
    public let onStartSpeedtest: () -> Void

    @State private var isPulseActive: Bool = false
    @State private var isButtonPressed: Bool = false

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
                Text("СКОРОСТЬ СОЕДИНЕНИЯ")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NPTheme.textSecondary)
                    .tracking(0.5)

                Spacer()

                if isRunning {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(uploadMbps > 0 ? NPTheme.upload : NPTheme.accentPrimary)
                            .frame(width: 6, height: 6)
                            .scaleEffect(isPulseActive ? 1.3 : 0.8)
                            .opacity(isPulseActive ? 1.0 : 0.5)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulseActive)

                        Text(uploadMbps > 0 ? "ОТДАЧА" : "СКАЧИВАНИЕ")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(uploadMbps > 0 ? NPTheme.upload : NPTheme.accentPrimary)
                            .contentTransition(.opacity)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((uploadMbps > 0 ? NPTheme.upload : NPTheme.accentPrimary).opacity(0.1))
                    .clipShape(Capsule())
                    .transition(.scale.combined(with: .opacity))
                }
            }

            // Центральный анимированный спидометр с белым свечением
            ZStack {
                // 1. Внешняя пульсирующая волна при замере (белое свечение)
                if isRunning {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [NPTheme.accentPrimary.opacity(0.25), NPTheme.accentPrimary.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2
                        )
                        .frame(width: isPulseActive ? 215 : 185, height: isPulseActive ? 215 : 185)
                        .opacity(isPulseActive ? 0.0 : 0.8)
                        .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: isPulseActive)
                }

                // 2. Фоновая направляющая дуга
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(
                        NPTheme.cardBackgroundTertiary,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: 185, height: 185)

                // 3. Активная дуга — белый градиент с glow (как глиф в лого)
                Circle()
                    .trim(from: 0.15, to: 0.15 + (0.70 * gaugeProgress))
                    .stroke(
                        NPTheme.accentGradient,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: 185, height: 185)
                    .animation(.spring(response: 0.45, dampingFraction: 0.7), value: gaugeProgress)
                    .shadow(color: isRunning ? NPTheme.glowActive : Color.clear, radius: 12, x: 0, y: 0)

                // 4. Центральные цифровые показатели
                VStack(spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", currentDisplaySpeed))
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundStyle(NPTheme.textPrimary)
                            .contentTransition(.numericText(value: currentDisplaySpeed))
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentDisplaySpeed)
                    }

                    Text("Мбит/с")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NPTheme.textSecondary)

                    Text(statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isRunning ? NPTheme.accentSoft : NPTheme.textSecondary)
                        .padding(.top, 4)
                        .contentTransition(.opacity)
                }
            }
            .frame(height: 175)
            .onAppear {
                isPulseActive = true
            }

            // Сетка 4 метрик с анимацией чисел
            HStack(spacing: 10) {
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

            // Кнопка запуска — белая с чёрным текстом (инвертированная, как глиф в лого)
            Button(action: {
                HapticManager.shared.impactMedium()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                    isButtonPressed = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isButtonPressed = false
                    }
                }
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
                            .font(.system(size: 13, weight: .semibold))
                        Text(downloadMbps > 0 ? "Повторить замер" : "Начать тест скорости")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isRunning ? NPTheme.buttonDisabledGradient : NPTheme.buttonGradient)
                .foregroundStyle(isRunning ? NPTheme.textSecondary : NPTheme.backgroundDeep)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .scaleEffect(isButtonPressed ? 0.96 : 1.0)
                .shadow(color: NPTheme.glow, radius: isRunning ? 4 : 10, x: 0, y: 4)
            }
            .disabled(isRunning)
        }
        .padding(18)
        .npCardStyle(cornerRadius: 18)
    }

    private var statusText: String {
        if isRunning {
            return uploadMbps > 0 ? "Замер отдачи..." : "Замер скачивания..."
        }
        if downloadMbps > 0 {
            return "Готово"
        }
        return "Нажмите для замера"
    }
}

/// Анимированная плашка отдельной метрики (Obsidian Mono)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? NPTheme.accentPrimary : NPTheme.textSecondary)
                .scaleEffect(isActive ? 1.15 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(isActive ? NPTheme.accentPrimary : NPTheme.textPrimary)
                .contentTransition(.numericText(value: numericValue))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: numericValue)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(unit)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(NPTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(isActive ? NPTheme.accentPrimary.opacity(0.06) : NPTheme.cardBackgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? NPTheme.accentPrimary.opacity(0.15) : NPTheme.border, lineWidth: 1)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)
    }
}
