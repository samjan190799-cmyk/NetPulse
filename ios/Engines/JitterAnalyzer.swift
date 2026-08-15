//
//  JitterAnalyzer.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Математический анализатор сетевых метрик и джиттера по стандарту RFC 3550.
public struct JitterAnalyzer: Sendable {

    /// Расчет джиттера по RFC 3550
    /// D(i-1, i) = |Transit(i) - Transit(i-1)|
    /// J(i) = J(i-1) + (|D(i-1, i)| - J(i-1)) / 16
    public static func calculateRFC3550Jitter(
        previousJitter: Double,
        previousLatency: Double?,
        currentLatency: Double
    ) -> Double {
        guard let prev = previousLatency else {
            return 0.0
        }
        let diff = abs(currentLatency - prev)
        let newJitter = previousJitter + (diff - previousJitter) / 16.0
        return max(0.0, (newJitter * 100).rounded() / 100)
    }

    /// Расчет перцентилей задержки P50 (медиана), P95, P99
    public static func calculatePercentiles(from latencies: [Double]) -> (p50: Double, p95: Double, p99: Double) {
        guard !latencies.isEmpty else {
            return (0.0, 0.0, 0.0)
        }
        let sorted = latencies.sorted()
        let count = Double(sorted.count)

        func percentile(_ p: Double) -> Double {
            let index = (count - 1) * (p / 100.0)
            let lower = Int(floor(index))
            let upper = Int(ceil(index))
            if lower == upper {
                return sorted[lower]
            }
            let weight = index - Double(lower)
            return sorted[lower] * (1.0 - weight) + sorted[upper] * weight
        }

        return (
            (percentile(50) * 10).rounded() / 10,
            (percentile(95) * 10).rounded() / 10,
            (percentile(99) * 10).rounded() / 10
        )
    }
}
