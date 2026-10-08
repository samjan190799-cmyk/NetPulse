//
//  NetPulseUITests.swift
//  NetPulseUITests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import XCTest

/// Проверка приложения в симуляторе: запуск, вкладки, главный экран с картой, настройки, Dynamic Island и запись маршрута.
///
/// Что симулятор доказать НЕ может: усыпление свёрнутого приложения на реальном iPhone он не воспроизводит,
/// поэтому «остров не замирает в фоне» окончательно проверяется только на устройстве. Здесь проверяется всё
/// остальное: приложение запускается и не падает, интерфейс на месте, Live Activity стартует, режим включается,
/// а скриншоты острова в фоне сохраняются во вложения результата и публикуются артефактами CI.
///
/// Строки с префиксом `NETPULSE-CI:` попадают в журнал и помогают разобрать прогон без скачивания артефактов.
final class NetPulseUITests: XCTestCase {

    // MARK: - Запуск и общие помощники

    /// `motion: false` выключает все анимации (заставка, «рисование» маршрута, бесконечное движение): снимки
    /// экрана должны быть одинаковыми, а бесконечные анимации не дают дождаться покоя приложения. `motion: true`
    /// оставляет разовые анимации (заставку, появление экранов), бесконечные по-прежнему выключены.
    /// `pro: true` (по умолчанию) запускает отладочную сборку с подпиской: остров, HUD и AI-аудит открыты. Тесты платного
    /// доступа запускают приложение с `pro: false`.
    @MainActor private func launchApp(motion: Bool = false, pro: Bool = true) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        if pro {
            app.launchArguments += ["-netpulse_pro", "YES"]
        }
        // Подсказка «остров замирал» может быть скрыта предыдущим запуском: сбрасываем её
        app.launchArguments += ["-netpulse_recording_hint_dismissed", "NO"]
        app.launchArguments += motion ? ["-netpulse_continuous_off", "YES"] : ["-netpulse_motion_off", "YES"]
        app.launch()
        dismissSystemAlerts()
        return app
    }

    /// Закрывает системные окна SpringBoard (геолокация, уведомления, Live Activities), предпочитая «Разрешить».
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

    /// Ждёт появления элемента и возвращает, сколько секунд на это ушло (`nil` — не дождался)
    @MainActor private func secondsUntilExists(_ element: XCUIElement, timeout: TimeInterval) -> TimeInterval? {
        let start = Date()
        let deadline = start.addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists {
                return Date().timeIntervalSince(start)
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return element.exists ? Date().timeIntervalSince(start) : nil
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

    /// Ждёт панель вкладок и главный экран с картой (кнопка «Записать маршрут»)
    @MainActor private func waitForHome(_ app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Панель вкладок не появилась: приложение не запустилось или упало")
        let start = app.buttons["networkMapStartButton"]
        if !start.waitForExistence(timeout: 20) {
            attachScreenshot("home-not-found")
            attachHierarchy(app, name: "home-not-found-hierarchy")
        }
        XCTAssertTrue(start.exists, "На главном экране нет кнопки «Записать маршрут»")
    }

    /// Открывает настройки кнопкой с ползунками на главном экране
    @MainActor private func openSettings(_ app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Панель вкладок не появилась: приложение не запустилось или упало")
        let button = app.buttons["homeSettingsButton"]
        if !button.waitForExistence(timeout: 20) {
            attachScreenshot("settings-button-not-found")
            attachHierarchy(app, name: "settings-button-not-found-hierarchy")
        }
        XCTAssertTrue(button.exists, "На главном экране нет кнопки «Настройки»")
        button.tap()
        let opened = app.navigationBars["Настройки"].waitForExistence(timeout: 10)
        if !opened {
            attachScreenshot("settings-not-opened")
            attachHierarchy(app, name: "settings-not-opened-hierarchy")
        }
        XCTAssertTrue(opened, "Экран «Настройки» не открылся")
    }

    /// Закрывает настройки кнопкой «Готово» и ждёт возвращения на главный экран
    @MainActor private func closeSettings(_ app: XCUIApplication) {
        let close = app.buttons["settingsCloseButton"]
        guard close.waitForExistence(timeout: 5) else {
            attachScreenshot("settings-close-not-found")
            XCTFail("В настройках нет кнопки «Готово»")
            return
        }
        close.tap()
        XCTAssertTrue(app.buttons["homeSettingsButton"].waitForExistence(timeout: 10), "После закрытия настроек главный экран не появился")
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

    /// Заголовок подсказки «остров замирал» над нижней панелью главного экрана
    @MainActor private func recordingHintTitle(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["iOS усыпила приложение, пока оно было свёрнуто"]
    }

    /// Разворачивает нижнюю панель главного экрана: нажатие на ряд «Мои маршруты»
    @MainActor private func expandPanel(_ app: XCUIApplication) {
        let row = app.buttons["homeRoutesRow"]
        guard row.waitForExistence(timeout: 10) else {
            attachScreenshot("routes-row-not-found")
            attachHierarchy(app, name: "routes-row-not-found-hierarchy")
            XCTFail("На главном экране нет ряда «Мои маршруты»")
            return
        }
        row.tap()
        Thread.sleep(forTimeInterval: 1)       // панель «доезжает» до развёрнутого положения
    }

    /// Число записанных точек из строки состояния записи («Точек: 12 · 450 м · …»); `nil` — строки нет
    @MainActor private func recordedPoints(_ app: XCUIApplication) -> Int? {
        let status = app.descendants(matching: .any)["networkMapStatus"]
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

    /// Начинает запись маршрута на главном экране: нажимает кнопку, отвечает на запрос геолокации
    /// и дожидается строки состояния записи. Возвращает `false`, если запись не началась.
    @discardableResult
    @MainActor private func startRecording(_ app: XCUIApplication) -> Bool {
        let start = app.buttons["networkMapStartButton"]
        guard start.waitForExistence(timeout: 10) else {
            attachScreenshot("recording-start-not-found")
            attachHierarchy(app, name: "recording-start-not-found-hierarchy")
            return false
        }
        start.tap()
        return waitForRecordingStatus(app)
    }

    /// Отвечает на запрос геолокации (если он есть) и ждёт строку состояния идущей записи
    @MainActor private func waitForRecordingStatus(_ app: XCUIApplication) -> Bool {
        dismissSystemAlerts(timeout: 8)       // запрос геолокации, если разрешение ещё не выдано

        let status = app.descendants(matching: .any)["networkMapStatus"]
        guard status.waitForExistence(timeout: 20) else {
            attachScreenshot("recording-status-not-found")
            attachHierarchy(app, name: "recording-status-not-found-hierarchy")
            return false
        }
        print("NETPULSE-CI: запись маршрута началась: \(status.label)")
        return true
    }

    /// Ждёт, пока элемент исчезнет с экрана
    @MainActor private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return !element.exists
    }

    /// Останавливает запись на главном экране
    @MainActor private func stopRecording(_ app: XCUIApplication) {
        let stop = app.buttons["networkMapStopButton"]
        guard stop.waitForExistence(timeout: 10) else {
            attachScreenshot("recording-stop-not-found")
            attachHierarchy(app, name: "recording-stop-not-found-hierarchy")
            XCTFail("Кнопка «Остановить и сохранить» не найдена")
            return
        }
        stop.tap()
    }

    /// Уходит на главный экран устройства и фиксирует состояние приложения и скриншот через заданные паузы.
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
        waitForHome(app)
        attachScreenshot("launch-home")

        // Главный экран: карта, плашка связи, кнопки справа и две главные кнопки в нижней панели
        for identifier in ["homeSettingsButton", "networkMapStyleButton", "homeCoverageButton", "networkMapRecenterButton", "homeSpeedButton", "homeRoutesRow"] {
            XCTAssertTrue(app.buttons[identifier].exists, "На главном экране нет элемента «\(identifier)»")
        }

        let tabs: [(title: String, slug: String)] = [
            ("Сеть", "map"), ("Инструменты", "hosts"), ("Трафик", "traffic")
        ]
        for tab in tabs {
            XCTAssertTrue(app.tabBars.buttons[tab.title].exists, "Нет вкладки «\(tab.title)»")
        }
        // Настройки больше не вкладка: они открываются кнопкой на главном экране
        XCTAssertFalse(app.tabBars.buttons["Настройки"].exists, "Вкладки «Настройки» быть не должно")

        for tab in tabs {
            app.tabBars.buttons[tab.title].tap()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "Приложение закрылось на вкладке «\(tab.title)»")
            attachScreenshot("tab-\(tab.slug)")
        }
    }

    @MainActor func testSettingsOpenFromHomeAndContainIslandControls() throws {
        let app = launchApp()
        openSettings(app)

        XCTAssertTrue(reveal(app.switches["dynamicIslandToggle"], in: app), "Тумблер Dynamic Island не найден")
        attachScreenshot("settings-island-controls")

        XCTAssertFalse(
            app.switches["continuousModeToggle"].exists,
            "Отдельного тумблера, который держит приложение геолокацией без записи маршрута, быть не должно"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["networkMapLink"].exists,
            "«Карта сети» теперь главный экран: отдельного входа в неё из настроек быть не должно"
        )

        scrollToTop(app)
        closeSettings(app)
        attachScreenshot("settings-closed")
    }

    /// В настройках есть раздел «Запись маршрута»: фоновая запись включена по умолчанию, её можно выключить и вернуть
    @MainActor func testRouteRecordingSettingsAreInSettings() throws {
        let app = launchApp()
        openSettings(app)

        let background = app.switches["routeBackgroundToggle"]
        XCTAssertTrue(reveal(background, in: app), "В настройках нет тумблера «Записывать маршрут в фоне»")
        XCTAssertEqual(background.value as? String, "1", "Фоновая запись по умолчанию включена")
        XCTAssertTrue(app.switches["routeAutoStopToggle"].exists, "В настройках нет тумблера автоостановки записи")
        attachScreenshot("settings-route-recording")

        // Переключатель справа в строке; настройка хранится на устройстве, поэтому в конце возвращаем как было
        let switchPoint = background.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
        switchPoint.tap()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(background.value as? String, "0", "Тумблер фоновой записи не выключился")
        attachScreenshot("settings-route-background-off")
        switchPoint.tap()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(background.value as? String, "1", "Тумблер фоновой записи не включился обратно")
        print("NETPULSE-CI: настройки записи маршрута: тумблеры на месте, фоновая запись переключается")

        scrollToTop(app)
        closeSettings(app)
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

    /// Нижнюю панель можно развернуть: в ней маршруты, настройки записи, инструменты и оценка возможностей сети.
    @MainActor func testHomePanelExpandsAndCollapses() throws {
        let app = launchApp()
        waitForHome(app)
        attachScreenshot("home-medium")

        let speed = app.descendants(matching: .any)["homeSpeedValue"]
        XCTAssertTrue(speed.waitForExistence(timeout: 10), "На главном экране нет блока со скоростью")

        expandPanel(app)
        attachScreenshot("home-expanded")
        XCTAssertTrue(
            reveal(app.descendants(matching: .any)["networkMapSpeedToggle"], in: app),
            "В развёрнутой панели нет переключателя «Замерять скорость на маршруте»"
        )
        XCTAssertTrue(
            reveal(app.descendants(matching: .any)["homeToolDNS"], in: app),
            "В развёрнутой панели нет входа в инструменты"
        )
        XCTAssertTrue(
            reveal(app.descendants(matching: .any)["networkMapHistoryEmpty"], in: app)
                || app.descendants(matching: .any)["networkMapHistoryRow"].exists,
            "В развёрнутой панели нет списка маршрутов"
        )
        attachScreenshot("home-expanded-tools")

        // Ручка сворачивает панель обратно
        let handle = app.descendants(matching: .any)["homePanelHandle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5), "У панели нет ручки")
        handle.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.buttons["homeSpeedButton"].isHittable, "После сворачивания панели кнопка замера недоступна")
        attachScreenshot("home-collapsed-again")
    }

    /// Запись маршрута: старт, точки с положением и проверкой сети, остановка, итог маршрута и маршрут в списке.
    /// Положение в симуляторе меняет скрипт CI (`simctl location`), поэтому точки должны прибавляться.
    @MainActor func testRecordingSavesRouteWithPoints() throws {
        let app = launchApp()
        waitForHome(app)

        XCTAssertTrue(startRecording(app), "Запись маршрута не началась")
        XCTAssertTrue(app.descendants(matching: .any)["recordingBanner"].waitForExistence(timeout: 10), "Нет плашки «Запись» над картой")
        let points = waitForPoints(app, atLeast: 3, timeout: 75)
        print("NETPULSE-CI: запись маршрута: набрано точек \(points)")
        attachScreenshot("route-recording")
        XCTAssertGreaterThanOrEqual(points, 3, "Запись не набрала три точки за 75 секунд: не работает геолокация или проверка сети")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "Приложение закрылось во время записи")

        stopRecording(app)

        // Сразу после остановки панель показывает итог сохранённого маршрута
        let summary = app.descendants(matching: .any)["networkMapSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15), "После остановки нет итога маршрута")
        print("NETPULSE-CI: сводка сохранённого маршрута: \(summary.label)")
        attachScreenshot("route-saved")
        XCTAssertTrue(summary.label.hasPrefix("Точек:"), "Странная сводка: «\(summary.label)»")

        // «Готово» возвращает обычный вид, а маршрут лежит в списке
        let done = app.buttons["homeDoneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "В итоге маршрута нет кнопки «Готово»")
        done.tap()
        XCTAssertTrue(app.buttons["homeSpeedButton"].waitForExistence(timeout: 10), "После «Готово» не вернулся обычный вид")

        // Линии маршрутов: в обычном режиме над панелью легенда цветов, а кнопка справа прячет и возвращает
        // линии прежних маршрутов (зон и полос на карте нет)
        let legend = app.descendants(matching: .any)["homeCoverageLegend"]
        XCTAssertTrue(legend.waitForExistence(timeout: 10), "После записи маршрута нет легенды цветов линий")
        Thread.sleep(forTimeInterval: 2)       // карта дорисовывает линии
        attachScreenshot("lines-idle")
        let coverage = app.buttons["homeCoverageButton"]
        XCTAssertTrue(coverage.waitForExistence(timeout: 5), "На карте нет кнопки «Прежние маршруты»")
        XCTAssertEqual(coverage.value as? String, "Показаны", "Линии прежних маршрутов по умолчанию должны быть включены")
        coverage.tap()
        XCTAssertTrue(waitUntilGone(legend, timeout: 5), "Легенда осталась после выключения линий")
        XCTAssertEqual(coverage.value as? String, "Скрыты")
        Thread.sleep(forTimeInterval: 2)
        attachScreenshot("lines-off")
        coverage.tap()
        XCTAssertTrue(legend.waitForExistence(timeout: 5), "Легенда не вернулась после включения линий")
        XCTAssertEqual(coverage.value as? String, "Показаны")
        print("NETPULSE-CI: линии маршрутов: легенда и кнопка работают")

        expandPanel(app)
        let row = app.descendants(matching: .any).matching(identifier: "networkMapHistoryRow").firstMatch
        XCTAssertTrue(reveal(row, in: app), "Маршрут не появился в списке «Мои маршруты»")
        attachScreenshot("route-in-list")
    }

    /// Пока записей нет, в развёрнутой панели есть пример: так видно, что покажет функция, даже если ещё не двигались
    @MainActor func testDemoRouteShowsMapAndSummary() throws {
        let app = launchApp()
        waitForHome(app)

        // Карта Apple Maps видна и до первой записи (раньше вместо неё была заглушка)
        let mapVisible = app.maps.firstMatch.waitForExistence(timeout: 10)
            || app.descendants(matching: .any)["networkMapMap"].waitForExistence(timeout: 2)
        print("NETPULSE-CI: карта на экране до записи: \(mapVisible ? "есть" : "НЕТ")")
        attachScreenshot("map-idle")

        expandPanel(app)
        let demo = app.buttons["networkMapDemoButton"]
        XCTAssertTrue(reveal(demo, in: app), "Нет кнопки «Показать пример маршрута»")
        demo.tap()

        let badge = app.descendants(matching: .any)["networkMapDemoBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10), "Пример не показан или не подписан как демо-данные")
        let summary = app.descendants(matching: .any)["networkMapSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "Нет итога по примеру")
        print("NETPULSE-CI: сводка примера: \(summary.label)")
        XCTAssertTrue(summary.label.hasPrefix("Точек: 72"), "Сводка примера: «\(summary.label)»")
        attachScreenshot("map-demo")

        // Переключатель «Схема / Спутник» на карте
        let styleButton = app.buttons["networkMapStyleButton"]
        XCTAssertTrue(styleButton.waitForExistence(timeout: 5), "На карте нет кнопки «Спутник»")
        styleButton.tap()
        Thread.sleep(forTimeInterval: 3)
        attachScreenshot("map-demo-satellite")

        // «Скрыть пример» возвращает обычный вид
        let hide = app.buttons["networkMapDemoHideButton"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "Нет кнопки «Скрыть пример»")
        hide.tap()
        XCTAssertTrue(app.buttons["homeSpeedButton"].waitForExistence(timeout: 10), "После скрытия примера не вернулся обычный вид")
        attachScreenshot("map-demo-hidden")
    }

    /// Контрольный прогон: свёрнутое приложение без записи маршрута. После возврата над нижней панелью появляется
    /// подсказка, и её кнопка начинает запись маршрута.
    @MainActor func testBackgroundWithoutRecordingShowsHintThatStartsRecording() throws {
        let app = launchApp()
        waitForHome(app)
        attachScreenshot("control-0-before-home")

        sampleBackground(app, prefix: "control-bg", pauses: [6, 20, 20])

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "Приложение не вернулось на передний план")

        // Пока приложение было свёрнуто дольше 40 секунд, а запись не шла, на главном экране появляется подсказка
        let hint = recordingHintTitle(app)
        let hintShown = hint.waitForExistence(timeout: 10)
        print("NETPULSE-CI: подсказка после долгого фона без записи маршрута: \(hintShown ? "показана" : "НЕ показана")")
        attachScreenshot("control-hint")
        XCTAssertTrue(hintShown, "После долгого фона без записи маршрута подсказка не появилась")

        let start = app.buttons["recordingHintStart"]
        XCTAssertTrue(start.waitForExistence(timeout: 3), "В подсказке нет кнопки «Записать маршрут»")
        start.tap()
        XCTAssertTrue(waitForRecordingStatus(app), "Кнопка из подсказки не начала запись маршрута")
        attachScreenshot("control-hint-started-recording")

        // Уборка: останавливаем запись, чтобы она не мешала следующим тестам
        stopRecording(app)
    }

    /// Основной прогон: запись маршрута идёт, пока приложение свёрнуто. Точки продолжают прибавляться, подсказки нет,
    /// на главном экране видна плашка записи, а остров не зависал.
    @MainActor func testRecordingContinuesInBackground() throws {
        let app = launchApp()
        waitForHome(app)

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
        let banner = app.descendants(matching: .any)["recordingBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "На главном экране нет плашки «Запись»")
        let hintShown = recordingHintTitle(app).waitForExistence(timeout: 3)
        print("NETPULSE-CI: подсказка во время записи маршрута: \(hintShown ? "ПОКАЗАНА (ошибка)" : "не показана")")
        XCTAssertFalse(hintShown, "Во время записи маршрута подсказка показываться не должна")
        attachScreenshot("recording-dashboard-banner")

        // Конвейер острова после фона: отправки не зависали, запись видна в диагностике
        openSettings(app)
        let summary = readIslandDiagnostics(app)
        logDiagnostics(summary, label: "после фона с записью маршрута")
        XCTAssertTrue(summary.contains("Остров: активна"), "После фона остров не активен:\n\(summary)")
        XCTAssertTrue(summary.contains("Зависших отправок: 0"), "В фоне отправки зависали:\n\(summary)")
        XCTAssertTrue(summary.contains("Запись маршрута: идёт"), "Диагностика не видит идущей записи:\n\(summary)")
        scrollToTop(app)
        closeSettings(app)

        // Уборка: останавливаем запись, чтобы она не мешала следующим тестам
        stopRecording(app)
    }

    /// Анимации включены (заставка, появление экранов, «рисование» маршрута): приложение запускается, главный
    /// экран доступен, вкладки переключаются и главный экран остаётся рабочим
    @MainActor func testMotionDoesNotBreakNavigation() throws {
        let app = launchApp(motion: true)
        waitForHome(app)
        XCTAssertTrue(app.buttons["homeSpeedButton"].waitForExistence(timeout: 20), "Нет кнопки замера скорости")

        for title in ["Инструменты", "Трафик", "Сеть"] {
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "Приложение закрылось на вкладке «\(title)»")
        }

        XCTAssertTrue(app.buttons["homeSpeedButton"].waitForExistence(timeout: 10), "После вкладок нет кнопки замера")
        XCTAssertTrue(app.buttons["homeSpeedButton"].isHittable, "Из-за анимаций кнопка замера скорости недоступна")
        XCTAssertTrue(app.buttons["networkMapStartButton"].isHittable, "Из-за анимаций кнопка записи недоступна")
        attachScreenshot("motion-home")
    }

    // MARK: - Подписка PRO

    /// Без подписки остров закрыт: кнопка острова на главном экране открывает окно подписки с ценой, условиями и кнопкой
    /// «Восстановить покупки» (правило App Store 3.1.2)
    @MainActor func testFreeUserSeesPaywallInsteadOfIsland() throws {
        let app = launchApp(pro: false)
        waitForHome(app)

        let island = app.buttons["homeIslandButton"]
        XCTAssertTrue(island.waitForExistence(timeout: 15), "На главном экране нет кнопки острова")
        island.tap()

        let paywall = app.descendants(matching: .any)["paywallView"]
        XCTAssertTrue(paywall.waitForExistence(timeout: 10), "Окно подписки не открылось")
        XCTAssertTrue(app.buttons["paywallSubscribeButton"].exists, "В окне подписки нет кнопки «Подписаться»")
        XCTAssertTrue(app.buttons["paywallRestoreButton"].exists, "В окне подписки нет «Восстановить покупки»")
        XCTAssertTrue(app.descendants(matching: .any)["paywallLegal"].exists, "В окне подписки нет условий автопродления")
        attachScreenshot("paywall")

        app.buttons["paywallCloseButton"].tap()
        XCTAssertTrue(app.buttons["homeSpeedButton"].waitForExistence(timeout: 10), "После закрытия окна нет главного экрана")
    }

    /// Без подписки AI-аудит в «Инструментах» закрыт: плитка открывает окно подписки
    @MainActor func testFreeUserSeesPaywallFromAIAudit() throws {
        let app = launchApp(pro: false)
        waitForHome(app)

        app.tabBars.buttons["Инструменты"].tap()
        let tile = app.buttons["toolsAIAuditButton"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15), "В «Инструментах» нет плитки AI-аудита")
        tile.tap()
        XCTAssertTrue(app.descendants(matching: .any)["paywallView"].waitForExistence(timeout: 10), "Плитка не открыла окно подписки")
        attachScreenshot("ai-paywall")
    }

    /// С подпиской плитка открывает сам AI-аудит
    @MainActor func testSubscriberOpensAIAudit() throws {
        let app = launchApp()
        waitForHome(app)

        app.tabBars.buttons["Инструменты"].tap()
        let tile = app.buttons["toolsAIAuditButton"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15), "В «Инструментах» нет плитки AI-аудита")
        tile.tap()
        XCTAssertTrue(app.navigationBars["AI-аудит"].waitForExistence(timeout: 10), "AI-аудит не открылся")
        XCTAssertFalse(app.descendants(matching: .any)["paywallView"].exists, "У подписчика открылось окно подписки")
        app.buttons["aiAuditCloseButton"].tap()
    }
}
