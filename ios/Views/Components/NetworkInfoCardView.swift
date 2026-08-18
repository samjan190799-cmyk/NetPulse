//
//  NetworkInfoCardView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Карточка системной информации и сетевого интерфейса в стиле «Obsidian Mono».
public struct NetworkInfoCardView: View {
    public let info: NetworkInterfaceInfo
    public let isMonitoring: Bool

    public var body: some View {
        VStack(spacing: 16) {
            // Верхняя строка: Тип подключения и статус
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: iconForConnectionType(info.connectionType))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isMonitoring ? NPTheme.accentPrimary : NPTheme.textSecondary)

                    Text(info.connectionType.rawValue)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(NPTheme.textPrimary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(isMonitoring ? NPTheme.accentPrimary : NPTheme.semanticWarn)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isMonitoring ? 1.1 : 0.9)
                        .animation(.easeInOut(duration: 0.8).repeatForever(), value: isMonitoring)

                    Text(isMonitoring ? "ONLINE" : "PAUSED")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(isMonitoring ? NPTheme.accentPrimary : NPTheme.semanticWarn)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isMonitoring ? NPTheme.accentPrimary.opacity(0.08) : NPTheme.semanticWarn.opacity(0.1))
                .clipShape(Capsule())
            }

            Divider()
                .background(NPTheme.border)

            // Сетка параметров
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                InfoItem(title: "Локальный IP", value: info.localIP, icon: "network")
                InfoItem(title: "Шлюз", value: info.gatewayIP ?? "...", icon: "arrow.triangle.branch")
                InfoItem(title: "Публичный IP", value: info.publicIP ?? "...", icon: "globe")
                InfoItem(title: "Провайдер", value: info.ispName ?? "...", icon: "antenna.radiowaves.left.and.right")
            }
        }
        .padding(16)
        .npCardStyle()
    }

    private func iconForConnectionType(_ type: NetworkConnectionType) -> String {
        switch type {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .ethernet: return "cable.connector"
        case .loopback: return "arrow.triangle.2.circlepath"
        case .unavailable: return "wifi.slash"
        }
    }
}

private struct InfoItem: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NPTheme.textSecondary)
                .frame(width: 26, height: 26)
                .background(NPTheme.cardBackgroundTertiary)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(NPTheme.textSecondary)
                Text(value)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(NPTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}
