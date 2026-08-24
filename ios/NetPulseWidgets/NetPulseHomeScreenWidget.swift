//
//  NetPulseHomeScreenWidget.swift
//  NetPulseWidgets
//
//  Created for iOS (Swift 6.0+ / SwiftUI / WidgetKit) - 2026.
//

import SwiftUI
import WidgetKit

/// Запись таймлайна виджета NetPulse
public struct NetPulseWidgetEntry: TimelineEntry {
    public let date: Date
    public let data: NetPulseWidgetData

    public init(date: Date, data: NetPulseWidgetData) {
        self.date = date
        self.data = data
    }
}

/// Поставщик таймлайна для домашних виджетов и экрана блокировки NetPulse
public struct NetPulseWidgetProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> NetPulseWidgetEntry {
        NetPulseWidgetEntry(date: Date(), data: .placeholder)
    }

    public func getSnapshot(in context: Context, completion: @escaping (NetPulseWidgetEntry) -> Void) {
        let snapshotData = WidgetDataManager.shared.loadLatestSnapshot()
        let entry = NetPulseWidgetEntry(date: Date(), data: snapshotData)
        completion(entry)
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<NetPulseWidgetEntry>) -> Void) {
        let currentData = WidgetDataManager.shared.loadLatestSnapshot()
        let currentDate = Date()
        let entry = NetPulseWidgetEntry(date: currentDate, data: currentData)

        // Обновление таймлайна каждые 15 минут
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate) ?? currentDate.addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Представление виджета для всех семейств экранов

public struct NetPulseWidgetEntryView: View {
    public var entry: NetPulseWidgetProvider.Entry
    @Environment(\.widgetFamily) var family

    public var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(data: entry.data)
            case .systemMedium:
                MediumWidgetView(data: entry.data)
            case .systemLarge:
                LargeWidgetView(data: entry.data)
            case .accessoryCircular:
                AccessoryCircularView(data: entry.data)
            case .accessoryRectangular:
                AccessoryRectangularView(data: entry.data)
            case .accessoryInline:
                AccessoryInlineView(data: entry.data)
            default:
                SmallWidgetView(data: entry.data)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.08, blue: 0.12),
                    Color(red: 0.02, green: 0.03, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - 1. Компактный виджет (Small: 2x2)

private struct SmallWidgetView: View {
    let data: NetPulseWidgetData

    private var statusColor: Color {
        if let ping = data.pingMs {
            if ping < 50 { return .green }
            if ping < 120 { return .orange }
            return .red
        }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Верх: Иконка и тип подключения
            HStack(spacing: 5) {
                Image(systemName: "wifi")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)

                Text(data.connectionType)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)

                Spacer()

                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: statusColor.opacity(0.6), radius: 3)
            }

            Spacer()

            // Центр: Крупная задержка RTT
            VStack(alignment: .leading, spacing: 0) {
                Text("RTT ПИНГ")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(0.5)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(data.pingMs != nil ? String(format: "%.0f", data.pingMs!) : "—")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)

                    Text("мс")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()

            // Низ: Джиттер и Health Score
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.cyan)
                    Text(data.formattedJitter)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.cyan)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.cyan.opacity(0.12))
                .clipShape(Capsule())

                Spacer()

                HStack(spacing: 2) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green)
                    Text("\(data.healthScore)")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
            }
        }
        .padding(4)
    }
}

// MARK: - 2. Средний виджет (Medium: 4x2)

private struct MediumWidgetView: View {
    let data: NetPulseWidgetData

    private var formattedTrafficMB: String {
        let mb = Double(data.todayTrafficBytes) / 1_048_576.0
        if mb >= 1024.0 {
            return String(format: "%.1f ГБ", mb / 1024.0)
        }
        return String(format: "%.0f МБ", mb)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Левая колонка: Скорость и задержка
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.cyan)
                    Text("СКОРОСТЬ")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.6))
                        .tracking(0.5)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                            Text("DOWN")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Text(String(format: "%.1f", data.downloadSpeedMbps))
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("Мбит/с")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.cyan)
                            Text("UP")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.cyan.opacity(0.7))
                        }
                        Text(String(format: "%.1f", data.uploadSpeedMbps))
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.cyan)
                        Text("Мбит/с")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.cyan.opacity(0.6))
                    }
                }

                HStack(spacing: 6) {
                    Text("Пинг: \(data.formattedPing)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            Divider()
                .background(Color.white.opacity(0.15))

            // Правая колонка: Трафик и лимит
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.green)
                        Text("ТРАФИК СЕГОДНЯ")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Text("\(data.healthScore)%")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.green)
                }

                Text(formattedTrafficMB)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                // Прогресс-бар лимита трафика
                VStack(alignment: .leading, spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 5)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.cyan, .green],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(data.budgetProgress), height: 5)
                        }
                    }
                    .frame(height: 5)

                    HStack {
                        Text("\(Int(data.budgetProgress * 100))% лимита")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Text(data.ispName)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(2)
    }
}

// MARK: - 3. Большой виджет (Large: 4x4)

private struct LargeWidgetView: View {
    let data: NetPulseWidgetData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Шапка: Имя провайдера, тип сети и Health Score
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.cyan)
                        Text(data.connectionType)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Text(data.ispName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()

                // Health Score бейдж
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                    Text("Health \(data.healthScore)/100")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
            }

            // Метрики качества в 4 ячейках
            HStack(spacing: 8) {
                LargeMetricCell(title: "Скачивание", value: String(format: "%.1f", data.downloadSpeedMbps), unit: "Мбит/с", icon: "arrow.down", color: .white)
                LargeMetricCell(title: "Отдача", value: String(format: "%.1f", data.uploadSpeedMbps), unit: "Мбит/с", icon: "arrow.up", color: .cyan)
                LargeMetricCell(title: "Пинг", value: data.pingMs != nil ? String(format: "%.0f", data.pingMs!) : "—", unit: "мс", icon: "network", color: .green)
                LargeMetricCell(title: "Джиттер", value: data.jitterMs != nil ? String(format: "%.1f", data.jitterMs!) : "—", unit: "мс", icon: "waveform.path.ecg", color: .orange)
            }

            Divider()
                .background(Color.white.opacity(0.15))

            // Статус целевых DNS-узлов
            VStack(alignment: .leading, spacing: 6) {
                Text("МОНИТОРИНГ УЗЛОВ И DNS")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(0.5)

                if data.dnsHosts.isEmpty {
                    Text("1.1.1.1, 8.8.8.8, Шлюз LAN онлайн")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(data.dnsHosts.prefix(4)) { host in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(host.isOK ? Color.green : Color.red)
                                    .frame(width: 6, height: 6)
                                Text(host.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer()
                                Text(host.latencyMs != nil ? String(format: "%.0fмс", host.latencyMs!) : "—")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }

            Spacer()

            // Нижняя плашка времени обновления
            HStack {
                Text("Обновлено: \(data.lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text("NetPulse 2026")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.cyan.opacity(0.8))
            }
        }
        .padding(2)
    }
}

private struct LargeMetricCell: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(unit)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - 4. Виджеты экрана блокировки (Accessory Widgets)

private struct AccessoryCircularView: View {
    let data: NetPulseWidgetData

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(data.pingMs != nil ? String(format: "%.0f", data.pingMs!) : "—")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("ms")
                    .font(.system(size: 8, weight: .bold))
            }
        }
    }
}

private struct AccessoryRectangularView: View {
    let data: NetPulseWidgetData

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 10, weight: .bold))
                Text("NetPulse • \(data.connectionType)")
                    .font(.system(size: 11, weight: .bold))
            }

            Text("RTT: \(data.formattedPing) (Jitter: \(data.formattedJitter))")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .monospacedDigit()

            Text("↓ \(String(format: "%.0f", data.downloadSpeedMbps)) Mbps • ↑ \(String(format: "%.0f", data.uploadSpeedMbps)) Mbps")
                .font(.system(size: 10, weight: .regular))
                .monospacedDigit()
        }
    }
}

private struct AccessoryInlineView: View {
    let data: NetPulseWidgetData

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bolt.fill")
            Text("\(data.formattedPing) • ↓\(String(format: "%.0f", data.downloadSpeedMbps))M")
                .monospacedDigit()
        }
    }
}

// MARK: - Главная декларация домашнего виджета WidgetKit

public struct NetPulseHomeScreenWidget: Widget {
    public let kind: String = "NetPulseHomeScreenWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NetPulseWidgetProvider()) { entry in
            NetPulseWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("NetPulse Монитор")
        .description("Живой статус сети, задержка RTT, скорость соединения и расход трафика.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}
