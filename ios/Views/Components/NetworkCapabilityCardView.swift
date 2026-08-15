//
//  NetworkCapabilityCardView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Блок оценки применимости текущей скорости сети для реальных задач.
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

/// Строка конкретной возможности сети
private struct CapabilityRow: View {
    let item: CapabilityItem
    @State private var isExpanded: Bool = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    // Иконка категории
                    Image(systemName: item.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(item.level.color)
                        .frame(width: 32, height: 32)
                        .background(item.level.color.opacity(0.12))
                        .clipShape(Circle())

                    // Название и статус
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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(item.level.color.opacity(0.12))
                    .clipShape(Capsule())
                }

                // Раскрывающееся пояснение
                if isExpanded {
                    Text(item.detail)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .padding(.leading, 44)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
