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
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // 1. Компактная плашка текущего подключения
                        ConnectionStatusHeader(info: viewModel.systemInfo)

                        // 2. Плашка быстрого AI-аудита сети
                        AIQuickAuditBanner(viewModel: viewModel)

                        // 3. Быстрые переключатели виджетов (Dynamic Island & HUD)
                        WidgetQuickControlsBar(viewModel: viewModel)

                        // 4. Интерактивный замер скорости (Speedtest)
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

                        // 5. Блок оценки применимости скорости (Для чего подходит сеть)
                        NetworkCapabilityCardView(items: capabilities)
                    }
                    .padding(16)
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

/// Панель быстрого переключения Dynamic Island и игрового HUD
private struct WidgetQuickControlsBar: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    var body: some View {
        HStack(spacing: 10) {
            // Кнопка Dynamic Island
            Button {
                HapticManager.shared.impactMedium()
                viewModel.toggleLiveActivity(enabled: !viewModel.liveActivityEnabled)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.liveActivityEnabled ? "circle.fill" : "circle")
                        .font(.system(size: 8))
                        .foregroundStyle(viewModel.liveActivityEnabled ? .green : .secondary)

                    Image(systemName: "pip.enter")
                        .font(.system(size: 12, weight: .semibold))

                    Text("Островок")
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(viewModel.liveActivityEnabled ? Color.blue.opacity(0.15) : Color(uiColor: .secondarySystemBackground))
                .foregroundStyle(viewModel.liveActivityEnabled ? Color.blue : Color.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(viewModel.liveActivityEnabled ? Color.blue.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                )
            }

            // Кнопка Игрового HUD
            Button {
                HapticManager.shared.impactMedium()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    viewModel.floatingHUDEnabled.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.floatingHUDEnabled ? "circle.fill" : "circle")
                        .font(.system(size: 8))
                        .foregroundStyle(viewModel.floatingHUDEnabled ? .green : .secondary)

                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 12, weight: .semibold))

                    Text("Игровой HUD")
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(viewModel.floatingHUDEnabled ? Color.cyan.opacity(0.15) : Color(uiColor: .secondarySystemBackground))
                .foregroundStyle(viewModel.floatingHUDEnabled ? Color.cyan : Color.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(viewModel.floatingHUDEnabled ? Color.cyan.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }
}

/// Компактная плашка статуса текущего интернет-соединения
private struct ConnectionStatusHeader: View {
    let info: NetworkInterfaceInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconForType(info.connectionType))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(info.ispName ?? "Определение провайдера...")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(info.connectionType.rawValue) • \(info.publicIP ?? "...")")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("АКТИВНО")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.1))
            .clipShape(Capsule())
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func iconForType(_ type: NetworkConnectionType) -> String {
        switch type {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .ethernet: return "cable.connector"
        case .loopback: return "arrow.triangle.2.circlepath"
        case .unavailable: return "wifi.slash"
        }
    }
}

/// Плашка быстрого запуска AI-аудита сети
private struct AIQuickAuditBanner: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.cyan.opacity(0.2), .blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)

                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.cyan)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("AI-Диагност NetPulse")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)

                    if let score = viewModel.currentHealthReport?.overallScore {
                        Text("\(score)/100")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(viewModel.currentHealthReport?.statusBadgeColor ?? .green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                Text(viewModel.currentHealthReport?.statusTitle ?? "Готов к мгновенному анализу задержки и стабильности")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task {
                    await viewModel.runAIDiagnosticsAudit()
                }
            } label: {
                if viewModel.isAIAnalyzing {
                    ProgressView()
                        .tint(.cyan)
                        .scaleEffect(0.8)
                } else {
                    Text("Аудит ✨")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(Capsule())
                }
            }
            .disabled(viewModel.isAIAnalyzing)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

