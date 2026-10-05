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
///
/// Маршрут — линия: зелёная там, где сеть хорошая, жёлтая — средняя, оранжевая — плохая, красная пунктирная — связи нет.
/// Тёмная подложка под цветной линией делает цвет читаемым и на светлых улицах, и на спутниковом снимке. В обычном
/// режиме на карте лежат и прежние маршруты: те же цветные линии, только тоньше, чтобы последний маршрут оставался
/// главным. Широких полос вдоль маршрута нет. Цвет есть только у тех мест, где вы действительно были и измеряли сеть;
/// зоны покрытия (по желанию, в Настройках) — это клетки 100 × 100 м, где вы бывали не меньше двух раз, под линиями.
@MainActor
struct HomeMapLayer: View {
    let route: RouteRecord?
    let metric: RouteMetric
    let isLive: Bool
    let showsUserDot: Bool
    let satellite: Bool
    /// Зоны покрытия по накопленным маршрутам (лежат под всеми линиями), только в обычном режиме
    let zones: [CoverageZone]
    /// Линии прежних маршрутов (в порядке рисования), только в обычном режиме
    let previousRoutes: [CoverageRun]
    /// Метки «Старт» и «Финиш»: в обычном режиме они только мешают (могут уехать под строку состояния)
    let showsEndpoints: Bool
    @Binding var camera: MapCameraPosition

    private var mapStyleValue: MapStyle {
        // Приглушённая схема без значков заведений: цветная линия маршрута читается лучше, чем на пёстрой карте
        satellite
            ? .hybrid(pointsOfInterest: .excludingAll)
            : .standard(emphasis: .muted, pointsOfInterest: .excludingAll)
    }

    private func coordinates(of path: [GeoCoordinate]) -> [CLLocationCoordinate2D] {
        path.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func coordinate(of point: RoutePoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }

    private func underlayStyle(width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    private func lineStyle(width: CGFloat, quality: RouteQuality) -> StrokeStyle {
        // Участок без связи — пунктир: он заметен и без цвета
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: quality == .dead ? [1, 8] : [])
    }

    var body: some View {
        let points = route?.points ?? []
        let segments = RouteAnalyzer.segments(for: points, metric: metric)
        let zones = RouteAnalyzer.deadZones(in: points)
        let first = points.first
        let last = points.last

        Map(position: $camera) {
            if showsUserDot {
                UserAnnotation {
                    HomeUserMarker()
                }
            }

            // Зоны покрытия: цветные клетки там, где вы бывали не раз; лежат под линиями и не закрывают названия улиц
            ForEach(zones) { zone in
                MapPolygon(coordinates: coordinates(of: zone.corners))
                    .foregroundStyle(zone.quality.displayColor.opacity(0.28))
                    .stroke(zone.quality.displayColor.opacity(0.5), lineWidth: 1)
            }

            // Прежние маршруты: тонкие линии лежат под показанным маршрутом
            ForEach(previousRoutes) { run in
                MapPolyline(coordinates: coordinates(of: run.path))
                    .stroke(Color.black.opacity(0.45), style: underlayStyle(width: 6.5))
            }
            ForEach(previousRoutes) { run in
                MapPolyline(coordinates: coordinates(of: run.path))
                    .stroke(run.quality.displayColor, style: lineStyle(width: 3.5, quality: run.quality))
            }

            // Показанный маршрут: тёмная подложка и цветная линия
            ForEach(segments) { segment in
                MapPolyline(coordinates: coordinates(of: segment.path))
                    .stroke(Color.black.opacity(0.55), style: underlayStyle(width: 9.5))
            }
            ForEach(segments) { segment in
                MapPolyline(coordinates: coordinates(of: segment.path))
                    .stroke(segment.quality.displayColor, style: lineStyle(width: 5.5, quality: segment.quality))
            }

            ForEach(zones) { zone in
                Annotation("Нет сети", coordinate: CLLocationCoordinate2D(latitude: zone.center.latitude, longitude: zone.center.longitude)) {
                    deadZoneMarker
                }
            }

            if showsEndpoints, let first, points.count > 1 {
                Marker("Старт", systemImage: "flag.fill", coordinate: coordinate(of: first))
                    .tint(.green)
            }

            if showsEndpoints, let last, !isLive, points.count > 1 {
                Marker("Финиш", systemImage: "flag.checkered", coordinate: coordinate(of: last))
                    .tint(.red)
            }
        }
        .mapStyle(mapStyleValue)
        .mapControlVisibility(.hidden)
    }

    /// Круглая метка места без сети: значок «нет Wi-Fi» читается и без цвета
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
