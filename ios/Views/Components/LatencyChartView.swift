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

/// Интерактивный график задержки Swift Charts в стиле «Obsidian Mono».
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
                        .foregroundStyle(NPTheme.textSecondary)
                    Text("В реальном времени (мс)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(NPTheme.textPrimary)
                }
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 18))
                    .foregroundStyle(NPTheme.accentPrimary)
            }

            if chartPoints.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(NPTheme.accentPrimary)
                    Text("Накопление данных мониторинга...")
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textSecondary)
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
                        .opacity(0.08)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartForegroundStyleScale(range: [NPTheme.accentPrimary, NPTheme.accentSilver, NPTheme.accentSoft])
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(NPTheme.border)
                        AxisValueLabel {
                            if let intVal = value.as(Int.self) {
                                Text("\(intVal) мс")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(NPTheme.textSecondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(NPTheme.border)
                    }
                }
                .frame(height: 190)
                .animation(.smooth(duration: 0.4), value: chartPoints.count)
            }
        }
        .padding(16)
        .npCardStyle()
    }
}
