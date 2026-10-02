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

    func requestPermission()
    /// Начинает (или заново начинает) получение положения, в том числе в фоне
    func start()
    func stop()
}

/// Настоящий источник положения на CoreLocation.
///
/// Нужен полноточный GPS и фоновые обновления: запись маршрута продолжается, пока телефон лежит в кармане.
/// Пока запись идёт, iOS показывает в строке состояния значок геолокации. Вариант «Однократно» в запросе
/// разрешения система отзывает вскоре после сворачивания, поэтому нужно «При использовании приложения».
@MainActor
public final class CoreLocationSession: NSObject, LocationSessionProviding, @preconcurrency CLLocationManagerDelegate {
    public var onFix: (@MainActor (LocationFix) -> Void)?
    public var onAuthorizationChange: (@MainActor () -> Void)?

    private let manager = CLLocationManager()
    private var isRunning = false

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

    public func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    public func start() {
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .other
        // Иначе система приостанавливает обновления, когда телефон лежит неподвижно, и запись обрывается
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true

        if isRunning {
            // Система могла молча остановить сеанс: запускаем его заново
            manager.stopUpdatingLocation()
        }
        manager.startUpdatingLocation()
        isRunning = true
    }

    public func stop() {
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
