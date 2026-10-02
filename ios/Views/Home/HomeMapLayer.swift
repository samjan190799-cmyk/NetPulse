//
//  HomeMapLayer.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import MapKit

enum HomeMapDefaults {
    /// Пока геолокация не разрешена и маршрутов нет, карта показывает европейскую часть России: приложение на русском.
    /// Как только пользователь разрешит геолокацию (при первой записи), карта следует за ним.
    @MainActor static let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 55.75, longitude: 37.62),
        span: MKCoordinateSpan(latitudeDelta: 14, longitudeDelta: 20)
    )
}

/// Карта Apple Maps (MapKit) на весь главный экран: положение пользователя и маршрут, раскрашенный по качеству сети.
/// Тёмная подложка под цветной линией делает цвет читаемым и на светлых улицах, и на спутниковом снимке.
@MainActor
struct HomeMapLayer: View {
    let route: RouteRecord?
    let metric: RouteMetric
    let isLive: Bool
    let showsUserDot: Bool
    let satellite: Bool
    @Binding var camera: MapCameraPosition

    private var mapStyleValue: MapStyle {
        // Приглушённая схема без значков заведений: цветная линия маршрута читается лучше, чем на пёстрой карте
        satellite
            ? .hybrid(pointsOfInterest: .excludingAll)
            : .standard(emphasis: .muted, pointsOfInterest: .excludingAll)
    }

    private func coordinates(of segment: RouteSegment) -> [CLLocationCoordinate2D] {
        segment.path.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func coordinate(of point: RoutePoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }

    var body: some View {
        let points = route?.points ?? []
        let segments = RouteAnalyzer.segments(for: points, metric: metric)
        let zones = RouteAnalyzer.deadZones(in: points)
        let first = points.first
        let last = points.last

        Map(position: $camera) {
            if showsUserDot {
                UserAnnotation()
            }

            // Тёмная подложка под линией
            ForEach(segments) { segment in
                MapPolyline(coordinates: coordinates(of: segment))
                    .stroke(Color.black.opacity(0.55), style: StrokeStyle(lineWidth: 9.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(segments) { segment in
                MapPolyline(coordinates: coordinates(of: segment))
                    .stroke(
                        segment.quality.displayColor,
                        style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round, dash: segment.quality == .dead ? [1, 8] : [])
                    )
            }

            ForEach(zones) { zone in
                Annotation("Нет сети", coordinate: CLLocationCoordinate2D(latitude: zone.center.latitude, longitude: zone.center.longitude)) {
                    deadZoneMarker
                }
            }

            if let first, points.count > 1 {
                Marker("Старт", systemImage: "flag.fill", coordinate: coordinate(of: first))
                    .tint(.green)
            }

            if let last, !isLive, points.count > 1 {
                Marker("Финиш", systemImage: "flag.checkered", coordinate: coordinate(of: last))
                    .tint(.red)
            }
        }
        .mapStyle(mapStyleValue)
        .mapControlVisibility(.hidden)
    }

    /// Круглая метка зоны без сети: значок «нет Wi-Fi» читается и без цвета
    private var deadZoneMarker: some View {
        ZStack {
            Circle()
                .fill(HomePalette.stopRed)
                .frame(width: 28, height: 28)
            Image(systemName: "wifi.slash")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
    }
}
