//
//  ContinuousModeManager.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
@preconcurrency import CoreLocation

/// «Непрерывный режим»: приложение остаётся активным в фоне, поэтому Dynamic Island продолжает показывать
/// реальную скорость, а не замирает примерно через 30 секунд после сворачивания.
///
/// Зачем нужна геолокация. iOS усыпляет свёрнутое приложение, а обновить Live Activity может только его код:
/// скорость устройства знает лишь сам телефон, поэтому серверные push-обновления здесь не помогут.
/// Приложение с активными фоновыми обновлениями геолокации не усыпляется. Координаты приложение не читает,
/// не сохраняет и никуда не отправляет.
///
/// Два уровня удержания:
/// - «Надёжный» (по умолчанию): геолокация на полной точности с GPS. iOS считает такое приложение навигационным
///   и не усыпляет его. Расход батареи заметно выше.
/// - «Экономный»: приблизительное положение (порядка километров) без GPS. Расход меньше, но iOS может усыпить
///   приложение, и тогда остров снова замрёт. Первая версия режима работала только так и замирала у пользователя.
///
/// Что нужно знать:
/// - в строке состояния iOS показывает значок использования геолокации;
/// - правило App Store 2.5.4 разрешает фоновую геолокацию для функций, которым нужно местоположение,
///   поэтому режим выключен по умолчанию и включается только самим пользователем с понятным объяснением;
/// - если пользователь закрыл приложение смахиванием, оно не запустится само: режим вернётся при следующем открытии;
/// - если в запросе геолокации выбрать «Один раз», iOS отключит доступ вскоре после сворачивания — нужно «При использовании»;
/// - Live Activity живёт не дольше 8 часов, потом iOS её завершает, а новую можно запустить только из открытого приложения.
@MainActor
public final class ContinuousModeManager: NSObject, @preconcurrency CLLocationManagerDelegate {
    public static let shared = ContinuousModeManager()

    /// Режим входит в PRO. Пока `false`, включить его может любой пользователь: продукт PRO ещё не создан
    /// в App Store Connect, и функцию иначе нельзя проверить. Значение `true` включает проверку PRO в настройках
    /// (тумблер открывает экран покупки так же, как плавающий HUD).
    public static let requiresPro = false

    private static let levelKey = "netpulse_continuous_mode_level"

    /// Насколько настойчиво приложение удерживается в фоне
    public enum Level: String, CaseIterable, Identifiable, Sendable {
        /// Полная точность (GPS): iOS не усыпляет такое приложение
        case reliable
        /// Приблизительное положение без GPS: расход меньше, но удержание не гарантировано
        case economy

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .reliable: return "Надёжный (GPS)"
            case .economy: return "Экономный"
            }
        }

        public var explanation: String {
            switch self {
            case .reliable:
                return "Включается GPS: iOS не усыпляет приложение, остров обновляется всегда. Батарея расходуется заметно быстрее."
            case .economy:
                return "Без GPS, батарея расходуется меньше, но iOS может усыпить приложение, и остров снова замрёт."
            }
        }
    }

    public enum State: Equatable, Sendable {
        /// Режим выключен
        case off
        /// Ждём ответа пользователя на запрос геолокации
        case waitingForPermission
        /// Приложение удерживается активным в фоне
        case running
        /// Пользователь запретил геолокацию (или службы геолокации выключены в системе)
        case denied
        /// Геолокация ограничена на устройстве (например, родительским контролем)
        case restricted
        /// В приложении не включён фоновый режим геолокации (ошибка сборки)
        case unavailable

        /// Подпись состояния для экрана настроек
        public var statusText: String {
            switch self {
            case .off:
                return ""
            case .waitingForPermission:
                return "Ожидается ответ на запрос геолокации. Выберите «При использовании приложения»: вариант «Один раз» iOS отключает вскоре после сворачивания."
            case .running:
                return "Активен: остров обновляется и в фоне. В строке состояния виден значок геолокации."
            case .denied:
                return "Нет доступа к геолокации. Разрешите «При использовании приложения» в Настройках iOS."
            case .restricted:
                return "Геолокация ограничена на этом устройстве (например, родительским контролем)."
            case .unavailable:
                return "Режим недоступен: в этой сборке не включён фоновый режим геолокации."
            }
        }

        /// Короткое название для журнала и сводки
        public var logLabel: String {
            switch self {
            case .off: return "выключен"
            case .waitingForPermission: return "ждёт разрешения на геолокацию"
            case .running: return "работает"
            case .denied: return "нет доступа к геолокации"
            case .restricted: return "геолокация ограничена на устройстве"
            case .unavailable: return "недоступен: в сборке нет фонового режима location"
            }
        }

        /// Требует действий пользователя или исправления сборки
        public var needsAttention: Bool {
            switch self {
            case .denied, .restricted, .unavailable:
                return true
            case .off, .waitingForPermission, .running:
                return false
            }
        }
    }

    /// Текущее состояние (для интерфейса)
    public private(set) var state: State = .off {
        didSet {
            guard state != oldValue else { return }
            IslandDiagnostics.shared.log("Непрерывный режим: \(state.logLabel)", .location)
            onStateChange?(state)
        }
    }

    /// Вызывается при смене состояния: ViewModel зеркалит его в наблюдаемое свойство
    public var onStateChange: (@MainActor (State) -> Void)?

    /// Выбранный уровень удержания
    public private(set) var level: Level

    /// С какого момента режим работает без перерыва (`nil` — не работает)
    public private(set) var runningSince: Date?

    /// Сколько раз приложение приостанавливали в фоне, пока режим работал (с запуска приложения)
    public private(set) var pausesWhileRunning = 0

    private let manager = CLLocationManager()
    private let defaults = UserDefaults.standard
    private var wantsActive = false
    private var isUpdating = false
    private var lastArmedAt = Date.distantPast

    private override init() {
        let stored = UserDefaults.standard.string(forKey: ContinuousModeManager.levelKey)
        self.level = stored.flatMap { Level(rawValue: $0) } ?? .reliable
        super.init()
        manager.delegate = self
    }

    /// Сводка для журнала и экрана диагностики
    public var summaryDescription: String {
        state == .running ? "работает — \(level.title)" : state.logLabel
    }

    /// Обстоятельства для записи о паузе в журнале
    public func diagnosticContext() -> String {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled ? "вкл" : "выкл"
        return "Непрерывный режим: \(summaryDescription); энергосбережение: \(lowPower)."
    }

    /// Выбирает уровень удержания; если режим работает, настройки геолокации применяются сразу
    public func setLevel(_ newLevel: Level) {
        guard newLevel != level else { return }
        level = newLevel
        defaults.set(newLevel.rawValue, forKey: Self.levelKey)
        IslandDiagnostics.shared.log("Непрерывный режим: выбран уровень «\(newLevel.title)»", .location)
        if isUpdating {
            startUpdates(forceRearm: true)
        }
    }

    /// Включает или выключает удержание в фоне. Это желаемое состояние: фактическое зависит от разрешения
    /// на геолокацию и отражено в `state`. Вызывать нужно при открытом приложении: запрос разрешения и запуск
    /// обновлений геолокации из фона система не принимает. Повторный вызов при возврате в приложение заново
    /// запускает сеанс геолокации, если система успела его остановить.
    public func setActive(_ active: Bool) {
        wantsActive = active
        applyDesiredState()
    }

    /// Учитывает паузу приложения в фоне, если она случилась при работающем режиме
    public func noteBackgroundPause(seconds: TimeInterval, now: Date = Date()) {
        guard state == .running, let since = runningSince else { return }
        // Пауза началась до запуска режима (приложение усыпили, пока режим ещё не работал) — не считается
        guard now.addingTimeInterval(-seconds) >= since else { return }
        pausesWhileRunning += 1
    }

    private func applyDesiredState() {
        guard wantsActive else {
            stopUpdates()
            state = .off
            return
        }

        // Без значения `location` в UIBackgroundModes включение фоновых обновлений завершает приложение исключением
        guard Self.hasLocationBackgroundMode else {
            stopUpdates()
            state = .unavailable
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            state = .waitingForPermission
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdates()
        case .restricted:
            stopUpdates()
            state = .restricted
        case .denied:
            stopUpdates()
            state = .denied
        @unknown default:
            stopUpdates()
            state = .denied
        }
    }

    private func startUpdates(forceRearm: Bool = false) {
        switch level {
        case .reliable:
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = kCLDistanceFilterNone
        case .economy:
            manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
            manager.distanceFilter = 3_000
        }
        manager.activityType = .other
        // Без этого система приостанавливает обновления, когда телефон лежит неподвижно, и приложение засыпает
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true

        let now = Date()
        if !isUpdating {
            manager.startUpdatingLocation()
            isUpdating = true
            lastArmedAt = now
        } else if forceRearm || now.timeIntervalSince(lastArmedAt) > 10 {
            // Система могла молча остановить сеанс геолокации: запускаем его заново
            manager.stopUpdatingLocation()
            manager.startUpdatingLocation()
            lastArmedAt = now
        }

        if runningSince == nil {
            runningSince = now
        }
        state = .running
    }

    private func stopUpdates() {
        runningSince = nil
        guard isUpdating else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isUpdating = false
    }

    private static var hasLocationBackgroundMode: Bool {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        return modes.contains("location")
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.applyDesiredState()
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Временные ошибки (например, «положение пока не определено») система повторяет сама;
        // важен только запрет доступа
        let isDenied = (error as? CLError)?.code == .denied
        let nsError = error as NSError
        let domain = nsError.domain
        let code = nsError.code

        Task { @MainActor in
            IslandDiagnostics.shared.log("Геолокация: ошибка \(domain), код \(code)", .location)
            if isDenied {
                self.stopUpdates()
                self.state = .denied
            }
        }
    }

    nonisolated public func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor in
            IslandDiagnostics.shared.log("iOS приостановила обновления геолокации — запускаю заново", .location)
            if self.wantsActive {
                self.startUpdates(forceRearm: true)
            }
        }
    }

    nonisolated public func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor in
            IslandDiagnostics.shared.log("iOS возобновила обновления геолокации", .location)
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Координаты намеренно не читаются: режим нужен только затем, чтобы приложение не засыпало
    }
}
