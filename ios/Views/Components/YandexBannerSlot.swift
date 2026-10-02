//
//  YandexBannerSlot.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / Yandex Mobile Ads SDK 8) - 2026.
//

import SwiftUI
import OSLog
import YandexMobileAds

private let bannerLog = Logger(subsystem: "com.samvel.netpulse", category: "ads")

/// Баннер Яндекса 320×50, который не занимает места, пока объявление не пришло.
///
/// Баннер всегда лежит в иерархии экрана с настоящим размером (SDK грузит его только там), но пока объявления нет,
/// он невидим и не принимает нажатия, а место в раскладке получает лишь после загрузки. Если загрузка не удалась
/// (нет сети, нет подходящих объявлений), баннер запрашивается заново с нарастающими паузами (`AdRetryPolicy`).
///
/// Для проверок в UI-тестах внутри лежит невидимая метка: `yandexBanner.waiting` (SDK ещё запускается),
/// `yandexBanner.requested` (баннер запрошен) и `yandexBanner.loaded` (объявление пришло).
@MainActor
struct YandexBannerSlot: View {
    /// Пришло ли объявление: по этому признаку родитель рисует рамку и прячет запасное предложение
    @Binding var isLoaded: Bool
    /// Скругление углов самого объявления
    var cornerRadius: CGFloat = 0

    private let manager = YandexAdManager.shared
    @State private var bannerState: BannerState?
    @State private var attempt = 0
    @State private var failures = 0
    @State private var retryTask: Task<Void, Never>?

    private var width: CGFloat { YandexAdConfig.bannerWidth }
    private var height: CGFloat { YandexAdConfig.bannerHeight }

    var body: some View {
        Color.clear
            .frame(width: width, height: isLoaded ? height : 0)
            .overlay(alignment: .top) {
                if let bannerState {
                    Banner(state: bannerState)
                        .onAdLoad { _ in bannerDidLoad() }
                        .onAdFailure { error in bannerDidFail(error) }
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .opacity(isLoaded ? 1 : 0)
                        .allowsHitTesting(isLoaded)
                        .id(attempt)
                }
            }
            .overlay(alignment: .topLeading) {
                stateMarker
            }
            .onChange(of: manager.canLoadBanners, initial: true) { _, ready in
                if ready {
                    requestBannerIfNeeded()
                }
            }
            .onAppear {
                // Пауза перед повтором прерывается при уходе с экрана: возвращаемся и продолжаем
                if retryTask?.isCancelled == true, !isLoaded {
                    scheduleRetry()
                }
            }
            .onDisappear {
                retryTask?.cancel()
            }
    }

    private var stateMarker: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isLoaded ? "Реклама" : "")
            .accessibilityIdentifier(markerIdentifier)
    }

    private var markerIdentifier: String {
        if isLoaded {
            return "yandexBanner.loaded"
        }
        return bannerState == nil ? "yandexBanner.waiting" : "yandexBanner.requested"
    }

    // MARK: - Загрузка

    private func makeState() -> BannerState {
        BannerState(
            size: .fixed(width: width, height: height),
            request: AdRequest(adUnitID: YandexAdConfig.bannerUnitID)
        )
    }

    private func requestBannerIfNeeded() {
        guard bannerState == nil else { return }
        bannerState = makeState()
        bannerLog.notice("Баннер запрошен")
    }

    private func bannerDidLoad() {
        failures = 0
        retryTask?.cancel()
        retryTask = nil
        bannerLog.notice("Баннер загружен")
        if !isLoaded {
            withAnimation(.easeOut(duration: 0.25)) {
                isLoaded = true
            }
        }
    }

    private func bannerDidFail(_ error: any Error) {
        bannerLog.error("Баннер не загрузился: \(error.localizedDescription, privacy: .public)")
        // Уже показанное объявление остаётся на месте: SDK сам обновит его при следующей попытке
        guard !isLoaded else { return }
        failures += 1
        scheduleRetry()
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = AdRetryPolicy.delay(afterFailures: max(failures, 1))
        retryTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            bannerLog.notice("Баннер запрашивается повторно после \(failures) неудач(и)")
            attempt += 1
            bannerState = makeState()
        }
    }
}
