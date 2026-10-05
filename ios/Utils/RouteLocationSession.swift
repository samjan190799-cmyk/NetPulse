//
//  RouteLocationSession.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
@preconcurrency import CoreLocation

/// Разрешение на геолокацию в упрощённом виде
public enum LocationAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

/// Источник положения для записи маршрута. В приложении — CoreLocation (`CoreLocationSession`), в тестах — подставной.
@MainActor
public protocol LocationSessionProviding: AnyObject {
    var authorization: LocationAuthorization { get }
    /// Новое положение
    var onFix: (@MainActor (LocationFix) -> Void)? { get set }
    /// Изменилось разрешение на геолокацию
    var onAuthorizationChange: (@MainActor () -> Void)? { get set }

    /// Дано ли разрешение «Всегда»: только с ним iOS может сама запустить закрытое приложение
    var hasAlwaysAuthorization: Bool { get }

    func requestPermission()
    /// Просит у iOS разрешение «Всегда» (после «При использовании приложения»); нужно для продолжения записи после закрытия
    func requestAlwaysPermission()
    /// Можно ли получать положение, пока приложение свёрнуто. Если нет, в фоне запись стоит на паузе,
    /// а значок геолокации в строке состояния не появляется.
    func setBackgroundUpdates(allowed: Bool)
    /// Режим экономии заряда: положение грубее (около 100 м) и реже, GPS работает меньше. Действует со следующего `start()`.
    func setPowerSaving(_ enabled: Bool)
    /// Следить ли за значительными перемещениями (примерно от 500 м): если приложение закроют, iOS запустит его
    /// заново, когда телефон переместится, и запись продолжится.
    func setRelaunchOnMove(enabled: Bool)
    /// Начинает (или заново начинает) получение положения; в фоне — если это разрешено `setBackgroundUpdates`
    func start()
    func stop()
}

extension LocationSessionProviding {
    // Источникам, которым эти возможности не нужны (в тестах), достаточно значений по умолчанию
    public var hasAlwaysAuthorization: Bool { false }
    public func requestAlwaysPermission() {}
    public func setPowerSaving(_ enabled: Bool) {}
    public func setRelaunchOnMove(enabled: Bool) {}
}

/// Настоящий источник положения на CoreLocation.
///
/// Нужен GPS и (если пользователь не отключил в настройках) фоновые обновления: запись маршрута продолжается,
/// пока телефон лежит в кармане. Точность «до десяти метров» достаточна для линии маршрута и заметно экономнее
/// режима «Лучшая». Пока запись идёт в фоне, iOS показывает в строке состояния значок геолокации. Вариант
/// «Однократно» в запросе разрешения система отзывает вскоре после сворачивания, поэтому нужно «При использовании
/// приложения».
@MainActor
public final class CoreLocationSession: NSObject, LocationSessionProviding, @preconcurrency CLLocationManagerDelegate {
    public var onFix: (@MainActor (LocationFix) -> Void)?
    public var onAuthorizationChange: (@MainActor () -> Void)?

    private let manager = CLLocationManager()
    private var isRunning = false
    private var allowsBackground = true
    private var powerSaving = false

    public override init() {
        super.init()
        manager.delegate = self
    }

    public var authorization: LocationAuthorization {
        switch manager.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorizedWhenInUse, .authorizedAlways:
            return .authorized
        @unknown default:
            return .denied
        }
    }

    public var hasAlwaysAuthorization: Bool {
        manager.authorizationStatus == .authorizedAlways
    }

    public func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    public func requestAlwaysPermission() {
        manager.requestAlwaysAuthorization()
    }

    public func setPowerSaving(_ enabled: Bool) {
        powerSaving = enabled
    }

    public func setRelaunchOnMove(enabled: Bool) {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        if enabled {
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
        }
    }

    public func setBackgroundUpdates(allowed: Bool) {
        allowsBackground = allowed
        guard isRunning else { return }
        manager.allowsBackgroundLocationUpdates = allowed
        manager.showsBackgroundLocationIndicator = allowed
    }

    public func start() {
        // Для линии маршрута хватает десяти метров; режим «Лучшая» держит датчики на полной мощности зря.
        // В режиме экономии заряда требуется только около 100 м: iOS может обойтись Wi-Fi и вышками, не включая GPS.
        manager.desiredAccuracy = powerSaving ? kCLLocationAccuracyHundredMeters : kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .other
        // Иначе система приостанавливает обновления, когда телефон лежит неподвижно, и запись обрывается
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = allowsBackground
        manager.showsBackgroundLocationIndicator = allowsBackground

        if isRunning {
            // Система могла молча остановить сеанс: запускаем его заново
            manager.stopUpdatingLocation()
        }
        manager.startUpdatingLocation()
        isRunning = true
    }

    public func stop() {
        // Запись закончена или стоит на паузе: запускать приложение по перемещению больше не нужно
        manager.stopMonitoringSignificantLocationChanges()
        guard isRunning else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isRunning = false
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.onAuthorizationChange?()
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.map {
            LocationFix(
                latitude: $0.coordinate.latitude,
                longitude: $0.coordinate.longitude,
                horizontalAccuracy: $0.horizontalAccuracy,
                speed: $0.speed,
                timestamp: $0.timestamp
            )
        }
        Task { @MainActor in
            for fix in fixes {
                self.onFix?(fix)
            }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Временные ошибки («положение пока не определено») система повторяет сама, а запрет доступа
        // приходит отдельно, через смену разрешения
    }

    nonisolated public func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.isRunning {
                self.start()
            }
        }
    }
}
