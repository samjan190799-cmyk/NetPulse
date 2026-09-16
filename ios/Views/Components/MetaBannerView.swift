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

    private var activeAd: MetaAdItem {
        metaManager.adForContext(contextTag)
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
                    // Graceful Fallback: Премиальный промо-блок при отсутствии заполнения (No Fill) или оффлайне
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
                // Премиум экран
                proUpgradeSheetView
            }
        }
    }

    // MARK: - Резервная карточка (Graceful Fallback)
    private var fallbackCardView: some View {
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
                        .shadow(color: (activeAd.customLogoGradient.first ?? Color.blue).opacity(0.35), radius: 6, y: 2)

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

    // MARK: - Быстрый экран перехода на NetPulse PRO
    private var proUpgradeSheetView: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [NPTheme.accentPrimary, Color.yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(Color.black)
                }
                .padding(.top, 30)

                Text("NetPulse PRO")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(NPTheme.textPrimary)

                Text("Отключите любую рекламу от Meta и AdMob навсегда, получите безлимитный доступ к AI-диагносту и игровой HUD-оверлей.")
                    .font(.system(size: 14))
                    .foregroundStyle(NPTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer()

                Button {
                    AdMobManager.shared.upgradeToPremium()
                    showProSheet = false
                    HapticManager.shared.notificationSuccess()
                } label: {
                    Text("Перейти на NetPulse PRO")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(NPTheme.backgroundDeep)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [NPTheme.accentPrimary, Color.yellow],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(NPTheme.backgroundDeep)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        showProSheet = false
                    }
                    .foregroundStyle(NPTheme.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
