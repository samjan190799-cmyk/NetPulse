//
//  YandexBannerView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / Yandex Mobile Ads SDK 8) - 2026.
//

import SwiftUI

/// Рекламная карточка с баннером Яндекса для экранов-списков.
/// Пока объявления нет (нет сети, нет подходящей рекламы, SDK ещё запускается), вместо него показывается
/// собственное предложение приложения — NetPulse PRO (только если платная версия включена: `AppFeatures`).
@MainActor
struct YandexBannerView: View {
    private let manager = YandexAdManager.shared
    /// Подпись места показа (для разбора в журнале и будущей аналитики)
    private let contextTag: String?
    @State private var isLoaded = false
    @State private var showProSheet = false

    init(contextTag: String? = nil) {
        self.contextTag = contextTag
    }

    var body: some View {
        if manager.canShowAds {
            VStack(spacing: 6) {
                if !isLoaded && AppFeatures.proPurchaseEnabled {
                    fallbackCardView
                }
                adCard
            }
            .sheet(isPresented: $showProSheet) {
                // Единый экран покупки NetPulse PRO
                NetPulseProUpgradeSheet()
            }
        }
    }

    // MARK: - Карточка с объявлением

    /// Баннер всегда стоит на одном и том же месте иерархии (иначе SDK загружал бы его заново): рамка, подпись и
    /// отступы появляются вокруг него, только когда объявление пришло.
    private var adCard: some View {
        VStack(spacing: 4) {
            if isLoaded {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "megaphone.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(NPTheme.textTertiary)
                        Text("Реклама")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundStyle(NPTheme.textTertiary)
                    }

                    Spacer()

                    if AppFeatures.proPurchaseEnabled {
                        Button {
                            showProSheet = true
                            HapticManager.shared.impactLight()
                        } label: {
                            Text("Отключить в PRO 💎")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(NPTheme.accentPrimary)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            YandexBannerSlot(isLoaded: $isLoaded, cornerRadius: 10)
        }
        .frame(maxWidth: .infinity)
        .padding(isLoaded ? 10 : 0)
        .background {
            if isLoaded {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NPTheme.cardBackground.opacity(0.85))
                    .background(.ultraThinMaterial)
            }
        }
        .overlay {
            if isLoaded {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(NPTheme.border, lineWidth: 1)
            }
        }
    }

    // MARK: - Предложение NetPulse PRO вместо рекламы

    /// Пока реального баннера нет, показывается собственное предложение приложения — NetPulse PRO.
    private var fallbackCardView: some View {
        Button {
            showProSheet = true
            HapticManager.shared.impactLight()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [NPTheme.accentPrimary, Color.yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.black)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("NetPulse PRO")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(NPTheme.textPrimary)

                    Text("Без рекламы и с игровым HUD-оверлеем поверх экрана")
                        .font(.system(size: 11))
                        .foregroundStyle(NPTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NPTheme.textTertiary)
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
                    .stroke(NPTheme.accentPrimary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(NPPressableButtonStyle(scale: 0.98))
    }
}
