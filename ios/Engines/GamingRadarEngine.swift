//
//  GamingRadarEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / Network.framework) - 2026.
//

import Foundation
import Network

/// Асинхронный движок параллельного замера задержки до региональных узлов (AWS).
public actor GamingRadarEngine {
    public static let shared = GamingRadarEngine()

    /// Число учитываемых замеров на регион
    private static let samplesPerRegion = 5
    /// Таймаут одного соединения
    private static let timeoutSeconds: Double = 1.5

    public init() {}

    /// Параллельный замер всех региональных узлов
    public func scanRegions(
        regions: [GameClusterInfo] = GameClusterInfo.referenceRegions,
        onProgress: (@Sendable (GameClusterResult) -> Void)? = nil
    ) async -> [GameClusterResult] {
        var results: [GameClusterResult] = []

        await withTaskGroup(of: GameClusterResult.self) { group in
            for region in regions {
                group.addTask {
                    await self.pingRegion(region)
                }
            }

            for await result in group {
                results.append(result)
                onProgress?(result)
            }
        }

        return results.sorted { a, b in
            if a.isReachable != b.isReachable { return a.isReachable }
            return (a.latencyMs ?? .infinity) < (b.latencyMs ?? .infinity)
        }
    }

    /// Замер одного регионального узла
    public func pingRegion(_ region: GameClusterInfo) async -> GameClusterResult {
        // Прогревочное соединение не учитывается: оно включает разрешение DNS-имени и маршрут,
        // а замер должен показывать задержку сети, а не скорость DNS
        _ = await Self.measureConnectLatency(host: region.targetHost, port: region.port)

        var latencies: [Double] = []
        for _ in 0..<Self.samplesPerRegion {
            if Task.isCancelled { break }
            if let latency = await Self.measureConnectLatency(host: region.targetHost, port: region.port) {
                latencies.append(latency)
            }
        }

        guard !latencies.isEmpty else {
            return GameClusterResult(
                cluster: region,
                latencyMs: nil,
                jitterMs: nil,
                packetLossPct: 100.0,
                isReachable: false,
                isTested: true
            )
        }

        let sorted = latencies.sorted()
        let middle = sorted.count / 2
        let median = sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2.0 : sorted[middle]

        // Джиттер — средняя абсолютная разница соседних замеров (раньше считалась разность максимума и минимума)
        var jitter: Double?
        if latencies.count > 1 {
            var differences = 0.0
            for index in 1..<latencies.count {
                differences += abs(latencies[index] - latencies[index - 1])
            }
            jitter = differences / Double(latencies.count - 1)
        }

        let lostCount = Self.samplesPerRegion - latencies.count
        return GameClusterResult(
            cluster: region,
            latencyMs: (median * 10).rounded() / 10,
            jitterMs: jitter.map { ($0 * 10).rounded() / 10 },
            packetLossPct: Double(lostCount) / Double(Self.samplesPerRegion) * 100.0,
            isReachable: true,
            isTested: true
        )
    }

    private static func measureConnectLatency(host: String, port: UInt16) async -> Double? {
        await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port) ?? .https
            )

            let params = NWParameters.tcp
            params.preferNoProxies = true

            let connection = NWConnection(to: endpoint, using: params)
            let queue = DispatchQueue(label: "com.samvel.netpulse.gaming.\(host)", qos: .userInteractive)
            let start = ContinuousClock().now

            let box = SafeContinuationBox<Double?>(continuation)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = ContinuousClock().now - start
                    let milliseconds = Double(elapsed.components.seconds) * 1000.0
                        + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0
                    connection.cancel()
                    box.resumeOnce((milliseconds * 10).rounded() / 10)
                case .failed, .cancelled:
                    box.resumeOnce(nil)
                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                connection.cancel()
                box.resumeOnce(nil)
            }
        }
    }
}
