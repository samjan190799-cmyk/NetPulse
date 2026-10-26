//
//  IslandRefreshIntent.swift
//  NetPulse
//
//  Кнопка «Обновить» на острове и на экране блокировки. Файл входит и в приложение, и в расширение виджетов:
//  расширению нужен тип кнопки, чтобы нарисовать её, а выполняет кнопку система в процессе приложения
//  (так устроен LiveActivityIntent). Поэтому здесь нет ничего, что недоступно в расширении (например, UIApplication).
//

import AppIntents
import Foundation

/// Просьба обновить остров: свежий замер пинга и скорости, затем новый кадр в Live Activity.
struct RefreshIslandIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Обновить остров"
    static let description = IntentDescription("Делает свежий замер и обновляет остров NetPulse.")

    init() {}

    func perform() async throws -> some IntentResult {
        await IslandRefreshBridge.run()
        return .result()
    }
}

/// Связка между кнопкой и приложением. Приложение при запуске ставит обработчик; кнопка вызывает его.
/// Если обработчика нет (например, команда пришла раньше, чем приложение закончило запуск в фоне),
/// кнопка немного ждёт, а потом тихо ничего не делает: остров просто не обновится.
enum IslandRefreshBridge {
    typealias Handler = @Sendable () async -> Void

    /// Сколько секунд кнопка ждёт обработчик при холодном запуске приложения в фоне
    static let installWaitSeconds: TimeInterval = 3

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: Handler?

        func set(_ value: Handler?) {
            lock.lock()
            handler = value
            lock.unlock()
        }

        func get() -> Handler? {
            lock.lock()
            defer { lock.unlock() }
            return handler
        }
    }

    private static let box = Box()

    static func install(_ handler: @escaping Handler) {
        box.set(handler)
    }

    /// Убирает обработчик (нужно тестам)
    static func uninstall() {
        box.set(nil)
    }

    /// Вызывает обработчик приложения. Возвращает `true`, если обработчик был и отработал.
    @discardableResult
    static func run(waitSeconds: TimeInterval = IslandRefreshBridge.installWaitSeconds) async -> Bool {
        var waited: TimeInterval = 0
        while box.get() == nil, waited < waitSeconds {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 0.1
        }
        guard let handler = box.get() else { return false }
        await handler()
        return true
    }
}
