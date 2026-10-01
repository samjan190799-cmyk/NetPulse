//
//  AdMobBannerContainerView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//  Здесь остался только экран покупки NetPulse PRO (самодельный контейнер «рекламы AdMob» удалён: он нигде
//  не использовался, а SDK AdMob в проект не подключён).
//

import SwiftUI
import UIKit

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

                            Text("Без рекламы и с игровым HUD-оверлеем")
                                .font(.system(size: 13))
                                .foregroundStyle(NPTheme.textSecondary)
                        }

                        // Список преимуществ
                        VStack(spacing: 12) {
                            proFeatureRow(
                                icon: "bolt.shield.fill",
                                title: "Без рекламы",
                                description: "Баннеры и рекламные блоки в приложении отключаются."
                            )

                            proFeatureRow(
                                icon: "gamecontroller.fill",
                                title: "Игровой HUD-оверлей",
                                description: "Мини-виджет пинга и скорости поверх экрана; режим «картинка в картинке» работает, если его поддерживает устройство."
                            )
                        }
                        .padding(16)
                        .npGlassCard(cornerRadius: 18)
                        .padding(.horizontal)

                        // Кнопка покупки
                        VStack(spacing: 10) {
                            if adManager.isPremiumUser {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(NPTheme.semanticOK)
                                    Text("NetPulse PRO активен")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(NPTheme.textPrimary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .npGlassCard(cornerRadius: 14)
                            } else {
                            Button {
                                adManager.purchaseProVersion()
                            } label: {
                                HStack(spacing: 8) {
                                    if adManager.isPurchaseInProgress {
                                        ProgressView()
                                            .tint(NPTheme.backgroundDeep)
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                    Text(adManager.proPriceText.map { "Купить NetPulse PRO — \($0)" } ?? "Купить NetPulse PRO")
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
                            .disabled(adManager.isPurchaseInProgress)
                            }

                            if let message = adManager.purchaseMessage {
                                Text(message)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(NPTheme.semanticWarn)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                            }

                            Button {
                                adManager.restorePurchases()
                            } label: {
                                Text("Восстановить покупки")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(NPTheme.textSecondary)
                            }
                            .disabled(adManager.isPurchaseInProgress)
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
