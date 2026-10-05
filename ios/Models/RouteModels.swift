//
//  RouteModels.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

// MARK: - Координаты без CoreLocation

/// Широта и долгота. Логика маршрутов не зависит от CoreLocation, поэтому проверяется юнит-тестами.
public struct GeoCoordinate: Codable, Sendable, Equatable, Hashable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Расстояние по поверхности Земли в метрах (формула гаверсинусов)
    public func distance(to other: GeoCoordinate) -> Double {
        let radius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, sqrt(a)))
    }
}

/// Положение устройства в один момент (то, что нужно записи маршрута от CoreLocation)
public struct LocationFix: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    /// Горизонтальная точность, метры; отрицательное значение — положение недостоверно
    public var horizontalAccuracy: Double
    /// Скорость, м/с; отрицательное значение — неизвестна
    public var speed: Double
    public var timestamp: Date

    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double = 10, speed: Double = -1, timestamp: Date = Date()) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.timestamp = timestamp
    }

    public var coordinate: GeoCoordinate {
        GeoCoordinate(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Вид связи

/// Вид связи в точке маршрута
public enum LinkKind: String, Codable, Sendable, CaseIterable {
    case offline
    case wifi
    case ethernet
    case g5
    case lte
    case g3
    case g2
    case cellular
    case other

    public var title: String {
        switch self {
        case .offline: return "Нет сети"
        case .wifi: return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .g5: return "5G"
        case .lte: return "4G (LTE)"
        case .g3: return "3G"
        case .g2: return "2G"
        case .cellular: return "Сотовая"
        case .other: return "Другая"
        }
    }

    /// Поколение сотовой связи по названию технологии радиодоступа из CoreTelephony
    /// (например, «CTRadioAccessTechnologyLTE»); неизвестное название — `.cellular`.
    public static func fromRadioTechnology(_ name: String) -> LinkKind {
        // Общий префикс убирается: в нём самом есть сочетания букв, похожие на названия технологий
        let tech = name.replacingOccurrences(of: "CTRadioAccessTechnology", with: "").uppercased()
        if tech.hasPrefix("NR") { return .g5 }
        if tech.contains("LTE") { return .lte }
        if tech.contains("WCDMA") || tech.contains("HSDPA") || tech.contains("HSUPA")
            || tech.contains("EVDO") || tech.contains("EHRPD") {
            return .g3
        }
        if tech.contains("GPRS") || tech.contains("EDGE") || tech.contains("CDMA1X") {
            return .g2
        }
        return .cellular
    }

    /// Вид связи по состоянию сетевого пути и технологии радиодоступа
    public static func detect(
        isSatisfied: Bool,
        usesWifi: Bool,
        usesCellular: Bool,
        usesWired: Bool,
        radioTechnology: String?
    ) -> LinkKind {
        guard isSatisfied else { return .offline }
        if usesWifi { return .wifi }
        if usesWired { return .ethernet }
        if usesCellular {
            if let radioTechnology, !radioTechnology.isEmpty {
                return fromRadioTechnology(radioTechnology)
            }
            return .cellular
        }
        return .other
    }
}

// MARK: - Качество сети в точке

/// По какому показателю раскрашивается маршрут
public enum RouteMetric: String, CaseIterable, Identifiable, Sendable {
    case latency
    case speed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .latency: return "Задержка"
        case .speed: return "Скорость"
        }
    }
}

/// Качество сети в точке; порядок — от лучшего к худшему
public enum RouteQuality: Int, Codable, Sendable, Comparable, CaseIterable, Hashable {
    case good = 0
    case fair = 1
    case poor = 2
    case dead = 3

    public static func < (lhs: RouteQuality, rhs: RouteQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .good: return "Хорошо"
        case .fair: return "Средне"
        case .poor: return "Плохо"
        case .dead: return "Нет сети"
        }
    }

    /// Задержка TCP-соединения до контрольного узла, мс: до этого значения — хорошо
    public static let goodMaxLatencyMs: Double = 120
    /// До этого значения — средне, выше — плохо
    public static let fairMaxLatencyMs: Double = 300
    /// Скорость скачивания, Мбит/с: от этого значения — хорошо
    public static let goodMinMbps: Double = 5
    /// От этого значения — средне, ниже — плохо
    public static let fairMinMbps: Double = 1

    /// Качество по задержке. Узел не ответил — нет сети.
    public static func byLatency(reachable: Bool, latencyMs: Double?) -> RouteQuality {
        guard reachable else { return .dead }
        guard let latencyMs else { return .fair }
        if latencyMs <= goodMaxLatencyMs { return .good }
        if latencyMs <= fairMaxLatencyMs { return .fair }
        return .poor
    }

    /// Качество по скорости скачивания; `nil` — скорость в этой точке не измерялась
    public static func bySpeed(reachable: Bool, downloadMbps: Double?) -> RouteQuality? {
        guard reachable else { return .dead }
        guard let downloadMbps, downloadMbps > 0 else { return nil }
        if downloadMbps >= goodMinMbps { return .good }
        if downloadMbps >= fairMinMbps { return .fair }
        return .poor
    }

    /// Общая оценка: худшая из задержки и скорости (если она измерялась)
    public static func overall(reachable: Bool, latencyMs: Double?, downloadMbps: Double?) -> RouteQuality {
        let byDelay = byLatency(reachable: reachable, latencyMs: latencyMs)
        guard let bySpeedValue = bySpeed(reachable: reachable, downloadMbps: downloadMbps) else { return byDelay }
        return max(byDelay, bySpeedValue)
    }
}

// MARK: - Точка и запись маршрута

/// Одна точка маршрута: где был телефон и какой была сеть
public struct RoutePoint: Codable, Sendable, Equatable {
    public var time: Date
    public var latitude: Double
    public var longitude: Double
    /// Горизонтальная точность положения, метры
    public var accuracy: Double
    /// Скорость устройства, м/с (`nil` — неизвестна)
    public var speedMps: Double?
    /// Задержка TCP-соединения, мс (`nil` — узел не ответил)
    public var latencyMs: Double?
    /// Ответил ли контрольный узел
    public var reachable: Bool
    public var link: LinkKind
    /// Скорость скачивания, Мбит/с (`nil` — не измерялась)
    public var downloadMbps: Double?

    private enum CodingKeys: String, CodingKey {
        case time = "t"
        case latitude = "la"
        case longitude = "lo"
        case accuracy = "ac"
        case speedMps = "sp"
        case latencyMs = "ms"
        case reachable = "ok"
        case link = "lk"
        case downloadMbps = "dl"
    }

    public init(
        time: Date,
        latitude: Double,
        longitude: Double,
        accuracy: Double = 10,
        speedMps: Double? = nil,
        latencyMs: Double? = nil,
        reachable: Bool = true,
        link: LinkKind = .other,
        downloadMbps: Double? = nil
    ) {
        self.time = time
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.speedMps = speedMps
        self.latencyMs = latencyMs
        self.reachable = reachable
        self.link = link
        self.downloadMbps = downloadMbps
    }

    public var coordinate: GeoCoordinate {
        GeoCoordinate(latitude: latitude, longitude: longitude)
    }

    /// Общая оценка точки (худшая из задержки и скорости)
    public var quality: RouteQuality {
        RouteQuality.overall(reachable: reachable, latencyMs: latencyMs, downloadMbps: downloadMbps)
    }
}

/// Записанный маршрут
public struct RouteRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var points: [RoutePoint]
    /// Запись оборвалась без нажатия «Остановить» (приложение закрыто системой): маршрут сохранён как есть
    public var interrupted: Bool
    /// Во время записи измерялась скорость скачивания
    public var measuredSpeed: Bool

    public init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        points: [RoutePoint] = [],
        interrupted: Bool = false,
        measuredSpeed: Bool = false
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.points = points
        self.interrupted = interrupted
        self.measuredSpeed = measuredSpeed
    }

    /// Длительность записи; у идущей записи — до последней точки
    public var duration: TimeInterval {
        let end = endedAt ?? points.last?.time ?? startedAt
        return max(0, end.timeIntervalSince(startedAt))
    }
}

// MARK: - Участки, мёртвые зоны и статистика

/// Участок маршрута одного качества (одна цветная линия на карте)
public struct RouteSegment: Identifiable, Sendable, Equatable {
    public let id: Int
    public let quality: RouteQuality
    public let path: [GeoCoordinate]

    public init(id: Int, quality: RouteQuality, path: [GeoCoordinate]) {
        self.id = id
        self.quality = quality
        self.path = path
    }
}

/// Зона без сети: несколько точек подряд, где контрольный узел не отвечал
public struct DeadZone: Identifiable, Sendable, Equatable {
    public let id: Int
    public let center: GeoCoordinate
    public let pointCount: Int
    public let lengthMeters: Double
    public let duration: TimeInterval

    public init(id: Int, center: GeoCoordinate, pointCount: Int, lengthMeters: Double, duration: TimeInterval) {
        self.id = id
        self.center = center
        self.pointCount = pointCount
        self.lengthMeters = lengthMeters
        self.duration = duration
    }
}

/// Сводка по маршруту
public struct RouteStats: Sendable, Equatable {
    public var pointCount: Int
    public var distanceMeters: Double
    public var duration: TimeInterval
    public var averageLatencyMs: Double?
    public var worstLatencyMs: Double?
    public var averageDownloadMbps: Double?
    /// Доля точек каждого качества (сумма долей равна 1, если точки есть)
    public var shares: [RouteQuality: Double]
    public var deadZoneCount: Int
    public var longestDeadStretchMeters: Double

    public func share(of quality: RouteQuality) -> Double {
        shares[quality] ?? 0
    }
}

/// Расчёты по маршруту: участки для карты, мёртвые зоны, длина и сводка
public enum RouteAnalyzer {
    /// Если между соседними точками прошло больше секунд, линию между ними не проводим (потеря сигнала, пауза записи)
    public static let maxGapSeconds: TimeInterval = 90
    /// Сколько секунд измеренная скорость считается действующей для следующих точек
    public static let speedCarrySeconds: TimeInterval = 45
    /// Минимум подряд идущих точек без ответа, чтобы считать это зоной без сети (одиночный сбой — не зона)
    public static let minDeadPoints = 2

    /// Качество каждой точки по выбранному показателю. Для скорости последний замер переносится на ближайшие
    /// точки (замер идёт реже, чем запись); `nil` — данных нет.
    public static func qualities(for points: [RoutePoint], metric: RouteMetric) -> [RouteQuality?] {
        switch metric {
        case .latency:
            return points.map { RouteQuality.byLatency(reachable: $0.reachable, latencyMs: $0.latencyMs) }
        case .speed:
            var result: [RouteQuality?] = []
            result.reserveCapacity(points.count)
            var carried: Double?
            var carriedAt: Date?
            for point in points {
                if let own = point.downloadMbps, own > 0 {
                    carried = own
                    carriedAt = point.time
                }
                var effective = point.downloadMbps
                if effective == nil, let value = carried, let at = carriedAt,
                   point.time.timeIntervalSince(at) <= speedCarrySeconds {
                    effective = value
                }
                result.append(RouteQuality.bySpeed(reachable: point.reachable, downloadMbps: effective))
            }
            return result
        }
    }

    /// Цветные участки маршрута: соседние отрезки одного качества сливаются в одну линию.
    /// Качество отрезка — худшее из двух его концов.
    public static func segments(for points: [RoutePoint], metric: RouteMetric) -> [RouteSegment] {
        guard points.count >= 2 else { return [] }
        let perPoint = qualities(for: points, metric: metric)

        var result: [RouteSegment] = []
        var currentQuality: RouteQuality?
        var currentPath: [GeoCoordinate] = []

        func flush() {
            if let quality = currentQuality, currentPath.count >= 2 {
                result.append(RouteSegment(id: result.count, quality: quality, path: currentPath))
            }
            currentQuality = nil
            currentPath = []
        }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let next = points[index]
            if next.time.timeIntervalSince(previous.time) > maxGapSeconds {
                flush()
                continue
            }
            let known = [perPoint[index - 1], perPoint[index]].compactMap { $0 }
            guard let worst = known.max() else {
                flush()
                continue
            }
            if worst != currentQuality {
                flush()
                currentQuality = worst
                currentPath = [previous.coordinate]
            }
            currentPath.append(next.coordinate)
        }
        flush()
        return result
    }

    /// Длина пройденного пути, метры (промежутки длиннее `maxGapSeconds` не считаются)
    public static func distanceMeters(of points: [RoutePoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for index in 1..<points.count {
            let previous = points[index - 1]
            let next = points[index]
            if next.time.timeIntervalSince(previous.time) > maxGapSeconds { continue }
            total += previous.coordinate.distance(to: next.coordinate)
        }
        return total
    }

    /// Зоны без сети: не меньше `minDeadPoints` подряд идущих точек, где контрольный узел не отвечал
    public static func deadZones(in points: [RoutePoint]) -> [DeadZone] {
        var zones: [DeadZone] = []
        var run: [RoutePoint] = []

        func closeRun() {
            if run.count >= minDeadPoints {
                let middle = run[run.count / 2]
                let length = distanceMeters(of: run)
                let span = (run.last?.time ?? middle.time).timeIntervalSince(run.first?.time ?? middle.time)
                zones.append(DeadZone(
                    id: zones.count,
                    center: middle.coordinate,
                    pointCount: run.count,
                    lengthMeters: length,
                    duration: max(0, span)
                ))
            }
            run = []
        }

        for point in points {
            if point.reachable {
                closeRun()
                continue
            }
            if let last = run.last, point.time.timeIntervalSince(last.time) > maxGapSeconds {
                closeRun()
            }
            run.append(point)
        }
        closeRun()
        return zones
    }

    /// Сводка по маршруту
    public static func stats(of record: RouteRecord) -> RouteStats {
        let points = record.points
        let zones = deadZones(in: points)

        var shares: [RouteQuality: Double] = [:]
        if !points.isEmpty {
            for quality in RouteQuality.allCases {
                let count = points.filter { $0.quality == quality }.count
                shares[quality] = Double(count) / Double(points.count)
            }
        }

        let latencies = points.compactMap { $0.reachable ? $0.latencyMs : nil }
        let speeds = points.compactMap { $0.downloadMbps }.filter { $0 > 0 }

        return RouteStats(
            pointCount: points.count,
            distanceMeters: distanceMeters(of: points),
            duration: record.duration,
            averageLatencyMs: latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count),
            worstLatencyMs: latencies.max(),
            averageDownloadMbps: speeds.isEmpty ? nil : speeds.reduce(0, +) / Double(speeds.count),
            shares: shares,
            deadZoneCount: zones.count,
            longestDeadStretchMeters: zones.map { $0.lengthMeters }.max() ?? 0
        )
    }
}

// MARK: - Политика выборки точек

/// Когда записывать очередную точку: запись идёт по таймеру, но стоящий на месте телефон не засоряет маршрут
/// и не тратит трафик на лишние проверки сети.
public struct RouteSamplingPolicy: Sendable, Equatable {
    /// Как часто проверять, нужна ли новая точка, секунд
    public var tickInterval: TimeInterval = 5
    /// Раз в сколько секунд писать точку, если телефон стоит на месте
    public var stationaryInterval: TimeInterval = 30
    /// Меньше стольких метров от прошлой точки — телефон считается стоящим
    public var minMoveMeters: Double = 15
    /// Положение хуже этой точности (метры) не используется
    public var maxAccuracyMeters: Double = 100
    /// Положение старше стольких секунд считается устаревшим
    public var maxFixAge: TimeInterval = 20

    public enum Decision: Equatable, Sendable {
        case record
        case skipNoFix
        case skipPoorAccuracy
        case skipStationary
    }

    public init() {}

    /// Обычный режим: приложение открыто, экран включён
    public static let standard = RouteSamplingPolicy()

    /// Экономный режим для фона и режима энергосбережения: пробуждений и проверок сети вдвое меньше.
    /// Точки при этом остаются достаточно частыми, чтобы линия маршрута повторяла повороты и у пешехода,
    /// и у автомобиля.
    public static let economy: RouteSamplingPolicy = {
        var policy = RouteSamplingPolicy()
        policy.tickInterval = 10
        policy.stationaryInterval = 60
        policy.minMoveMeters = 30
        policy.maxFixAge = 40
        return policy
    }()

    public func decide(lastPoint: RoutePoint?, fix: LocationFix?, now: Date) -> Decision {
        guard let fix, now.timeIntervalSince(fix.timestamp) <= maxFixAge else { return .skipNoFix }
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= maxAccuracyMeters else { return .skipPoorAccuracy }
        guard let lastPoint else { return .record }

        let moved = lastPoint.coordinate.distance(to: fix.coordinate)
        let elapsed = now.timeIntervalSince(lastPoint.time)
        if moved < minMoveMeters && elapsed < stationaryInterval {
            return .skipStationary
        }
        return .record
    }
}

// MARK: - Подписи для интерфейса

public enum RouteFormat {
    /// «850 м» или «3.4 км»
    public static func distance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters.rounded())) м"
        }
        return String(format: "%.1f км", meters / 1000)
    }

    /// «12:31» или «1:05:09»
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// «42 %»
    public static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded())) %"
    }

    /// «85 мс»
    public static func latency(_ ms: Double) -> String {
        "\(Int(ms.rounded())) мс"
    }

    /// «12.5 Мбит/с»
    public static func speed(_ mbps: Double) -> String {
        String(format: "%.1f Мбит/с", mbps)
    }
}

// MARK: - Пример маршрута

/// Демонстрационный маршрут для пустого экрана: показывает, как выглядит карта, пока своих записей нет.
/// Данные выдуманы и в историю не попадают; в интерфейсе они всегда подписаны как пример.
public enum RouteDemo {
    public static func sample(startedAt: Date = Date(timeIntervalSince1970: 1_760_000_000)) -> RouteRecord {
        var points: [RoutePoint] = []
        let steps = 72
        for index in 0..<steps {
            let time = startedAt.addingTimeInterval(Double(index) * 5)
            // С северо-запада на юго-восток: метка «Старт» не попадает в левый нижний угол карты,
            // где Apple рисует свой значок и ссылку «Правовые документы», и подпись не налезает на них
            let latitude = 55.7749 - Double(index) * 0.00035
            let longitude = 37.6000 + Double(index) * 0.00060

            let reachable: Bool
            let latency: Double?
            let link: LinkKind
            var download: Double?

            switch index {
            case 0..<24:
                reachable = true
                latency = 35 + Double(index % 5) * 5
                link = .lte
                if index % 6 == 0 { download = 25 }
            case 24..<40:
                reachable = true
                latency = 160 + Double(index % 4) * 30
                link = .lte
                if index % 6 == 0 { download = 6 }
            case 40..<46:
                reachable = false
                latency = nil
                link = .offline
            case 46..<52:
                reachable = true
                latency = 350 + Double(index % 3) * 40
                link = .g3
                if index % 6 == 0 { download = 0.8 }
            default:
                reachable = true
                latency = 40 + Double(index % 6) * 6
                link = .lte
                if index % 6 == 0 { download = 30 }
            }

            points.append(RoutePoint(
                time: time,
                latitude: latitude,
                longitude: longitude,
                accuracy: 8,
                speedMps: 11,
                latencyMs: latency,
                reachable: reachable,
                link: link,
                downloadMbps: download
            ))
        }
        return RouteRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000DE70") ?? UUID(),
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(Double(steps) * 5),
            points: points,
            interrupted: false,
            measuredSpeed: true
        )
    }
}
