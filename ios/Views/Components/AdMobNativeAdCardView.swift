//
//  AdMobNativeAdCardView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / AdMob 2026).
//

import SwiftUI

/// Нативная рекламная карточка Google AdMob (Native Advanced Ad) в дизайне Glassmorphism
public struct AdMobNativeAdCardView: View {
    @State private var adManager = AdMobManager.shared
    @State private var currentItem: SponsorAdItem
    private let customContextTag: String?

    public init(contextTag: String? = nil) {
        self.customContextTag = contextTag
        _currentItem = State(initialValue: SponsorAdItem.defaults.randomElement() ?? SponsorAdItem.defaults[0])
    }

    public var body: some View {
        if adManager.canShowAds && adManager.isNativeAdsEnabled {
            VStack(alignment: .leading, spacing: 12) {
                // Верхняя строка: Иконка, Заголовок, Рейтинг и Бейдж Рекламы
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(NPTheme.accentPrimary.opacity(0.18))
                            .frame(width: 42, height: 42)

                        Image(systemName: currentItem.iconName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(NPTheme.accentPrimary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(currentItem.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(NPTheme.textPrimary)
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            // Бейдж рекламы
                            Text("СПОНСОР")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(NPTheme.accentPrimary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(NPTheme.accentPrimary.opacity(0.15))
                                .clipShape(Capsule())
                        }

                        HStack(spacing: 4) {
                            // Звезды рейтинга
                            HStack(spacing: 1.5) {
                                ForEach(0..<5) { idx in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color.yellow)
                                }
                            }

                            Text(String(format: "%.1f", currentItem.rating))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(NPTheme.textSecondary)

                            if let tag = customContextTag {
                                Text("• \(tag)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(NPTheme.textTertiary)
                            }
                        }
                    }
                }

                // Описание спонсорского предложения
                Text(currentItem.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.textSecondary)
                    .lineLimit(2)

                // Нижняя панель действий (Call To Action)
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 10))
                            .foregroundStyle(NPTheme.textTertiary)
                        Text("Google AdMob Verified")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(NPTheme.textTertiary)
                    }

                    Spacer()

                    Link(destination: URL(string: currentItem.destinationURL) ?? URL(string: "https://netpulse.app")!) {
                        HStack(spacing: 6) {
                            Text(currentItem.ctaText)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(NPTheme.backgroundDeep)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(NPTheme.accentPrimary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(NPPressableButtonStyle(scale: 0.95))
                }
            }
            .padding(14)
            .npGlassCard(cornerRadius: 16)
            .padding(.horizontal)
            .onAppear {
                if let random = SponsorAdItem.defaults.randomElement() {
                    currentItem = random
                }
            }
        }
    }
}
