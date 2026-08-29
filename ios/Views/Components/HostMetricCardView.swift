//
//  HostMetricCardView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import Charts

/// Карточка целевого узла в стиле «Obsidian Mono»: белые метрики, glow для активных элементов.
public struct HostMetricCardView: View {
    public let metrics: HostMetrics
    public let onTracerouteTapped: () -> Void

    @State private var isTraceroutePressed: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Заголовок карточки и статус-бейдж
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if metrics.isGateway {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(NPTheme.accentSoft)
                        }
                        Text(metrics.name)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(NPTheme.textPrimary)
                    }

                    Text(metrics.address)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(NPTheme.textSecondary)
                }

                Spacer()

                // Статус хоста с пульсирующей точкой
                StatusPill(status: metrics.status)
            }

            // Основной блок задержки и Sparkline
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ТЕКУЩИЙ RTT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(NPTheme.textSecondary)

                    if let rtt = metrics.lastLatencyMs {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(String(format: "%.1f", rtt))
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(colorForLatency(rtt))
                                .contentTransition(.numericText(value: rtt))
                                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: rtt)

                            Text("мс")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NPTheme.textSecondary)
                        }
                    } else {
                        Text(metrics.sentCount > 0 ? "LOST" : "--")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(NPTheme.semanticCritical)
                    }
                }

                Spacer()

                // Мини-график истории задержки (Sparkline)
                MiniSparklineView(data: metrics.latencyHistory)
                    .frame(width: 100, height: 32)
            }

            Divider()
                .background(NPTheme.border)

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

                Button(action: {
                    HapticManager.shared.impactMedium()
                    onTracerouteTapped()
                }) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NPTheme.accentPrimary)
                        .frame(width: 36, height: 36)
                        .background(NPTheme.accentPrimary.opacity(0.12))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(NPTheme.accentPrimary.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(NPPressableButtonStyle(scale: 0.90))
                .npMinHitTarget()
                .accessibilityLabel("Запустить MTR трассировку до \(metrics.name)")
            }
        }
        .padding(16)
        .npCardStyle()
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(strokeColorForStatus(metrics.status), lineWidth: 1)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: metrics.status)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metrics.name), адрес \(metrics.address), текущая задержка \(metrics.lastLatencyMs != nil ? String(format: "%.1f", metrics.lastLatencyMs!) : "нет ответа") миллисекунд, статус \(metrics.status.rawValue)")
    }

    private func colorForLatency(_ lat: Double) -> Color {
        if lat < 60 { return NPTheme.accentPrimary }
        if lat < 140 { return NPTheme.semanticWarn }
        return NPTheme.semanticCritical
    }

    private func strokeColorForStatus(_ status: HostStatus) -> Color {
        switch status {
        case .ok: return NPTheme.border
        case .warning: return NPTheme.semanticWarn.opacity(0.35)
        case .critical: return NPTheme.semanticCritical.opacity(0.45)
        case .down: return NPTheme.semanticCritical.opacity(0.6)
        case .unknown: return NPTheme.border
        }
    }

    private func intOrDash(_ val: Double?) -> String {
        guard let v = val else { return "-" }
        return String(format: "%.0f", v)
    }
}

// MARK: - Вспомогательные компоненты (Obsidian Mono)

private struct StatusPill: View {
    let status: HostStatus
    @State private var isBreathing: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .scaleEffect(status == .ok && isBreathing ? 1.3 : 1.0)
                .opacity(status == .ok && isBreathing ? 0.7 : 1.0)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isBreathing)

            Text(status.rawValue)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
        .onAppear {
            isBreathing = true
        }
    }

    private var statusColor: Color {
        switch status {
        case .ok: return NPTheme.accentPrimary
        case .warning: return NPTheme.semanticWarn
        case .critical, .down: return NPTheme.semanticCritical
        case .unknown: return NPTheme.textTertiary
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
                .foregroundStyle(NPTheme.textSecondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(isAlert ? NPTheme.semanticCritical : NPTheme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(NPTheme.cardBackgroundTertiary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MiniSparklineView: View {
    let data: [Double?]

    var body: some View {
        GeometryReader { proxy in
            let valid = data.compactMap { $0 }
            if valid.count >= 2, let minV = valid.min(), let maxV = valid.max() {
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
                    LinearGradient(colors: [NPTheme.accentPrimary, NPTheme.accentSoft], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: data.count)
            } else {
                Color.clear
            }
        }
    }
}
