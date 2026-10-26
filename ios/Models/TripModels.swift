//
//  TripModels.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

// MARK: - Режим «Поездка»

/// Предупреждение «впереди слабая связь»: по ходу движения лежит место, где на ваших прошлых маршрутах сеть была
/// плохой или пропадала. Это только ваши собственные записи: данных операторов приложение не использует.
public struct TripWarning: Sendable, Equatable {
    /// Худшее качество связи на ближайшем слабом участке впереди (`.poor` или `.dead`)
    public let quality: RouteQuality
    /// Сколько метров до ближайшей слабой точки по ходу движения
    public let distanceMeters: Double
    /// На скольких прошлых маршрутах здесь была слабая связь
    public let routeCount: Int
    /// Ключ участка (квадрат около 200 м): по нему одно и то же предупреждение не повторяется
    public let zoneKey: String

    public init(quality: RouteQuality, distanceMeters: Double, routeCount: Int, zoneKey: String) {
        self.quality = quality
        self.distanceMeters = distanceMeters
        self.routeCount = routeCount
        self.zoneKey = zoneKey
    }

    public var title: String {
        quality == .dead ? "Впереди может пропасть связь" : "Впереди слабая связь"
    }

    /// Расстояние для показа: до километра округляется до 50 м, дальше до 100 м (точнее знать незачем,
    /// а прыгающие каждую секунду цифры только отвлекают)
    public var roundedDistanceMeters: Double {
        let step: Double = distanceMeters < 1000 ? 50 : 100
        return max(step, (distanceMeters / step).rounded() * step)
    }

    public var detail: String {
        "Через \(RouteFormat.distance(roundedDistanceMeters)) · по вашим прошлым поездкам"
    }
}

/// Поиск слабой связи впереди по сохранённым маршрутам.
///
/// Слабый участок прошлого маршрута — не меньше двух подряд идущих точек, где связь была плохой или пропадала
/// (одиночный сбой не участок). Из таких точек строится индекс. Дальше по текущему положению, направлению и скорости
/// ищутся слабые точки в коридоре впереди: чем быстрее движение, тем дальше смотрим вперёд (две минуты пути, от 300 м
/// до 3 км). Предупреждаем только о том, что лежит по ходу, а не рядом на соседней дороге.
public struct TripAdvisor: Sendable {
    /// Столько подряд идущих слабых точек нужно, чтобы считать участок слабым
    public static let minWeakPoints = 2
    /// Меньше этой скорости (м/с) никуда не едем: «впереди» не определено
    public static let minSpeedMps: Double = 1.0
    /// Сколько секунд пути смотрим вперёд
    public static let lookAheadSeconds: TimeInterval = 120
    public static let minLookAheadMeters: Double = 300
    public static let maxLookAheadMeters: Double = 3_000
    /// Ближе этого расстояния слабое место уже под ногами, о нём не предупреждаем
    public static let minDistanceMeters: Double = 80
    /// Слабая точка годится, если она не дальше этого угла от направления движения
    public static let coneHalfAngleDegrees: Double = 40
    /// и не дальше этого расстояния в стороне от линии движения
    public static let maxLateralMeters: Double = 150
    /// Слабые точки дальше ближайшей не больше чем на столько метров считаются тем же участком
    public static let clusterMeters: Double = 400
    /// Направление считается по точке, оставшейся позади не меньше чем на столько метров
    public static let headingBaselineMeters: Double = 40
    /// Сколько последних точек просматривается при поиске направления
    public static let headingLookBackPoints = 12

    private static let metersPerDegree = 6_371_000.0 * Double.pi / 180

    private struct WeakPoint: Sendable {
        let latitude: Double
        let longitude: Double
        let quality: RouteQuality
        let route: Int
    }

    /// Слабые точки, по возрастанию широты (по ней идёт двоичный поиск)
    private let weakPoints: [WeakPoint]

    /// Индекс по сохранённым маршрутам. Тяжёлый для длинной истории: строить стоит не на главном потоке.
    public init(routes: [RouteRecord]) {
        var collected: [WeakPoint] = []
        for (routeIndex, route) in routes.enumerated() where route.points.count >= 2 {
            var run: [WeakPoint] = []
            var previous: RoutePoint?

            func flush() {
                if run.count >= Self.minWeakPoints {
                    collected.append(contentsOf: run)
                }
                run.removeAll(keepingCapacity: true)
            }

            for point in route.points {
                // Битые координаты (повреждённый файл) не должны ронять приложение
                guard point.latitude.isFinite, point.longitude.isFinite,
                      abs(point.latitude) <= 90, abs(point.longitude) <= 180 else {
                    flush()
                    previous = nil
                    continue
                }
                if let previous, point.time.timeIntervalSince(previous.time) > RouteAnalyzer.maxGapSeconds {
                    flush()
                }
                let quality = point.quality
                if quality >= .poor {
                    run.append(WeakPoint(latitude: point.latitude, longitude: point.longitude, quality: quality, route: routeIndex))
                } else {
                    flush()
                }
                previous = point
            }
            flush()
        }
        collected.sort { $0.latitude < $1.latitude }
        weakPoints = collected
    }

    /// Нет ни одного слабого места: искать нечего
    public var isEmpty: Bool {
        weakPoints.isEmpty
    }

    public var weakPointCount: Int {
        weakPoints.count
    }

    /// Как далеко смотреть вперёд при такой скорости
    public static func lookAheadMeters(speedMps: Double) -> Double {
        guard speedMps.isFinite, speedMps > 0 else { return minLookAheadMeters }
        return min(maxLookAheadMeters, max(minLookAheadMeters, speedMps * lookAheadSeconds))
    }

    /// Направление движения (градусы от севера по часовой стрелке, 0..<360) по последним точкам записи: от точки,
    /// оставшейся позади не меньше чем на 40 м, к последней. `nil` — телефон почти не сдвинулся или точки разорваны паузой.
    public static func heading(from points: [RoutePoint]) -> Double? {
        guard let last = points.last, points.count >= 2 else { return nil }
        let lowerBound = max(0, points.count - 1 - headingLookBackPoints)
        var index = points.count - 2
        while index >= lowerBound {
            let candidate = points[index]
            // Пауза между точками: направление до неё уже ничего не говорит
            if last.time.timeIntervalSince(candidate.time) > RouteAnalyzer.maxGapSeconds * 2 { return nil }
            let (dx, dy) = offsetMeters(
                fromLatitude: candidate.latitude, longitude: candidate.longitude,
                toLatitude: last.latitude, longitude: last.longitude
            )
            if hypot(dx, dy) >= headingBaselineMeters {
                return normalizedDegrees(atan2(dx, dy) * 180 / .pi)
            }
            index -= 1
        }
        return nil
    }

    /// Скорость движения, м/с: большая из скорости по данным геолокации в последней точке и скорости между двумя
    /// последними точками (у геолокации в начале движения скорость бывает нулевой). `nil` — оценить не из чего.
    public static func speed(from points: [RoutePoint]) -> Double? {
        guard let last = points.last else { return nil }
        var estimates: [Double] = []
        if let reported = last.speedMps, reported.isFinite, reported >= 0 {
            estimates.append(reported)
        }
        if points.count >= 2 {
            let previous = points[points.count - 2]
            let seconds = last.time.timeIntervalSince(previous.time)
            if seconds > 0, seconds <= RouteAnalyzer.maxGapSeconds {
                estimates.append(previous.coordinate.distance(to: last.coordinate) / seconds)
            }
        }
        return estimates.max()
    }

    /// Предупреждение о слабой связи впереди или `nil`.
    /// - Parameters:
    ///   - position: где телефон сейчас
    ///   - headingDegrees: направление движения, градусы от севера
    ///   - speedMps: скорость, м/с
    ///   - currentQuality: качество связи в текущей точке; если она уже слабая, предупреждать не о чем
    public func warning(
        at position: GeoCoordinate,
        headingDegrees: Double,
        speedMps: Double,
        currentQuality: RouteQuality? = nil
    ) -> TripWarning? {
        guard !weakPoints.isEmpty,
              speedMps.isFinite, speedMps >= Self.minSpeedMps,
              headingDegrees.isFinite,
              position.latitude.isFinite, position.longitude.isFinite,
              abs(position.latitude) <= 90, abs(position.longitude) <= 180 else { return nil }
        if let currentQuality, currentQuality >= .poor { return nil }

        let lookAhead = Self.lookAheadMeters(speedMps: speedMps)
        let latitudeSpan = lookAhead / Self.metersPerDegree

        // Нижняя граница полосы по широте: двоичный поиск
        var low = 0
        var high = weakPoints.count
        let southEdge = position.latitude - latitudeSpan
        while low < high {
            let middle = (low + high) / 2
            if weakPoints[middle].latitude < southEdge {
                low = middle + 1
            } else {
                high = middle
            }
        }

        var candidates: [(forward: Double, point: WeakPoint)] = []
        var index = low
        let northEdge = position.latitude + latitudeSpan
        while index < weakPoints.count, weakPoints[index].latitude <= northEdge {
            let point = weakPoints[index]
            index += 1

            let (dx, dy) = Self.offsetMeters(
                fromLatitude: position.latitude, longitude: position.longitude,
                toLatitude: point.latitude, longitude: point.longitude
            )
            let distance = hypot(dx, dy)
            guard distance >= Self.minDistanceMeters, distance <= lookAhead else { continue }

            let bearing = atan2(dx, dy) * 180 / .pi
            let delta = Self.angleDifference(bearing, headingDegrees)
            guard abs(delta) <= Self.coneHalfAngleDegrees else { continue }

            let radians = delta * .pi / 180
            let forward = distance * cos(radians)
            let lateral = distance * abs(sin(radians))
            guard forward >= Self.minDistanceMeters, forward <= lookAhead, lateral <= Self.maxLateralMeters else { continue }
            candidates.append((forward: forward, point: point))
        }

        guard let nearest = candidates.min(by: { $0.forward < $1.forward }) else { return nil }
        let cluster = candidates.filter { $0.forward <= nearest.forward + Self.clusterMeters }
        let worst = cluster.map { $0.point.quality }.max() ?? nearest.point.quality
        let routes = Set(cluster.map { $0.point.route }).count
        return TripWarning(
            quality: worst,
            distanceMeters: nearest.forward,
            routeCount: routes,
            zoneKey: Self.zoneKey(latitude: nearest.point.latitude, longitude: nearest.point.longitude)
        )
    }

    // MARK: - Геометрия

    /// Смещение от одной точки к другой в метрах: на восток и на север (плоское приближение, для сотен метров точное)
    static func offsetMeters(
        fromLatitude: Double, longitude fromLongitude: Double,
        toLatitude: Double, longitude toLongitude: Double
    ) -> (east: Double, north: Double) {
        let scale = max(0.05, cos(fromLatitude * .pi / 180))
        let east = (toLongitude - fromLongitude) * metersPerDegree * scale
        let north = (toLatitude - fromLatitude) * metersPerDegree
        return (east, north)
    }

    /// Разность двух направлений в градусах: от -180 до 180
    static func angleDifference(_ first: Double, _ second: Double) -> Double {
        var difference = (first - second).truncatingRemainder(dividingBy: 360)
        if difference > 180 { difference -= 360 }
        if difference < -180 { difference += 360 }
        return difference
    }

    static func normalizedDegrees(_ value: Double) -> Double {
        var degrees = value.truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    /// Квадрат около 200 м (0,002 градуса)
    static func zoneKey(latitude: Double, longitude: Double) -> String {
        "\(Int((latitude * 500).rounded())):\(Int((longitude * 500).rounded()))"
    }
}

/// Решает, когда о слабом участке стоит сообщить (щелчок, уведомление), а когда достаточно плашки на экране.
/// Об одном и том же участке повторно не сообщаем; о другом — не чаще чем раз в три минуты.
public struct TripAnnouncer: Sendable {
    public static let minimumInterval: TimeInterval = 180
    public static let sameZoneInterval: TimeInterval = 900

    private var lastKey: String?
    private var lastAt: Date?

    public init() {}

    public mutating func shouldAnnounce(_ warning: TripWarning, now: Date) -> Bool {
        if let lastAt {
            let age = now.timeIntervalSince(lastAt)
            // Часы перевели назад (age < 0): ждать нечего, сообщаем как в первый раз
            if age >= 0 {
                if warning.zoneKey == lastKey {
                    if age < Self.sameZoneInterval { return false }
                } else if age < Self.minimumInterval {
                    return false
                }
            }
        }
        lastKey = warning.zoneKey
        lastAt = now
        return true
    }

    public mutating func reset() {
        lastKey = nil
        lastAt = nil
    }
}
