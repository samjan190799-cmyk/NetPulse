//
//  DashboardView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Главный экран: Замер скорости (Speedtest), быстрые Pro-инструменты и оценка возможностей сети.
public struct DashboardView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    private var isCellular: Bool {
        viewModel.systemInfo.connectionType == .cellular
    }

    private var currentPing: Double? {
        // На сотовой сети локальный шлюз (роутер) отсутствует — берем публичные хосты
        if !isCellular, let gw = viewModel.hostMetrics.values.first(where: { $0.isGateway }), let lat = gw.lastLatencyMs, lat > 0 {
            return lat
        }
        let reachableLatencies = viewModel.hostMetrics.values
            .filter { !($0.isGateway && isCellular) }
            .compactMap { $0.lastLatencyMs }
            .filter { $0 > 0 }
        guard !reachableLatencies.isEmpty else {
            return viewModel.lastSpeedtestResult?.pingMs
        }
        return (reachableLatencies.reduce(0, +) / Double(reachableLatencies.count) * 10).rounded() / 10
    }

    private var currentJitter: Double? {
        if !isCellular, let gw = viewModel.hostMetrics.values.first(where: { $0.isGateway }), gw.jitterMs > 0 {
            return gw.jitterMs
        }
        let reachableJitters = viewModel.hostMetrics.values
            .filter { !($0.isGateway && isCellular) }
            .map { $0.jitterMs }
            .filter { $0 > 0 }
        guard !reachableJitters.isEmpty else {
            return viewModel.lastSpeedtestResult?.jitterMs ?? 1.5
        }
        return (reachableJitters.reduce(0, +) / Double(reachableJitters.count) * 10).rounded() / 10
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
                    VStack(spacing: 18) {
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

                        // 2. Быстрые карточки Pro-инструментов (DNS, Gaming, Bufferbloat, LAN)
                        quickToolsSection

                        // 3. Блок оценки применимости скорости (Для чего подходит сеть)
                        NetworkCapabilityCardView(items: capabilities)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 90) // Безопасный отступ для плавающего таб-бара
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

    // MARK: - Быстрые инструменты на дашборде

    private var quickToolsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                NavigationLink(destination: DNSBenchmarkView(viewModel: viewModel)) {
                    quickDashboardChip(
                        title: "DNS Гонка",
                        icon: "bolt.shield.fill",
                        color: NPTheme.accentPrimary
                    )
                }
                .buttonStyle(NPPressableButtonStyle())

                NavigationLink(destination: GamingRadarView(viewModel: viewModel)) {
                    quickDashboardChip(
                        title: "Gaming Радар",
                        icon: "gamecontroller.fill",
                        color: Color.mint
                    )
                }
                .buttonStyle(NPPressableButtonStyle())

                NavigationLink(destination: BufferbloatView(viewModel: viewModel)) {
                    quickDashboardChip(
                        title: "Bufferbloat",
                        icon: "gauge.with.dots.needle.67percent",
                        color: Color.yellow
                    )
                }
                .buttonStyle(NPPressableButtonStyle())

                NavigationLink(destination: LANScannerView(viewModel: viewModel)) {
                    quickDashboardChip(
                        title: "LAN Сканер",
                        icon: "wifi.router.fill",
                        color: Color.cyan
                    )
                }
                .buttonStyle(NPPressableButtonStyle())
            }
        }
    }

    private func quickDashboardChip(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)

            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NPTheme.textPrimary)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(NPTheme.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .npGlassCard(cornerRadius: 12)
    }
}
