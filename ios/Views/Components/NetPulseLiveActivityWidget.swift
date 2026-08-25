//
//  NetPulseLiveActivityWidget.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(WidgetKit) && canImport(ActivityKit)
/// Виджет Live Activity и Dynamic Island для отображения реальной скорости загрузки и отдачи в реальном времени.
public struct NetPulseLiveActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: NetPulseAttributes.self) { context in
            // Экран блокировки / Баннер уведомлений
            LockScreenLiveActivityView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                // Расширенный вид (по долгому нажатию на остров)
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.cyan)
                            Text("СКАЧИВАНИЕ")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(context.state.downloadSpeedText)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 8)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(context.state.isTesting ? "ОТДАЧА" : "RTT ПИНГ")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Image(systemName: context.state.isTesting ? "arrow.up" : "network")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.green)
                        }
                        Text(context.state.uploadSpeedText)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.trailing, 8)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text(cleanISP(context.state.ispName))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        Text(cleanConnType(context.state.connectionType))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 10))
                                .foregroundStyle(.cyan)
                            Text("NetPulse Мониторинг")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if context.state.isTesting {
                            Text("Speedtest активен")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.cyan)
                        } else {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 5, height: 5)
                                Text("Онлайн")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                }
            } compactLeading: {
                // Компактный вид слева (скачивание со стрелкой или иконка сети)
                HStack(spacing: 2.5) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.cyan)
                    Text(cleanDownload(context.state.compactDownloadText))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            } compactTrailing: {
                // Компактный вид справа: при замере стрелка отдачи, в обычном режиме — живой пинг с цветной точкой
                HStack(spacing: 2.5) {
                    if context.state.isTesting {
                        Text(cleanUpload(context.state.compactUploadText))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Color.green)
                    } else {
                        Circle()
                            .fill(pingColor(context.state.pingMs))
                            .frame(width: 5, height: 5)
                        Text(cleanPing(context.state.compactUploadText, ping: context.state.pingMs))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }
            } minimal: {
                // Минимальный вид (когда в островке активны 2 индикатора одновременно)
                HStack(spacing: 2) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Color.cyan)
                    Text(cleanDownload(context.state.compactDownloadText))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func cleanDownload(_ text: String) -> String {
        let s = text.replacingOccurrences(of: "↓", with: "")
            .replacingOccurrences(of: "↑", with: "")
            .trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "0 B" : s
    }

    private func cleanUpload(_ text: String) -> String {
        let s = text.replacingOccurrences(of: "↓", with: "")
            .replacingOccurrences(of: "↑", with: "")
            .trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "0 B" : s
    }

    private func cleanPing(_ text: String, ping: Double?) -> String {
        let s = text.replacingOccurrences(of: "↓", with: "")
            .replacingOccurrences(of: "↑", with: "")
            .trimmingCharacters(in: .whitespaces)
        if s.contains("ms") || s.contains("мс") {
            return s
        }
        if let p = ping, p > 0 {
            return String(format: "%.0fms", p)
        }
        if s.isEmpty || s == "0K" || s == "0" {
            return "Live"
        }
        return s
    }

    private func pingColor(_ ping: Double?) -> Color {
        guard let p = ping else { return .green }
        if p < 50 { return .green }
        if p < 120 { return .yellow }
        return .red
    }

    private func cleanSpeed(_ text: String) -> String {
        let s = text.replacingOccurrences(of: "↓", with: "")
            .replacingOccurrences(of: "↑", with: "")
            .trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "100M" : s
    }

    private func cleanISP(_ text: String) -> String {
        if text.isEmpty || text == "Подключение отсутствует" || text == "Интернет" {
            return "Мобильный интернет"
        }
        return text
    }

    private func cleanConnType(_ text: String) -> String {
        if text.isEmpty || text == "Нет соединения" || text == "Поиск сети..." {
            return "5G / LTE"
        }
        return text
    }
}

/// Баннер на экране блокировки с реальной скоростью
private struct LockScreenLiveActivityView: View {
    let state: NetPulseAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "speedometer")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.cyan)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("NetPulse Трафик")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(state.connectionType)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.cyan)
                }

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.cyan)
                        Text(state.downloadSpeedText)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: state.isTesting ? "arrow.up" : "network")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.green)
                        Text(state.uploadSpeedText)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                }
                Text(state.ispName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.07, green: 0.08, blue: 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
#endif

