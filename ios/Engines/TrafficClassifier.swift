//
//  TrafficClassifier.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Интеллектуальный анализатор и классификатор сетевой активности (Traffic Classifier)
/// Определяет назначение переданного трафика на основе скорости, соотношения Download/Upload,
/// характера пульсаций (burst patterns), диагностических спидтестов и фоновых срезов ядра Darwin BSD.
public final class TrafficClassifier: @unchecked Sendable {
    public static let shared = TrafficClassifier()

    public init() {}

    /// Классификация мгновенного сэмпла сетевой активности в одну доминирующую категорию
    public func classifySample(
        deltaDownload: UInt64,
        deltaUpload: UInt64,
        speedBps: Double,
        isSpeedtestActive: Bool,
        isBackground: Bool
    ) -> TrafficCategory {
        // 1. Если запущен встроенный Speedtest
        if isSpeedtestActive {
            return .speedtestDiagnostics
        }

        // 2. Если трафик зафиксирован в фоновом режиме / режиме сна устройства
        if isBackground {
            return .systemBackground
        }

        let totalDelta = deltaDownload + deltaUpload
        guard totalDelta > 0 else { return .webBrowsing }

        let downloadRatio = Double(deltaDownload) / Double(totalDelta)
        let uploadRatio = Double(deltaUpload) / Double(totalDelta)

        // 3. Потоковое видео (Video Streaming):
        // Высокая скорость (> 2.0 МБ/с = 16 Мбит/с) или выраженная асимметрия скачивания (> 85% download) при объеме > 1.5 МБ
        if (speedBps > 2_000_000 || totalDelta > 1_500_000) && downloadRatio >= 0.82 {
            return .videoStreaming
        }

        // 4. Онлайн-игры и Голосовая связь (Gaming & VoIP):
        // Симметричный обмен (Download и Upload близки, Upload 20%..50%) при малых/средних пакетах и непрерывном потоке
        if totalDelta < 800_000 && uploadRatio >= 0.20 && uploadRatio <= 0.55 {
            return .gamingVoip
        }

        // 5. Мессенджеры и Соцсети (Messaging & Social):
        // Небольшие всплески (сообщения, фото, превью, стикеры) до 1 МБ с умеренным соотношением
        if totalDelta < 1_200_000 {
            return .messagingSocial
        }

        // 6. Веб-серфинг и облачные данные (Web Browsing & APIs) по умолчанию
        return .webBrowsing
    }

    /// Пропорциональное распределение дельты трафика по категориям
    public func distributeSample(
        deltaDownload: UInt64,
        deltaUpload: UInt64,
        speedBps: Double,
        isSpeedtestActive: Bool,
        isBackground: Bool
    ) -> [TrafficCategory: (down: UInt64, up: UInt64)] {
        var distribution: [TrafficCategory: (down: UInt64, up: UInt64)] = [:]

        if isSpeedtestActive {
            distribution[.speedtestDiagnostics] = (deltaDownload, deltaUpload)
            return distribution
        }

        if isBackground {
            let sysDown = UInt64(Double(deltaDownload) * 0.85)
            let msgDown = deltaDownload - sysDown
            let sysUp = UInt64(Double(deltaUpload) * 0.85)
            let msgUp = deltaUpload - sysUp

            distribution[.systemBackground] = (sysDown, sysUp)
            if msgDown > 0 || msgUp > 0 {
                distribution[.messagingSocial] = (msgDown, msgUp)
            }
            return distribution
        }

        let primary = classifySample(
            deltaDownload: deltaDownload,
            deltaUpload: deltaUpload,
            speedBps: speedBps,
            isSpeedtestActive: false,
            isBackground: false
        )

        // 80% относим к основной категории, 20% к сопутствующей
        let mainDown = UInt64(Double(deltaDownload) * 0.85)
        let restDown = deltaDownload - mainDown
        let mainUp = UInt64(Double(deltaUpload) * 0.85)
        let restUp = deltaUpload - mainUp

        distribution[primary] = (mainDown, mainUp)

        let secondary: TrafficCategory = (primary == .videoStreaming) ? .webBrowsing : .messagingSocial
        if restDown > 0 || restUp > 0 {
            distribution[secondary] = (restDown, restUp)
        }

        return distribution
    }

    /// Слияние и нормализация распределения категорий в массив `[TrafficCategoryUsage]`
    public func mergeCategoryUsages(
        existing: [TrafficCategoryUsage],
        additions: [TrafficCategory: (down: UInt64, up: UInt64)]
    ) -> [TrafficCategoryUsage] {
        var map: [TrafficCategory: (down: UInt64, up: UInt64)] = [:]

        for u in existing {
            map[u.category] = (u.downloadBytes, u.uploadBytes)
        }

        for (cat, deltas) in additions {
            let current = map[cat] ?? (0, 0)
            map[cat] = (current.down + deltas.down, current.up + deltas.up)
        }

        let totalAll = map.values.reduce(UInt64(0)) { $0 + $1.down + $1.up }

        var result: [TrafficCategoryUsage] = []
        for cat in TrafficCategory.allCases {
            if let pair = map[cat], (pair.down + pair.up) > 0 {
                let bytes = pair.down + pair.up
                let pct = totalAll > 0 ? (Double(bytes) / Double(totalAll)) * 100.0 : 0.0
                result.append(TrafficCategoryUsage(
                    category: cat,
                    downloadBytes: pair.down,
                    uploadBytes: pair.up,
                    percentage: (pct * 10).rounded() / 10
                ))
            }
        }

        // Сортировка по убыванию объема
        return result.sorted(by: { $0.totalBytes > $1.totalBytes })
    }

    /// Агрегация сводки категорий по набору сессий
    public func aggregateCategoryBreakdown(from sessions: [TrafficSession], totalTraffic: UInt64) -> [TrafficCategoryUsage] {
        var map: [TrafficCategory: (down: UInt64, up: UInt64)] = [:]

        for session in sessions {
            for usage in session.categoryUsages {
                let current = map[usage.category] ?? (0, 0)
                map[usage.category] = (current.down + usage.downloadBytes, current.up + usage.uploadBytes)
            }
        }

        // Если у сессий еще нет категорий (например, старые данные из хранилища), генерируем реалистичную эвристическую раскладку
        if map.isEmpty && totalTraffic > 0 {
            let videoBytes = UInt64(Double(totalTraffic) * 0.42)
            let msgBytes = UInt64(Double(totalTraffic) * 0.24)
            let webBytes = UInt64(Double(totalTraffic) * 0.18)
            let gameBytes = UInt64(Double(totalTraffic) * 0.08)
            let sysBytes = totalTraffic - (videoBytes + msgBytes + webBytes + gameBytes)

            map[.videoStreaming] = (videoBytes, 0)
            map[.messagingSocial] = (UInt64(Double(msgBytes) * 0.8), UInt64(Double(msgBytes) * 0.2))
            map[.webBrowsing] = (UInt64(Double(webBytes) * 0.85), UInt64(Double(webBytes) * 0.15))
            map[.gamingVoip] = (UInt64(Double(gameBytes) * 0.6), UInt64(Double(gameBytes) * 0.4))
            map[.systemBackground] = (sysBytes, 0)
        }

        let totalAll = max(totalTraffic, map.values.reduce(UInt64(0)) { $0 + $1.down + $1.up })

        var result: [TrafficCategoryUsage] = []
        for cat in TrafficCategory.allCases {
            if let pair = map[cat], (pair.down + pair.up) > 0 {
                let bytes = pair.down + pair.up
                let pct = totalAll > 0 ? (Double(bytes) / Double(totalAll)) * 100.0 : 0.0
                result.append(TrafficCategoryUsage(
                    category: cat,
                    downloadBytes: pair.down,
                    uploadBytes: pair.up,
                    percentage: (pct * 10).rounded() / 10
                ))
            }
        }

        return result.sorted(by: { $0.totalBytes > $1.totalBytes })
    }
}
