//
//  TracerouteSheetView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Интерактивный экран трассировки маршрута (MTR 2026) с топологической картой узлов (Node-Hop Pipeline)
public struct TracerouteSheetView: View {
    public let targetHost: String
    public let hops: [TracerouteHop]
    public let isRunning: Bool
    @Environment(\.dismiss) private var dismiss

    private var averageLatency: Double? {
        let validLatencies = hops.compactMap { $0.latencyMs }
        guard !validLatencies.isEmpty else { return nil }
        return validLatencies.reduce(0, +) / Double(validLatencies.count)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Информационный баннер цели и сводки
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("ЦЕЛЕВОЙ УЗЕЛ МАРШРУТИЗАЦИИ")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(NPTheme.textSecondary)
                                    .tracking(0.5)
                                Text(targetHost)
                                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(NPTheme.accentPrimary)
                            }
                            Spacer()
                            if isRunning {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .tint(NPTheme.accentPrimary)
                                        .scaleEffect(0.85)
                                    Text("Сканирование...")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(NPTheme.accentSoft)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(NPTheme.accentPrimary.opacity(0.12))
                                .clipShape(Capsule())
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(NPTheme.semanticOK)
                                    Text("Маршрут построен")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(NPTheme.textPrimary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(NPTheme.cardBackgroundTertiary)
                                .clipShape(Capsule())
                            }
                        }

                        // Сводка хопов
                        HStack(spacing: 10) {
                            HopStatPill(title: "Хопов в пути", value: "\(hops.count)")
                            HopStatPill(title: "Ср. задержка", value: averageLatency != nil ? String(format: "%.1f мс", averageLatency!) : "—")
                            HopStatPill(
                                title: "Потери",
                                value: "\(hops.filter { $0.lossPercent > 0 }.count) узлов",
                                isAlert: hops.contains(where: { $0.lossPercent > 0 })
                            )
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundStyle(NPTheme.border),
                        alignment: .bottom
                    )

                    // Топологическая цепочка узлов (Node-Hop Pipeline)
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(hops.enumerated()), id: \.element.id) { index, hop in
                                NodeHopRowView(
                                    hop: hop,
                                    isFirst: index == 0,
                                    isLast: index == hops.count - 1
                                )
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Traceroute MTR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(NPTheme.accentPrimary)
                }
            }
        }
    }
}

/// Мини-статистика в шапке Traceroute
private struct HopStatPill: View {
    let title: String
    let value: String
    var isAlert: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(NPTheme.textSecondary)
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(isAlert ? NPTheme.semanticCritical : NPTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(NPTheme.cardBackgroundTertiary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Строка узла трассировки со связующим каналом (Node-Hop Pipeline Item)
private struct NodeHopRowView: View {
    let hop: TracerouteHop
    let isFirst: Bool
    let isLast: Bool

    private var nodeIcon: String {
        if isFirst {
            return "wifi.router.fill"
        } else if isLast {
            return "server.rack"
        } else {
            return "point.3.connected.trianglepath.dotted"
        }
    }

    private var nodeRoleName: String {
        if isFirst {
            return "Локальный шлюз (Wi-Fi/LAN)"
        } else if isLast {
            return "Целевой сервер"
        } else {
            return "Магистральный узел #\(hop.hopNumber)"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Вертикальная линия соединения с анимированным узлом
            VStack(spacing: 0) {
                // Точка узла
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.18))
                        .frame(width: 32, height: 32)

                    Circle()
                        .stroke(statusColor, lineWidth: 1.5)
                        .frame(width: 32, height: 32)
                        .shadow(color: statusColor.opacity(0.4), radius: 4)

                    Image(systemName: nodeIcon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(statusColor)
                }

                // Связующая линия вниз к следующему узлу
                if !isLast {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [statusColor.opacity(0.6), NPTheme.border],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2, height: 38)
                }
            }

            // Карточка с деталями хопа
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Хоп \(hop.hopNumber)")
                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                .foregroundStyle(NPTheme.accentPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(NPTheme.accentPrimary.opacity(0.12))
                                .clipShape(Capsule())

                            Text(nodeRoleName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(NPTheme.textSecondary)
                        }

                        Text(hop.ipAddress ?? "* * * (Таймаут)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(NPTheme.textPrimary)

                        if let host = hop.hostname {
                            Text(host)
                                .font(.system(size: 11))
                                .foregroundStyle(NPTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Задержка и потери
                    VStack(alignment: .trailing, spacing: 2) {
                        if let lat = hop.latencyMs {
                            Text(String(format: "%.1f мс", lat))
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(statusColor)
                        } else {
                            Text("LOST")
                                .font(.system(size: 12, weight: .heavy))
                                .monospacedDigit()
                                .foregroundStyle(NPTheme.semanticCritical)
                        }

                        Text("Loss: \(Int(hop.lossPercent))%")
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(hop.lossPercent > 0 ? NPTheme.semanticCritical : NPTheme.textSecondary)
                    }
                }
            }
            .padding(12)
            .npGlassCard(cornerRadius: 14)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Узел \(hop.hopNumber): \(hop.ipAddress ?? "таймаут"), задержка \(hop.latencyMs != nil ? String(format: "%.1f мс", hop.latencyMs!) : "потеря пакета")")
        }
        .padding(.bottom, isLast ? 0 : 8)
    }

    private var statusColor: Color {
        if let lat = hop.latencyMs {
            if hop.lossPercent > 0 {
                return NPTheme.semanticCritical
            } else if lat < 45 {
                return NPTheme.accentPrimary
            } else if lat < 110 {
                return NPTheme.semanticWarn
            } else {
                return NPTheme.semanticCritical
            }
        }
        return NPTheme.semanticCritical
    }
}
