//
//  AdMobManager.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / StoreKit 2) - 2026.
//

import SwiftUI
import StoreKit
#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif

/// Идентификаторы покупок App Store.
///
/// ВАЖНО: идентификатор должен совпадать с продуктом, созданным в App Store Connect
/// (автообновляемая подписка или неисчерпываемая покупка «NetPulse PRO»). Пока продукта там нет,
/// приложение честно сообщает «покупка недоступна» и PRO НЕ выдаётся.
public enum StoreConfig {
    public static let proProductID = "com.samvel.netpulse.pro"
}

/// Менеджер покупки NetPulse PRO (StoreKit 2) и разрешения на отслеживание (ATT).
///
/// Статус PRO определяется ТОЛЬКО подтверждённой покупкой App Store. Раньше `purchaseProVersion()` просто
/// выставлял флаг, «режим владельца» включался пятью нажатиями на строку «Версия», а `restorePurchases()`
/// ничего не восстанавливал — PRO можно было получить бесплатно.
@Observable
@MainActor
public final class AdMobManager {
    public static let shared = AdMobManager()

    private static let kEntitlementCacheKey = "netpulse_pro_entitlement_cache_v2"

    // MARK: - Состояние PRO

    /// Есть ли подтверждённая покупка. Устанавливается только после проверки транзакции StoreKit
    /// (значение кэшируется, чтобы PRO не «пропадал» при запуске без сети, и перепроверяется при каждом старте).
    public private(set) var isPremiumUser: Bool {
        didSet {
            UserDefaults.standard.set(isPremiumUser, forKey: Self.kEntitlementCacheKey)
        }
    }

    public private(set) var isPurchaseInProgress: Bool = false

    /// Сообщение пользователю о результате покупки/восстановления (nil — нечего показывать)
    public var purchaseMessage: String?

    /// Цена PRO в локальной валюте из App Store (nil — товар не загружен)
    public private(set) var proPriceText: String?

    /// Реклама показывается, пока PRO не куплен
    public var canShowAds: Bool {
        !isPremiumUser
    }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    private init() {
        // Прежние локальные флаги («бесплатная покупка» и «режим владельца») больше не действуют
        UserDefaults.standard.removeObject(forKey: "netpulse_owner_unlocked")
        UserDefaults.standard.removeObject(forKey: "netpulse_is_premium_user")
        self.isPremiumUser = UserDefaults.standard.bool(forKey: Self.kEntitlementCacheKey)

        updatesTask = Task { [weak self] in
            await self?.refreshEntitlements()
            await self?.loadProductInfo()

            // Транзакции, прошедшие вне приложения (продление, возврат, покупка на другом устройстве)
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self.refreshEntitlements()
            }
        }
    }

    // MARK: - Права доступа

    /// Перепроверка действующих покупок по данным App Store
    private func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == StoreConfig.proProductID,
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        isPremiumUser = entitled
    }

    private func loadProductInfo() async {
        do {
            let products = try await Product.products(for: [StoreConfig.proProductID])
            proPriceText = products.first?.displayPrice
        } catch {
            proPriceText = nil
        }
    }

    // MARK: - Покупка NetPulse PRO

    public func purchaseProVersion() {
        guard !isPurchaseInProgress else { return }
        isPurchaseInProgress = true
        purchaseMessage = nil

        Task { [weak self] in
            guard let self else { return }
            await self.performPurchase()
            self.isPurchaseInProgress = false
        }
    }

    private func performPurchase() async {
        do {
            let products = try await Product.products(for: [StoreConfig.proProductID])
            guard let product = products.first else {
                purchaseMessage = "Покупка сейчас недоступна: товар не найден в App Store. Попробуйте позже."
                return
            }
            proPriceText = product.displayPrice

            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    isPremiumUser = true
                    purchaseMessage = nil
                    HapticManager.shared.notificationSuccess()
                case .unverified:
                    purchaseMessage = "Не удалось подтвердить покупку. Попробуйте ещё раз или восстановите покупки."
                }
            case .userCancelled:
                break
            case .pending:
                purchaseMessage = "Покупка ожидает подтверждения (например, от организатора семейного доступа)."
            @unknown default:
                purchaseMessage = "Неизвестный результат покупки."
            }
        } catch {
            purchaseMessage = "Не удалось выполнить покупку: \(error.localizedDescription)"
        }
    }

    /// Восстановление покупок: синхронизация с App Store и повторная проверка прав
    public func restorePurchases() {
        guard !isPurchaseInProgress else { return }
        isPurchaseInProgress = true
        purchaseMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                try await AppStore.sync()
                await self.refreshEntitlements()
                if self.isPremiumUser {
                    HapticManager.shared.notificationSuccess()
                } else {
                    self.purchaseMessage = "Активных покупок NetPulse PRO не найдено."
                }
            } catch {
                self.purchaseMessage = "Не удалось восстановить покупки: \(error.localizedDescription)"
            }
            self.isPurchaseInProgress = false
        }
    }

    // MARK: - Запрос разрешения App Tracking Transparency (ATT)
    private nonisolated static func requestATTAuth() async -> ATTrackingManager.AuthorizationStatus {
        #if canImport(AppTrackingTransparency)
        if #available(iOS 14.5, *) {
            return await withCheckedContinuation { continuation in
                ATTrackingManager.requestTrackingAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
        #endif
        return .authorized
    }

    public func requestTrackingAuthorization() {
        #if canImport(AppTrackingTransparency)
        if #available(iOS 14.5, *) {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
                guard UIApplication.shared.applicationState == .active else { return }
                let status = await Self.requestATTAuth()
                print("[AdMobManager] ATT Status: \(status.rawValue)")
            }
        }
        #endif
    }
}
