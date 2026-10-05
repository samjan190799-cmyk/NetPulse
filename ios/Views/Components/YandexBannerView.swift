//
//  YandexBannerView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / Yandex Mobile Ads SDK 8) - 2026.
//

import SwiftUI

/// Рекламная карточка с баннером Яндекса для экранов-списков.
/// Пока объявления нет (нет сети, нет подходящей рекламы, SDK ещё запускается) или реклама в этой сборке выключена,
/// карточка места не занимает.
@MainActor
struct YandexBannerView: View {
    private let manager = YandexAdManager.shared
    /// Подпись места показа (для разбора в журнале и будущей аналитики)
    private let contextTag: String?
    @State private var isLoaded = false

    init(contextTag: String? = nil) {
        self.contextTag = contextTag
    }

    var body: some View {
        if manager.canShowAds {
            adCard
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
}
