//
//  NetPulseLiveActivityWidget.swift
//  NetPulseWidgets
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
                // Левый регион: Скачивание (Download Speed)
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Image(systemName: context.state.isGamingMode ? "gamecontroller.fill" : "arrow.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(context.state.isGamingMode ? Color.mint : Color.cyan)
                            Text(context.state.isGamingMode ? (context.state.gameTitle ?? "ГЕЙМИНГ") : "СКАЧИВАНИЕ")
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

                // Правый регион: Отдача или живой RTT пинг
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(context.state.isTesting ? "ОТДАЧА" : (context.state.isGamingMode ? "PING RTT" : "RTT ПИНГ"))
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.secondary)
                            Image(systemName: context.state.isTesting ? "arrow.up" : "bolt.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(context.state.isTesting ? Color.mint : pingColor(context.state.pingMs))
                        }
                        Text(context.state.isTesting ? context.state.uploadSpeedText : (context.state.pingMs.map { String(format: "%.0f ms", $0) } ?? context.state.uploadSpeedText))
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.trailing, 8)
                }

                // Нижний регион: Полноразмерная информационная панель под камерой TrueDepth
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        // Левый чип: Сеть и провайдер
                        HStack(spacing: 5) {
                            Circle()
                                .fill(pingColor(context.state.pingMs))
                                .frame(width: 6, height: 6)
                            Text(cleanConnType(context.state.connectionType))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                            Text("•")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.4))
                            Text(context.state.isGamingMode ? (context.state.gameRegion ?? cleanISP(context.state.ispName)) : cleanISP(context.state.ispName))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())

                        Spacer()

                        // Правый блок: Статус замера, джиттер и процент потерь
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

                                if !isPingValue(context.state.compactUploadText) && !isNegligibleUpload(context.state.compactUploadText) {
                                    HStack(spacing: 2) {
                                        Image(systemName: "arrow.up")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(Color.mint)
                                        Text(cleanUpload(context.state.compactUploadText))
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .monospacedDigit()
                                            .foregroundStyle(Color.mint)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.mint.opacity(0.12))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                }
            } compactLeading: {
                // MARK: - Компактный вид слева
                HStack(spacing: 3) {
                    Image(systemName: context.state.isGamingMode ? "gamecontroller.fill" : "arrow.down")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(context.state.isGamingMode ? Color.mint : Color.cyan)
                    Text(cleanDownload(context.state.compactDownloadText))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            } compactTrailing: {
                // MARK: - Компактный вид справа (БЕЗ ложных стрелок вверх для пинга)
                HStack(spacing: 3) {
                    if context.state.isTesting {
                        // Активный замер отдачи: скорость со стрелкой вверх
                        Text(cleanUpload(context.state.compactUploadText))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Color.mint)
                    } else if context.state.isGamingMode || isPingValue(context.state.compactUploadText) || isNegligibleUpload(context.state.compactUploadText) {
                        // Живой пинг: цветной статус-индикатор + значение RTT (БЕЗ стрелки вверх)
                        Circle()
                            .fill(pingColor(context.state.pingMs))
                            .frame(width: 5, height: 5)
                            .shadow(color: pingColor(context.state.pingMs).opacity(0.6), radius: 2)
                        Text(cleanPing(context.state.compactUploadText, ping: context.state.pingMs))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    } else {
                        // Реальная активная отдача трафика (> 50 КБ/с)
                        Text(cleanUpload(context.state.compactUploadText))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Color.mint)
                    }
                }
            } minimal: {
                // MARK: - Минимальный вид (Apple HIG: идеальное вписывание в круг 12pt без обрезки)
                ZStack {
                    if context.state.isGamingMode {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.mint)
                    } else if context.state.isTesting {
                        Image(systemName: "speedometer")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.cyan)
                    } else {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(pingColor(context.state.pingMs))
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
        return s.isEmpty ? "0 B" : s
    }

    private func cleanUpload(_ text: String) -> String {
        let s = text.replacingOccurrences(of: "↓", with: "")
            .replacingOccurrences(of: "↑", with: "")
            .trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "0 B" : s
    }

    private func isPingValue(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("ms") || lower.contains("мс")
    }

    private func isNegligibleUpload(_ text: String) -> Bool {
        let s = cleanUpload(text).lowercased()
        return s == "0 b" || s == "0b" || s == "0 k" || s == "0k" || s == "0 m" || s == "0" || s.isEmpty
    }

    private func cleanPing(_ text: String, ping: Double?) -> String {
        if let p = ping, p > 0 {
            return String(format: "%.0fms", p)
        }
        let s = text.replacingOccurrences(of: "↓", with: "")
            .replacingOccurrences(of: "↑", with: "")
            .trimmingCharacters(in: .whitespaces)
        if s.contains("ms") || s.contains("мс") {
            return s
        }
        return "Live"
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
                        Image(systemName: state.isTesting ? "arrow.up" : (state.isGamingMode ? "bolt.fill" : "arrow.up"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(state.isTesting ? Color.mint : statusColor)
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
