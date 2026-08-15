//
//  LatencyChartView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import Charts

/// Точка для графика задержки
public struct ChartDataPoint: Identifiable, Sendable {
    public var id: String { "\(targetName)_\(index)" }
    public let index: Int
    public let targetName: String
    public let latencyMs: Double
}

/// Интерактивный график задержки Swift Charts.
public struct LatencyChartView: View {
    public let hostMetrics: [String: HostMetrics]

    private var chartPoints: [ChartDataPoint] {
        var points: [ChartDataPoint] = []
        for (_, metrics) in hostMetrics {
            for (idx, val) in metrics.latencyHistory.enumerated() {
                if let lat = val {
                    points.append(
                        ChartDataPoint(
                            index: idx,
                            targetName: metrics.name,
                            latencyMs: lat
                        )
                    )
                }
            }
        }
        return points
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ДИНАМИКА ЗАДЕРЖКИ RTT")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("В реальном времени (мс)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 18))
                    .foregroundStyle(.cyan)
            }

            if chartPoints.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(.cyan)
                    Text("Накопление данных мониторинга...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart {
                    ForEach(chartPoints) { point in
                        LineMark(
                            x: .value("Шаг", point.index),
                            y: .value("RTT", point.latencyMs),
                            series: .value("Узел", point.targetName)
                        )
                        .foregroundStyle(by: .value("Узел", point.targetName))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.2))

                        AreaMark(
                            x: .value("Шаг", point.index),
                            y: .value("RTT", point.latencyMs),
                            series: .value("Узел", point.targetName)
                        )
                        .foregroundStyle(by: .value("Узел", point.targetName))
                        .opacity(0.12)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel {
                            if let intVal = value.as(Int.self) {
                                Text("\(intVal) мс")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(Color.white.opacity(0.08))
                    }
                }
                .frame(height: 190)
                .animation(.smooth(duration: 0.4), value: chartPoints.count)
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
}
