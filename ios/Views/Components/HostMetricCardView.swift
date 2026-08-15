//
//  HostMetricCardView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import Charts

/// Glassmorphic карточка целевого узла со статусом, RTT и джиттером RFC 3550.
public struct HostMetricCardView: View {
    public let metrics: HostMetrics
    public let onTracerouteTapped: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Заголовок карточки и статус-бейдж
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if metrics.isGateway {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.yellow)
                        }
                        Text(metrics.name)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    Text(metrics.address)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Статус хоста
                StatusPill(status: metrics.status)
            }

            // Основной блок задержки и Sparkline
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ТЕКУЩИЙ RTT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)

                    if let rtt = metrics.lastLatencyMs {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(String(format: "%.1f", rtt))
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                                .foregroundStyle(colorForLatency(rtt))

                            Text("мс")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(metrics.sentCount > 0 ? "LOST" : "--")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.red)
                    }
                }

                Spacer()

                // Мини-график истории задержки (Sparkline)
                MiniSparklineView(data: metrics.latencyHistory)
                    .frame(width: 100, height: 32)
            }

            Divider()
                .background(Color.white.opacity(0.08))

            // Сетка метрик: Min/Avg/Max, Jitter RFC 3550, Loss %
            HStack(spacing: 8) {
                MetricPill(
                    label: "Min/Avg/Max",
                    value: "\(intOrDash(metrics.minLatencyMs))/\(intOrDash(metrics.avgLatencyMs))/\(intOrDash(metrics.maxLatencyMs))"
                )

                MetricPill(
                    label: "Джиттер",
                    value: String(format: "%.1f мс", metrics.jitterMs)
                )

                MetricPill(
                    label: "Потери",
                    value: String(format: "%.1f%%", metrics.lossWindowPct),
                    isAlert: metrics.lossWindowPct > 3.0
                )

                Button(action: onTracerouteTapped) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color(uiColor: .tertiarySystemBackground))
                        .clipShape(Circle())
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func colorForLatency(_ lat: Double) -> Color {
        if lat < 60 { return .green }
        if lat < 140 { return .yellow }
        return .red
    }

    private func strokeColorForStatus(_ status: HostStatus) -> Color {
        switch status {
        case .ok: return Color.white.opacity(0.1)
        case .warning: return Color.yellow.opacity(0.35)
        case .critical: return Color.red.opacity(0.45)
        case .down: return Color.red.opacity(0.6)
        case .unknown: return Color.white.opacity(0.08)
        }
    }

    private func intOrDash(_ val: Double?) -> String {
        guard let v = val else { return "-" }
        return String(format: "%.0f", v)
    }
}

// MARK: - Вспомогательные компоненты

private struct StatusPill: View {
    let status: HostStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(status.rawValue)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .ok: return .green
        case .warning: return .yellow
        case .critical, .down: return .red
        case .unknown: return .gray
        }
    }
}

private struct MetricPill: View {
    let label: String
    let value: String
    var isAlert: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(isAlert ? .red : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MiniSparklineView: View {
    let data: [Double?]

    var body: some View {
        GeometryReader { proxy in
            let valid = data.compactMap { $0 }
            if valid.count >= 2 {
                let minV = valid.min()!
                let maxV = valid.max()!
                let range = max(maxV - minV, 1.0)

                Path { path in
                    for (index, val) in data.enumerated() {
                        let x = proxy.size.width * CGFloat(index) / CGFloat(max(data.count - 1, 1))
                        let num = val ?? minV
                        let y = proxy.size.height * (1.0 - CGFloat((num - minV) / range))
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(
                    LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            } else {
                Color.clear
            }
        }
    }
}
