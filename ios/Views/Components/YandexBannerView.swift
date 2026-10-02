//
//  YandexBannerView.swift
//  NetPulse
//
//  Рекламный баннер Yandex Mobile Ads (SwiftUI API SDK 8.x).
//

import SwiftUI
import YandexMobileAds

/// Баннер Яндекса 320×50. Скрыт, пока реклама не загрузилась, и целиком убирается при ошибке или у Pro-пользователей.
@MainActor
public struct YandexBannerView: View {
    private var adManager = YandexAdManager.shared

    @State private var bannerState: BannerState?
    @State private var isLoaded = false
    @State private var didFail = false

    public init() {}

    public var body: some View {
        Group {
            if adManager.canShowAds && !didFail {
                ZStack {
                    if let bannerState {
                        Banner(state: bannerState)
                            .onAdLoad { _ in isLoaded = true }
                            .onAdFailure { _ in didFail = true }
                            .opacity(isLoaded ? 1 : 0)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .onAppear {
                    guard bannerState == nil else { return }
                    bannerState = BannerState(
                        size: .fixed(width: 320, height: 50),
                        request: AdRequest(adUnitID: YandexAdConfig.bannerUnitID)
                    )
                }
            }
        }
    }
}
