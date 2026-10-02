//
//  NetPulseUITests.swift
//  NetPulseUITests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest

/// Проверка приложения в симуляторе: запуск, вкладки, экран настроек, Dynamic Island и «Карта сети» (запись маршрута).
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
        // Подсказка «остров замирал» может быть скрыта предыдущим запуском: сбрасываем её
        app.launchArguments += ["-netpulse_recording_hint_dismissed", "NO"]
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
    /// Сначала ищет ниже по списку, затем возвращается выше: после чтения диагностики список остаётся прокрученным
    /// до её кнопки, и нужная строка (например, «Перезапустить») оказывается над экраном.
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
        for _ in 0..<(maxSwipes * 2) {
            app.swipeDown()
            if visibleAndSettled() { return true }
        }
        return false
    }

    /// Возвращает список в начало: после чтения диагностики он остаётся там, где была её кнопка
    @MainActor private func scrollToTop(_ app: XCUIApplication, swipes: Int = 6) {
        for _ in 0..<swipes { app.swipeDown() }
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

        // Дожидаемся закрытия экрана и возвращаем список настроек в начало: следующий поиск элементов начнётся оттуда
        let closeDeadline = Date().addingTimeInterval(5)
        while summary.exists, Date() < closeDeadline { Thread.sleep(forTimeInterval: 0.3) }
        Thread.sleep(forTimeInterval: 0.5)
        scrollToTop(app)
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
    @MainActor private func recordingHintTitle(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["Остров замирал, пока приложение было свёрнуто"]
    }

    /// Открывает «Карту сети» из настроек
    @MainActor private func openNetworkMap(_ app: XCUIApplication) {
        let link = app.descendants(matching: .any)["networkMapLink"]
        guard reveal(link, in: app) else {
            attachScreenshot("network-map-link-not-found")
            attachHierarchy(app, name: "network-map-link-not-found-hierarchy")
            XCTFail("В настройках нет входа в «Карту сети»")
            return
        }
        link.tap()
        let opened = app.navigationBars["Карта сети"].waitForExistence(timeout: 10)
        if !opened {
            attachScreenshot("network-map-not-opened")
            attachHierarchy(app, name: "network-map-not-opened-hierarchy")
        }
        XCTAssertTrue(opened, "Экран «Карта сети» не открылся")
    }

    /// Число записанных точек из строки состояния записи («Точек: 12 · 450 м · …»); `nil` — строки нет
    @MainActor private func recordedPoints(_ app: XCUIApplication) -> Int? {
        let status = app.staticTexts["networkMapStatus"]
        guard status.exists else { return nil }
        let label = status.label
        guard label.hasPrefix("Точек:") else { return nil }
        let digits = label.dropFirst("Точек:".count).prefix { $0 == " " || $0.isNumber }
        return Int(digits.trimmingCharacters(in: .whitespaces))
    }

    /// Ждёт, пока в записи наберётся не меньше `minimum` точек; возвращает последнее прочитанное число
    @MainActor private func waitForPoints(_ app: XCUIApplication, atLeast minimum: Int, timeout: TimeInterval) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var last = recordedPoints(app) ?? 0
        while Date() < deadline, last < minimum {
            Thread.sleep(forTimeInterval: 1)
            last = recordedPoints(app) ?? last
        }
        return last
    }

    /// Начинает запись маршрута на открытом экране «Карта сети»: нажимает кнопку, отвечает на запрос геолокации
    /// и дожидается строки состояния записи. Возвращает `false`, если запись не началась.
    @discardableResult
    @MainActor private func startRecording(_ app: XCUIApplication) -> Bool {
        let start = app.buttons["networkMapStartButton"]
        guard reveal(start, in: app) else {
            attachScreenshot("recording-start-not-found")
            attachHierarchy(app, name: "recording-start-not-found-hierarchy")
            return false
        }
        start.tap()
        dismissSystemAlerts(timeout: 8)       // запрос геолокации, если разрешение ещё не выдано

        let status = app.staticTexts["networkMapStatus"]
        guard status.waitForExistence(timeout: 20) else {
            attachScreenshot("recording-status-not-found")
            attachHierarchy(app, name: "recording-status-not-found-hierarchy")
            return false
        }
        print("NETPULSE-CI: запись маршрута началась: \(status.label)")
        return true
    }

    /// Останавливает запись на открытом экране «Карта сети»
    @MainActor private func stopRecording(_ app: XCUIApplication) {
        let stop = app.buttons["networkMapStopButton"]
        guard reveal(stop, in: app) else {
            attachScreenshot("recording-stop-not-found")
            attachHierarchy(app, name: "recording-stop-not-found-hierarchy")
            XCTFail("Кнопка «Остановить и сохранить» не найдена")
            return
        }
        stop.tap()
    }

    /// Возвращается с экрана «Карта сети» на предыдущий
    @MainActor private func goBack(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
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

    @MainActor func testSettingsContainIslandAndNetworkMapEntry() throws {
        let app = launchApp()
        openSettings(app)

        XCTAssertTrue(reveal(app.switches["dynamicIslandToggle"], in: app), "Тумблер Dynamic Island не найден")
        XCTAssertTrue(reveal(app.descendants(matching: .any)["networkMapLink"], in: app), "В настройках нет входа в «Карту сети»")
        attachScreenshot("settings-island-controls")

        XCTAssertFalse(
            app.switches["continuousModeToggle"].exists,
            "Отдельного тумблера, который держит приложение геолокацией без записи маршрута, быть не должно"
        )
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
        let sentAfter = sentFrames(in: after) ?? -1
        print("NETPULSE-CI: кадров до перезапуска: \(sentBefore), после: \(sentAfter)")
        XCTAssertTrue(after.contains("Остров: активна"), "После перезапуска остров не активен:\n\(after)")
        // Счётчик не обнуляется при перезапуске: рост значит, что новая активность действительно получает кадры
        XCTAssertGreaterThan(sentAfter, sentBefore, "После перезапуска кадры не уходят:\n\(after)")
        XCTAssertTrue(after.contains("Зависших отправок: 0"), "После перезапуска отправки зависали:\n\(after)")
    }

    /// Запись маршрута: старт, точки с положением и проверкой сети, остановка, маршрут в истории. Положение в симуляторе
    /// меняет скрипт CI (`simctl location`), поэтому точки должны прибавляться.
    @MainActor func testRecordingSavesRouteWithPoints() throws {
        let app = launchApp()
        openSettings(app)
        openNetworkMap(app)

        XCTAssertTrue(startRecording(app), "Запись маршрута не началась")
        let points = waitForPoints(app, atLeast: 3, timeout: 75)
        print("NETPULSE-CI: запись маршрута: набрано точек \(points)")
        attachScreenshot("route-recording")
        XCTAssertGreaterThanOrEqual(points, 3, "Запись не набрала три точки за 75 секунд: не работает геолокация или проверка сети")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "Приложение закрылось во время записи")

        stopRecording(app)

        let row = app.descendants(matching: .any).matching(identifier: "networkMapHistoryRow").firstMatch
        XCTAssertTrue(reveal(row, in: app), "После остановки маршрут не появился в истории")
        let summary = app.staticTexts["networkMapSummary"]
        XCTAssertTrue(reveal(summary, in: app), "Нет сводки по сохранённому маршруту")
        print("NETPULSE-CI: сводка сохранённого маршрута: \(summary.label)")
        attachScreenshot("route-saved")
        XCTAssertTrue(summary.label.hasPrefix("Точек:"), "Странная сводка: «\(summary.label)»")
    }

    /// Пока записи нет, на экране «Карта сети» есть пример: так видно, что покажет функция, даже если ещё не двигались
    @MainActor func testDemoRouteShowsMapAndSummary() throws {
        let app = launchApp()
        openSettings(app)
        openNetworkMap(app)

        let demo = app.buttons["networkMapDemoButton"]
        XCTAssertTrue(reveal(demo, in: app), "Нет кнопки «Показать пример»")
        demo.tap()

        let badge = app.descendants(matching: .any)["networkMapDemoBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10), "Пример не показан или не подписан как демо-данные")
        let summary = app.staticTexts["networkMapSummary"]
        XCTAssertTrue(reveal(summary, in: app), "Нет сводки по примеру")
        print("NETPULSE-CI: сводка примера: \(summary.label)")
        XCTAssertTrue(summary.label.hasPrefix("Точек: 72"), "Сводка примера: «\(summary.label)»")
        attachScreenshot("map-demo")
    }

    /// Контрольный прогон: свёрнутое приложение без записи маршрута. После возврата на главном экране появляется
    /// подсказка, и она ведёт на «Карту сети».
    @MainActor func testBackgroundWithoutRecordingShowsHintThatOpensMap() throws {
        let app = launchApp()
        openSettings(app)
        attachScreenshot("control-0-before-home")

        sampleBackground(app, prefix: "control-bg", pauses: [6, 20, 20])

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "Приложение не вернулось на передний план")

        // Пока приложение было свёрнуто дольше 40 секунд, а запись не шла, на главном экране появляется подсказка
        app.tabBars.buttons["Скорость"].tap()
        let hint = recordingHintTitle(app)
        let hintShown = hint.waitForExistence(timeout: 10)
        print("NETPULSE-CI: подсказка после долгого фона без записи маршрута: \(hintShown ? "показана" : "НЕ показана")")
        attachScreenshot("control-hint")
        XCTAssertTrue(hintShown, "После долгого фона без записи маршрута подсказка не появилась")

        let open = app.buttons["recordingHintOpenMap"]
        XCTAssertTrue(open.waitForExistence(timeout: 3), "В подсказке нет кнопки «Открыть карту сети»")
        open.tap()
        XCTAssertTrue(
            app.buttons["networkMapStartButton"].waitForExistence(timeout: 10),
            "Кнопка из подсказки не открыла «Карту сети»"
        )
        attachScreenshot("control-hint-opened-map")
    }

    /// Основной прогон: запись маршрута идёт, пока приложение свёрнуто. Точки продолжают прибавляться, подсказки нет,
    /// на главном экране видна плашка записи, а остров не зависал.
    @MainActor func testRecordingContinuesInBackground() throws {
        let app = launchApp()
        openSettings(app)
        openNetworkMap(app)

        XCTAssertTrue(startRecording(app), "Запись маршрута не началась")
        let before = waitForPoints(app, atLeast: 2, timeout: 60)
        XCTAssertGreaterThanOrEqual(before, 2, "До сворачивания запись не набрала точки")
        attachScreenshot("recording-bg-0-before-home")

        sampleBackground(app, prefix: "recording-bg", pauses: [6, 20, 20, 20])

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "Приложение не вернулось на передний план: оно завершилось в фоне")

        // Запись не прервалась: за время в фоне точек стало больше
        let after = waitForPoints(app, atLeast: before + 1, timeout: 30)
        print("NETPULSE-CI: точек до сворачивания: \(before), после возврата: \(after)")
        attachScreenshot("recording-bg-after")
        XCTAssertGreaterThan(after, before, "Запись маршрута не продолжалась в фоне")

        // На главном экране: плашка записи есть, подсказки «остров замирал» нет
        goBack(app)
        app.tabBars.buttons["Скорость"].tap()
        let banner = app.descendants(matching: .any)["recordingBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "На главном экране нет плашки «Идёт запись маршрута»")
        let hintShown = recordingHintTitle(app).waitForExistence(timeout: 3)
        print("NETPULSE-CI: подсказка во время записи маршрута: \(hintShown ? "ПОКАЗАНА (ошибка)" : "не показана")")
        XCTAssertFalse(hintShown, "Во время записи маршрута подсказка показываться не должна")
        attachScreenshot("recording-dashboard-banner")

        // Конвейер острова после фона: отправки не зависали, запись видна в диагностике
        app.tabBars.buttons["Настройки"].tap()
        let summary = readIslandDiagnostics(app)
        logDiagnostics(summary, label: "после фона с записью маршрута")
        XCTAssertTrue(summary.contains("Остров: активна"), "После фона остров не активен:\n\(summary)")
        XCTAssertTrue(summary.contains("Зависших отправок: 0"), "В фоне отправки зависали:\n\(summary)")
        XCTAssertTrue(summary.contains("Запись маршрута: идёт"), "Диагностика не видит идущей записи:\n\(summary)")

        // Уборка: останавливаем запись, чтобы она не мешала следующим тестам
        openNetworkMap(app)
        stopRecording(app)
    }
}
