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
/// Приложение с активными фоновыми обновлениями геолокации не усыпляется. Включается самая экономная
/// конфигурация: точность порядка километров (GPS не задействуется) и почти без событий.
/// Координаты приложение не читает, не сохраняет и никуда не отправляет.
///
/// Что нужно знать:
/// - в строке состояния iOS показывает значок использования геолокации, расход батареи выше обычного;
/// - правило App Store 2.5.4 разрешает фоновую геолокацию для функций, которым нужно местоположение,
///   поэтому режим выключен по умолчанию и включается только самим пользователем с понятным объяснением;
/// - если пользователь закрыл приложение смахиванием, оно не запустится само: режим вернётся при следующем открытии;
/// - Live Activity живёт не дольше 8 часов, потом iOS её завершает, а новую можно запустить только из открытого приложения.
@MainActor
public final class ContinuousModeManager: NSObject, @preconcurrency CLLocationManagerDelegate {
    public static let shared = ContinuousModeManager()

    /// Режим входит в PRO. Пока `false`, включить его может любой пользователь: продукт PRO ещё не создан
    /// в App Store Connect, и функцию иначе нельзя проверить. Значение `true` включает проверку PRO в настройках
    /// (тумблер открывает экран покупки так же, как плавающий HUD).
    public static let requiresPro = false

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
                return "Ожидается ответ на запрос геолокации"
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
            onStateChange?(state)
        }
    }

    /// Вызывается при смене состояния: ViewModel зеркалит его в наблюдаемое свойство
    public var onStateChange: (@MainActor (State) -> Void)?

    private let manager = CLLocationManager()
    private var wantsActive = false
    private var isUpdating = false

    private override init() {
        super.init()
        manager.delegate = self
    }

    /// Включает или выключает удержание в фоне. Это желаемое состояние: фактическое зависит от разрешения
    /// на геолокацию и отражено в `state`. Вызывать нужно при открытом приложении: запрос разрешения и запуск
    /// обновлений геолокации из фона система не принимает.
    public func setActive(_ active: Bool) {
        wantsActive = active
        applyDesiredState()
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

    private func startUpdates() {
        // Самая экономная конфигурация: приблизительное положение по сотовым вышкам и Wi-Fi, GPS не нужен
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 3_000
        manager.activityType = .other
        // Без этого система приостанавливает обновления, когда телефон лежит неподвижно, и приложение засыпает
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true

        if !isUpdating {
            manager.startUpdatingLocation()
            isUpdating = true
        }
        state = .running
    }

    private func stopUpdates() {
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
        let isDenied: Bool
        if let locationError = error as? CLError {
            isDenied = locationError.code == .denied
        } else {
            isDenied = false
        }

        Task { @MainActor in
            if isDenied {
                self.stopUpdates()
                self.state = .denied
            }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Координаты намеренно не читаются: режим нужен только затем, чтобы приложение не засыпало
    }
}
