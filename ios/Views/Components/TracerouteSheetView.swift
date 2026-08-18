//
//  TracerouteSheetView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Всплывающий экран трассировки маршрута (MTR) в стиле «Obsidian Mono».
public struct TracerouteSheetView: View {
    public let targetHost: String
    public let hops: [TracerouteHop]
    public let isRunning: Bool
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Информационный баннер
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ТРАССИРОВКА ДО УЗЛА")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NPTheme.textSecondary)
                        Text(targetHost)
                            .font(.system(size: 18, weight: .heavy, design: .monospaced))
                            .foregroundStyle(NPTheme.accentPrimary)
                    }
                    Spacer()
                    if isRunning {
                        HStack(spacing: 6) {
                            ProgressView()
                                .tint(NPTheme.accentPrimary)
                            Text("Сканирование...")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(NPTheme.accentSoft)
                        }
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(NPTheme.accentPrimary)
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial)

                Divider()

                // Список хопов
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(hops) { hop in
                            HopRowView(hop: hop)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Traceroute MTR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(NPTheme.accentPrimary)
                }
            }
        }
    }
}

private struct HopRowView: View {
    let hop: TracerouteHop

    var body: some View {
        HStack(spacing: 14) {
            // Номер хопа — белый бейдж с тёмным текстом
            Text("\(hop.hopNumber)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(NPTheme.backgroundDeep)
                .frame(width: 28, height: 28)
                .background(NPTheme.accentPrimary)
                .clipShape(Circle())

            // IP и Hostname
            VStack(alignment: .leading, spacing: 2) {
                Text(hop.ipAddress ?? "* * *")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(NPTheme.textPrimary)
                if let host = hop.hostname {
                    Text(host)
                        .font(.system(size: 11))
                        .foregroundStyle(NPTheme.textSecondary)
                }
            }

            Spacer()

            // Задержка и потери
            VStack(alignment: .trailing, spacing: 2) {
                if let lat = hop.latencyMs {
                    Text(String(format: "%.1f мс", lat))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(lat < 50 ? NPTheme.accentPrimary : (lat < 120 ? NPTheme.semanticWarn : NPTheme.semanticCritical))
                } else {
                    Text("LOST")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(NPTheme.semanticCritical)
                }

                Text("Loss: \(Int(hop.lossPercent))%")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hop.lossPercent > 0 ? NPTheme.semanticCritical : NPTheme.textSecondary)
            }
        }
        .padding(14)
        .npCardStyle(cornerRadius: 14)
    }
}
