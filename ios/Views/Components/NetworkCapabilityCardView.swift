//
//  NetworkCapabilityCardView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Блок оценки применимости текущей скорости сети для реальных задач с интерактивными микро-анимациями.
public struct NetworkCapabilityCardView: View {
    public let items: [CapabilityItem]

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ОЦЕНКА ВОЗМОЖНОСТЕЙ СЕТИ")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Spacer()

                Text("Для чего подходит")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
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

/// Строка конкретной возможности сети с анимацией прогресса и раскрытия
private struct CapabilityRow: View {
    let item: CapabilityItem
    @State private var isExpanded: Bool = false
    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: {
            HapticManager.shared.impactLight()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                isExpanded.toggle()
            }
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    // Иконка категории с мягким свечением
                    Image(systemName: item.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(item.level.color)
                        .frame(width: 34, height: 34)
                        .background(item.level.color.opacity(0.12))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(item.level.color.opacity(0.2), lineWidth: 1)
                        )

                    // Название и краткое описание
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(item.description)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
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
                    .foregroundStyle(item.level.color)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(item.level.color.opacity(0.12))
                    .clipShape(Capsule())

                    // Индикатор раскрытия с поворотом
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
                }

                // Индикатор шкалы готовности сети (анимированный прогресс-бар)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .frame(height: 4)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [item.level.color.opacity(0.7), item.level.color],
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
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .padding(.leading, 46)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isExpanded ? item.level.color.opacity(0.25) : Color.white.opacity(0.06), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isPressed)
        }
        .buttonStyle(.plain)
    }

    private func scoreRatio(for level: CapabilityLevel) -> CGFloat {
        switch level {
        case .perfect: return 1.0
        case .excellent: return 0.85
        case .good: return 0.65
        case .moderate: return 0.45
        case .poor: return 0.2
        }
    }
}
