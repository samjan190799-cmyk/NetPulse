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
/// главным. Никаких зон и полос: цвет есть только у тех мест, где вы действительно были и измеряли сеть.
@MainActor
struct HomeMapLayer: View {
    let route: RouteRecord?
    let metric: RouteMetric
    let isLive: Bool
    let showsUserDot: Bool
    let satellite: Bool
    /// Линии прежних маршрутов (в порядке рисования), только в обычном режиме
    let previousRoutes: [CoverageRun]
    /// Метки «Старт» и «Финиш»: в обычном режиме они только мешают (могут уехать под строку состояния)
    let showsEndpoints: Bool
    @Binding var camera: MapCameraPosition

    @Environment(\.npOneShotMotion) private var oneShotMotion
    /// Какому маршруту (по времени начала) относится `revealFraction`
    @State private var revealedKey: Date?
    /// Какая часть маршрута уже «нарисована» (1 — весь маршрут)
    @State private var revealFraction: Double = 0

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
        let allPoints = route?.points ?? []
        let points = visiblePoints(of: allPoints)
        let segments = RouteAnalyzer.segments(for: points, metric: metric)
        let zones = RouteAnalyzer.deadZones(in: points)
        let first = points.first
        // Флажок «Финиш» появляется, когда маршрут дорисован
        let last = currentFraction >= 1 ? allPoints.last : nil

        Map(position: $camera) {
            if showsUserDot {
                UserAnnotation {
                    HomeUserMarker()
                }
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
                    HomeDeadZoneMarker()
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
        .task(id: route?.startedAt) {
            await reveal()
        }
    }

    // MARK: - «Рисование» маршрута

    /// Доля маршрута, которую сейчас нужно показать: у маршрута, который ещё не «рисовали», — ноль
    private var currentFraction: Double {
        revealedKey == route?.startedAt ? revealFraction : 0
    }

    private func visiblePoints(of all: [RoutePoint]) -> [RoutePoint] {
        let fraction = currentFraction
        guard fraction < 1 else { return all }
        return Array(all.prefix(Int(Double(all.count) * fraction)))
    }

    /// Новый маршрут на карте не появляется разом, а «рисуется» от старта к финишу примерно за секунду.
    /// Идущая запись растёт сама, по мере появления точек; при «Уменьшении движения» и у коротких маршрутов
    /// маршрут появляется сразу.
    private func reveal() async {
        let key = route?.startedAt
        guard oneShotMotion, !isLive, (route?.points.count ?? 0) > 4 else {
            revealedKey = key
            revealFraction = 1
            return
        }
        revealedKey = key
        revealFraction = 0
        let steps = 24
        for step in 1...steps {
            try? await Task.sleep(for: .milliseconds(40))
            if Task.isCancelled { return }
            revealFraction = Double(step) / Double(steps)
        }
    }
}

/// Круглая метка места без сети: значок «нет Wi-Fi» читается и без цвета. Появляется с отскоком.
@MainActor
struct HomeDeadZoneMarker: View {
    @Environment(\.npOneShotMotion) private var oneShot
    @State private var popped = false

    var body: some View {
        ZStack {
            Circle()
                .fill(HomePalette.stopRed)
                .frame(width: 28, height: 28)
            Image(systemName: "wifi.slash")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
        .scaleEffect(popped || !oneShot ? 1 : 0.2)
        .onAppear {
            guard oneShot else { return }
            withAnimation(NPMotion.pop) {
                popped = true
            }
        }
    }
}
