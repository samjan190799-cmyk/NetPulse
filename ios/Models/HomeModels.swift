//
//  HomeModels.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

// MARK: - Нижняя панель главного экрана

/// Положение нижней панели главного экрана: обычное (скорость и кнопки) или развёрнутое (маршруты, настройки записи)
public enum HomePanelDetent: Sendable, Equatable {
    case medium
    case expanded
}

/// Расчёты для жестов нижней панели. Вынесены из интерфейса, чтобы проверяться юнит-тестами.
public enum HomePanelLayout {
    /// На сколько пунктов нужно потянуть панель, чтобы она сменила положение
    public static let switchThreshold: Double = 70

    /// Положение панели после жеста. `predictedTranslation` — вертикальный сдвиг, на котором жест закончился бы
    /// по инерции: вверх — отрицательный, вниз — положительный. Короткий жест оставляет панель на месте.
    public static func detent(from current: HomePanelDetent, predictedTranslation: Double) -> HomePanelDetent {
        if predictedTranslation <= -switchThreshold { return .expanded }
        if predictedTranslation >= switchThreshold { return .medium }
        return current
    }

    /// Высота панели во время жеста: исходная высота минус сдвиг пальца вниз, но не меньше `lower` и не больше `upper`
    public static func height(base: Double, translation: Double, lower: Double, upper: Double) -> Double {
        let ceiling = max(lower, upper)
        return min(max(base - translation, lower), ceiling)
    }
}

// MARK: - Связь сейчас

/// Оценка связи для плашки на карте
public enum HomeLinkStatus {
    /// Качество связи по пингу до узлов мониторинга. Без подключения — «нет сети»; `nil` — пинга ещё нет,
    /// и плашка не пишет «хорошо» наугад.
    public static func quality(isOnline: Bool, pingMs: Double?) -> RouteQuality? {
        guard isOnline else { return .dead }
        guard let pingMs else { return nil }
        return RouteQuality.byLatency(reachable: true, latencyMs: pingMs)
    }
}

extension RouteQuality {
    /// Заголовок карточки «Связь сейчас» во время записи маршрута
    public var liveTitle: String {
        switch self {
        case .good: return "Связь хорошая"
        case .fair: return "Связь средняя"
        case .poor: return "Связь плохая"
        case .dead: return "Нет связи"
        }
    }
}

// MARK: - На что хватает сети

/// Короткая сводка «Хватает для: 4K · игры · звонки» по оценке возможностей сети
public enum CapabilityTags {
    /// Метки для сценариев, где сеть справляется хорошо или отлично. Пусто — ни один сценарий не набрал нужной оценки.
    public static func summary(_ items: [CapabilityItem]) -> [String] {
        var tags: [String] = []
        for item in items where item.level == .excellent || item.level == .good {
            switch item.category {
            case "Медиа":
                tags.append(item.title.contains("4K") ? "4K" : "видео")
            case "Гейминг":
                tags.append("игры")
            case "Связь":
                tags.append("звонки")
            default:
                break
            }
        }
        return tags
    }
}

// MARK: - Подписи маршрута

/// Русское склонение существительного по числу: 1 место, 2 места, 5 мест
public enum RussianPlural {
    public static func form(_ number: Int, one: String, few: String, many: String) -> String {
        let n = abs(number) % 100
        let last = n % 10
        if n >= 11 && n <= 14 { return many }
        if last == 1 { return one }
        if last >= 2 && last <= 4 { return few }
        return many
    }
}

extension RouteFormat {
    /// «45 с», «2 мин 14 с», «1 ч 05 мин» — для фраз вроде «Без связи 2 мин 14 с»
    public static func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d ч %02d мин", hours, minutes)
        }
        if minutes > 0 {
            return secs == 0 ? "\(minutes) мин" : "\(minutes) мин \(secs) с"
        }
        return "\(secs) с"
    }
}

public enum RouteTitle {
    /// «Сегодня, 18:40 — 19:08», «Вчера, 09:15 — 09:40», «2 окт., 18:40 — 19:08»
    public static func dateRange(
        of route: RouteRecord,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "ru_RU")
    ) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "HH:mm"

        let day: String
        if calendar.isDate(route.startedAt, inSameDayAs: now) {
            day = "Сегодня"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(route.startedAt, inSameDayAs: yesterday) {
            day = "Вчера"
        } else {
            let dayFormatter = DateFormatter()
            dayFormatter.locale = locale
            dayFormatter.calendar = calendar
            dayFormatter.timeZone = calendar.timeZone
            dayFormatter.setLocalizedDateFormatFromTemplate("d MMM")
            day = dayFormatter.string(from: route.startedAt)
        }

        let start = timeFormatter.string(from: route.startedAt)
        guard let end = route.endedAt ?? route.points.last?.time, end > route.startedAt else {
            return "\(day), \(start)"
        }
        return "\(day), \(start) — \(timeFormatter.string(from: end))"
    }
}
