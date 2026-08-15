//
//  SpeedtestHeroView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Минималистичный и строгий блок замера скорости (Speedtest) в стиле Apple HIG.
public struct SpeedtestHeroView: View {
    public let isRunning: Bool
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let pingMs: Double?
    public let jitterMs: Double?
    public let onStartSpeedtest: () -> Void

    private var currentDisplaySpeed: Double {
        if isRunning {
            return uploadMbps > 0 ? uploadMbps : downloadMbps
        }
        return downloadMbps > 0 ? downloadMbps : 0.0
    }

    private var gaugeProgress: Double {
        // Нормализация скорости до 500 Мбит/с для шкалы
        min(max(currentDisplaySpeed / 500.0, 0.0), 1.0)
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Верхняя плашка с заголовком
            HStack {
                Text("СКОРОСТЬ СОЕДИНЕНИЯ")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Spacer()

                if isRunning {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                        Text(uploadMbps > 0 ? "ОТДАЧА" : "СКАЧИВАНИЕ")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.blue)
                    }
                }
            }

            // Центральный спидометр
            ZStack {
                // Фоновая дуга
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(
                        Color(uiColor: .tertiarySystemFill),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: 190, height: 190)

                // Активная дуга (сдержанный системный синий)
                Circle()
                    .trim(from: 0.15, to: 0.15 + (0.70 * gaugeProgress))
                    .stroke(
                        Color.blue,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: 190, height: 190)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: gaugeProgress)

                // Числовое значение в центре
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", currentDisplaySpeed))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())

                    Text("Мбит/с")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(statusText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .frame(height: 170)

            // Сетка ключевых метрик
            HStack(spacing: 12) {
                MetricItemBox(
                    title: "Скачивание",
                    value: downloadMbps > 0 ? String(format: "%.1f", downloadMbps) : "—",
                    unit: "Мбит/с",
                    icon: "arrow.down"
                )

                MetricItemBox(
                    title: "Отдача",
                    value: uploadMbps > 0 ? String(format: "%.1f", uploadMbps) : "—",
                    unit: "Мбит/с",
                    icon: "arrow.up"
                )

                MetricItemBox(
                    title: "Пинг",
                    value: pingMs != nil ? String(format: "%.0f", pingMs!) : "—",
                    unit: "мс",
                    icon: "network"
                )

                MetricItemBox(
                    title: "Джиттер",
                    value: jitterMs != nil ? String(format: "%.1f", jitterMs!) : "—",
                    unit: "мс",
                    icon: "waveform.path.ecg"
                )
            }

            // Кнопка запуска
            Button(action: {
                HapticManager.shared.impactMedium()
                onStartSpeedtest()
            }) {
                HStack(spacing: 8) {
                    if isRunning {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }

                    Text(isRunning ? "Выполняется замер..." : "Начать тест скорости")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(isRunning ? Color.gray.opacity(0.3) : Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(isRunning)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var statusText: String {
        if !isRunning {
            return downloadMbps > 0 ? "Тест завершен" : "Готов к замеру"
        }
        if uploadMbps > 0 {
            return "Замер отдачи..."
        }
        return "Замер скачивания..."
    }
}

/// Минималистичная ячейка числовой метрики
private struct MetricItemBox: View {
    let title: String
    let value: String
    let unit: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text(unit)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
