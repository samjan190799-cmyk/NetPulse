//
//  AdMobBannerContainerView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / AdMob 2026).
//

import SwiftUI
import UIKit

/// Адаптивный баннерный контейнер Google AdMob с поддержкой Glassmorphism и NetPulse Pro
@MainActor
public struct AdMobBannerContainerView: View {
    private var adManager = AdMobManager.shared
    @State private var currentSponsor: SponsorAdItem = SponsorAdItem.defaults[0]
    @State private var showProUpgradeSheet: Bool = false

    public init() {}

    public var body: some View {
        if adManager.canShowAds && adManager.isBannerEnabled {
            VStack(spacing: 0) {
                // Тонкая разделительная световая линия
                Divider()
                    .background(NPTheme.border)

                HStack(spacing: 12) {
                    // Иконка спонсора / рекламодателя
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(NPTheme.accentPrimary.opacity(0.15))
                            .frame(width: 36, height: 36)

                        Image(systemName: currentSponsor.iconName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(NPTheme.accentPrimary)
                    }

                    // Текстовый блок
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(currentSponsor.title)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(NPTheme.textPrimary)
                                .lineLimit(1)

                            // Бейдж "Реклама" по стандартам Apple и Google AdMob
                            Text("РЕКЛАМА")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(NPTheme.textTertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }

                        Text(currentSponsor.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(NPTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    // Кнопка перехода
                    if let targetURL = URL(string: currentSponsor.destinationURL) ?? URL(string: "https://netpulse.app") {
                        Link(destination: targetURL) {
                            Text(currentSponsor.ctaText)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(NPTheme.backgroundDeep)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(NPTheme.accentPrimary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(NPPressableButtonStyle(scale: 0.94))
                    }

                    // Кнопка перехода на PRO для скрытия баннеров
                    Button {
                        showProUpgradeSheet = true
                        HapticManager.shared.impactLight()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(NPTheme.textTertiary)
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .npMinHitTarget()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Rectangle()
                        .fill(NPTheme.cardBackground.opacity(0.92))
                        .background(.ultraThinMaterial)
                )
            }
            .sheet(isPresented: $showProUpgradeSheet) {
                NetPulseProUpgradeSheet()
            }
            .onAppear {
                // Ротация спонсорского контента при каждом показе
                if let randomItem = SponsorAdItem.defaults.randomElement() {
                    currentSponsor = randomItem
                }
            }
        }
    }
}

/// Модальный экран предложения отключения рекламы (NetPulse Pro)
@MainActor
public struct NetPulseProUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    private var adManager = AdMobManager.shared

    public var body: some View {
        NavigationStack {
            ZStack {
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Иконка PRO
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [NPTheme.accentPrimary, NPTheme.accentSoft],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ).opacity(0.2)
                                )
                                .frame(width: 84, height: 84)

                            Image(systemName: "crown.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [NPTheme.accentPrimary, Color.yellow],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .padding(.top, 16)

                        VStack(spacing: 6) {
                            Text("NetPulse PRO")
                                .font(.system(size: 24, weight: .heavy, design: .rounded))
                                .foregroundStyle(NPTheme.textPrimary)

                            Text("Максимальная производительность без рекламы")
                                .font(.system(size: 13))
                                .foregroundStyle(NPTheme.textSecondary)
                        }

                        // Список преимуществ
                        VStack(spacing: 12) {
                            proFeatureRow(
                                icon: "bolt.shield.fill",
                                title: "100% Без рекламы",
                                description: "Полное отключение всех баннеров и нативных объявлений AdMob."
                            )

                            proFeatureRow(
                                icon: "sparkles",
                                title: "Безлимитный AI Диагност",
                                description: "Неограниченные глубокие сетевые аудиты и мастер устранения проблем."
                            )

                            proFeatureRow(
                                icon: "gauge.with.dots.needle.67percent",
                                title: "Приоритетный Speedtest 10G",
                                description: "Выделенные гигабитные каналы для максимально точного замера."
                            )

                            proFeatureRow(
                                icon: "gamecontroller.fill",
                                title: "PRO Gaming Radar",
                                description: "Непрерывный мониторинг серверов 30+ игр с микро-джиттером."
                            )
                        }
                        .padding(16)
                        .npGlassCard(cornerRadius: 18)
                        .padding(.horizontal)

                        // Кнопка покупки
                        VStack(spacing: 10) {
                            Button {
                                adManager.purchaseProVersion()
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                    Text("Активировать NetPulse PRO")
                                }
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(NPTheme.backgroundDeep)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(
                                    LinearGradient(
                                        colors: [NPTheme.accentPrimary, Color.yellow.opacity(0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: NPTheme.accentPrimary.opacity(0.35), radius: 10, y: 4)
                            }
                            .buttonStyle(NPPressableButtonStyle())

                            Button {
                                adManager.restorePurchases()
                                dismiss()
                            } label: {
                                Text("Восстановить покупки")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(NPTheme.textSecondary)
                            }
                            .npMinHitTarget()
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("NetPulse PRO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { dismiss() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NPTheme.accentPrimary)
                }
            }
        }
    }

    private func proFeatureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(NPTheme.accentPrimary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(NPTheme.textSecondary)
            }
            Spacer()
        }
    }
}
