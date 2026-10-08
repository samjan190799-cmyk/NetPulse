//
//  PaywallView.swift
//  NetPulse
//
//  Окно подписки NetPulse PRO и заглушка для закрытых возможностей.
//

import SwiftUI

// MARK: - Значок PRO

/// Маленький значок «PRO» рядом с платной возможностью
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(NPTheme.backgroundDeep)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(NPTheme.buttonGradient))
            .accessibilityLabel("Входит в подписку PRO")
    }
}

// MARK: - Окно подписки

/// Окно подписки: что входит, цена из App Store, условия автопродления, «Восстановить покупки», ссылки на условия
/// и политику. Всё, что правило App Store 3.1.2 требует показывать до покупки, находится на этом экране.
@MainActor
struct PaywallView: View {
    let feature: ProFeature
    @Bindable private var store = ProStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            NPTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    header
                    featureList
                    purchaseBlock
                    legal
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NPTheme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(.top, 8)
            .padding(.trailing, 8)
            .accessibilityLabel("Закрыть")
            .accessibilityIdentifier("paywallCloseButton")
        }
        .preferredColorScheme(.dark)
        .task {
            await store.loadProduct()
        }
        .alert(
            "Подписка",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { shown in
                    if !shown { store.errorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .accessibilityIdentifier("paywallView")
    }

    // MARK: - Шапка

    private var header: some View {
        VStack(spacing: 10) {
            NetworkPulseLine(color: NPTheme.accentPrimary, intensity: 0.9, isBusy: true)
                .frame(height: 64)
            Text("NetPulse PRO")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(NPTheme.textPrimary)
            Text(feature == .general ? "Остров, игровой HUD и AI-аудит сети" : "«\(feature.title)» входит в подписку PRO")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(NPTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Что входит

    private var featureList: some View {
        VStack(spacing: 10) {
            ForEach(ProFeature.included) { item in
                featureRow(item)
            }
        }
    }

    private func featureRow(_ item: ProFeature) -> some View {
        let highlighted = item == feature
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(NPTheme.accentPrimary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(NPTheme.accentPrimary.opacity(0.14)))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)
                Text(item.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(NPTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(NPTheme.cardBackgroundTertiary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(highlighted ? NPTheme.accentPrimary : Color.white.opacity(0.08), lineWidth: highlighted ? 1.5 : 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Покупка

    private var purchaseBlock: some View {
        VStack(spacing: 12) {
            if store.isPro {
                Label("Подписка активна", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(RouteQuality.good.displayColor)
                    .accessibilityIdentifier("paywallActive")
                Button {
                    openURL(AppLinks.manageSubscriptions)
                } label: {
                    Text("Управлять подпиской")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NPTheme.accentPrimary)
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("paywallManageButton")
            } else {
                Text(store.priceText ?? "—")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(NPTheme.textPrimary)
                    .accessibilityIdentifier("paywallPrice")

                Button {
                    HapticManager.shared.impactMedium()
                    Task {
                        await store.purchase()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if store.isPurchasing {
                            ProgressView()
                                .tint(NPTheme.backgroundDeep)
                        }
                        Text("Подписаться")
                    }
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(NPTheme.backgroundDeep)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(NPTheme.buttonGradient)
                    )
                    .opacity(store.product == nil ? 0.5 : 1)
                }
                .buttonStyle(NPPressableButtonStyle(scale: 0.97))
                .disabled(store.product == nil || store.isPurchasing)
                .accessibilityIdentifier("paywallSubscribeButton")

                if store.product == nil {
                    Text(store.isLoadingProduct ? "Загружаем цену…" : "Не удалось загрузить цену. Проверьте подключение к интернету.")
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("paywallPriceStatus")
                }
            }

            Button {
                Task {
                    await store.restore()
                }
            } label: {
                Text("Восстановить покупки")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NPTheme.textPrimary)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("paywallRestoreButton")
        }
    }

    // MARK: - Условия

    private var legal: some View {
        VStack(spacing: 10) {
            Text(legalText)
                .font(.system(size: 11))
                .foregroundStyle(NPTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                Link("Условия использования", destination: AppLinks.termsOfUse)
                Link("Политика конфиденциальности", destination: AppLinks.privacyPolicy)
            }
            .font(.system(size: 12, weight: .semibold))
            .tint(NPTheme.accentPrimary)
        }
        .accessibilityIdentifier("paywallLegal")
    }

    private var legalText: String {
        let price = store.priceText.map { "Стоимость: \($0)." } ?? "Стоимость и срок показаны в окне покупки App Store."
        return "NetPulse PRO — подписка с автоматическим продлением. \(price) Оплата списывается с вашей учётной записи Apple ID при подтверждении покупки. Подписка продлевается автоматически каждый месяц, если не отменить её минимум за 24 часа до конца текущего периода. Управлять подпиской и отменить её можно в настройках учётной записи Apple ID."
    }
}

// MARK: - Заглушка закрытой возможности

/// Экран на месте платной возможности, пока подписки нет: что это и кнопка, которая открывает окно подписки
@MainActor
struct ProLockedView: View {
    let feature: ProFeature

    var body: some View {
        ZStack {
            NPTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(NPTheme.accentPrimary.opacity(0.14))
                        .frame(width: 96, height: 96)
                    Image(systemName: feature.icon)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(NPTheme.accentPrimary)
                }

                HStack(spacing: 8) {
                    Text(feature.title)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(NPTheme.textPrimary)
                    ProBadge()
                }

                Text(feature.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(NPTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    HapticManager.shared.impactMedium()
                    ProStore.shared.requirePro(feature)
                } label: {
                    Text("Открыть NetPulse PRO")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(NPTheme.backgroundDeep)
                        .padding(.horizontal, 24)
                        .frame(height: 50)
                        .background(Capsule().fill(NPTheme.buttonGradient))
                }
                .buttonStyle(NPPressableButtonStyle(scale: 0.97))
                .accessibilityIdentifier("proUnlockButton")
            }
            .padding(28)
        }
        .accessibilityIdentifier("proLockedView")
    }
}
