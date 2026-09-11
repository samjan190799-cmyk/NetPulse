//
//  MetaBannerView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / Meta Audience Network 2026).
//

import SwiftUI

/// Премиальный адаптивный баннер Meta Audience Network (Meta Ads 2026)
@MainActor
public struct MetaBannerView: View {
    private var metaManager = MetaAdManager.shared
    private let contextTag: String?
    @State private var isHovered: Bool = false

    public init(contextTag: String? = nil) {
        self.contextTag = contextTag
    }

    private var activeAd: MetaAdItem {
        metaManager.adForContext(contextTag)
    }

    public var body: some View {
        if metaManager.isBannerEnabled {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Фирменный логотип / иконка креатива Meta с градиентом
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: activeAd.customLogoGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .shadow(color: activeAd.customLogoGradient[0].opacity(0.35), radius: 6, y: 2)

                        Image(systemName: activeAd.iconSystemName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    // Текстовый блок объявления
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(activeAd.title)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(NPTheme.textPrimary)
                                .lineLimit(1)

                            Spacer(minLength: 2)

                            // Маркировка "Реклама от Meta"
                            HStack(spacing: 3) {
                                Image(systemName: "infinity")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(Color(red: 0.0, green: 0.55, blue: 1.0))
                                Text("Meta Ads")
                                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color(red: 0.0, green: 0.55, blue: 1.0))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.0, green: 0.55, blue: 1.0).opacity(0.12))
                            .clipShape(Capsule())
                        }

                        Text(activeAd.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(NPTheme.textSecondary)
                            .lineLimit(2)

                        // Дополнительная строка: Рейтинг и спонсор
                        HStack(spacing: 6) {
                            HStack(spacing: 1.5) {
                                ForEach(0..<5) { _ in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color.yellow)
                                }
                            }

                            Text(String(format: "%.1f", activeAd.rating))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(NPTheme.textTertiary)

                            Text("• \(activeAd.sponsorTag)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(NPTheme.textTertiary)
                        }
                    }

                    Spacer(minLength: 4)

                    // Кнопка призыва к действию (CTA)
                    if let targetURL = URL(string: activeAd.destinationURL) {
                        Link(destination: targetURL) {
                            HStack(spacing: 4) {
                                Text(activeAd.ctaText)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .black))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.0, green: 0.5, blue: 1.0),
                                        Color(red: 0.2, green: 0.2, blue: 0.9)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(color: Color.blue.opacity(0.3), radius: 4, y: 2)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            metaManager.recordAdClick(ad: activeAd)
                        })
                        .buttonStyle(NPPressableButtonStyle(scale: 0.94))
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(NPTheme.cardBackground.opacity(0.85))
                        .background(.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.0, green: 0.55, blue: 1.0).opacity(0.4),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.25), radius: 10, y: 4)
            }
        }
    }
}
