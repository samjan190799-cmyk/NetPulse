//
//  AlertSound.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import AudioToolbox
import Foundation

/// Решает, можно ли сейчас играть звук предупреждения: не чаще одного раза за `minimumInterval`.
/// Отдельная структура без обращений к системе, чтобы правило проверялось тестами.
struct AlertSoundThrottle: Equatable {
    let minimumInterval: TimeInterval
    private(set) var lastPlayedAt: Date?

    init(minimumInterval: TimeInterval, lastPlayedAt: Date? = nil) {
        self.minimumInterval = minimumInterval
        self.lastPlayedAt = lastPlayedAt
    }

    /// Можно ли играть звук в момент `now`. Если можно, момент запоминается. Отказ тишину не продлевает:
    /// отсчёт идёт от последнего сыгранного звука, а не от последнего предупреждения.
    mutating func claim(at now: Date) -> Bool {
        if let last = lastPlayedAt {
            let elapsed = now.timeIntervalSince(last)
            // Часы перевели назад (elapsed < 0): тишина не должна растянуться на часы
            if elapsed >= 0, elapsed < minimumInterval { return false }
        }
        lastPlayedAt = now
        return true
    }
}

/// Звук предупреждения о серьёзной проблеме с сетью.
///
/// Раньше играла «тройная» мелодия SMS (системный звук 1007), а при долгой проблеме с сетью предупреждение повторялось
/// каждую минуту по каждому узлу и показателю, и телефон звенел почти без остановки. Теперь это один короткий щелчок
/// «Tink» не чаще раза в пять минут. Системные звуки не прерывают музыку и молчат, когда звук выключен боковой кнопкой.
@MainActor
final class AlertSound {
    static let shared = AlertSound()

    /// Системный звук «Tink»: короткий щелчок вместо мелодии
    nonisolated static let soundID: SystemSoundID = 1057
    /// Не чаще одного звука за это время, как бы ни повторялись предупреждения
    nonisolated static let minimumInterval: TimeInterval = 5 * 60

    private var throttle = AlertSoundThrottle(minimumInterval: AlertSound.minimumInterval)
    private let player: @MainActor (SystemSoundID) -> Void
    private let clock: () -> Date

    init(
        player: @escaping @MainActor (SystemSoundID) -> Void = { AudioServicesPlaySystemSound($0) },
        clock: @escaping () -> Date = { Date() }
    ) {
        self.player = player
        self.clock = clock
    }

    /// Играет звук, если недавно он не звучал. Возвращает, сыграл ли.
    @discardableResult
    func playIfDue() -> Bool {
        guard throttle.claim(at: clock()) else { return false }
        player(Self.soundID)
        return true
    }
}
