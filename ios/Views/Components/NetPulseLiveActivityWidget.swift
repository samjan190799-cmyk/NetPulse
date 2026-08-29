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
/// Виджет Live Activity и Dynamic Island для отображения реальной скорости, пинга и гейминг-статуса в реальном времени.
public struct NetPulseLiveActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: NetPulseAttributes.self) { context in
            // Экран блокировки / Баннер уведомлений
            LockScreenLiveActivityView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Расширенный вид (Expanded Region)
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: context.state.isGamingMode ? "gamecontroller.fill" : "arrow.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(context.state.isGamingMode ? Color.mint : Color.cyan)
                            Text(context.state.isGamingMode ? (context.state.gameTitle ?? "ГЕЙМИНГ") : "СКАЧИВАНИЕ")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(context.state.downloadSpeedText)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.leading, 8)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(context.state.isTesting ? "ОТДАЧА" : (context.state.isGamingMode ? "PING RTT" : "RTT ПИНГ"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Image(systemName: context.state.isTesting ? "arrow.up" : (context.state.isGamingMode ? "bolt.fill" : "network"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(pingColor(context.state.pingMs))
                        }
                        Text(context.state.isTesting ? context.state.uploadSpeedText : (context.state.pingMs != nil ? String(format: "%.0f ms", context.state.pingMs!) : context.state.uploadSpeedText))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.trailing, 8)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(context.state.isGamingMode ? Color.mint : Color.green)
                                .frame(width: 6, height: 6)
                            Text(context.state.isGamingMode ? (context.state.gameRegion ?? cleanISP(context.state.ispName)) : cleanISP(context.state.ispName))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        Text(cleanConnType(context.state.connectionType))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: context.state.isGamingMode ? "gamecontroller" : "waveform.path.ecg")
                                .font(.system(size: 10))
                                .foregroundStyle(context.state.isGamingMode ? .mint : .cyan)
                            Text(context.state.isGamingMode ? "Киберспортивный HUD" : "NetPulse Мониторинг")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if context.state.isTesting {
                            Text("Speedtest активен")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.cyan)
                        } else if let jitter = context.state.jitterMs, jitter > 0 {
                            HStack(spacing: 5) {
                                Text("Джиттер: ±\(String(format: "%.1f", jitter))мс")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)

                                if let loss = context.state.packetLossPct, loss > 0 {
                                    Text("Loss \(Int(loss))%")
                                        .font(.system(size: 9, weight: .heavy))
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.red.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
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
                // MARK: - Компактный вид слева
                HStack(spacing: 2.5) {
                    Image(systemName: context.state.isGamingMode ? "gamecontroller.fill" : "arrow.down")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(context.state.isGamingMode ? Color.mint : Color.cyan)
                    Text(cleanDownload(context.state.compactDownloadText))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            } compactTrailing: {
                // MARK: - Компактный вид справа
                HStack(spacing: 2.5) {
                    if context.state.isTesting {
                        Text(cleanUpload(context.state.compactUploadText))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            } minimal: {
                // MARK: - Минимальный вид
                HStack(spacing: 2) {
                    Image(systemName: context.state.isGamingMode ? "gamecontroller.fill" : "gauge.with.dots.needle.67percent")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(context.state.isGamingMode ? Color.mint : Color.cyan)
                    Text(context.state.isGamingMode ? cleanPing(context.state.compactUploadText, ping: context.state.pingMs) : cleanDownload(context.state.compactDownloadText))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
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
        if p < 45 { return .green }
        if p < 95 { return .yellow }
        return .red
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

/// Баннер на экране блокировки с реальной скоростью и пингом
private struct LockScreenLiveActivityView: View {
    let state: NetPulseAttributes.ContentState

    private var statusColor: Color {
        guard let p = state.pingMs else { return .green }
        if p < 45 { return .green }
        if p < 95 { return .yellow }
        return .red
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((state.isGamingMode ? Color.mint : Color.cyan).opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: state.isGamingMode ? "gamecontroller.fill" : "speedometer")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(state.isGamingMode ? Color.mint : Color.cyan)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(state.isGamingMode ? (state.gameTitle ?? "Gaming Radar") : "NetPulse Трафик")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(state.isGamingMode ? (state.gameRegion ?? state.connectionType) : state.connectionType)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(state.isGamingMode ? .mint : .cyan)
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.cyan)
                        Text(state.downloadSpeedText)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: state.isTesting ? "arrow.up" : (state.isGamingMode ? "bolt.fill" : "network"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(statusColor)
                        Text(state.uploadSpeedText)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor)
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

