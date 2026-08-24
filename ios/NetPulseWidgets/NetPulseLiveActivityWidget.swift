//
//  NetPulseLiveActivityWidget.swift
//  NetPulseWidgets
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
                                .foregroundStyle(.white)
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
                            Text("ОТДАЧА")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
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
                            Image(systemName: "waveform.path")
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                            Text("Реальный сетевой трафик")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if context.state.isTesting {
                            Text("Speedtest активен")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("Мониторинг")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                }
            } compactLeading: {
                // Компактный вид слева (скачивание с белой стрелкой и цифрами)
                HStack(spacing: 2.5) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(cleanSpeed(context.state.compactDownloadText))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            } compactTrailing: {
                // Компактный вид справа (отдача с белой стрелкой и цифрами)
                HStack(spacing: 2.5) {
                    Text(cleanSpeed(context.state.compactUploadText))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                }
            } minimal: {
                // Минимальный вид (когда в островке активны 2 индикатора одновременно)
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(cleanSpeed(context.state.compactDownloadText))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func cleanSpeed(_ text: String) -> String {
        let s = text.replacingOccurrences(of: "↓", with: "").replacingOccurrences(of: "↑", with: "").trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "0K" : s
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
            Image(systemName: "arrow.up.arrow.down.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 3) {
                Text("NetPulse Трафик")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                        Text(state.downloadSpeedText)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
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
                        .fill(Color.white)
                        .frame(width: 5, height: 5)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                Text(state.connectionType)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground))
    }
}
#endif
