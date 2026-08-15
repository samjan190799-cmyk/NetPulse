//
//  FloatingGameOverlayView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Минималистичный плавающий игровой HUD-виджет с 95% прозрачностью (5% заливка), отображающий реальную скорость загрузки и отдачи.
public struct FloatingGameOverlayView: View {
    public let downloadSpeedText: String
    public let uploadSpeedText: String
    public let pingMs: Double?
    public let jitterMs: Double?
    public let packetLossPct: Double
    public let onTogglePiP: () -> Void
    public let onClose: () -> Void

    @State private var offset: CGSize = CGSize(width: 16, height: 70)
    @State private var dragTranslation: CGSize = .zero
    @State private var isCollapsed: Bool = false
    @State private var isDragging: Bool = false

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
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.blue)

                        Text(downloadSpeedText)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.9), radius: 1, x: 0, y: 1)

                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.cyan)

                        Text(uploadSpeedText)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.cyan)
                            .shadow(color: .black.opacity(0.9), radius: 1, x: 0, y: 1)
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
                    HStack(spacing: 10) {
                        // 1. Реальная скорость скачивания
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 0) {
                                Text(downloadSpeedText)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.95), radius: 1, x: 0, y: 1)
                                Text("СКАЧИВАНИЕ")
                                    .font(.system(size: 7, weight: .semibold))
                                    .foregroundStyle(.gray)
                            }
                        }

                        Divider()
                            .frame(height: 18)
                            .background(Color.white.opacity(0.15))

                        // 2. Реальная скорость отдачи
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.cyan)

                            VStack(alignment: .leading, spacing: 0) {
                                Text(uploadSpeedText)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.cyan)
                                    .shadow(color: .black.opacity(0.95), radius: 1, x: 0, y: 1)
                                Text("ОТДАЧА")
                                    .font(.system(size: 7, weight: .semibold))
                                    .foregroundStyle(.gray)
                            }
                        }

                        // 3. Кнопка выноса в Picture-in-Picture (поверх всех игр и приложений)
                        Button(action: {
                            HapticManager.shared.impactMedium()
                            onTogglePiP()
                        }) {
                            Image(systemName: "pip.enter")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.green)
                                .padding(5)
                                .background(Color.black.opacity(0.1))
                                .clipShape(Circle())
                        }

                        // 4. Кнопка сворачивания
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

                        // 5. Кнопка закрытия
                        Button(action: {
                            HapticManager.shared.impactLight()
                            onClose()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.gray)
                                .padding(4)
                        }
                    }
                    .padding(.horizontal, 12)
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
            .scaleEffect(isDragging ? 1.03 : 1.0)
            .offset(
                x: offset.width + dragTranslation.width,
                y: offset.height + dragTranslation.height
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        dragTranslation = value.translation
                    }
                    .onEnded { value in
                        isDragging = false
                        let finalX = offset.width + value.translation.width
                        let finalY = offset.height + value.translation.height

                        // Умное прилипание к краям экрана (Safe Area Snap)
                        let screenWidth = geometry.size.width
                        let snapX: CGFloat = finalX > screenWidth / 2 - 80 ? screenWidth - (isCollapsed ? 140 : 260) : 16
                        let clampedY = min(max(finalY, 50), geometry.size.height - 120)

                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            offset = CGSize(width: snapX, height: clampedY)
                            dragTranslation = .zero
                        }
                        HapticManager.shared.impactLight()
                    }
            )
        }
    }
}
