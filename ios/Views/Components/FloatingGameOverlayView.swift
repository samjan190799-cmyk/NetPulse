//
//  FloatingGameOverlayView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Премиальный плавающий игровой HUD-виджет 2.0 (2026) с живым спарклайном задержки,
/// магнитной физикой краев экрана (Magnetic Edge Snapping) и ультратонким стеклом.
public struct FloatingGameOverlayView: View {
    @Binding public var isCollapsed: Bool
    public let downloadSpeedText: String
    public let uploadSpeedText: String
    public let pingMs: Double?
    public let jitterMs: Double?
    public let packetLossPct: Double
    public let onTogglePiP: () -> Void
    public let onClose: () -> Void

    @State private var offset: CGSize = CGSize(width: 16, height: 75)
    @State private var dragTranslation: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var pingHistory: [Double] = [24, 26, 25, 23, 28, 24, 25, 27, 24, 23]

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                if isCollapsed {
                    // Свернутый режим (Компактная стеклянная капсула с индикатором пинга)
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(NPTheme.accentPrimary)

                        Text(downloadSpeedText)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(NPTheme.accentPrimary)

                        if let ping = pingMs {
                            Circle()
                                .fill(ping < 45 ? NPTheme.semanticOK : (ping < 100 ? NPTheme.semanticWarn : NPTheme.semanticCritical))
                                .frame(width: 5, height: 5)

                            Text(String(format: "%.0fms", ping))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(NPTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.4))
                            .background(.ultraThinMaterial, in: Capsule())
                    )
                    .overlay(
                        Capsule()
                            .stroke(NPTheme.border, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 6, y: 2)
                    .onTapGesture {
                        HapticManager.shared.impactLight()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            isCollapsed = false
                        }
                    }
                } else {
                    // Развернутый режим (Игровой HUD с метриками и мини-спарклайном)
                    VStack(spacing: 6) {
                        HStack(spacing: 10) {
                            // 1. Скачивание
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(NPTheme.accentPrimary)

                                VStack(alignment: .leading, spacing: 0) {
                                    Text(downloadSpeedText)
                                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(NPTheme.accentPrimary)
                                    Text("DOWN")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(NPTheme.textTertiary)
                                }
                            }

                            Divider()
                                .frame(height: 16)
                                .background(NPTheme.border)

                            // 2. Отдача
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(NPTheme.accentSilver)

                                VStack(alignment: .leading, spacing: 0) {
                                    Text(uploadSpeedText)
                                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(NPTheme.accentSilver)
                                    Text("UP")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(NPTheme.textTertiary)
                                }
                            }

                            Divider()
                                .frame(height: 16)
                                .background(NPTheme.border)

                            // 3. Пинг, джиттер и потери пакетов
                            HStack(spacing: 4) {
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack(spacing: 3) {
                                        Text(pingMs != nil ? String(format: "%.0f ms", pingMs!) : "—")
                                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                                            .monospacedDigit()
                                            .foregroundStyle(pingColor)

                                        if packetLossPct > 0 {
                                            Text("\(Int(packetLossPct))%L")
                                                .font(.system(size: 7, weight: .heavy))
                                                .foregroundStyle(NPTheme.semanticCritical)
                                                .padding(.horizontal, 3)
                                                .padding(.vertical, 1)
                                                .background(NPTheme.semanticCritical.opacity(0.2))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    HStack(spacing: 2) {
                                        Text("PING")
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundStyle(NPTheme.textTertiary)
                                        if let j = jitterMs, j > 0 {
                                            Text("• ±\(String(format: "%.0f", j))")
                                                .font(.system(size: 7, weight: .medium, design: .monospaced))
                                                .foregroundStyle(NPTheme.textTertiary)
                                        }
                                    }
                                }
                            }

                            // 4. Кнопка PiP
                            Button(action: {
                                HapticManager.shared.impactMedium()
                                onTogglePiP()
                            }) {
                                Image(systemName: "pip.enter")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(NPTheme.accentPrimary)
                                    .padding(4)
                                    .background(NPTheme.accentPrimary.opacity(0.12))
                                    .clipShape(Circle())
                            }

                            // 5. Кнопка сворачивания
                            Button(action: {
                                HapticManager.shared.impactLight()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    isCollapsed = true
                                }
                            }) {
                                Image(systemName: "chevron.left.2")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(NPTheme.textTertiary)
                                    .padding(3)
                            }

                            // 6. Кнопка закрытия
                            Button(action: {
                                HapticManager.shared.impactLight()
                                onClose()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(NPTheme.textTertiary)
                                    .padding(3)
                            }
                        }

                        // Мини-спарклайн пинга в нижней части HUD
                        if !pingHistory.isEmpty {
                            HUDMiniSparkline(data: pingHistory, color: pingColor)
                                .frame(height: 10)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black.opacity(0.4))
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [NPTheme.border, Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 8, y: 3)
                }
            }
            .scaleEffect(isDragging ? 1.04 : 1.0)
            .offset(
                x: offset.width + dragTranslation.width,
                y: offset.height + dragTranslation.height
            )
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        isDragging = true
                        dragTranslation = value.translation
                    }
                    .onEnded { value in
                        isDragging = false
                        let finalX = offset.width + value.translation.width
                        let finalY = offset.height + value.translation.height

                        // Магнитное прилипание к краям экрана (Magnetic Edge Snapping)
                        let screenWidth = geometry.size.width
                        let hudWidth: CGFloat = isCollapsed ? 140 : 280
                        let snapX: CGFloat = finalX > (screenWidth / 2 - hudWidth / 2) ? (screenWidth - hudWidth - 14) : 14
                        let clampedY = min(max(finalY, 50), geometry.size.height - 120)

                        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                            offset = CGSize(width: snapX, height: clampedY)
                            dragTranslation = .zero
                        }
                        HapticManager.shared.impactLight()
                    }
            )
            .onChange(of: pingMs) { _, newPing in
                if let p = newPing {
                    pingHistory.append(p)
                    if pingHistory.count > 16 {
                        pingHistory.removeFirst()
                    }
                }
            }
        }
    }

    private var pingColor: Color {
        guard let p = pingMs else { return NPTheme.textSecondary }
        if p < 45 {
            return NPTheme.accentPrimary
        } else if p < 100 {
            return NPTheme.semanticWarn
        } else {
            return NPTheme.semanticCritical
        }
    }
}

/// Микро-спарклайн задержки для HUD
private struct HUDMiniSparkline: View {
    let data: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            if data.count > 1 {
                let minVal = (data.min() ?? 0) * 0.8
                let maxVal = max((data.max() ?? 100) * 1.2, minVal + 1)
                let step = geometry.size.width / CGFloat(data.count - 1)

                Path { path in
                    for (index, val) in data.enumerated() {
                        let x = CGFloat(index) * step
                        let normalizedY = CGFloat((val - minVal) / (maxVal - minVal))
                        let y = geometry.size.height * (1.0 - normalizedY)

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
