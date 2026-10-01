//
//  PingEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import Network

/// Потокобезопасная обертка для CheckedContinuation во избежание множественного возобновления
private final class SafeContinuation<T: Sendable, E: Error>: @unchecked Sendable {
    nonisolated(unsafe) private var continuation: CheckedContinuation<T, E>?
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

/// Результат TCP-проверки: задержка и признак «порт закрыт, но хост ответил RST».
private struct TCPProbeResult: Sendable {
    let latencyMs: Double
    let refused: Bool
}

/// Ошибка превышения времени ожидания (отличается от прочих сетевых ошибок текстом в записи).
private struct PingTimeoutError: Error {}

/// ECONNREFUSED / ECONNRESET: узел ответил (RST), то есть он доступен, просто порт закрыт.
/// Network.framework при ECONNREFUSED обычно не переходит в `.failed`, а остаётся в `.waiting` с POSIX-ошибкой.
private func isConnectionRefused(_ error: NWError) -> Bool {
    if case .posix(let code) = error {
        return code == .ECONNREFUSED || code == .ECONNRESET
    }
    return false
}

private func elapsedMilliseconds(_ duration: Duration) -> Double {
    Double(duration.components.attoseconds) / 1_000_000_000_000_000.0 + Double(duration.components.seconds) * 1000.0
}

/// Асинхронный многопоточный движок сетевого пинга для iOS.
public actor PingEngine {
    private let timeoutInterval: TimeInterval

    public init(timeout: TimeInterval = 2.0) {
        self.timeoutInterval = timeout
    }

    /// Проверка одиночного хоста через TCP Connect (Network.framework)
    public func pingTarget(_ target: HostTarget) async -> PingRecord {
        let hostStr = target.address

        // Шлюз, адрес которого ещё не определён, не проверяется: раньше вместо него опрашивался
        // жёстко заданный 192.168.1.1, которого в большинстве сетей не существует.
        if target.isGateway && (hostStr == "gateway" || hostStr.isEmpty) {
            return PingRecord(
                host: hostStr,
                targetName: target.name,
                isSuccess: false,
                errorMessage: "Адрес шлюза пока не определён",
                protocolType: "unknown"
            )
        }

        guard !hostStr.isEmpty else {
            return PingRecord(
                host: hostStr,
                targetName: target.name,
                isSuccess: false,
                errorMessage: "Хост не указан"
            )
        }

        // Для локального шлюза проверяем DNS (53), для остальных — заданный порт.
        // Порт проверяется на диапазон: UInt16(Int) вне 0...65535 аварийно завершает приложение.
        let requestedPort = target.isGateway ? 53 : target.tcpPort
        let portNum: UInt16 = (requestedPort > 0 && requestedPort <= 65_535) ? UInt16(requestedPort) : 443

        do {
            let probe = try await withTimeout(seconds: timeoutInterval) {
                try await self.tcpConnect(host: hostStr, port: portNum)
            }
            return PingRecord(
                host: hostStr,
                targetName: target.name,
                isSuccess: true,
                latencyMs: probe.latencyMs,
                protocolType: probe.refused ? "tcp:rst:\(portNum)" : "tcp:\(portNum)"
            )
        } catch is PingTimeoutError {
            return PingRecord(
                host: hostStr,
                targetName: target.name,
                isSuccess: false,
                latencyMs: nil,
                errorMessage: "Таймаут ответа",
                protocolType: "tcp:\(portNum)"
            )
        } catch is CancellationError {
            // Проверка прервана (остановка мониторинга) — это не потеря пакета, но запись должна быть неуспешной
            return PingRecord(
                host: hostStr,
                targetName: target.name,
                isSuccess: false,
                latencyMs: nil,
                errorMessage: "Проверка отменена",
                protocolType: "tcp:\(portNum)"
            )
        } catch {
            return PingRecord(
                host: hostStr,
                targetName: target.name,
                isSuccess: false,
                latencyMs: nil,
                errorMessage: "Соединение не установлено",
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

    private func tcpConnect(host: String, port: UInt16) async throws -> TCPProbeResult {
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
                        let ms = elapsedMilliseconds(clock.now - startTime)
                        connection.cancel()
                        safeContinuation.resume(returning: TCPProbeResult(latencyMs: (ms * 10).rounded() / 10, refused: false))

                    case .waiting(let err):
                        // ECONNREFUSED: узел жив (прислал RST). Остальные причины ожидания (нет маршрута и т.п.)
                        // не завершают проверку досрочно — их обработает общий таймаут.
                        if isConnectionRefused(err) {
                            let ms = elapsedMilliseconds(clock.now - startTime)
                            connection.cancel()
                            safeContinuation.resume(returning: TCPProbeResult(latencyMs: max(0.1, (ms * 10).rounded() / 10), refused: true))
                        }

                    case .failed(let err):
                        connection.cancel()
                        if isConnectionRefused(err) {
                            let ms = elapsedMilliseconds(clock.now - startTime)
                            safeContinuation.resume(returning: TCPProbeResult(latencyMs: max(0.1, (ms * 10).rounded() / 10), refused: true))
                        } else {
                            safeContinuation.resume(throwing: err)
                        }

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
                try await Task.sleep(nanoseconds: UInt64(max(0.1, seconds) * 1_000_000_000))
                throw PingTimeoutError()
            }

            guard let result = try await group.next() else {
                throw PingTimeoutError()
            }

            group.cancelAll()
            return result
        }
    }
}
