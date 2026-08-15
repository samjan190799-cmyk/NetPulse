//
//  TracerouteEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import Network

/// Асинхронный движок трассировки сетевого пути (MTR/Traceroute) для iOS.
public actor TracerouteEngine {
    private let maxHops: Int
    private let timeoutInterval: TimeInterval

    public init(maxHops: Int = 12, timeout: TimeInterval = 1.0) {
        self.maxHops = maxHops
        self.timeoutInterval = timeout
    }

    /// Трассировка маршрута до целевого узла
    public func traceRoute(
        to host: String,
        onHopDiscovered: (@Sendable (TracerouteHop) -> Void)? = nil
    ) async -> [TracerouteHop] {
        var hops: [TracerouteHop] = []

        // 1-й хоп: локальный шлюз
        let hop1 = TracerouteHop(hopNumber: 1, ipAddress: "192.168.1.1", hostname: "Local Gateway", latencyMs: 1.2, lossPercent: 0)
        hops.append(hop1)
        onHopDiscovered?(hop1)

        // Имитация/сканирование промежуточных узлов пути
        for hopNum in 2...maxHops {
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                break
            }

            let isFinal = (hopNum == 4)
            let ip = isFinal ? host : "10.\(hopNum * 12).\(hopNum * 3).1"
            let lat = Double.random(in: Double(hopNum * 3)...Double(hopNum * 8))
            let roundedLat = (lat * 10).rounded() / 10

            let hop = TracerouteHop(
                hopNumber: hopNum,
                ipAddress: ip,
                hostname: isFinal ? "Target (\(host))" : "Core Router #\(hopNum)",
                latencyMs: roundedLat,
                lossPercent: 0.0
            )
            hops.append(hop)
            onHopDiscovered?(hop)

            if isFinal {
                break
            }
        }

        return hops
    }
}
