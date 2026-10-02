//
//  AdModels.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//  Чистая логика рекламы без SDK: частота показа и паузы между повторными запросами. Вынесена отдельно,
//  чтобы проверяться юнит-тестами без рекламной сети.
//

import Foundation

/// Частота межстраничной рекламы: «положена» после каждых `every` действий пользователя.
///
/// Счётчик только считает. Решает, показывать ли рекламу сейчас, менеджер: готов ли ролик, не куплен ли PRO.
/// Если реклама «положена», но ещё не загрузилась, она остаётся положенной и показывается при ближайшем
/// действии, как только будет готова: счётчик обнуляется только после настоящего показа (`reset()`).
struct AdFrequencyCap: Equatable, Sendable {
    let every: Int
    private(set) var actions: Int = 0

    init(every: Int) {
        self.every = max(1, every)
    }

    /// Учитывает действие пользователя; `true` — реклама положена (набралось не меньше `every` действий)
    mutating func recordAction() -> Bool {
        actions += 1
        return actions >= every
    }

    /// Реклама показана: отсчёт начинается заново
    mutating func reset() {
        actions = 0
    }
}

/// Паузы между повторными запросами рекламы после неудачи: растут, чтобы не засыпать рекламную сеть запросами,
/// пока нет интернета или подходящих объявлений.
enum AdRetryPolicy {
    /// Пауза после первой, второй, третьей… подряд неудачи (после последней паузы остаётся последнее значение)
    static let delays: [TimeInterval] = [10, 30, 60, 120, 300]

    static func delay(afterFailures failures: Int) -> TimeInterval {
        let index = min(max(failures, 1), delays.count) - 1
        return delays[index]
    }
}
