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
    @State private var isRealAdLoaded: Bool = false

    public init() {}

    public var body: some View {
        if metaManager.isBannerEnabled && metaManager.isStickyBannerVisible && !isClosedTemporarily {
            VStack(spacing: 0) {
                if isRealAdLoaded {
                    // Тонкая разделительная световая линия
                    Rectangle()
                        .fill(NPTheme.border)
                        .frame(height: 1)

                    // Реальный FBAdView от Meta Audience Network
                    HStack(spacing: 0) {
                        MetaNativeBannerRepresentable(
                            placementID: MetaAdConfig.bannerPlacementID,
                            onAdLoaded: {
                                isRealAdLoaded = true
                            },
                            onAdFailed: { _ in
                                isRealAdLoaded = false
                            }
                        )
                        .frame(height: 50)

                        Button {
                            HapticManager.shared.impactLight()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isClosedTemporarily = true
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(NPTheme.textTertiary)
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 8)
                    }
                    .background(
                        NPTheme.backgroundDeep.opacity(0.95)
                            .background(.ultraThinMaterial)
                    )
                } else {
                    // Реального баннера нет — ничего не рисуем (раньше здесь показывалась самодельная «реклама Meta»
                    // с вымышленными брендами); невидимый предзагрузчик продолжает запрашивать настоящий баннер.
                    Color.clear
                        .frame(height: 0)
                        .background(
                            MetaNativeBannerRepresentable(
                                placementID: MetaAdConfig.bannerPlacementID,
                                onAdLoaded: {
                                    isRealAdLoaded = true
                                },
                                onAdFailed: { _ in
                                    isRealAdLoaded = false
                                }
                            )
                            .frame(width: 1, height: 1)
                            .opacity(0.001)
                        )
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
