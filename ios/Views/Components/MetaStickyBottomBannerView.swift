//
//  MetaStickyBottomBannerView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / Meta Audience Network 2026).
//

import SwiftUI

/// Глобальный закрепленный баннер Meta Audience Network над системным таб-баром (Sticky Bottom Banner)
@MainActor
public struct MetaStickyBottomBannerView: View {
    private var metaManager = MetaAdManager.shared
    @State private var isClosedTemporarily: Bool = false

    public init() {}

    public var body: some View {
        if metaManager.isBannerEnabled && metaManager.isStickyBannerVisible && !isClosedTemporarily {
            let ad = metaManager.currentAd

            VStack(spacing: 0) {
                // Тонкая разделительная световая линия с градиентом Meta
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.0, green: 0.55, blue: 1.0).opacity(0.6),
                                Color(red: 0.6, green: 0.1, blue: 0.9).opacity(0.3),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)

                HStack(spacing: 10) {
                    // Компактный значок Meta с градиентом
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: ad.customLogoGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 32, height: 32)

                        Image(systemName: ad.iconSystemName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    // Текстовая информация
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(ad.title)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(NPTheme.textPrimary)
                                .lineLimit(1)

                            HStack(spacing: 2) {
                                Image(systemName: "infinity")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color(red: 0.0, green: 0.55, blue: 1.0))
                                Text("Meta Ads")
                                    .font(.system(size: 7.5, weight: .black))
                                    .foregroundStyle(Color(red: 0.0, green: 0.55, blue: 1.0))
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Color(red: 0.0, green: 0.55, blue: 1.0).opacity(0.12))
                            .clipShape(Capsule())
                        }

                        Text(ad.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(NPTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    // CTA Кнопка перехода
                    if let targetURL = URL(string: ad.destinationURL) {
                        Link(destination: targetURL) {
                            Text(ad.ctaText)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.0, green: 0.55, blue: 1.0),
                                            Color(red: 0.1, green: 0.35, blue: 0.95)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(Capsule())
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            metaManager.recordAdClick(ad: ad)
                        })
                        .buttonStyle(NPPressableButtonStyle(scale: 0.94))
                    }

                    // Кнопка временного закрытия
                    Button {
                        HapticManager.shared.impactLight()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isClosedTemporarily = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(NPTheme.textTertiary)
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .npMinHitTarget()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    NPTheme.backgroundDeep.opacity(0.92)
                        .background(.ultraThinMaterial)
                )
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
