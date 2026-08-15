//
//  SpeedtestGaugeView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Футуристический спидометр для замера скорости сети (Bandwidth & Speedtest).
public struct SpeedtestGaugeView: View {
    public let isRunning: Bool
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let onStartSpeedtest: () -> Void

    private var displaySpeed: Double {
        uploadMbps > 0 ? uploadMbps : downloadMbps
    }

    private var gaugeProgress: Double {
        // Нормализация скорости до 300 Mbps для шкалы спидометра
        min(max(displaySpeed / 300.0, 0.0), 1.0)
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Заголовок
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ПРОПУСКНАЯ СПОСОБНОСТЬ")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("Тест скорости соединения")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "gauge.with.dots.needle.bottom.100percent")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)
            }

            // Круговой индикатор скорости
            ZStack {
                // Фоновая дуга
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(
                        Color.white.opacity(0.08),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: 170, height: 170)

                // Активная неоновая дуга
                Circle()
                    .trim(from: 0.15, to: 0.15 + (0.70 * gaugeProgress))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.cyan, .green, .yellow, .red]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: 170, height: 170)
                    .shadow(color: .green.opacity(isRunning ? 0.6 : 0.2), radius: 10)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: gaugeProgress)

                // Текст в центре
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", displaySpeed))
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())

                    Text("Mbps")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.green)

                    Text(isRunning ? (uploadMbps > 0 ? "Отдача..." : "Скачивание...") : "Готов")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .frame(height: 150)

            // Блок Download / Upload результатов
            HStack(spacing: 16) {
                SpeedStatBox(
                    title: "Скачивание",
                    value: String(format: "%.1f", downloadMbps),
                    icon: "arrow.down.circle.fill",
                    color: .green
                )

                SpeedStatBox(
                    title: "Отдача",
                    value: String(format: "%.1f", uploadMbps),
                    icon: "arrow.up.circle.fill",
                    color: .cyan
                )
            }

            // Кнопка запуска
            Button(action: onStartSpeedtest) {
                HStack(spacing: 8) {
                    if isRunning {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .bold))
                    }

                    Text(isRunning ? "Идет замер скорости..." : "Запустить Speedtest")
                        .font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: isRunning ? [Color.gray.opacity(0.4), Color.gray.opacity(0.2)] : [Color.cyan, Color.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: isRunning ? .clear : Color.cyan.opacity(0.3), radius: 8, y: 4)
            }
            .disabled(isRunning)
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct SpeedStatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(value) Mbps")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
