//
//  NetworkCapabilityCardView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Блок оценки применимости текущей скорости сети в стиле «Obsidian Mono».
public struct NetworkCapabilityCardView: View {
    public let items: [CapabilityItem]

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ОЦЕНКА ВОЗМОЖНОСТЕЙ СЕТИ")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NPTheme.textSecondary)
                    .tracking(0.5)

                Spacer()

                Text("Для чего подходит")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(NPTheme.textSecondary)
            }
            .padding(.horizontal, 4)

            LazyVStack(spacing: 10) {
                ForEach(items) { item in
                    CapabilityRow(item: item)
                }
            }
        }
    }
}

/// Строка конкретной возможности сети (Obsidian Mono)
private struct CapabilityRow: View {
    let item: CapabilityItem
    @State private var isExpanded: Bool = false
    @State private var isPressed: Bool = false

    /// Монохромный цвет для уровня готовности
    private var levelColor: Color {
        switch item.level {
        case .excellent: return NPTheme.accentPrimary
        case .good: return NPTheme.accentSoft
        case .moderate: return NPTheme.accentSilver
        case .poor: return NPTheme.semanticWarn
        case .unknown: return NPTheme.textTertiary
        }
    }

    var body: some View {
        Button(action: {
            HapticManager.shared.impactLight()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                isExpanded.toggle()
            }
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    // Иконка категории с монохромным свечением
                    Image(systemName: item.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(levelColor)
                        .frame(width: 34, height: 34)
                        .background(levelColor.opacity(0.08))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(levelColor.opacity(0.12), lineWidth: 1)
                        )

                    // Название и краткое описание
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(NPTheme.textPrimary)

                        Text(item.description)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(NPTheme.textSecondary)
                            .lineLimit(isExpanded ? nil : 1)
                    }

                    Spacer()

                    // Бейдж статуса
                    HStack(spacing: 4) {
                        Image(systemName: item.level.systemIcon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(item.level.rawValue)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(levelColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(levelColor.opacity(0.08))
                    .clipShape(Capsule())

                    // Индикатор раскрытия с поворотом
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NPTheme.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
                }

                // Индикатор шкалы готовности сети (монохромный прогресс-бар)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(NPTheme.cardBackgroundTertiary)
                            .frame(height: 4)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [levelColor.opacity(0.5), levelColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * scoreRatio(for: item.level), height: 4)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: item.level)
                    }
                }
                .frame(height: 4)
                .padding(.leading, 46)

                // Раскрывающееся пояснение
                if isExpanded {
                    Text(item.detail)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(NPTheme.textSecondary)
                        .padding(.top, 4)
                        .padding(.leading, 46)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(14)
            .npCardStyle(cornerRadius: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isExpanded ? levelColor.opacity(0.15) : Color.clear, lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isPressed)
        }
        .buttonStyle(.plain)
    }

    private func scoreRatio(for level: CapabilityLevel) -> CGFloat {
        switch level {
        case .excellent: return 1.0
        case .good: return 0.75
        case .moderate: return 0.5
        case .poor: return 0.25
        case .unknown: return 0.05
        }
    }
}
