//
//  ZoneModels.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

// MARK: - Зоны покрытия

/// Клетка покрытия: квадрат около 100 × 100 м, окрашенный по замерам из нескольких проходов
public struct CoverageZone: Identifiable, Sendable, Equatable {
    /// «строка:столбец» сетки: не меняется, пока клетка остаётся на месте
    public let id: String
    public let quality: RouteQuality
    /// Четыре угла по кругу: юго-запад, юго-восток, северо-восток, северо-запад
    public let corners: [GeoCoordinate]
    /// Сколько замеров легло в клетку
    public let sampleCount: Int
    /// В скольких разных маршрутах встретилась клетка
    public let routeCount: Int

    public init(id: String, quality: RouteQuality, corners: [GeoCoordinate], sampleCount: Int, routeCount: Int) {
        self.id = id
        self.quality = quality
        self.corners = corners
        self.sampleCount = sampleCount
        self.routeCount = routeCount
    }
}

/// Зоны покрытия по сохранённым маршрутам.
///
/// Линия маршрута показывает только то, где вы проехали, а зона говорит больше: какой сеть бывает в этом месте
/// обычно. Поэтому клетка закрашивается, только если там были не меньше двух разных маршрутов и набралось не меньше
/// четырёх замеров: один проход мог попасть на случайный сбой. Цвет — по большинству замеров. Вокруг клетки ничего
/// не дорисовывается: зона никогда не шире того, что измерено на самом деле. Слой появляется, когда сохранено не
/// меньше трёх маршрутов. Зоны строятся по сохранённым маршрутам и пропадают вместе с ними.
public enum ZoneBuilder {
    /// Сторона клетки, метры
    public static let cellMeters: Double = 100
    /// Слой зон появляется, когда сохранено столько маршрутов (учитываются маршруты хотя бы из двух точек)
    public static let minRoutes = 3
    /// Клетка рисуется, если в ней были столько разных маршрутов
    public static let minRoutesPerCell = 2
    /// и набралось столько замеров
    public static let minSamplesPerCell = 4
    /// Сколько клеток рисуется на карте самое большее: каждая клетка — отдельный слой карты
    public static let maxZones = 600

    /// Метров в одном градусе широты (радиус Земли тот же, что в `GeoCoordinate.distance`)
    private static let metersPerDegree = 6_371_000.0 * Double.pi / 180

    private struct Cell: Hashable {
        let row: Int
        let column: Int
    }

    private struct Tally {
        /// Сколько замеров каждого качества: индекс — `RouteQuality.rawValue`
        var counts = [Int](repeating: 0, count: RouteQuality.allCases.count)
        var routes = Set<UUID>()

        var total: Int { counts.reduce(0, +) }
    }

    /// Сколько маршрутов годятся для зон (в них есть хотя бы две точки)
    public static func usableRouteCount(in routes: [RouteRecord]) -> Int {
        routes.filter { $0.points.count >= 2 }.count
    }

    /// Зоны покрытия по сохранённым маршрутам. Пока маршрутов меньше `minRoutes`, зон нет.
    /// Порядок стабильный (по строкам сетки с юга на север, внутри строки с запада на восток).
    public static func zones(
        from routes: [RouteRecord],
        metric: RouteMetric,
        cellMeters: Double = ZoneBuilder.cellMeters,
        minRoutes: Int = ZoneBuilder.minRoutes,
        minRoutesPerCell: Int = ZoneBuilder.minRoutesPerCell,
        minSamplesPerCell: Int = ZoneBuilder.minSamplesPerCell,
        maxZones: Int = ZoneBuilder.maxZones
    ) -> [CoverageZone] {
        let usable = routes.filter { $0.points.count >= 2 }
        guard usable.count >= minRoutes, cellMeters > 0, maxZones > 0 else { return [] }

        let latitudeStep = cellMeters / metersPerDegree
        var tallies: [Cell: Tally] = [:]

        for route in usable {
            let qualities = RouteAnalyzer.qualities(for: route.points, metric: metric)
            for (index, point) in route.points.enumerated() {
                // Битые координаты (повреждённый файл) не должны ронять приложение
                guard point.latitude.isFinite, point.longitude.isFinite,
                      abs(point.latitude) <= 90, abs(point.longitude) <= 180,
                      let quality = qualities[index] else { continue }
                let key = cellIndex(latitude: point.latitude, longitude: point.longitude, latitudeStep: latitudeStep)
                tallies[key, default: Tally()].counts[quality.rawValue] += 1
                tallies[key, default: Tally()].routes.insert(route.id)
            }
        }

        var ready: [(cell: Cell, zone: CoverageZone)] = []
        for (cell, tally) in tallies where tally.routes.count >= minRoutesPerCell && tally.total >= minSamplesPerCell {
            let south = Double(cell.row) * latitudeStep
            let west = Double(cell.column) * longitudeStep(row: cell.row, latitudeStep: latitudeStep)
            let north = south + latitudeStep
            let east = west + longitudeStep(row: cell.row, latitudeStep: latitudeStep)
            let zone = CoverageZone(
                id: "\(cell.row):\(cell.column)",
                quality: typicalQuality(tally.counts),
                corners: [
                    GeoCoordinate(latitude: south, longitude: west),
                    GeoCoordinate(latitude: south, longitude: east),
                    GeoCoordinate(latitude: north, longitude: east),
                    GeoCoordinate(latitude: north, longitude: west)
                ],
                sampleCount: tally.total,
                routeCount: tally.routes.count
            )
            ready.append((cell, zone))
        }

        // Клеток больше предела: остаются те, где замеров больше (им можно верить сильнее)
        if ready.count > maxZones {
            ready.sort { left, right in
                if left.zone.sampleCount != right.zone.sampleCount { return left.zone.sampleCount > right.zone.sampleCount }
                return left.zone.id < right.zone.id
            }
            ready = Array(ready.prefix(maxZones))
        }

        ready.sort { left, right in
            if left.cell.row != right.cell.row { return left.cell.row < right.cell.row }
            return left.cell.column < right.cell.column
        }
        return ready.map(\.zone)
    }

    /// Качество «посередине»: замеры выстраиваются от лучшего к худшему, берётся серединный (при чётном числе
    /// замеров — худший из двух средних). Половина замеров не лучше этого цвета, половина не хуже.
    static func typicalQuality(_ counts: [Int]) -> RouteQuality {
        let total = counts.reduce(0, +)
        let target = total / 2
        var seen = 0
        for quality in RouteQuality.allCases {
            seen += counts[quality.rawValue]
            if target < seen { return quality }
        }
        return .dead
    }

    private static func cellIndex(latitude: Double, longitude: Double, latitudeStep: Double) -> Cell {
        let row = Int((latitude / latitudeStep).rounded(.down))
        let step = longitudeStep(row: row, latitudeStep: latitudeStep)
        return Cell(row: row, column: Int((longitude / step).rounded(.down)))
    }

    /// Шаг по долготе в строке сетки: к полюсам градус долготы короче, клетка остаётся квадратной
    private static func longitudeStep(row: Int, latitudeStep: Double) -> Double {
        let centerLatitude = (Double(row) + 0.5) * latitudeStep
        let scale = max(0.05, cos(centerLatitude * Double.pi / 180))
        return latitudeStep / scale
    }
}
