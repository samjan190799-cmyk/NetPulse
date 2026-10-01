//
//  MetaBannerView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / Meta Audience Network 2026).
//

import SwiftUI

/// Премиальный адаптивный баннер Meta Audience Network (Meta Ads 2026)
/// Поддерживает автоматическое переключение: реальный FBAdView <-> Graceful Fallback
@MainActor
public struct MetaBannerView: View {
    private var metaManager = MetaAdManager.shared
    private let contextTag: String?
    @State private var isRealAdLoaded: Bool = false
    @State private var showProSheet: Bool = false

    public init(contextTag: String? = nil) {
        self.contextTag = contextTag
    }

    public var body: some View {
        if metaManager.isBannerEnabled {
            VStack(spacing: 6) {
                // Если живой баннер Meta Audience Network загружен — показываем его
                if isRealAdLoaded {
                    VStack(spacing: 4) {
                        // Верхняя строка маркировки Meta и кнопки отключения
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "infinity")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color(red: 0.0, green: 0.55, blue: 1.0))
                                Text("Meta Audience Network")
                                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(NPTheme.textTertiary)
                            }

                            Spacer()

                            Button {
                                showProSheet = true
                                HapticManager.shared.impactLight()
                            } label: {
                                Text("Отключить в PRO 💎")
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundStyle(NPTheme.accentPrimary)
                            }
                        }
                        .padding(.horizontal, 4)

                        // Нативное представление FBAdView
                        MetaNativeBannerRepresentable(
                            placementID: MetaAdConfig.bannerPlacementID,
                            onAdLoaded: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isRealAdLoaded = true
                                }
                            },
                            onAdFailed: { _ in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isRealAdLoaded = false
                                }
                            }
                        )
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(NPTheme.cardBackground.opacity(0.85))
                            .background(.ultraThinMaterial)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(red: 0.0, green: 0.55, blue: 1.0).opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 8, y: 3)
                } else {
                    // Нет реального баннера (No Fill / оффлайн / идентификаторы-заглушки): собственное предложение PRO
                    fallbackCardView
                        .background(
                            // Фоновый невидимый предзагрузчик реального баннера Meta
                            MetaNativeBannerRepresentable(
                                placementID: MetaAdConfig.bannerPlacementID,
                                onAdLoaded: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        isRealAdLoaded = true
                                    }
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
            .sheet(isPresented: $showProSheet) {
                // Единый экран покупки NetPulse PRO
                NetPulseProUpgradeSheet()
            }
        }
    }

    // MARK: - Предложение NetPulse PRO вместо самодельных «объявлений»

    /// Пока реальный баннер Meta не загружен, показывается собственное предложение приложения — NetPulse PRO.
    /// Раньше здесь рисовались вымышленные «объявления Meta» (Quest, Threads, WhatsApp, Llama…) с придуманными
    /// рейтингами и числом отзывов, метками «Meta Verified» и пятью жёлтыми звёздами при любом рейтинге.
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
