//
//  TracerouteSheetView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Всплывающий экран с интерактивной трассировкой сетевого маршрута (MTR).
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
                            .foregroundStyle(.secondary)
                        Text(targetHost)
                            .font(.system(size: 18, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }
                    Spacer()
                    if isRunning {
                        HStack(spacing: 6) {
                            ProgressView()
                                .tint(.cyan)
                            Text("Сканирование...")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.cyan)
                        }
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.green)
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
                }
            }
        }
    }
}

private struct HopRowView: View {
    let hop: TracerouteHop

    var body: some View {
        HStack(spacing: 14) {
            // Номер хопа
            Text("\(hop.hopNumber)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.cyan.opacity(0.8))
                .clipShape(Circle())

            // IP и Hostname
            VStack(alignment: .leading, spacing: 2) {
                Text(hop.ipAddress ?? "* * *")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                if let host = hop.hostname {
                    Text(host)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Задержка и потери
            VStack(alignment: .trailing, spacing: 2) {
                if let lat = hop.latencyMs {
                    Text(String(format: "%.1f мс", lat))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(lat < 50 ? .green : (lat < 120 ? .yellow : .red))
                } else {
                    Text("LOST")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.red)
                }

                Text("Loss: \(Int(hop.lossPercent))%")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hop.lossPercent > 0 ? .red : .secondary)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
