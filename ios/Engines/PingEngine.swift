//
//  PingEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import Network

/// Асинхронный многопоточный движок сетевого пинга для iOS.
public actor PingEngine {
    private let timeoutInterval: TimeInterval

    public init(timeout: TimeInterval = 2.0) {
        self.timeoutInterval = timeout
    }

    /// Проверка одиночного хоста через TCP Connect (Network.framework)
    public func pingTarget(_ target: HostTarget) async -> PingRecord {
        let hostStr = target.address
        guard hostStr != "gateway" && !hostStr.isEmpty else {
            return PingRecord(
                host: hostStr,
                targetName: target.name,
                isSuccess: false,
                errorMessage: "Шлюз еще не определен"
            )
        }

        let portNum = UInt16(target.tcpPort > 0 ? target.tcpPort : 443)
        let clock = ContinuousClock()
        let start = clock.now

        do {
            let latencyMs = try await withTimeout(seconds: timeoutInterval) {
                try await self.tcpConnect(host: hostStr, port: portNum)
            }
            return PingRecord(
                host: hostStr,
                targetName: target.name,
                isSuccess: true,
                latencyMs: latencyMs,
                protocolType: "tcp:\(portNum)"
            )
        } catch {
            let elapsed = clock.now - start
            return PingRecord(
                host: hostStr,
                targetName: target.name,
                isSuccess: false,
                latencyMs: nil,
                errorMessage: error.localizedDescription,
                protocolType: "tcp:\(portNum)"
            )
        }
    }

    /// Параллельный опрос группы целевых хостов
    public func pingAll(targets: [HostTarget]) async -> [PingRecord] {
        let active = targets.filter { $0.isEnabled }
        return await withTaskGroup(of: PingRecord.self, returning: [PingRecord].self) { group in
            for target in active {
                group.addTask {
                    await self.pingTarget(target)
                }
            }
            var results: [PingRecord] = []
            for await record in group {
                results.append(record)
            }
            return results
        }
    }

    // MARK: - Внутренняя реализация подключения

    private func tcpConnect(host: String, port: UInt16) async throws -> Double {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? .https
        )

        let params = NWParameters.tcp
        params.preferNoProxies = true

        let connection = NWConnection(to: endpoint, using: params)
        let clock = ContinuousClock()
        let startTime = clock.now

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            connection.stateUpdateHandler = { state in
                guard !hasResumed else { return }

                switch state {
                case .ready:
                    hasResumed = true
                    let duration = clock.now - startTime
                    let ms = Double(duration.components.attoseconds) / 1_000_000_000_000_000.0 + Double(duration.components.seconds) * 1000.0
                    connection.cancel()
                    continuation.resume(returning: (ms * 10).rounded() / 10)

                case .failed(let err):
                    hasResumed = true
                    connection.cancel()
                    continuation.resume(throwing: err)

                case .cancelled:
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: CancellationError())
                    }

                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw URLError(.timedOut)
            }

            guard let success = try await group.next() else {
                throw URLError(.cancelled)
            }
            group.cancelAll()
            return success
        }
    }
}
