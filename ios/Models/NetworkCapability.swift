//
//  NetworkCapability.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import SwiftUI

/// Статус качества конкретного сценария использования сети
public enum CapabilityLevel: String, Sendable {
    case excellent = "Отлично"
    case good = "Хорошо"
    case moderate = "Приемлемо"
    case poor = "Ограниченно"
    case unknown = "Требуется замер"

    public var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .blue
        case .moderate: return .orange
        case .poor: return .red
        case .unknown: return .secondary
        }
    }

    public var systemIcon: String {
        switch self {
        case .excellent: return "checkmark.seal.fill"
        case .good: return "checkmark.circle.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .poor: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// Элемент оценки возможностей подключения
public struct CapabilityItem: Identifiable, Sendable {
    public var id: String { title }
    public let title: String
    public let category: String
    public let icon: String
    public let level: CapabilityLevel
    public let description: String
    public let detail: String
}

/// Анализатор пригодности сети для реальных задач (Стриминг, Игры, Звонки, Загрузка)
public struct NetworkCapabilityEvaluator: Sendable {
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let pingMs: Double?
    public let jitterMs: Double?

    public init(
        downloadMbps: Double,
        uploadMbps: Double,
        pingMs: Double?,
        jitterMs: Double?
    ) {
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.pingMs = pingMs
        self.jitterMs = jitterMs
    }

    /// Сгенерировать список оценок по категориям
    public func evaluateAll() -> [CapabilityItem] {
        guard downloadMbps > 0 else {
            return defaultEmptyCapabilities()
        }

        return [
            evaluateStreaming(),
            evaluateGaming(),
            evaluateVideoConferencing(),
            evaluateFileTransfer()
        ]
    }

    // 1. Видео и Стриминг (Netflix, YouTube, Кинопоиск)
    private func evaluateStreaming() -> CapabilityItem {
        if downloadMbps >= 100 {
            return CapabilityItem(
                title: "Стриминг 4K / 8K Ultra HD",
                category: "Медиа",
                icon: "play.tv.fill",
                level: .excellent,
                description: "Идеально для нескольких 4K потоков без буферизации",
                detail: "Поддержка HDR, Dolby Vision и 8K видео на всех устройствах в сети"
            )
        } else if downloadMbps >= 25 {
            return CapabilityItem(
                title: "Стриминг 4K Ultra HD",
                category: "Медиа",
                icon: "play.tv.fill",
                level: .good,
                description: "Стабильное воспроизведение 4K на 1-2 экранах",
                detail: "Быстрый старт видео высокой четкости без задержек"
            )
        } else if downloadMbps >= 10 {
            return CapabilityItem(
                title: "Стриминг Full HD (1080p)",
                category: "Медиа",
                icon: "tv",
                level: .moderate,
                description: "Комфортный просмотр Full HD 1080p",
                detail: "4K может потребовать предварительной буферизации"
            )
        } else {
            return CapabilityItem(
                title: "Стриминг SD / 720p",
                category: "Медиа",
                icon: "tv",
                level: .poor,
                description: "Базовое качество видео (720p/480p)",
                detail: "Возможны паузы при воспроизведении тяжелых видео"
            )
        }
    }

    // 2. Онлайн-игры и Cloud Gaming (CS, Dota, Warzone, GeForce NOW)
    private func evaluateGaming() -> CapabilityItem {
        let ping = pingMs ?? 50.0
        let jitter = jitterMs ?? 5.0

        if ping < 25 && jitter < 5 {
            return CapabilityItem(
                title: "Онлайн-игры и Cloud Gaming",
                category: "Гейминг",
                icon: "gamecontroller.fill",
                level: .excellent,
                description: "Идеальный мгновенный отклик для киберспорта",
                detail: "Минимальный пинг (\(Int(ping)) мс). Облачный гейминг (GeForce NOW, PS Plus) без задержки"
            )
        } else if ping < 55 && jitter < 15 {
            return CapabilityItem(
                title: "Онлайн-игры (Шутеры / MMO)",
                category: "Гейминг",
                icon: "gamecontroller.fill",
                level: .good,
                description: "Плавный геймплей без ощутимых лагов",
                detail: "Комфортный пинг (\(Int(ping)) мс) для большинства сетевых игр"
            )
        } else if ping < 110 {
            return CapabilityItem(
                title: "Сетевые игры",
                category: "Гейминг",
                icon: "gamecontroller",
                level: .moderate,
                description: "Приемлемо для казуальных и пошаговых игр",
                detail: "Задержка (\(Int(ping)) мс) может ощущаться в динамичных шутерах"
            )
        } else {
            return CapabilityItem(
                title: "Онлайн-игры",
                category: "Гейминг",
                icon: "gamecontroller",
                level: .poor,
                description: "Высокая задержка и рассинхронизация",
                detail: "Высокий пинг (\(Int(ping)) мс) затрудняет онлайн-матчи"
            )
        }
    }

    // 3. Видеозвонки и Конференции (Zoom, FaceTime HD, Teams, Telegram)
    private func evaluateVideoConferencing() -> CapabilityItem {
        let upload = uploadMbps > 0 ? uploadMbps : downloadMbps * 0.3
        let jitter = jitterMs ?? 5.0

        if upload >= 15 && jitter < 10 {
            return CapabilityItem(
                title: "Конференции (Zoom, FaceTime HD)",
                category: "Связь",
                icon: "video.fill",
                level: .excellent,
                description: "Кристально четкое HD видео и объемный звук",
                detail: "Идеальная стабильность для групповых звонков и демонстрации экрана 4K"
            )
        } else if upload >= 5 && jitter < 25 {
            return CapabilityItem(
                title: "Видеосвязь 1080p",
                category: "Связь",
                icon: "video.fill",
                level: .good,
                description: "Стабильные звонки высокой четкости",
                detail: "Без заиканий звука и выпадения кадров"
            )
        } else if upload >= 2 {
            return CapabilityItem(
                title: "Видеозвонки 720p",
                category: "Связь",
                icon: "video",
                level: .moderate,
                description: "Базовые видеозвонки",
                detail: "Возможно временное снижение качества картинки при слабом канале"
            )
        } else {
            return CapabilityItem(
                title: "Аудиозвонки и мессенджеры",
                category: "Связь",
                icon: "phone.fill",
                level: .poor,
                description: "Рекомендуется аудиосвязь",
                detail: "Низкая скорость отдачи (\(String(format: "%.1f", upload)) Мбит/с) для стабильного видео"
            )
        }
    }

    // 4. Загрузка и передача тяжелых файлов
    private func evaluateFileTransfer() -> CapabilityItem {
        let secondsFor1GB = (1024.0 * 8.0) / max(downloadMbps, 1.0)
        let timeStr1GB = formatDuration(secondsFor1GB)

        if downloadMbps >= 100 {
            return CapabilityItem(
                title: "Передача больших файлов",
                category: "Файлы",
                icon: "arrow.down.doc.fill",
                level: .excellent,
                description: "1 ГБ скачается за ~\(timeStr1GB)",
                detail: "10 ГБ игра или фильм скачается примерно за ~\(formatDuration(secondsFor1GB * 10))"
            )
        } else if downloadMbps >= 30 {
            return CapabilityItem(
                title: "Загрузка файлов",
                category: "Файлы",
                icon: "arrow.down.doc.fill",
                level: .good,
                description: "1 ГБ скачается за ~\(timeStr1GB)",
                detail: "Быстрая загрузка обновлений системы и тяжелых приложений"
            )
        } else {
            return CapabilityItem(
                title: "Загрузка файлов",
                category: "Файлы",
                icon: "arrow.down.doc",
                level: .moderate,
                description: "1 ГБ скачается за ~\(timeStr1GB)",
                detail: "Для больших файлов потребуется некоторое время"
            )
        }
    }

    private func defaultEmptyCapabilities() -> [CapabilityItem] {
        [
            CapabilityItem(
                title: "Стриминг 4K / 8K",
                category: "Медиа",
                icon: "play.tv",
                level: .unknown,
                description: "Запустите замер скорости",
                detail: "Тест покажет готовность канала для 4K/8K видео"
            ),
            CapabilityItem(
                title: "Онлайн-игры и Cloud Gaming",
                category: "Гейминг",
                icon: "gamecontroller",
                level: .unknown,
                description: "Запустите замер скорости",
                detail: "Оценка пинга для киберспорта и стриминга игр"
            ),
            CapabilityItem(
                title: "Конференции (Zoom, FaceTime)",
                category: "Связь",
                icon: "video",
                level: .unknown,
                description: "Запустите замер скорости",
                detail: "Оценка стабильности для рабочих видеозвонков"
            ),
            CapabilityItem(
                title: "Передача файлов (1 ГБ / 10 ГБ)",
                category: "Файлы",
                icon: "arrow.down.doc",
                level: .unknown,
                description: "Запустите замер скорости",
                detail: "Расчет точного времени скачивания файлов"
            )
        ]
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(max(1, Int(seconds))) сек"
        }
        let mins = Int(seconds / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        return "\(mins) мин \(secs) сек"
    }
}
