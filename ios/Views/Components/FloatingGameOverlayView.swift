//
//  FloatingGameOverlayView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Минималистичный плавающий игровой HUD-виджет с 95% прозрачностью (5% фона), свободно перемещаемый по экрану.
public struct FloatingGameOverlayView: View {
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let pingMs: Double?
    public let jitterMs: Double?
    public let packetLossPct: Double
    public let onClose: () -> Void

    @State private var offset: CGSize = CGSize(width: 16, height: 70)
    @State private var dragTranslation: CGSize = .zero
    @State private var isCollapsed: Bool = false
    @State private var isDragging: Bool = false

    private var currentSpeed: Double {
        uploadMbps > 0 ? uploadMbps : downloadMbps
    }

    private var pingColor: Color {
        guard let p = pingMs else { return .secondary }
        if p < 50 { return .green }
        if p < 110 { return .yellow }
        return .red
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                if isCollapsed {
                    // Свернутый режим (95% прозрачный компактный бейдж)
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.blue)

                        Text(String(format: "%.0f", currentSpeed))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.8), radius: 1, x: 0, y: 1)

                        if let ping = pingMs {
                            Circle()
                                .fill(pingColor)
                                .frame(width: 6, height: 6)
                            Text("\(Int(ping))")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(pingColor)
                                .shadow(color: .black.opacity(0.8), radius: 1, x: 0, y: 1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Color.black.opacity(0.05) // 95% прозрачности
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .onTapGesture {
                        HapticManager.shared.impactLight()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            isCollapsed = false
                        }
                    }
                } else {
                    // Развернутый режим (95% прозрачный игровой HUD)
                    HStack(spacing: 12) {
                        // 1. Скорость
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 0) {
                                Text(String(format: "%.1f", currentSpeed))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.9), radius: 1, x: 0, y: 1)
                                Text("Мбит/с")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.gray)
                            }
                        }

                        Divider()
                            .frame(height: 20)
                            .background(Color.white.opacity(0.15))

                        // 2. Пинг и джиттер
                        HStack(spacing: 4) {
                            Circle()
                                .fill(pingColor)
                                .frame(width: 6, height: 6)

                            VStack(alignment: .leading, spacing: 0) {
                                Text(pingMs != nil ? "\(Int(pingMs!)) мс" : "—")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(pingColor)
                                    .shadow(color: .black.opacity(0.9), radius: 1, x: 0, y: 1)
                                Text(jitterMs != nil ? "±\(String(format: "%.0f", jitterMs!))мс" : "Jitter")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.gray)
                            }
                        }

                        Divider()
                            .frame(height: 20)
                            .background(Color.white.opacity(0.15))

                        // 3. Потери пакетов
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(String(format: "%.0f", packetLossPct))%")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(packetLossPct > 2 ? .red : .white)
                                .shadow(color: .black.opacity(0.9), radius: 1, x: 0, y: 1)
                            Text("Потери")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.gray)
                        }

                        // Кнопка сворачивания
                        Button(action: {
                            HapticManager.shared.impactLight()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                isCollapsed = true
                            }
                        }) {
                            Image(systemName: "chevron.left.2")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.gray)
                                .padding(4)
                        }

                        // Кнопка закрытия
                        Button(action: {
                            HapticManager.shared.impactMedium()
                            onClose()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.gray)
                                .padding(4)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Color.black.opacity(0.05) // 95% прозрачности
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
            }
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
            .position(
                x: boundX(geometry: geometry),
                y: boundY(geometry: geometry)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            HapticManager.shared.impactLight()
                        }
                        dragTranslation = value.translation
                    }
                    .onEnded { value in
                        isDragging = false
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                        dragTranslation = .zero
                        HapticManager.shared.impactLight()
                    }
            )
        }
    }

    private func boundX(geometry: GeometryProxy) -> CGFloat {
        let currentX = offset.width + dragTranslation.width + 100
        let minX: CGFloat = 80
        let maxX: CGFloat = geometry.size.width - 80
        return min(max(currentX, minX), maxX)
    }

    private func boundY(geometry: GeometryProxy) -> CGFloat {
        let currentY = offset.height + dragTranslation.height + 40
        let minY: CGFloat = 60
        let maxY: CGFloat = geometry.size.height - 100
        return min(max(currentY, minY), maxY)
    }
}
