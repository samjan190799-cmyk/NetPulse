//
//  StoreManager.swift
//  NetPulse
//
//  Подписка NetPulse PRO на StoreKit 2 (автопродлеваемая, группа «NetPulse PRO»).
//

import StoreKit
import SwiftUI

/// Менеджер подписки NetPulse PRO: загрузка продуктов, покупка, восстановление, слежение за статусом
@Observable
@MainActor
public final class StoreManager {
    public static let shared = StoreManager()

    /// Идентификаторы продуктов — должны совпадать с App Store Connect
    public static let monthlyID = "com.samvel.netpulse.pro.monthly"
    public static let yearlyID = "com.samvel.netpulse.pro.yearly"
    private static let productIDs = [yearlyID, monthlyID]

    public private(set) var products: [Product] = []
    public private(set) var isLoadingProducts = false
    public private(set) var isPurchasing = false
    public var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                await self.handle(result)
            }
        }
    }

    /// Запуск при старте приложения: продукты и текущий статус подписки
    public func start() {
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    public func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: Self.productIDs).sorted { $0.price > $1.price }
        } catch {
            errorMessage = "Не удалось загрузить тарифы. Проверьте подключение к интернету."
        }
    }

    public func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Покупка не завершена: \(error.localizedDescription)"
        }
    }

    public func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = "Не удалось восстановить покупки: \(error.localizedDescription)"
        }
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await transaction.finish()
        await refreshEntitlements()
    }

    /// Пересчитывает наличие активной подписки по текущим правам пользователя
    public func refreshEntitlements() async {
        var isActive = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            if let expiration = transaction.expirationDate, expiration < Date() { continue }
            isActive = true
        }
        AdMobManager.shared.applyStoreEntitlement(isActive)
    }
}
