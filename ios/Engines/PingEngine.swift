//
//  PingEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import Network

/// Потокобезопасная обертка для CheckedContinuation во избежание множественного возобновления
private final class SafeContinuation<T, E: Error>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, E>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<T, E>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        defer { lock.unlock() }
        continuation?.resume(returning: value)
        continuation = nil
    }

    func resume(throwing error: E) {
        lock.lock()
        defer { lock.unlock() }
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

/// Асинхронный многопоточный движок сетевого пинга для iOS.
public actor PingEngine {
    private let timeoutInterval: TimeInterval

    public init(timeout: TimeInterval = 2.0) {
        self.timeoutInterval = timeout
    }

    /// Проверка одиночного хоста через TCP Connect (Network.framework)
    public func pingTarget(_ target: HostTarget) async -> PingRecord {
        let hostStr: String
        if (target.address == "gateway" || target.address.isEmpty) && target.isGateway {
            hostStr = "192.168.1.1"
        } else {
            hostStr = target.address
        }

        guard !hostStr.isEmpty else {
            return PingRecord(
                host: hostStr,
                targetName: target.name,
                isSuccess: false,
                errorMessage: "Хост не указан"
            )
        }

        // Для локального шлюза проверяем несколько стандартных портов (DNS, HTTPS, HTTP)
        let portsToTry: [UInt16] = target.isGateway ? [53, 443, 80, 8080] : [UInt16(target.tcpPort > 0 ? target.tcpPort : 443)]

        for portNum in portsToTry {
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
                let elapsedMs = Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0 + Double(elapsed.components.seconds) * 1000.0

                // Если шлюз отклонил порт (Connection Refused / RST), но ответил за <500мс — узел онлайн!
                let errStr = error.localizedDescription.lowercased()
                if target.isGateway && (errStr.contains("refused") || errStr.contains("61") || errStr.contains("reset")) && elapsedMs < 500 {
                    return PingRecord(
                        host: hostStr,
                        targetName: target.name,
                        isSuccess: true,
                        latencyMs: max(1.0, (elapsedMs * 10).rounded() / 10),
                        protocolType: "tcp:rst:\(portNum)"
                    )
                }
            }
        }

        return PingRecord(
            host: hostStr,
            targetName: target.name,
            isSuccess: false,
            latencyMs: nil,
            errorMessage: "Таймаут ответа",
            protocolType: "tcp:\(target.tcpPort)"
        )
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

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let safeContinuation = SafeContinuation(continuation)

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        let duration = clock.now - startTime
                        let ms = Double(duration.components.attoseconds) / 1_000_000_000_000_000.0 + Double(duration.components.seconds) * 1000.0
                        connection.cancel()
                        safeContinuation.resume(returning: (ms * 10).rounded() / 10)

                    case .failed(let err):
                        connection.cancel()
                        safeContinuation.resume(throwing: err)

                    case .cancelled:
                        safeContinuation.resume(throwing: CancellationError())

                    default:
                        break
                    }
                }

                connection.start(queue: .global(qos: .userInitiated))
            }
        } onCancel: {
            connection.cancel()
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
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "NetPulsePing", code: -1001, userInfo: [NSLocalizedDescriptionKey: "Таймаут соединения"])
            }

            guard let result = try await group.next() else {
                throw NSError(domain: "NetPulsePing", code: -1001, userInfo: [NSLocalizedDescriptionKey: "Ошибка выполнения"])
            }

            group.cancelAll()
            return result
        }
    }
}
