//
//  SpeedtestEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Асинхронный движок замера пропускной способности (Bandwidth & Speedtest) для iOS.
public actor SpeedtestEngine {
    private let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=10000000")! // 10 MB payload
    private let uploadURL = URL(string: "https://speed.cloudflare.com/__up")!

    public init() {}

    /// Запуск полного цикла тестирования скорости
    public func runSpeedtest(
        progressHandler: (@Sendable (Double, Double) -> Void)? = nil
    ) async throws -> SpeedtestResult {
        let startTime = ContinuousClock().now

        // 1. Замер скачивания (Download)
        let downloadSpeed = try await measureDownload { currentMbps in
            progressHandler?(currentMbps, 0.0)
        }

        // 2. Замер отдачи (Upload)
        let uploadSpeed = try await measureUpload { currentMbps in
            progressHandler?(downloadSpeed, currentMbps)
        }

        let elapsed = ContinuousClock().now - startTime
        let durationSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000.0

        return SpeedtestResult(
            downloadMbps: downloadSpeed,
            uploadMbps: uploadSpeed,
            serverName: "Cloudflare CDN Edge",
            durationSeconds: (durationSeconds * 10).rounded() / 10,
            isSuccess: downloadSpeed > 0
        )
    }

    /// Замер скорости скачивания
    public func measureDownload(
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Double {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10.0
        let session = URLSession(configuration: configuration)

        let clock = ContinuousClock()
        let start = clock.now
        var totalBytes = 0

        let (asyncBytes, response) = try await session.bytes(from: downloadURL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return 0.0
        }

        for try await byte in asyncBytes {
            totalBytes += 1
            if totalBytes % (128 * 1024) == 0 {
                let elapsed = clock.now - start
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000.0
                if seconds > 0.1 {
                    let currentMbps = (Double(totalBytes) * 8.0) / (seconds * 1_000_000.0)
                    onProgress?((currentMbps * 10).rounded() / 10)
                }
            }
        }

        let elapsed = clock.now - start
        let totalSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000.0
        guard totalSeconds > 0 else { return 0.0 }

        let mbps = (Double(totalBytes) * 8.0) / (totalSeconds * 1_000_000.0)
        return (mbps * 10).rounded() / 10
    }

    /// Замер скорости отдачи
    public func measureUpload(
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Double {
        let payloadSize = 3 * 1024 * 1024 // 3 MB
        var payload = Data(count: payloadSize)
        _ = payload.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, payloadSize, $0.baseAddress!) }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10.0
        let session = URLSession(configuration: configuration)

        let clock = ContinuousClock()
        let start = clock.now

        let (_, response) = try await session.upload(for: request, from: payload)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return 0.0
        }

        let elapsed = clock.now - start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000.0
        guard seconds > 0 else { return 0.0 }

        let mbps = (Double(payloadSize) * 8.0) / (seconds * 1_000_000.0)
        let rounded = (mbps * 10).rounded() / 10
        onProgress?(rounded)
        return rounded
    }
}
