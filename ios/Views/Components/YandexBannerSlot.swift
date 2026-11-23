//
//  YandexBannerSlot.swift
//  Kap
//

import SwiftUI

/// КОНТРОЛЬНАЯ СБОРКА БЕЗ SDK ЯНДЕКСА: баннер ничего не рисует и места не занимает.
@MainActor
struct YandexBannerSlot: View {
    @Binding var isLoaded: Bool
    private let cornerRadius: CGFloat

    init(isLoaded: Binding<Bool>, cornerRadius: CGFloat = 0) {
        self._isLoaded = isLoaded
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
    }
}
