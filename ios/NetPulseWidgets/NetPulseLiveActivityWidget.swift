//
//  NetPulseLiveActivityWidget.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / ActivityKit) - 2026.
//

import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(WidgetKit) && canImport(ActivityKit)
/// Виджет Live Activity и Dynamic Island: скорость загрузки и выгрузки в компактном режиме, пинг и детальная сеть по зажатию.
public struct NetPulseLiveActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: NetPulseAttributes.self) { context in
            // Экран блокировки / Баннер уведомлений
            LockScreenLiveActivityView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Расширенный вид (Expanded Region) по долгому зажатию островка
                // Левый регион: Скорость загрузки (Download Speed)
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.cyan)
                            Text("ЗАГРУЗКА")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(context.state.downloadSpeedText)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.leading, 8)
                }

                // Правый регион: Скорость выгрузки (Upload Speed)
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 4) {
                            Text("ВЫГРУЗКА")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.mint)
                        }
                        Text(context.state.uploadSpeedText)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.trailing, 8)
                }

                // Нижний регион (по зажатию): Панель задержки (Ping RTT), джиттера, потерь и сети
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        // Чип пинга с цветным индикатором задержки
                        HStack(spacing: 5) {
                            Circle()
                                .fill(pingColor(context.state.pingMs))
                                .frame(width: 6, height: 6)
                            Text(formatPingText(context.state.pingMs))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            Text("•")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.4))
                            Text(cleanConnType(context.state.connectionType))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())

                        Spacer()

                        // Правый блок: Джиттер, потери или статус Speedtest
                        if context.state.isTesting {
                            Text("Speedtest активен")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.cyan)
                        } else {
                            HStack(spacing: 6) {
                                if let jitter = context.state.jitterMs, jitter > 0 {
                                    Text("±\(String(format: "%.1f", jitter))мс")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .monospacedDigit()
                                        .foregroundStyle(.white.opacity(0.6))
                                }

                                if let loss = context.state.packetLossPct, loss > 0 {
                                    Text("Loss \(Int(loss))%")
                                        .font(.system(size: 9, weight: .heavy))
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.red.opacity(0.18))
                                        .clipShape(Capsule())
                                }

                                Text(cleanISP(context.state.ispName))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                }
            } compactLeading: {
                // MARK: - Компактный вид слева: Скачивание (Download)
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.cyan)
                    Text(cleanDownload(context.state.compactDownloadText))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } compactTrailing: {
                // MARK: - Компактный вид справа: Выгрузка / Отдача (Upload)
                HStack(spacing: 2) {
                    Text(cleanUpload(context.state.compactUploadText))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.mint)
                }
            } minimal: {
                // MARK: - Минимальный вид (Apple HIG: идеальное вписывание в круг 12pt без обрезки)
                ZStack {
                    if context.state.isTesting {
                        Image(systemName: "speedometer")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.cyan)
                    } else {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Color.cyan)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func cleanDownload(_ text: String) -> String {
        let s = text.replacingOccurrences(of: "↓", with: "")
            .replacingOccurrences(of: "↑", with: "")
            .trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "0K" : s
    }

    private func cleanUpload(_ text: String) -> String {
        let s = text.replacingOccurrences(of: "↓", with: "")
            .replacingOccurrences(of: "↑", with: "")
            .trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "0K" : s
    }

    private func formatPingText(_ ping: Double?) -> String {
        guard let p = ping, p > 0 else { return "-- ms" }
        return String(format: "%.0f ms PING", p)
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
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.mint)
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
                    if let p = state.pingMs, p > 0 {
                        Text(String(format: "%.0f ms", p))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(statusColor)
                    } else {
                        Text("LIVE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(statusColor)
                    }
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