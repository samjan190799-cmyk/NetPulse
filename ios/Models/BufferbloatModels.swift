//
//  BufferbloatModels.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import Foundation

/// Международный грейд качества Bufferbloat (RFC 8290).
///
/// Границы по росту задержки под нагрузкой (максимум из скачивания и отдачи):
/// A+ < 5 мс, A < 15 мс, B < 40 мс, C < 90 мс, D < 180 мс, F ≥ 180 мс.
public enum BufferbloatGrade: String, CaseIterable, Codable, Sendable {
    case aPlus = "A+"
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case f = "F"

    /// Грейд по росту задержки (мс)
    public static func grade(forDelta delta: Double) -> BufferbloatGrade {
        switch delta {
        case ..<5.0: return .aPlus
        case ..<15.0: return .a
        case ..<40.0: return .b
        case ..<90.0: return .c
        case ..<180.0: return .d
        default: return .f
        }
    }

    /// Грейд на ступень хуже (потери проб под нагрузкой — признак переполненной очереди)
    public func downgraded() -> BufferbloatGrade {
        switch self {
        case .aPlus: return .a
        case .a: return .b
        case .b: return .c
        case .c: return .d
        case .d, .f: return .f
        }
    }

    public var title: String {
        switch self {
        case .aPlus: return "Идеально (Киберспорт / 4K Стриминг)"
        case .a: return "Отлично (Минимальная буферизация)"
        case .b: return "Хорошо (Заметно при одновременной загрузке)"
        case .c: return "Умеренно (Задержки при скачивании)"
        case .d: return "Плохо (Высокий рост задержки под нагрузкой)"
        case .f: return "Критично (Сеть захлебывается при любом трафике)"
        }
    }

    public var badgeColor: Color {
        switch self {
        case .aPlus: return .green
        case .a: return .mint
        case .b: return .blue
        case .c: return .yellow
        case .d: return .orange
        case .f: return .red
        }
    }

    public var descriptionText: String {
        switch self {
        case .aPlus:
            return "Задержка под нагрузкой почти не растёт (меньше +5 мс). При скачивании больших файлов онлайн-игры и видеозвонки не испытывают задержек."
        case .a:
            return "Небольшой рост задержки (+5..15 мс). Соединение стабильно даже при активном фоновом потреблении трафика."
        case .b:
            return "Рост задержки составляет +15..40 мс. Если канал домашний, стоит включить SQM (Smart Queue Management) на роутере."
        case .c:
            return "Рост задержки +40..90 мс. Игры и FaceTime будут лагать, если кто-то дома смотрит 4K-видео или качает большие файлы."
        case .d:
            return "Рост задержки +90..180 мс. Очереди пакетов переполняются, вызывая скачки пинга и потерю пакетов."
        case .f:
            return "Рост задержки больше +180 мс. Очереди критически перегружены: под нагрузкой канал практически непригоден для игр и звонков."
        }
    }
}

/// Текущая фаза тестирования Bufferbloat
public enum BufferbloatPhase: String, CaseIterable, Codable, Sendable {
    case idle = "Готов к запуску"
    case unloadedLatency = "1. Замер ненагруженной задержки (Idle RTT)"
    case downloadSaturation = "2. Стресс-тест скачивания (Download Saturation)"
    case uploadSaturation = "3. Стресс-тест отдачи (Upload Saturation)"
    case completed = "Тестирование завершено"

    public var icon: String {
        switch self {
        case .idle: return "play.circle"
        case .unloadedLatency: return "speedometer"
        case .downloadSaturation: return "arrow.down.circle.fill"
        case .uploadSaturation: return "arrow.up.circle.fill"
        case .completed: return "checkmark.seal.fill"
        }
    }
}

/// Причины, по которым тест не дал результата
public enum BufferbloatError: Error, LocalizedError, Sendable, Equatable {
    /// Без нагрузки не получено ни одной успешной пробы — измерять не с чем
    case noConnection
    /// Тест остановлен пользователем (например, экран закрыт)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .noConnection:
            return "Не удалось измерить базовую задержку: опорный узел не отвечает. Проверьте подключение к интернету."
        case .cancelled:
            return "Тест остановлен."
        }
    }
}

/// Итоговый отчет замера Bufferbloat.
///
/// Если фазу нагрузки измерить не удалось, соответствующие значения равны `nil` (интерфейс показывает «—»):
/// раньше вместо них подставлялась ненагруженная задержка, и неудачный замер превращался в оценку «A+».
public struct BufferbloatReport: Identifiable, Codable, Sendable {
    /// Доля потерянных проб под нагрузкой, начиная с которой грейд понижается на ступень
    public static let lossPenaltyThresholdPercent: Double = 20.0

    public let id: UUID
    public let timestamp: Date
    public let unloadedPingMs: Double
    public let loadedDownloadPingMs: Double?
    public let loadedUploadPingMs: Double?
    public let downloadDeltaMs: Double?
    public let uploadDeltaMs: Double?
    public let maxDeltaMs: Double?
    /// `nil` — задержку под нагрузкой измерить не удалось ни в одной фазе
    public let grade: BufferbloatGrade?
    public let downloadSpeedMbps: Double?
    public let uploadSpeedMbps: Double?
    public let downloadLossPercent: Double?
    public let uploadLossPercent: Double?
    /// Пояснения к результату: что не удалось измерить и насколько результат надёжен
    public let notes: [String]
    public let recommendations: [String]

    public var dynamicVerdictTitle: String {
        guard let grade else {
            return "Недостаточно данных для оценки"
        }
        if (grade == .aPlus || grade == .a) && unloadedPingMs > 75.0 {
            return "Буферизация низкая (\(grade.rawValue)), высокий базовый RTT"
        }
        return grade.title
    }

    public var dynamicVerdictDescription: String {
        guard let grade else {
            return notes.first ?? "Не удалось измерить задержку под нагрузкой. Повторите тест позже."
        }
        if (grade == .aPlus || grade == .a) && unloadedPingMs > 75.0 {
            let delta = Int((maxDeltaMs ?? 0).rounded())
            return "Очереди не переполняются под нагрузкой (рост задержки +\(delta) мс). Однако базовая задержка (\(Int(unloadedPingMs)) мс) высока для соревновательных онлайн-игр."
        }
        return grade.descriptionText
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        unloadedPingMs: Double,
        loadedDownloadPingMs: Double?,
        loadedUploadPingMs: Double?,
        downloadSpeedMbps: Double? = nil,
        uploadSpeedMbps: Double? = nil,
        downloadLossPercent: Double? = nil,
        uploadLossPercent: Double? = nil,
        notes: [String] = [],
        recommendations: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.unloadedPingMs = unloadedPingMs
        self.loadedDownloadPingMs = loadedDownloadPingMs
        self.loadedUploadPingMs = loadedUploadPingMs

        let downloadDelta = loadedDownloadPingMs.map { max(0, $0 - unloadedPingMs) }
        let uploadDelta = loadedUploadPingMs.map { max(0, $0 - unloadedPingMs) }
        self.downloadDeltaMs = downloadDelta
        self.uploadDeltaMs = uploadDelta

        let measuredDeltas = [downloadDelta, uploadDelta].compactMap { $0 }
        let maxDelta = measuredDeltas.max()
        self.maxDeltaMs = maxDelta

        if let maxDelta {
            var computed = BufferbloatGrade.grade(forDelta: maxDelta)
            let worstLoss = max(downloadLossPercent ?? 0, uploadLossPercent ?? 0)
            if worstLoss >= Self.lossPenaltyThresholdPercent {
                computed = computed.downgraded()
            }
            self.grade = computed
        } else {
            self.grade = nil
        }

        self.downloadSpeedMbps = downloadSpeedMbps
        self.uploadSpeedMbps = uploadSpeedMbps
        self.downloadLossPercent = downloadLossPercent
        self.uploadLossPercent = uploadLossPercent
        self.notes = notes
        self.recommendations = recommendations
    }
}
