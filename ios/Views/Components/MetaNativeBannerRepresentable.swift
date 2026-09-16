//
//  MetaNativeBannerRepresentable.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / Meta Audience Network 2026).
//

import SwiftUI
import UIKit

#if canImport(FBAudienceNetwork)
import FBAudienceNetwork
#endif

/// Нативный мост UIViewRepresentable для баннера Meta Audience Network (FBAdView)
@MainActor
public struct MetaNativeBannerRepresentable: UIViewRepresentable {
    public let placementID: String
    public let onAdLoaded: (@MainActor () -> Void)?
    public let onAdFailed: (@MainActor (String) -> Void)?
    public let onAdClicked: (@MainActor () -> Void)?

    public init(
        placementID: String = MetaAdConfig.bannerPlacementID,
        onAdLoaded: (@MainActor () -> Void)? = nil,
        onAdFailed: (@MainActor (String) -> Void)? = nil,
        onAdClicked: (@MainActor () -> Void)? = nil
    ) {
        self.placementID = placementID
        self.onAdLoaded = onAdLoaded
        self.onAdFailed = onAdFailed
        self.onAdClicked = onAdClicked
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear

        #if canImport(FBAudienceNetwork)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            onAdFailed?("Не удалось определить rootViewController для FBAdView")
            return containerView
        }

        let adView = FBAdView(
            placementID: placementID,
            adSize: kFBAdSizeHeight50Banner,
            rootViewController: rootVC
        )
        adView.delegate = context.coordinator
        adView.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(adView)
        NSLayoutConstraint.activate([
            adView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            adView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            adView.topAnchor.constraint(equalTo: containerView.topAnchor),
            adView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            adView.heightAnchor.constraint(equalToConstant: 50)
        ])

        context.coordinator.adView = adView
        adView.loadAd()
        #else
        // Фолбек при компиляции без бинарного SDK
        onAdFailed?("SDK FBAudienceNetwork не подключен в бинарник")
        #endif

        return containerView
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        // Обновление не требуется — баннер управляется собственным жизненным циклом
    }

    public static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        #if canImport(FBAudienceNetwork)
        coordinator.adView?.delegate = nil
        coordinator.adView?.removeFromSuperview()
        coordinator.adView = nil
        #endif
    }

    // MARK: - Делегат Meta FBAdViewDelegate
    @MainActor
    public final class Coordinator: NSObject {
        var parent: MetaNativeBannerRepresentable
        #if canImport(FBAudienceNetwork)
        weak var adView: FBAdView?
        #endif

        init(parent: MetaNativeBannerRepresentable) {
            self.parent = parent
        }
    }
}

#if canImport(FBAudienceNetwork)
extension MetaNativeBannerRepresentable.Coordinator: FBAdViewDelegate {
    public func adViewDidLoad(_ adView: FBAdView) {
        print("⚡ [Meta Audience Network] Баннер успешно загружен (Placement: \(adView.placementID))")
        parent.onAdLoaded?()
    }

    public func adView(_ adView: FBAdView, didFailWithError error: Error) {
        print("⚠ [Meta Audience Network] Ошибка загрузки баннера: \(error.localizedDescription)")
        parent.onAdFailed?(error.localizedDescription)
    }

    public func adViewDidClick(_ adView: FBAdView) {
        print("⚡ [Meta Audience Network] Клик по баннеру Meta")
        HapticManager.shared.impactMedium()
        parent.onAdClicked?()
    }

    public func adViewWillLogImpression(_ adView: FBAdView) {
        print("⚡ [Meta Audience Network] Зафиксирован показ (Impression) баннера")
    }
}
#endif
