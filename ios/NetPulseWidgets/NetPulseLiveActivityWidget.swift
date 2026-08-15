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
                                .foregroundStyle(.blue)
                            Text("СКАЧИВАНИЕ")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(context.state.downloadSpeedText)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
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
                                .foregroundStyle(.cyan)
                        }
                        Text(context.state.uploadSpeedText)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.cyan)
                    }
                    .padding(.trailing, 8)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text(context.state.ispName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        Text(context.state.connectionType)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform.path")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                            Text("Реальный сетевой трафик")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if context.state.isTesting {
                            Text("Speedtest активен")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)
                        } else {
                            Text("Мониторинг")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                }
            } compactLeading: {
                // Компактный вид (слева от выреза) - РЕАЛЬНАЯ СКОРОСТЬ СКАЧИВАНИЯ
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.blue)
                    Text(context.state.compactDownloadText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            } compactTrailing: {
                // Компактный вид (справа от выреза) - РЕАЛЬНАЯ СКОРОСТЬ ОТДАЧИ
                HStack(spacing: 2) {
                    Text(context.state.compactUploadText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.cyan)
                }
            } minimal: {
                // Минимальный вид
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
            }
        }
    }
}

/// Баннер на экране блокировки с реальной скоростью
private struct LockScreenLiveActivityView: View {
    let state: NetPulseAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.up.arrow.down.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 3) {
                Text("NetPulse Трафик")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.blue)
                        Text(state.downloadSpeedText)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.cyan)
                        Text(state.uploadSpeedText)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.cyan)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
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
