//
//  BufferbloatEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / Network.framework) - 2026.
//

import Foundation
import Network

/// Асинхронный движок 3-фазного стресс-тестирования задержки под нагрузкой (Bufferbloat SQM)
public actor BufferbloatEngine {
    public static let shared = BufferbloatEngine()

    private let pingEngine = PingEngine(timeout: 2.0)
    private let downloadTestURL = URL(string: "https://speed.cloudflare.com/__down?bytes=15000000")!
    private let uploadTestURL = URL(string: "https://speed.cloudflare.com/__up")!

    public init() {}

    /// Запуск полного цикла Bufferbloat-теста
    public func runBufferbloatTest(
        onPhaseChange: (@Sendable (BufferbloatPhase, Double) -> Void)? = nil
    ) async -> BufferbloatReport {
        // 1. Unloaded Latency
        onPhaseChange?(.unloadedLatency, 0.0)
        let unloadedPing = await measureAveragePing(target: "1.1.1.1", count: 5)
        onPhaseChange?(.unloadedLatency, unloadedPing)

        // 2. Download Saturation Latency
        onPhaseChange?(.downloadSaturation, unloadedPing)
        let (downloadSpeed, loadedDownloadPing) = await measureDownloadSaturationPing(basePing: unloadedPing)
        onPhaseChange?(.downloadSaturation, loadedDownloadPing)

        // 3. Upload Saturation Latency
        onPhaseChange?(.uploadSaturation, loadedDownloadPing)
        let (uploadSpeed, loadedUploadPing) = await measureUploadSaturationPing(basePing: unloadedPing)
        onPhaseChange?(.uploadSaturation, loadedUploadPing)

        // Генерация персональных рекомендаций
        var recommendations: [String] = []
        let delta = max(loadedDownloadPing - unloadedPing, loadedUploadPing - unloadedPing)

        if delta < 10.0 {
            if unloadedPing > 75.0 {
                recommendations.append("Очереди пакетов не переполняются (дельта +0 мс).")
                recommendations.append("Базовая задержка сотовой сети (\(Int(unloadedPing)) мс) обусловлена расстоянием до вышки LTE/5G.")
            } else {
                recommendations.append("Ваш канал идеально настроен. Дополнительные настройки не требуются.")
                recommendations.append("Роутер эффективно распределяет пакеты в очередях.")
            }
        } else if delta < 40.0 {
            recommendations.append("Рекомендуется включить аппаратный Hardware Offload на роутере.")
            recommendations.append("При использовании Wi-Fi перейдите на диапазон 5 GHz (80 MHz).")
        } else {
            recommendations.append("Включите алгоритм SQM (Cake / FQ_CoDel) в настройках вашего роутера (Keenetic, OpenWrt, ASUS).")
            recommendations.append("Ограничьте скорость в шейпере роутера на 90–95% от максимальной тарифной скорости провайдера.")
            recommendations.append("Замените устаревший Wi-Fi роутер на модель с поддержкой Wi-Fi 6 / 6E и многопоточным процессором.")
        }

        onPhaseChange?(.completed, loadedUploadPing)

        return BufferbloatReport(
            unloadedPingMs: (unloadedPing * 10).rounded() / 10,
            loadedDownloadPingMs: (loadedDownloadPing * 10).rounded() / 10,
            loadedUploadPingMs: (loadedUploadPing * 10).rounded() / 10,
            downloadSpeedMbps: (downloadSpeed * 10).rounded() / 10,
            uploadSpeedMbps: (uploadSpeed * 10).rounded() / 10,
            recommendations: recommendations
        )
    }

    private func measureAveragePing(target: String, count: Int) async -> Double {
        var values: [Double] = []
        for _ in 0..<count {
            let record = await pingEngine.pingTarget(HostTarget(name: target, address: target))
            if let lat = record.latencyMs {
                values.append(lat)
            }
        }
        guard !values.isEmpty else { return 25.0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func measureDownloadSaturationPing(basePing: Double) async -> (Double, Double) {
        let startTime = Date()
        var totalBytesDownloaded: Int64 = 0
        var loadedPings: [Double] = []

        // Фоновый поток скачивания
        let downloadTask = Task { () -> Int64 in
            do {
                let (data, _) = try await URLSession.shared.data(from: self.downloadTestURL)
                return Int64(data.count)
            } catch {
                return 0
            }
        }

        // Параллельный замер пинга во время скачивания
        for _ in 0..<4 {
            let record = await pingEngine.pingTarget(HostTarget(name: "1.1.1.1", address: "1.1.1.1"))
            if let lat = record.latencyMs, lat > 0 {
                loadedPings.append(lat)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        totalBytesDownloaded = await downloadTask.value
        let elapsed = max(Date().timeIntervalSince(startTime), 0.5)
        let speedMbps = totalBytesDownloaded > 0 ? (Double(totalBytesDownloaded * 8) / (elapsed * 1_000_000.0)) : 0.0

        let avgLoadedPing = loadedPings.isEmpty ? basePing : (loadedPings.reduce(0, +) / Double(loadedPings.count))
        return (speedMbps, avgLoadedPing)
    }

    private func measureUploadSaturationPing(basePing: Double) async -> (Double, Double) {
        let startTime = Date()
        var totalBytesUploaded: Int64 = 0
        var loadedPings: [Double] = []

        let dummyData = Data(count: 6_000_000)
        var request = URLRequest(url: uploadTestURL)
        request.httpMethod = "POST"

        let uploadTask = Task { () -> Int64 in
            do {
                let (_, response) = try await URLSession.shared.upload(for: request, from: dummyData)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    return Int64(dummyData.count)
                }
                return 0
            } catch {
                return 0
            }
        }

        for _ in 0..<4 {
            let record = await pingEngine.pingTarget(HostTarget(name: "1.1.1.1", address: "1.1.1.1"))
            if let lat = record.latencyMs, lat > 0 {
                loadedPings.append(lat)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        totalBytesUploaded = await uploadTask.value
        let elapsed = max(Date().timeIntervalSince(startTime), 0.5)
        let speedMbps = totalBytesUploaded > 0 ? (Double(totalBytesUploaded * 8) / (elapsed * 1_000_000.0)) : 0.0

        let avgLoadedPing = loadedPings.isEmpty ? basePing : (loadedPings.reduce(0, +) / Double(loadedPings.count))
        return (speedMbps, avgLoadedPing)
    }
}
