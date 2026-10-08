//
//  ProStore.swift
//  NetPulse
//
//  Подписка NetPulse PRO на StoreKit 2: одна автопродлеваемая подписка (месяц), доступ к платным возможностям.
//

import Foundation
import Observation
import StoreKit

// MARK: - Платные возможности

/// Что закрыто подпиской PRO. Нужно, чтобы окно подписки знало, с чего его открыли, и подсветило эту возможность.
public enum ProFeature: String, Identifiable, CaseIterable, Sendable {
    /// Общее открытие окна (из настроек)
    case general
    /// Остров и экран блокировки: скорость в Dynamic Island
    case island
    /// Игровой HUD: плавающая панель пинга и скорости
    case hud
    /// Глубокий AI-аудит сети
    case aiAudit

    public var id: String { rawValue }

    /// Возможности, которые входят в подписку (без «общего» пункта)
    public static var included: [ProFeature] {
        [.island, .hud, .aiAudit]
    }

    public var title: String {
        switch self {
        case .general: return "NetPulse PRO"
        case .island: return "Скорость в Dynamic Island"
        case .hud: return "Игровой HUD"
        case .aiAudit: return "Глубокий AI-аудит"
        }
    }

    public var summary: String {
        switch self {
        case .general:
            return "Остров, игровой HUD и AI-аудит сети"
        case .island:
            return "Скачивание, отдача и пинг в Dynamic Island и на экране блокировки"
        case .hud:
            return "Плавающая панель пинга, джиттера, потерь и скорости поверх экранов приложения"
        case .aiAudit:
            return "Оценка сети от 0 до 100, предсказание просадок, мастер поиска причин и обращение к провайдеру"
        }
    }

    public var icon: String {
        switch self {
        case .general: return "star.fill"
        case .island: return "capsule.inset.filled"
        case .hud: return "gamecontroller.fill"
        case .aiAudit: return "sparkles"
        }
    }
}

// MARK: - Правило доступа

/// Какая покупка даёт PRO. Вынесено из менеджера, чтобы проверяться юнит-тестами без App Store.
enum ProEntitlement {
    /// Идентификатор подписки: должен совпадать с App Store Connect (группа «NetPulse PRO»)
    static let monthlyID = "com.samvel.netpulse.pro.monthly2"

    /// Даёт ли такая запись о покупке доступ к PRO: это наша подписка, она не отозвана и не истекла
    static func grantsPro(productID: String, revocationDate: Date?, expirationDate: Date?, now: Date = Date()) -> Bool {
        guard productID == monthlyID, revocationDate == nil else { return false }
        if let expirationDate, expirationDate < now { return false }
        return true
    }
}

// MARK: - Менеджер подписки

/// Менеджер подписки NetPulse PRO: загрузка цены, покупка, восстановление, слежение за статусом.
///
/// Остров, игровой HUD и AI-аудит работают, только пока `isPro` истинно. Состояние запоминается между запусками
/// (StoreKit подтвердит или отзовёт его сразу после старта), поэтому подписчик не видит замка на долю секунды.
@Observable
@MainActor
public final class ProStore {
    public static let shared = ProStore()

    private static let cacheKey = "netpulse_pro_cached"

    /// Есть ли активная подписка
    public private(set) var isPro: Bool
    /// Подписка из App Store: оттуда берутся цена и срок
    public private(set) var product: Product?
    public private(set) var isLoadingProduct = false
    public private(set) var isPurchasing = false
    /// Сообщение об ошибке покупки или восстановления (показывается в окне подписки)
    public var errorMessage: String?
    /// Окно подписки открыто, если не `nil`; значение подсвечивает возможность, с которой его открыли
    public var paywall: ProFeature?
    /// Вызывается, когда подписка появилась или закончилась: остров запускается или гасится
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    /// Отладочная сборка запущена с аргументом `-netpulse_pro YES` (UI-тесты): подписка считается купленной.
    /// В выпускной сборке такого выключателя нет.
    @ObservationIgnored private let debugForced: Bool
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        let forced = defaults.bool(forKey: "netpulse_pro")
        #else
        let forced = false
        #endif
        self.debugForced = forced
        self.isPro = forced || defaults.bool(forKey: Self.cacheKey)
    }

    // MARK: - Запуск

    /// Запускается при старте приложения: слушает покупки, подтверждает статус, загружает цену
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                await self.handle(result)
            }
        }
        Task {
            await refreshEntitlements()
            await loadProduct()
        }
    }

    public func loadProduct() async {
        guard product == nil, !isLoadingProduct else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            product = try await Product.products(for: [ProEntitlement.monthlyID]).first
        } catch {
            product = nil
        }
    }

    // MARK: - Доступ

    /// Проверка перед платной возможностью: если подписки нет, открывается окно подписки и возвращается `false`
    @discardableResult
    public func requirePro(_ feature: ProFeature) -> Bool {
        if isPro { return true }
        paywall = feature
        return false
    }

    /// Цена с периодом, как её показывает App Store: «$0.99 в месяц» (nil, пока цена не загрузилась)
    public var priceText: String? {
        guard let product else { return nil }
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayPrice }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "в день" : "за \(period.value) дн."
        case .week: unit = period.value == 1 ? "в неделю" : "за \(period.value) нед."
        case .month: unit = period.value == 1 ? "в месяц" : "за \(period.value) мес."
        case .year: unit = period.value == 1 ? "в год" : "за \(period.value) г."
        @unknown default: unit = ""
        }
        return "\(product.displayPrice) \(unit)".trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Покупка и восстановление

    public func purchase() async {
        guard let product, !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
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
        errorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPro {
                errorMessage = "Активной подписки на этой учётной записи Apple ID не найдено."
            }
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
        var active = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if ProEntitlement.grantsPro(
                productID: transaction.productID,
                revocationDate: transaction.revocationDate,
                expirationDate: transaction.expirationDate
            ) {
                active = true
            }
        }
        apply(isActive: active)
    }

    /// Применяет итог проверки: запоминает его и сообщает остальному приложению, если статус изменился
    func apply(isActive: Bool) {
        let value = debugForced || isActive
        if !debugForced {
            defaults.set(value, forKey: Self.cacheKey)
        }
        guard value != isPro else { return }
        isPro = value
        if value {
            paywall = nil
        }
        onChange?()
    }
}
