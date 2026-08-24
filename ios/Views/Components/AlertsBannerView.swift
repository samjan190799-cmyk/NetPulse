//
//  AlertsBannerView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Всплывающий Glassmorphic баннер активных сетевых предупреждений (Obsidian Mono).
public struct AlertsBannerView: View {
    public let alert: NetworkAlert
    public let onDismiss: () -> Void

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: alert.severity == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(alert.severity == .critical ? NPTheme.semanticCritical : NPTheme.semanticWarn)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.targetName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)

                Text(alert.message)
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(NPTheme.textSecondary)
            }
            .npMinHitTarget()
            .accessibilityLabel("Закрыть оповещение")
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(alert.severity == .critical ? NPTheme.semanticCritical.opacity(0.4) : NPTheme.semanticWarn.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
