//
//  NetPulseUITests.swift
//  NetPulseUITests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest

/// Проверка приложения в симуляторе: запуск, вкладки, экран настроек, Dynamic Island и «Непрерывный режим».
///
/// Что симулятор доказать НЕ может: усыпление свёрнутого приложения на реальном iPhone он не воспроизводит,
/// поэтому «остров не замирает в фоне» окончательно проверяется только на устройстве. Здесь проверяется всё
/// остальное: приложение запускается и не падает, интерфейс на месте, Live Activity стартует, режим включается,
/// а скриншоты острова в фоне сохраняются во вложения результата и публикуются артефактами CI.
///
/// Строки с префиксом `NETPULSE-CI:` попадают в журнал и помогают разобрать прогон без скачивания артефактов.
final class NetPulseUITests: XCTestCase {

    // MARK: - Запуск и общие помощники

    @MainActor private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Параметр запуска переопределяет сохранённое значение: каждый тест стартует с выключенным режимом
        app.launchArguments += ["-netpulse_continuous_mode_enabled", "NO"]
        app.launch()
        dismissSystemAlerts()
        return app
    }

    /// Закрывает системные окна SpringBoard (ATT, геолокация, уведомления, Live Activities), предпочитая «Разрешить».
    @MainActor private func dismissSystemAlerts(timeout: TimeInterval = 6) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let preferred = [
            "Allow While Using App", "Allow Once", "Allow", "OK", "Ask App Not to Track",
            "Разрешить при использовании приложения", "Разрешить", "Попросить приложение не отслеживать"
        ]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 1.5) else { continue }

            var tapped = false
            for title in preferred {
                let button = alert.buttons[title]
                if button.exists {
                    print("NETPULSE-CI: системное окно «\(alert.label)»: нажимаю «\(title)»")
                    button.tap()
                    tapped = true
                    break
                }
            }
            if !tapped {
                let titles = alert.buttons.allElementsBoundByIndex.map { $0.label }
                print("NETPULSE-CI: неизвестное системное окно «\(alert.label)», кнопки: \(titles)")
                attachScreenshot("unknown-system-alert")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    @MainActor private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Иерархия доступности приложения как текстовое вложение: по ней видно, что было на экране в момент сбоя.
    @MainActor private func attachHierarchy(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func openSettings(_ app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Панель вкладок не появилась: приложение не запустилось или упало")
        app.tabBars.buttons["Настройки"].tap()
    }

    /// Прокручивает экран, пока элемент не станет видимым (строки SwiftUI-списка создаются лениво).
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 15) -> Bool {
        if element.waitForExistence(timeout: 5), element.isHittable { return true }
        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.exists, element.isHittable { return true }
        }
        return false
    }

    /// Нажимает на сам переключатель (правая часть строки), а не на подпись.
    @MainActor private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    @MainActor private func isOn(_ toggle: XCUIElement) -> Bool {
        (toggle.value as? String) == "1"
    }

    @MainActor private func describe(_ state: XCUIApplication.State) -> String {
        switch state {
        case .unknown: return "unknown"
        case .notRunning: return "notRunning"
        case .runningBackgroundSuspended: return "runningBackgroundSuspended"
        case .runningBackground: return "runningBackground"
        case .runningForeground: return "runningForeground"
        @unknown default: return "other(\(state.rawValue))"
        }
    }

    /// Включает «Непрерывный режим» и дожидается статуса «Активен…». Возвращает последний прочитанный статус.
    @discardableResult
    @MainActor private func enableContinuousMode(_ app: XCUIApplication) -> String {
        let toggle = app.switches["continuousModeToggle"]
        XCTAssertTrue(reveal(toggle, in: app), "Тумблер «Непрерывный режим» не найден на экране настроек")
        if !isOn(toggle) { flip(toggle) }
        dismissSystemAlerts()

        // После системного окна список настроек может оказаться прокрученным в другое место (в первом прогоне
        // строка статуса осталась за пределами экрана), поэтому строку ищем прокруткой, а не там, где она была.
        let status = app.staticTexts["continuousModeStatus"]
        guard reveal(status, in: app) else {
            attachScreenshot("continuous-status-not-found")
            attachHierarchy(app, name: "continuous-status-not-found-hierarchy")
            print("NETPULSE-CI: строка статуса непрерывного режима не найдена")
            return "(строка статуса не найдена)"
        }
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !(status.exists && status.label.hasPrefix("Активен")) {
            Thread.sleep(forTimeInterval: 0.5)
        }
        let finalStatus = status.exists ? status.label : "(строка статуса пропала с экрана)"
        print("NETPULSE-CI: статус непрерывного режима: \(finalStatus)")
        return finalStatus
    }

    /// Уходит на главный экран и фиксирует состояние приложения и скриншот через заданные паузы.
    @MainActor private func sampleBackground(_ app: XCUIApplication, prefix: String, pauses: [TimeInterval]) {
        XCUIDevice.shared.press(.home)
        for (index, pause) in pauses.enumerated() {
            Thread.sleep(forTimeInterval: pause)
            let state = describe(app.state)
            print("NETPULSE-CI: \(prefix), шаг \(index + 1), состояние приложения: \(state)")
            attachScreenshot("\(prefix)-\(index + 1)")
        }
    }

    // MARK: - Тесты

    @MainActor func testAppLaunchesAndShowsAllTabs() throws {
        let app = launchApp()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Панель вкладок не появилась: приложение не запустилось или упало")
        attachScreenshot("launch-home")

        let tabs: [(title: String, slug: String)] = [
            ("Скорость", "speed"), ("Узлы", "hosts"), ("Трафик", "traffic"), ("AI Диагност", "ai"), ("Настройки", "settings")
        ]
        for tab in tabs {
            XCTAssertTrue(app.tabBars.buttons[tab.title].exists, "Нет вкладки «\(tab.title)»")
        }
        for tab in tabs {
            app.tabBars.buttons[tab.title].tap()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "Приложение закрылось на вкладке «\(tab.title)»")
            attachScreenshot("tab-\(tab.slug)")
        }
    }

    @MainActor func testSettingsContainIslandAndContinuousModeControls() throws {
        let app = launchApp()
        openSettings(app)

        XCTAssertTrue(reveal(app.switches["dynamicIslandToggle"], in: app), "Тумблер Dynamic Island не найден")
        XCTAssertTrue(reveal(app.switches["continuousModeToggle"], in: app), "Тумблер «Непрерывный режим» не найден")
        attachScreenshot("settings-island-controls")

        XCTAssertFalse(isOn(app.switches["continuousModeToggle"]), "Непрерывный режим не должен быть включён сам по себе")
    }

    @MainActor func testLiveActivityStartsInSimulator() throws {
        let app = launchApp()
        openSettings(app)

        let status = app.staticTexts["islandStatus"]
        XCTAssertTrue(reveal(status, in: app), "Нет строки статуса острова: Live Activities отключены или не поддерживаются")

        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, !status.label.contains("Активен в Dynamic Island") {
            Thread.sleep(forTimeInterval: 1)
        }
        print("NETPULSE-CI: статус острова: \(status.label)")
        attachScreenshot("live-activity-status")
        XCTAssertTrue(status.label.contains("Активен в Dynamic Island"), "Live Activity не запустилась. Статус: «\(status.label)»")
    }

    @MainActor func testContinuousModeCanBeEnabled() throws {
        let app = launchApp()
        openSettings(app)

        let status = enableContinuousMode(app)
        attachScreenshot("continuous-mode-enabled")
        XCTAssertTrue(status.hasPrefix("Активен"), "Непрерывный режим не запустился. Статус: «\(status)»")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "Приложение закрылось после включения режима")
    }

    /// Контрольный прогон: что происходит со свёрнутым приложением и островом без «Непрерывного режима».
    @MainActor func testBackgroundWithoutContinuousMode() throws {
        let app = launchApp()
        openSettings(app)
        attachScreenshot("control-0-before-home")

        sampleBackground(app, prefix: "control-bg", pauses: [6, 20, 20])

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "Приложение не вернулось на передний план")
    }

    /// Основной прогон: свёрнутое приложение с включённым режимом. Снимки острова сохраняются для просмотра.
    @MainActor func testBackgroundWithContinuousMode() throws {
        let app = launchApp()
        openSettings(app)

        let status = enableContinuousMode(app)
        XCTAssertTrue(status.hasPrefix("Активен"), "Непрерывный режим не запустился. Статус: «\(status)»")
        attachScreenshot("continuous-bg-0-before-home")

        sampleBackground(app, prefix: "continuous-bg", pauses: [6, 20, 20, 20])

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "Приложение не вернулось на передний план: оно завершилось в фоне")
    }
}
