//
//  DashboardView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Главный экран: Замер скорости (Speedtest) и оценка возможностей сети.
public struct DashboardView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    private var currentPing: Double? {
        if let gw = viewModel.hostMetrics.values.first(where: { $0.isGateway }), let lat = gw.lastLatencyMs {
            return lat
        }
        let latencies = viewModel.hostMetrics.values.compactMap { $0.lastLatencyMs }
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    private var currentJitter: Double? {
        if let gw = viewModel.hostMetrics.values.first(where: { $0.isGateway }) {
            return gw.jitterMs
        }
        let jitters = viewModel.hostMetrics.values.map { $0.jitterMs }.filter { $0 > 0 }
        guard !jitters.isEmpty else { return nil }
        return jitters.reduce(0, +) / Double(jitters.count)
    }

    private var capabilities: [CapabilityItem] {
        let evaluator = NetworkCapabilityEvaluator(
            downloadMbps: viewModel.liveDownloadSpeed > 0 ? viewModel.liveDownloadSpeed : (viewModel.lastSpeedtestResult?.downloadMbps ?? 0.0),
            uploadMbps: viewModel.liveUploadSpeed > 0 ? viewModel.liveUploadSpeed : (viewModel.lastSpeedtestResult?.uploadMbps ?? 0.0),
            pingMs: currentPing,
            jitterMs: currentJitter
        )
        return evaluator.evaluateAll()
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Фон: динамический градиент активной темы
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Интерактивный замер скорости (Speedtest 2026)
                        SpeedtestHeroView(
                            isRunning: viewModel.isSpeedtestRunning,
                            downloadMbps: viewModel.liveDownloadSpeed > 0 ? viewModel.liveDownloadSpeed : (viewModel.lastSpeedtestResult?.downloadMbps ?? 0.0),
                            uploadMbps: viewModel.liveUploadSpeed > 0 ? viewModel.liveUploadSpeed : (viewModel.lastSpeedtestResult?.uploadMbps ?? 0.0),
                            pingMs: currentPing,
                            jitterMs: currentJitter,
                            onStartSpeedtest: {
                                viewModel.startSpeedtest()
                            }
                        )

                        // Мгновенный вердикт от AI после завершения замера скорости
                        if let aiSummary = viewModel.instantAISummary, !viewModel.isSpeedtestRunning {
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(NPTheme.accentPrimary.opacity(0.12))
                                        .frame(width: 34, height: 34)
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(NPTheme.accentPrimary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("AI-вердикт")
                                        .font(.system(size: 12, weight: .heavy))
                                        .foregroundStyle(NPTheme.accentPrimary)

                                    Text(aiSummary)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(NPTheme.textPrimary)
                                        .lineSpacing(2)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .npGlassCard(cornerRadius: 14)
                            .transition(.scale.combined(with: .opacity))
                        }

                        // 2. Блок оценки применимости скорости (Для чего подходит сеть)
                        NetworkCapabilityCardView(items: capabilities)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("NetPulse")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !viewModel.isMonitoringActive {
                    viewModel.startMonitoring()
                }
            }
        }
    }
}
