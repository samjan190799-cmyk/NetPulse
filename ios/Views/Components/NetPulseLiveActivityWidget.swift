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
/// Виджет Live Activity и Dynamic Island для отображения скорости и пинга в реальном времени.
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
                        Text(String(format: "%.1f", context.state.downloadMbps))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("Мбит/с")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
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
                        Text(String(format: "%.1f", context.state.uploadMbps))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("Мбит/с")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 8)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(context.state.pingMs != nil && context.state.pingMs! < 80 ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(context.state.ispName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        if let ping = context.state.pingMs {
                            Text("Пинг: \(Int(ping)) мс")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.connectionType)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if context.state.isTesting {
                            Text("Идет замер...")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.blue)
                        } else {
                            Text("Мониторинг активен")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                }
            } compactLeading: {
                // Компактный вид (слева от выреза)
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.blue)
                    let speed = context.state.downloadMbps > 0 ? context.state.downloadMbps : context.state.uploadMbps
                    if speed > 0 {
                        Text(String(format: "%.0f", speed))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    } else {
                        Text("ON")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                    }
                }
            } compactTrailing: {
                // Компактный вид (справа от выреза)
                if let ping = context.state.pingMs {
                    Text("\(Int(ping))мс")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ping < 80 ? .green : .orange)
                } else {
                    Text("Live")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                }
            } minimal: {
                // Минимальный вид (когда остров разделен с другим приложением)
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
            }
        }
    }
}

/// Баннер на экране блокировки
private struct LockScreenLiveActivityView: View {
    let state: NetPulseAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 24))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("NetPulse Скорость")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Text("↓ \(String(format: "%.1f", state.downloadMbps)) Мбит/с")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.blue)

                    Text("↑ \(String(format: "%.1f", state.uploadMbps)) Мбит/с")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.cyan)
                }
            }

            Spacer()

            if let ping = state.pingMs {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(ping)) мс")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(ping < 80 ? .green : .orange)
                    Text("RTT")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground))
    }
}
#endif
