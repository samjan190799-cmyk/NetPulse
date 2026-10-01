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
        // Подсказка «остров замирал» может быть скрыта предыдущим запуском: сбрасываем её
        app.launchArguments += ["-netpulse_continuous_hint_dismissed", "NO"]
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
    /// Найденному элементу даётся «доехать»: после прокрутки список ещё движется по инерции, и нажатие по старым
    /// координатам попадает мимо (из-за этого переключатель иногда не включался).
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 15) -> Bool {
        func visibleAndSettled() -> Bool {
            guard element.exists, element.isHittable else { return false }
            Thread.sleep(forTimeInterval: 0.8)
            return element.exists && element.isHittable
        }
        if element.waitForExistence(timeout: 5), visibleAndSettled() { return true }
        for _ in 0..<maxSwipes {
            app.swipeUp()
            if visibleAndSettled() { return true }
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

    /// Открывает «Диагностику острова», возвращает текст сводки и закрывает экран
    @MainActor private func readIslandDiagnostics(_ app: XCUIApplication) -> String {
        let button = app.descendants(matching: .any)["islandDiagnosticsButton"]
        guard reveal(button, in: app) else {
            attachScreenshot("diagnostics-button-not-found")
            attachHierarchy(app, name: "diagnostics-button-not-found-hierarchy")
            return "(кнопка диагностики не найдена)"
        }
        button.tap()

        let summary = app.staticTexts["islandDiagnosticsSummary"]
        guard summary.waitForExistence(timeout: 10) else {
            attachScreenshot("diagnostics-summary-not-found")
            attachHierarchy(app, name: "diagnostics-summary-not-found-hierarchy")
            return "(сводка не появилась)"
        }
        Thread.sleep(forTimeInterval: 1.2)      // экран перечитывает состояние раз в секунду
        let text = summary.label
        attachScreenshot("island-diagnostics")
        let close = app.buttons["islandDiagnosticsClose"]
        if close.exists { close.tap() }
        return text
    }

    /// Достаёт из сводки число отправленных кадров («Отправлено кадров: N»)
    private func sentFrames(in summary: String) -> Int? {
        for line in summary.split(separator: "\n") where line.hasPrefix("Отправлено кадров:") {
            let number = line.replacingOccurrences(of: "Отправлено кадров:", with: "").trimmingCharacters(in: .whitespaces)
            return Int(number)
        }
        return nil
    }

    private func logDiagnostics(_ summary: String, label: String) {
        print("NETPULSE-CI: диагностика острова (\(label)): " + summary.replacingOccurrences(of: "\n", with: " | "))
    }

    /// Заголовок подсказки «остров замирал» на главном экране
    @MainActor private func continuousModeHintTitle(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["Остров замирал, пока приложение было свёрнуто"]
    }

    /// Включает «Непрерывный режим» и дожидается статуса «Активен…». Возвращает последний прочитанный статус.
    @discardableResult
    @MainActor private func enableContinuousMode(_ app: XCUIApplication) -> String {
        let toggle = app.switches["continuousModeToggle"]
        XCTAssertTrue(reveal(toggle, in: app), "Тумблер «Непрерывный режим» не найден на экране настроек")

        // Нажатие проверяется по значению переключателя и при необходимости повторяется
        var turnedOn = isOn(toggle)
        var attempt = 0
        while !turnedOn && attempt < 4 {
            attempt += 1
            flip(toggle)
            Thread.sleep(forTimeInterval: 1.5)
            dismissSystemAlerts(timeout: 4)       // запрос геолокации, если разрешение ещё не выдано
            _ = reveal(toggle, in: app)
            turnedOn = isOn(toggle)
            print("NETPULSE-CI: нажатие на тумблер непрерывного режима №\(attempt): включён = \(turnedOn)")
        }
        guard turnedOn else {
            attachScreenshot("continuous-toggle-not-on")
            attachHierarchy(app, name: "continuous-toggle-not-on-hierarchy")
            return "(тумблер не включился)"
        }
        dismissSystemAlerts()

        // После системного окна список настроек может оказаться прокрученным в другое место, поэтому строку
        // статуса ищем прокруткой, а не там, где она была.
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

        // Конвейер обновления: кадры должны реально уходить и подтверждаться системой
        Thread.sleep(forTimeInterval: 6)
        let summary = readIslandDiagnostics(app)
        logDiagnostics(summary, label: "после запуска")
        XCTAssertTrue(summary.contains("Остров: активна"), "Диагностика не видит активной Live Activity:\n\(summary)")
        XCTAssertGreaterThan(sentFrames(in: summary) ?? 0, 0, "Ни один кадр не отправлен:\n\(summary)")
        XCTAssertTrue(summary.contains("Зависших отправок: 0"), "Отправки зависали:\n\(summary)")
    }

    /// «Перезапустить» создаёт активность заново, и после этого остров продолжает обновляться
    @MainActor func testRestartButtonRecreatesIslandAndUpdatesContinue() throws {
        let app = launchApp()
        openSettings(app)

        let status = app.staticTexts["islandStatus"]
        XCTAssertTrue(reveal(status, in: app), "Нет строки статуса острова")
        let startDeadline = Date().addingTimeInterval(30)
        while Date() < startDeadline, !status.label.contains("Активен в Dynamic Island") {
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(status.label.contains("Активен в Dynamic Island"), "Остров не запустился. Статус: «\(status.label)»")

        Thread.sleep(forTimeInterval: 4)
        let before = readIslandDiagnostics(app)
        let sentBefore = sentFrames(in: before) ?? 0
        logDiagnostics(before, label: "до перезапуска")

        let restart = app.buttons["islandRestartButton"]
        XCTAssertTrue(reveal(restart, in: app), "Кнопка «Перезапустить» не найдена")
        restart.tap()
        Thread.sleep(forTimeInterval: 8)

        let after = readIslandDiagnostics(app)
        logDiagnostics(after, label: "после перезапуска")
        attachScreenshot("after-restart")
        XCTAssertTrue(after.contains("Остров: активна"), "После перезапуска остров не активен:\n\(after)")
        XCTAssertGreaterThan(sentFrames(in: after) ?? 0, 0, "После перезапуска кадры не уходят:\n\(after)")
        XCTAssertTrue(after.contains("Зависших отправок: 0"), "После перезапуска отправки зависали:\n\(after)")
        print("NETPULSE-CI: кадров до перезапуска: \(sentBefore), после: \(sentFrames(in: after) ?? -1)")
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

        // Пока приложение было свёрнуто дольше 40 секунд, а режим выключен, на главном экране появляется подсказка
        app.tabBars.buttons["Скорость"].tap()
        let hint = continuousModeHintTitle(app)
        let hintShown = hint.waitForExistence(timeout: 10)
        print("NETPULSE-CI: подсказка про непрерывный режим после долгого фона без режима: \(hintShown ? "показана" : "НЕ показана")")
        attachScreenshot("control-hint")
        XCTAssertTrue(hintShown, "После долгого фона без непрерывного режима подсказка не появилась")
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

        // С включённым режимом подсказки быть не должно
        app.tabBars.buttons["Скорость"].tap()
        let hintShown = continuousModeHintTitle(app).waitForExistence(timeout: 3)
        print("NETPULSE-CI: подсказка про непрерывный режим при включённом режиме: \(hintShown ? "ПОКАЗАНА (ошибка)" : "не показана")")
        XCTAssertFalse(hintShown, "При включённом непрерывном режиме подсказка показываться не должна")

        // Конвейер после фона: отправки не зависали, остров обновляется
        app.tabBars.buttons["Настройки"].tap()
        let summary = readIslandDiagnostics(app)
        logDiagnostics(summary, label: "после фона с режимом")
        XCTAssertTrue(summary.contains("Остров: активна"), "После фона остров не активен:\n\(summary)")
        XCTAssertTrue(summary.contains("Зависших отправок: 0"), "В фоне отправки зависали:\n\(summary)")
        XCTAssertTrue(summary.contains("работает"), "Диагностика не видит работающего непрерывного режима:\n\(summary)")
    }
}
