//
//  AdMobBannerContainerView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / AdMob 2026).
//

import SwiftUI
import StoreKit
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
    private var store = StoreManager.shared
    @State private var selectedProductID: String?

    /// Выбранный тариф; по умолчанию — первый (годовой, он дороже и идёт первым)
    private var effectiveProductID: String? {
        selectedProductID ?? store.products.first?.id
    }

    private func periodDescription(_ product: Product) -> String {
        switch product.subscription?.subscriptionPeriod.unit {
        case .year: return "Подписка на 1 год, автопродление"
        case .month: return "Подписка на 1 месяц, автопродление"
        default: return "Подписка с автопродлением"
        }
    }

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

                            Text("Без рекламы и с дополнительными возможностями")
                                .font(.system(size: 13))
                                .foregroundStyle(NPTheme.textSecondary)
                        }

                        // Список преимуществ
                        VStack(spacing: 12) {
                            proFeatureRow(
                                icon: "bolt.shield.fill",
                                title: "Без рекламы",
                                description: "Отключает все баннеры и рекламные ролики в приложении."
                            )

                            proFeatureRow(
                                icon: "sparkles",
                                title: "Глубокий AI-аудит сети сразу",
                                description: "Запуск углублённого анализа без просмотра рекламного видео."
                            )

                            proFeatureRow(
                                icon: "gamecontroller.fill",
                                title: "Игровой оверлей (HUD)",
                                description: "Мини-виджет пинга поверх экрана и Picture-in-Picture для онлайн-игр."
                            )
                        }
                        .padding(16)
                        .npGlassCard(cornerRadius: 18)
                        .padding(.horizontal)

                        // Тарифы и покупка
                        VStack(spacing: 10) {
                            if store.products.isEmpty {
                                if store.isLoadingProducts {
                                    ProgressView()
                                        .padding(.vertical, 20)
                                } else {
                                    Button {
                                        Task { await store.loadProducts() }
                                    } label: {
                                        Text("Загрузить тарифы")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(NPTheme.accentPrimary)
                                            .padding(.vertical, 12)
                                    }
                                }
                            } else {
                                ForEach(store.products, id: \.id) { product in
                                    Button {
                                        selectedProductID = product.id
                                        HapticManager.shared.impactLight()
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(product.displayName)
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundStyle(NPTheme.textPrimary)
                                                Text(periodDescription(product))
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(NPTheme.textSecondary)
                                            }
                                            Spacer()
                                            Text(product.displayPrice)
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundStyle(NPTheme.textPrimary)
                                            Image(systemName: effectiveProductID == product.id ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(NPTheme.accentPrimary)
                                        }
                                        .padding(12)
                                        .npGlassCard(cornerRadius: 14)
                                    }
                                    .buttonStyle(NPPressableButtonStyle(scale: 0.98))
                                }

                                Button {
                                    guard let product = store.products.first(where: { $0.id == effectiveProductID }) else { return }
                                    Task {
                                        await store.purchase(product)
                                        if adManager.isPremiumUser { dismiss() }
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        if store.isPurchasing {
                                            ProgressView()
                                        } else {
                                            Image(systemName: "sparkles")
                                            Text("Оформить подписку")
                                        }
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
                                .disabled(store.isPurchasing)
                            }

                            Button {
                                Task { await store.restore() }
                            } label: {
                                Text("Восстановить покупки")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(NPTheme.textSecondary)
                            }
                            .npMinHitTarget()

                            Text("Оплата списывается с вашего Apple ID при подтверждении покупки. Подписка продлевается автоматически на тот же срок по цене выбранного тарифа, пока вы не отключите автопродление минимум за 24 часа до окончания периода. Управлять подпиской и отключить автопродление можно в настройках Apple ID.")
                                .font(.system(size: 10))
                                .foregroundStyle(NPTheme.textTertiary)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 16) {
                                Link("Политика конфиденциальности", destination: URL(string: "https://github.com/samjan190799-cmyk/NetPulse/blob/appstore-assets/legal/privacy-policy-ru.md")!)
                                Link("Условия использования", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(NPTheme.accentPrimary)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("NetPulse PRO")
            .navigationBarTitleDisplayMode(.inline)
            .task { await store.loadProducts() }
            .alert("NetPulse PRO", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
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
