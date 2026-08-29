//
//  GamingRadarEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / Network.framework) - 2026.
//

import Foundation
import Network

/// Асинхронный движок параллельного замера пинга до игровых кластеров
public actor GamingRadarEngine {
    public static let shared = GamingRadarEngine()

    public init() {}

    /// Параллельный опрос всех кластеров для выбранной игры
    public func scanGameClusters(
        for game: GameTitle,
        onProgress: (@Sendable (GameClusterResult) -> Void)? = nil
    ) async -> [GameClusterResult] {
        let clusters = GameClusterInfo.defaultClusters.filter { $0.game == game }
        var results: [GameClusterResult] = []

        await withTaskGroup(of: GameClusterResult.self) { group in
            for cluster in clusters {
                group.addTask {
                    await self.pingCluster(cluster)
                }
            }

            for await res in group {
                results.append(res)
                onProgress?(res)
            }
        }

        return results.sorted { (a, b) -> Bool in
            if a.isReachable && !b.isReachable { return true }
            if !a.isReachable && b.isReachable { return false }
            return (a.latencyMs ?? 9999.0) < (b.latencyMs ?? 9999.0)
        }
    }

    /// Замер одиночного игрового дата-центра
    public func pingCluster(_ cluster: GameClusterInfo) async -> GameClusterResult {
        var latencies: [Double] = []
        let attempts = 4

        for _ in 0..<attempts {
            if let lat = await measureConnectLatency(to: cluster.targetHost, port: cluster.port) {
                latencies.append(lat)
            }
        }

        if latencies.isEmpty {
            return GameClusterResult(
                cluster: cluster,
                latencyMs: nil,
                jitterMs: nil,
                packetLossPct: 100.0,
                isReachable: false
            )
        }

        let avg = latencies.reduce(0.0, +) / Double(latencies.count)
        let lossPct = (Double(attempts - latencies.count) / Double(attempts)) * 100.0
        let jitter: Double
        if latencies.count > 1, let maxL = latencies.max(), let minL = latencies.min() {
            jitter = abs(maxL - minL)
        } else {
            jitter = 0.0
        }

        return GameClusterResult(
            cluster: cluster,
            latencyMs: (avg * 10).rounded() / 10,
            jitterMs: (jitter * 10).rounded() / 10,
            packetLossPct: lossPct,
            isReachable: true
        )
    }

    private func measureConnectLatency(to host: String, port: UInt16) async -> Double? {
        await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port) ?? .https
            )

            let params = NWParameters.tcp
            params.prohibitExpensivePaths = false

            let connection = NWConnection(to: endpoint, using: params)
            let queue = DispatchQueue(label: "com.samjan.netpulse.gaming.\(host)", qos: .userInteractive)
            let startTime = Date()

            let box = SafeContinuationBox<Double?>(continuation)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = Date().timeIntervalSince(startTime) * 1000.0
                    connection.cancel()
                    box.resumeOnce((elapsed * 10).rounded() / 10)
                case .failed, .cancelled:
                    box.resumeOnce(nil)
                case .waiting:
                    break
                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + 1.5) {
                connection.cancel()
                box.resumeOnce(nil)
            }
        }
    }
}

/// Потокобезопасный бокс однократного возобновления Continuation
private final class SafeContinuationBox<T>: @unchecked Sendable {
    private var isResumed = false
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resumeOnce(_ value: T) {
        lock.lock()
        defer { lock.unlock() }
        if !isResumed {
            isResumed = true
            continuation?.resume(returning: value)
            continuation = nil
        }
    }
}
