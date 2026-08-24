//
//  BufferbloatModels.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import Foundation

/// Международный грейд качества Bufferbloat (RFC 8290)
public enum BufferbloatGrade: String, CaseIterable, Codable, Sendable {
    case aPlus = "A+"
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case f = "F"

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
            return "Ваш роутер и канал связи работают превосходно. При скачивании больших файлов онлайн-игры и видеозвонки не испытывают задержек."
        case .a:
            return "Незначительный рост задержки (+0..10 мс). Соединение стабильно даже при активном фоновом потреблении трафика."
        case .b:
            return "Рост задержки составляет +10..30 мс. Рекомендуется включить SQM (Smart Queue Management) на Wi-Fi роутере."
        case .c:
            return "Рост задержки +30..80 мс. Игры и FaceTime будут лагать, если кто-то дома смотрит 4K-видео или качает торренты."
        case .d:
            return "Рост задержки +80..180 мс. Буферы пакетов на роутере переполняются, вызывая скачки пинга и потерю пакетов."
        case .f:
            return "Рост задержки >180 мс. Роутер критически перегружен. Требуется обновление прошивки или замена оборудования."
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

/// Итоговый отчет замера Bufferbloat
public struct BufferbloatReport: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let unloadedPingMs: Double
    public let loadedDownloadPingMs: Double
    public let loadedUploadPingMs: Double
    public let downloadDeltaMs: Double
    public let uploadDeltaMs: Double
    public let maxDeltaMs: Double
    public let grade: BufferbloatGrade
    public let downloadSpeedMbps: Double
    public let uploadSpeedMbps: Double
    public let recommendations: [String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        unloadedPingMs: Double,
        loadedDownloadPingMs: Double,
        loadedUploadPingMs: Double,
        downloadSpeedMbps: Double = 0.0,
        uploadSpeedMbps: Double = 0.0,
        recommendations: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.unloadedPingMs = unloadedPingMs
        self.loadedDownloadPingMs = loadedDownloadPingMs
        self.loadedUploadPingMs = loadedUploadPingMs
        self.downloadDeltaMs = max(0, loadedDownloadPingMs - unloadedPingMs)
        self.uploadDeltaMs = max(0, loadedUploadPingMs - unloadedPingMs)
        let maxD = max(self.downloadDeltaMs, self.uploadDeltaMs)
        self.maxDeltaMs = maxD

        if maxD < 5.0 {
            self.grade = .aPlus
        } else if maxD < 15.0 {
            self.grade = .a
        } else if maxD < 40.0 {
            self.grade = .b
        } else if maxD < 90.0 {
            self.grade = .c
        } else if maxD < 180.0 {
            self.grade = .d
        } else {
            self.grade = .f
        }

        self.downloadSpeedMbps = downloadSpeedMbps
        self.uploadSpeedMbps = uploadSpeedMbps
        self.recommendations = recommendations
    }
}
