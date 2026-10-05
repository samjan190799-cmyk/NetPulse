//
//  PowerSaverTests.swift
//  NetPulseTests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest
@testable import NetPulse

// MARK: - Таблица значений режима экономии заряда

final class PowerProfileTests: XCTestCase {

    /// Пока режим выключен, приложение обязано работать так же, как работало до его появления
    func testNormalProfileKeepsTheValuesTheAppAlwaysHad() {
        let normal = PowerProfile.normal
        XCTAssertEqual(normal.speedLoopForegroundSeconds, 1)
        XCTAssertEqual(normal.speedLoopBackgroundSeconds, 1)
        XCTAssertEqual(normal.islandMinIntervalSeconds, 0)
        XCTAssertEqual(normal.hostCheckSlowdown, 1)
        XCTAssertEqual(normal.networkInfoIntervalSeconds, 20)
        XCTAssertEqual(normal.widgetReloadIntervalSeconds, 0)
        XCTAssertEqual(normal.backgroundRefreshMinutes, 15)
        XCTAssertEqual(normal.backgroundProcessingMinutes, 30)
        XCTAssertTrue(normal.measuresSpeedOnRoute)
        XCTAssertEqual(normal.routeIdleStopSeconds, 20 * 60)
        XCTAssertTrue(normal.showsZones)
        XCTAssertEqual(normal.previousLineLimit, CoverageBuilder.maxRuns)
    }

    @MainActor
    func testNormalIdleLimitMatchesTheRecorderConstant() {
        XCTAssertEqual(PowerProfile.normal.routeIdleStopSeconds, RouteRecorder.idleStopSeconds)
    }

    /// Режим экономии только ослабляет: ни одно значение не может стать «жаднее» обычного
    func testSaverNeverDemandsMoreThanNormal() {
        let normal = PowerProfile.normal
        let saver = PowerProfile.saver
        XCTAssertGreaterThan(saver.speedLoopForegroundSeconds, normal.speedLoopForegroundSeconds)
        XCTAssertGreaterThan(saver.speedLoopBackgroundSeconds, normal.speedLoopBackgroundSeconds)
        XCTAssertGreaterThanOrEqual(saver.islandMinIntervalSeconds, normal.islandMinIntervalSeconds)
        XCTAssertGreaterThan(saver.hostCheckSlowdown, normal.hostCheckSlowdown)
        XCTAssertGreaterThan(saver.networkInfoIntervalSeconds, normal.networkInfoIntervalSeconds)
        XCTAssertGreaterThan(saver.widgetReloadIntervalSeconds, normal.widgetReloadIntervalSeconds)
        XCTAssertGreaterThan(saver.backgroundRefreshMinutes, normal.backgroundRefreshMinutes)
        XCTAssertGreaterThan(saver.backgroundProcessingMinutes, normal.backgroundProcessingMinutes)
        XCTAssertLessThan(saver.routeIdleStopSeconds, normal.routeIdleStopSeconds)
        XCTAssertLessThan(saver.previousLineLimit, normal.previousLineLimit)
    }

    func testSaverSwitchesOffWhatCanBeSwitchedOff() {
        XCTAssertFalse(PowerProfile.saver.measuresSpeedOnRoute, "Скачивание до 1,5 МБ каждые 30 секунд в режиме экономии не нужно")
        XCTAssertFalse(PowerProfile.saver.showsZones, "Зоны покрытия считаются и рисуются: в режиме экономии их нет")
    }

    /// Остров, который обновляется реже паузы цикла, пропускал бы кадры через один: обновление стало бы вдвое реже задуманного
    func testIslandFrameIntervalDoesNotExceedTheBackgroundLoopPause() {
        let saver = PowerProfile.saver
        XCTAssertLessThanOrEqual(saver.islandMinIntervalSeconds, saver.speedLoopBackgroundSeconds)
        XCTAssertGreaterThan(saver.islandMinIntervalSeconds, saver.speedLoopForegroundSeconds, "Иначе ограничение ничего не меняло бы при открытом приложении")
    }

    func testSpeedLoopPauseDependsOnWhetherTheAppIsInBackground() {
        XCTAssertEqual(PowerProfile.normal.speedLoopPause(isBackground: false), 1)
        XCTAssertEqual(PowerProfile.normal.speedLoopPause(isBackground: true), 1)
        XCTAssertEqual(PowerProfile.saver.speedLoopPause(isBackground: false), 3)
        XCTAssertEqual(PowerProfile.saver.speedLoopPause(isBackground: true), 5)
    }

    func testIslandFramesAreThrottledOnlyInSaverMode() {
        let saver = PowerProfile.saver
        XCTAssertTrue(saver.allowsIslandFrame(elapsed: nil, force: false), "Первый кадр проходит всегда")
        XCTAssertFalse(saver.allowsIslandFrame(elapsed: 1, force: false), "Через секунду после прошлого кадра рано")
        XCTAssertTrue(saver.allowsIslandFrame(elapsed: 1, force: true), "Кадр по запросу проходит всегда")
        XCTAssertTrue(saver.allowsIslandFrame(elapsed: saver.islandMinIntervalSeconds, force: false))
        XCTAssertTrue(saver.allowsIslandFrame(elapsed: -30, force: false), "Часы перевели назад: ждать нечего")

        XCTAssertTrue(PowerProfile.normal.allowsIslandFrame(elapsed: 0, force: false), "В обычном режиме кадры не ограничены")
        XCTAssertTrue(PowerProfile.normal.allowsIslandFrame(elapsed: 0.01, force: false))
    }

    func testWidgetReloadsAreThrottledOnlyInSaverMode() {
        let saver = PowerProfile.saver
        XCTAssertFalse(saver.allowsWidgetReload(elapsed: 60))
        XCTAssertTrue(saver.allowsWidgetReload(elapsed: saver.widgetReloadIntervalSeconds))
        XCTAssertTrue(saver.allowsWidgetReload(elapsed: .infinity), "Первый раз после запуска виджеты обновляются сразу")
        XCTAssertTrue(saver.allowsWidgetReload(elapsed: -1), "Часы перевели назад: ждать нечего")

        XCTAssertTrue(PowerProfile.normal.allowsWidgetReload(elapsed: 0))
        XCTAssertTrue(PowerProfile.normal.allowsWidgetReload(elapsed: -1))
    }

    /// Контрольная проверка цикла острова не должна принимать длинную паузу режима экономии за «цикл умер»
    func testIslandLoopStaleThresholdGrowsWithThePause() {
        XCTAssertEqual(PowerProfile.normal.islandLoopStaleSeconds, 5, "Обычный порог остался прежним")
        XCTAssertGreaterThan(PowerProfile.saver.islandLoopStaleSeconds, PowerProfile.saver.speedLoopBackgroundSeconds)
    }

    /// Выключатель читается из настроек: его используют и циклы вне главного потока, и фоновые задачи iOS
    func testCurrentProfileFollowsTheSwitchInSettings() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: PowerSaver.defaultsKey)
        defer {
            if let saved {
                defaults.set(saved, forKey: PowerSaver.defaultsKey)
            } else {
                defaults.removeObject(forKey: PowerSaver.defaultsKey)
            }
        }

        defaults.set(false, forKey: PowerSaver.defaultsKey)
        XCTAssertFalse(PowerSaver.isEnabled)
        XCTAssertEqual(PowerProfile.current, .normal)

        defaults.set(true, forKey: PowerSaver.defaultsKey)
        XCTAssertTrue(PowerSaver.isEnabled)
        XCTAssertEqual(PowerProfile.current, .saver)
    }

    func testSwitchKeyIsStable() {
        // Ключ лежит в настройках пользователя: переименование молча сбросило бы его выбор
        XCTAssertEqual(PowerSaver.defaultsKey, "netpulse_power_saver")
    }
}

// MARK: - Контроль пауз цикла при длинном шаге

final class LoopTimingScalingTests: XCTestCase {

    func testThresholdForTheUsualPauseIsUnchanged() {
        XCTAssertEqual(LoopTiming.threshold(expectedPause: 1), LoopTiming.pauseThreshold)
    }

    func testLongerPauseRaisesTheThreshold() {
        XCTAssertEqual(LoopTiming.threshold(expectedPause: 3), 7)
        XCTAssertEqual(LoopTiming.threshold(expectedPause: 5), 11)
    }

    func testSaverStepIsNotMistakenForAStop() {
        // Цикл ждёт 5 секунд и ещё немного работает: 6 секунд между шагами — норма
        XCTAssertEqual(
            LoopTiming.classify(gap: 6, previousTickWasBackground: true, expectedPause: 5),
            .normal
        )
        // Настоящее усыпление всё равно видно
        XCTAssertEqual(
            LoopTiming.classify(gap: 60, previousTickWasBackground: true, expectedPause: 5),
            .suspendedInBackground(seconds: 60)
        )
        XCTAssertEqual(
            LoopTiming.classify(gap: 20, previousTickWasBackground: false, expectedPause: 3),
            .stalledInForeground(seconds: 20)
        )
        // При обычной паузе те же 6 секунд — остановка, как и раньше
        XCTAssertEqual(
            LoopTiming.classify(gap: 6, previousTickWasBackground: true),
            .suspendedInBackground(seconds: 6)
        )
    }
}
