//
//  AppStoreScreenshotTests.swift
//  NetPulseUITests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest

/// Снимки экранов для карточки приложения в App Store Connect.
///
/// Запускается только workflow «App Store: скриншоты» на симуляторах нужного размера (iPhone 6.9″ и iPad 13″),
/// в обычных прогонах CI не участвует. Снимки настоящие: запись маршрута идёт по положению, которое меняет скрипт
/// workflow, а проверка сети и узлов — живые измерения; единственный экран с примерными данными — «пример
/// маршрута», и он подписан в самом приложении («Пример · демо-данные»). Реклама выключена.
///
/// Тест не падает, если какой-то экран не нашёлся: он печатает строку `NETPULSE-CI` и идёт дальше, чтобы остальные
/// снимки всё равно получились.
final class AppStoreScreenshotTests: XCTestCase {

    // MARK: - Помощники

    private func note(_ text: String) {
        print("NETPULSE-CI: скриншоты: \(text)")
    }

    /// Фиксирует снимок всего экрана в полном разрешении устройства под заданным именем
    @MainActor private func shoot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.6)      // анимации заканчиваются, карта дорисовывает плитки
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        note("снимок «\(name)»")
    }

    /// Закрывает системные окна (геолокация, уведомления), выбирая «Разрешить»
    @MainActor private func dismissSystemAlerts(timeout: TimeInterval = 6) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let preferred = [
            "Allow While Using App", "Allow Once", "Allow", "OK",
            "Разрешить при использовании приложения", "Разрешить"
        ]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 1.5) else { continue }
            var tapped = false
            for title in preferred {
                let button = alert.buttons[title]
                if button.exists {
                    note("системное окно «\(alert.label)»: «\(title)»")
                    button.tap()
                    tapped = true
                    break
                }
            }
            if !tapped {
                note("неизвестное системное окно «\(alert.label)»")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    /// Переходит на вкладку; на iPad панель вкладок может быть вверху и называться иначе, поэтому есть запасной поиск
    @MainActor @discardableResult
    private func openTab(_ app: XCUIApplication, _ title: String) -> Bool {
        let inBar = app.tabBars.buttons[title]
        if inBar.waitForExistence(timeout: 5) {
            inBar.tap()
            return true
        }
        let anyButton = app.buttons[title].firstMatch
        if anyButton.waitForExistence(timeout: 3) {
            anyButton.tap()
            return true
        }
        note("вкладка «\(title)» не найдена")
        return false
    }

    @MainActor private func waitForPoints(_ app: XCUIApplication, atLeast minimum: Int, timeout: TimeInterval) -> Int {
        func points() -> Int {
            let status = app.descendants(matching: .any)["networkMapStatus"]
            guard status.exists, status.label.hasPrefix("Точек:") else { return 0 }
            let digits = status.label.dropFirst("Точек:".count).prefix { $0 == " " || $0.isNumber }
            return Int(digits.trimmingCharacters(in: .whitespaces)) ?? 0
        }
        let deadline = Date().addingTimeInterval(timeout)
        var last = points()
        while Date() < deadline, last < minimum {
            Thread.sleep(forTimeInterval: 1)
            last = max(last, points())
        }
        return last
    }

    /// Ищет элемент, прокручивая экран вверх и вниз
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 10) -> Bool {
        func ready() -> Bool {
            guard element.exists, element.isHittable else { return false }
            Thread.sleep(forTimeInterval: 0.6)
            return element.exists && element.isHittable
        }
        if element.waitForExistence(timeout: 5), ready() { return true }
        for _ in 0..<maxSwipes {
            app.swipeUp()
            if ready() { return true }
        }
        for _ in 0..<(maxSwipes * 2) {
            app.swipeDown()
            if ready() { return true }
        }
        return false
    }

    @MainActor private func expandPanel(_ app: XCUIApplication) -> Bool {
        let row = app.buttons["homeRoutesRow"]
        guard row.waitForExistence(timeout: 10) else {
            note("нет ряда «Мои маршруты»")
            return false
        }
        row.tap()
        Thread.sleep(forTimeInterval: 1.2)
        return true
    }

    @MainActor private func collapsePanel(_ app: XCUIApplication) {
        let handle = app.descendants(matching: .any)["homePanelHandle"]
        if handle.waitForExistence(timeout: 5) {
            handle.tap()
            Thread.sleep(forTimeInterval: 1)
        }
    }

    // MARK: - Сценарий

    @MainActor func testCaptureStoreScreenshots() throws {
        continueAfterFailure = true

        let app = XCUIApplication()
        app.launchArguments += [
            "-netpulse_recording_hint_dismissed", "YES",   // подсказка про остров не должна закрывать карту
            "-netpulse_ads_disabled", "YES",               // в карточке магазина чужая реклама не нужна
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"
        ]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        dismissSystemAlerts()

        guard app.tabBars.firstMatch.waitForExistence(timeout: 30) || app.buttons["networkMapStartButton"].waitForExistence(timeout: 30) else {
            XCTFail("Приложение не запустилось")
            return
        }
        // Карта и панель успевают загрузиться, скорость и пинг прогреваются
        Thread.sleep(forTimeInterval: 10)

        // 1. Запись маршрута: разрешение геолокации выдаётся здесь, дальше экран главный с точкой «вы здесь»
        let start = app.buttons["networkMapStartButton"]
        if start.waitForExistence(timeout: 20) {
            start.tap()
            dismissSystemAlerts(timeout: 8)
            let status = app.descendants(matching: .any)["networkMapStatus"]
            if status.waitForExistence(timeout: 20) {
                let points = waitForPoints(app, atLeast: 8, timeout: 90)
                note("точек в записи: \(points)")
                Thread.sleep(forTimeInterval: 3)
                shoot("03-recording")

                let stop = app.buttons["networkMapStopButton"]
                if stop.waitForExistence(timeout: 10) {
                    stop.tap()
                    if app.descendants(matching: .any)["networkMapSummary"].waitForExistence(timeout: 15) {
                        Thread.sleep(forTimeInterval: 3)       // карта подстраивается под маршрут целиком
                        shoot("04-route-saved")
                    } else {
                        note("итог маршрута не появился")
                    }
                    let done = app.buttons["homeDoneButton"]
                    if done.waitForExistence(timeout: 5) { done.tap() }
                } else {
                    note("нет кнопки «Остановить и сохранить»")
                }
            } else {
                note("запись не началась")
            }
        } else {
            note("нет кнопки «Записать маршрут»")
        }

        // 2. Главный экран после записи: покрытие сети на карте, легенда, скорость
        _ = app.descendants(matching: .any)["homeCoverageLegend"].waitForExistence(timeout: 10)
        Thread.sleep(forTimeInterval: 4)
        shoot("01-home")

        // 3. Развёрнутая панель и пример маршрута со всеми цветами качества
        if expandPanel(app) {
            shoot("05-panel-expanded")
            let demo = app.buttons["networkMapDemoButton"]
            if reveal(demo, in: app) {
                let badge = app.descendants(matching: .any)["networkMapDemoBadge"]
                var shown = false
                // Первое нажатие бывает «пустым» (панель ещё доезжает после прокрутки): второй попытки хватает
                for attempt in 1...2 where !shown {
                    if attempt > 1, !(demo.waitForExistence(timeout: 3) && demo.isHittable) { break }
                    demo.tap()
                    shown = badge.waitForExistence(timeout: 10)
                    if !shown {
                        let hideShown = app.buttons["networkMapDemoHideButton"].exists
                        let summaryShown = app.descendants(matching: .any)["networkMapSummary"].exists
                        note("пример маршрута не показан (попытка \(attempt)): «Скрыть пример» \(hideShown), итог маршрута \(summaryShown)")
                    }
                }
                if shown {
                    Thread.sleep(forTimeInterval: 3)
                    shoot("02-route-demo")
                    let hide = app.buttons["networkMapDemoHideButton"]
                    if hide.waitForExistence(timeout: 5) { hide.tap() }
                }
            } else {
                note("нет кнопки «Показать пример маршрута»")
            }
            collapsePanel(app)
        }

        // 4. Остальные вкладки
        if openTab(app, "Узлы") {
            Thread.sleep(forTimeInterval: 12)         // карточки узлов набирают замеры, график рисуется
            shoot("06-hosts")
        }
        if openTab(app, "Трафик") {
            Thread.sleep(forTimeInterval: 4)
            shoot("07-traffic")
        }
        if openTab(app, "AI Диагност") {
            Thread.sleep(forTimeInterval: 4)
            shoot("08-ai")
        }

        // 5. Замер DNS из инструментов главного экрана
        if openTab(app, "Сеть"), expandPanel(app) {
            let dns = app.buttons["homeToolDNS"]
            if reveal(dns, in: app) {
                dns.tap()
                let run = app.buttons["Запустить замер DNS"]
                if run.waitForExistence(timeout: 10) {
                    run.tap()
                    let leader = app.staticTexts["Лидер:"]
                    if leader.waitForExistence(timeout: 60) {
                        Thread.sleep(forTimeInterval: 2)
                        shoot("09-dns")
                    } else {
                        note("замер DNS не завершился за 60 с")
                        shoot("09-dns-no-result")
                    }
                } else {
                    note("нет кнопки «Запустить замер DNS»")
                }
            } else {
                note("нет входа в замер DNS")
            }
        }

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "Приложение закрылось во время съёмки")
    }
}
