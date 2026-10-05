//
//  PowerSaver.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Режим экономии заряда: один общий выключатель в настройках.
///
/// Выключен — всё работает как обычно. Включён — приложение реже опрашивает сеть и обновляет остров, пишет маршрут
/// реже и грубее и не делает того, без чего можно обойтись. Что именно меняется, описывает `PowerProfile`.
public enum PowerSaver {
    /// Ключ в настройках (тот же читает `@AppStorage` в интерфейсе)
    public static let defaultsKey = "netpulse_power_saver"

    /// Включён ли режим. Читается из настроек: значение нужно и циклам вне главного потока, и фоновым задачам iOS.
    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }
}

/// Таблица значений: что и насколько меняется в режиме экономии. Все числа лежат в одном месте, чтобы их проверяли
/// тесты, а у `normal` стоят те значения, с которыми приложение работало до появления режима.
public struct PowerProfile: Equatable, Sendable {
    /// Пауза цикла скорости и острова при открытом приложении, секунды
    public let speedLoopForegroundSeconds: TimeInterval
    /// То же, пока приложение свёрнуто
    public let speedLoopBackgroundSeconds: TimeInterval
    /// Не чаще одного кадра острова за столько секунд (0 — без ограничения). Не больше паузы цикла в фоне: иначе кадры
    /// пропускались бы через один, и остров обновлялся бы вдвое реже, чем задумано.
    public let islandMinIntervalSeconds: TimeInterval
    /// Во сколько раз реже проверяются узлы мониторинга при открытом приложении
    public let hostCheckSlowdown: Double
    /// Как часто обновляются сведения о сети (внешний адрес, провайдер), секунды
    public let networkInfoIntervalSeconds: TimeInterval
    /// Не чаще одного обновления виджетов за столько секунд (0 — без ограничения)
    public let widgetReloadIntervalSeconds: TimeInterval
    /// Через сколько минут просим iOS о следующем фоновом обновлении
    public let backgroundRefreshMinutes: Double
    /// Через сколько минут просим iOS о следующей фоновой обработке
    public let backgroundProcessingMinutes: Double
    /// Замерять ли скорость скачивания во время записи маршрута
    public let measuresSpeedOnRoute: Bool
    /// Через сколько секунд без движения запись маршрута останавливается сама
    public let routeIdleStopSeconds: TimeInterval
    /// Рисовать ли на карте зоны покрытия
    public let showsZones: Bool
    /// Сколько линий прежних маршрутов рисуется на карте самое большее (в маршруте их несколько: по цветам качества)
    public let previousLineLimit: Int

    /// Обычный режим: значения, с которыми приложение работало раньше
    public static let normal = PowerProfile(
        speedLoopForegroundSeconds: 1,
        speedLoopBackgroundSeconds: 1,
        islandMinIntervalSeconds: 0,
        hostCheckSlowdown: 1,
        networkInfoIntervalSeconds: 20,
        widgetReloadIntervalSeconds: 0,
        backgroundRefreshMinutes: 15,
        backgroundProcessingMinutes: 30,
        measuresSpeedOnRoute: true,
        routeIdleStopSeconds: 20 * 60,
        showsZones: true,
        previousLineLimit: CoverageBuilder.maxRuns
    )

    /// Режим экономии: всё, что можно ослабить без потери главного (скорость в острове и запись маршрута остаются)
    public static let saver = PowerProfile(
        speedLoopForegroundSeconds: 3,
        speedLoopBackgroundSeconds: 5,
        islandMinIntervalSeconds: 4,
        hostCheckSlowdown: 3,
        networkInfoIntervalSeconds: 60,
        widgetReloadIntervalSeconds: 5 * 60,
        backgroundRefreshMinutes: 60,
        backgroundProcessingMinutes: 120,
        measuresSpeedOnRoute: false,
        routeIdleStopSeconds: 10 * 60,
        showsZones: false,
        previousLineLimit: 80
    )

    /// Профиль сейчас: по выключателю в настройках
    public static var current: PowerProfile {
        PowerSaver.isEnabled ? .saver : .normal
    }

    /// Пауза цикла скорости и острова: при открытом приложении и в фоне она разная
    public func speedLoopPause(isBackground: Bool) -> TimeInterval {
        isBackground ? speedLoopBackgroundSeconds : speedLoopForegroundSeconds
    }

    /// Можно ли отправить очередной кадр острова. `elapsed` — сколько прошло с прошлого кадра (`nil` — кадров ещё не было).
    /// Кадры «по запросу» (`force`) проходят всегда.
    public func allowsIslandFrame(elapsed: TimeInterval?, force: Bool) -> Bool {
        guard !force, islandMinIntervalSeconds > 0, let elapsed else { return true }
        // Часы перевели назад (`elapsed` меньше нуля): ждать нечего
        return elapsed < 0 || elapsed >= islandMinIntervalSeconds
    }

    /// Можно ли снова просить виджеты перерисоваться, если с прошлой просьбы прошло `elapsed` секунд
    public func allowsWidgetReload(elapsed: TimeInterval) -> Bool {
        widgetReloadIntervalSeconds <= 0 || elapsed < 0 || elapsed >= widgetReloadIntervalSeconds
    }

    /// Через сколько секунд без обновления цикл острова считается мёртвым: вдвое дольше его паузы в фоне, но не короче 5 секунд
    public var islandLoopStaleSeconds: TimeInterval {
        max(5, speedLoopBackgroundSeconds * 2)
    }
}
