//
//  YandexStickyBannerView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / Yandex Mobile Ads SDK 8) - 2026.
//

import SwiftUI

/// Закреплённый баннер Яндекса над системным таб-баром (на главном экране — внутри нижней панели).
/// Пока объявления нет, не занимает места; крестик скрывает баннер до следующего открытия экрана.
@MainActor
struct YandexStickyBannerView: View {
    private let manager = YandexAdManager.shared
    @State private var isLoaded = false
    @State private var isClosedTemporarily = false

    var body: some View {
        if manager.canShowAds && !isClosedTemporarily {
            VStack(spacing: 0) {
                if isLoaded {
                    // Тонкая разделительная световая линия
                    Rectangle()
                        .fill(NPTheme.border)
                        .frame(height: 1)
                }

                ZStack {
                    YandexBannerSlot(isLoaded: $isLoaded)

                    if isLoaded {
                        HStack {
                            Spacer()
                            closeButton
                        }
                        .padding(.trailing, 8)
                    }
                }
                .frame(maxWidth: .infinity)
                .background {
                    if isLoaded {
                        NPTheme.backgroundDeep.opacity(0.95)
                            .background(.ultraThinMaterial)
                    }
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var closeButton: some View {
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
        .accessibilityLabel("Скрыть рекламу")
        .accessibilityIdentifier("yandexStickyBannerClose")
    }
}
