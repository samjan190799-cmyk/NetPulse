//
//  DashboardView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Главный экран мониторинга и тестирования скорости сетевого соединения.
public struct DashboardView: View {
    @Bindable var viewModel: NetworkMonitorViewModel
    @State private var jsonExportURL: URL?
    @State private var csvExportURL: URL?
    @State private var isExporting = false

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

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Строгий системный темный фон
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // 1. Системный статус сети
                        NetworkInfoCardView(
                            info: viewModel.systemInfo,
                            isMonitoring: viewModel.isMonitoringActive
                        )

                        // 2. Интерактивный замер скорости (Speedtest Hero Card)
                        SpeedtestHeroView(
                            isRunning: viewModel.isSpeedtestRunning,
                            downloadMbps: viewModel.liveDownloadSpeed,
                            uploadMbps: viewModel.liveUploadSpeed,
                            pingMs: currentPing,
                            jitterMs: currentJitter,
                            onStartSpeedtest: {
                                viewModel.runSpeedtest()
                            }
                        )

                        // 3. График задержки (Swift Charts)
                        LatencyChartView(hostMetrics: viewModel.hostMetrics)

                        // 4. Секция целевых узлов
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("ЦЕЛЕВЫЕ УЗЛЫ")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .tracking(0.5)

                                Spacer()

                                Text("\(viewModel.targets.count) узлов")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 4)

                            LazyVStack(spacing: 10) {
                                ForEach(viewModel.targets) { target in
                                    if let metrics = viewModel.hostMetrics[target.address] {
                                        HostMetricCardView(metrics: metrics) {
                                            viewModel.startTraceroute(for: target.address)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 32)
                }

                // Всплывающий баннер алертов
                if let alert = viewModel.activeAlert {
                    AlertsBannerView(alert: alert) {
                        withAnimation {
                            viewModel.activeAlert = nil
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("NetPulse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Кнопка включения/выключения монитора
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if viewModel.isMonitoringActive {
                            viewModel.stopMonitoring()
                        } else {
                            viewModel.startMonitoring()
                        }
                    } label: {
                        Image(systemName: viewModel.isMonitoringActive ? "pause.circle" : "play.circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(viewModel.isMonitoringActive ? .orange : .blue)
                    }
                }

                // Меню экспорта отчетов
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            prepareJSONExport()
                        } label: {
                            Label("Экспорт JSON", systemImage: "arrow.down.doc")
                        }

                        Button {
                            prepareCSVExport()
                        } label: {
                            Label("Экспорт CSV", systemImage: "tablecells")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showTracerouteSheet) {
                TracerouteSheetView(
                    targetHost: viewModel.selectedTracerouteTarget,
                    hops: viewModel.tracerouteHops,
                    isRunning: viewModel.isTracerouteRunning
                )
            }
            .sheet(isPresented: $isExporting) {
                if let url = jsonExportURL ?? csvExportURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .onAppear {
                if !viewModel.isMonitoringActive {
                    viewModel.startMonitoring()
                }
            }
        }
    }

    private func prepareJSONExport() {
        Task {
            if let url = try? await viewModel.getExportJSONURL() {
                jsonExportURL = url
                csvExportURL = nil
                isExporting = true
            }
        }
    }

    private func prepareCSVExport() {
        Task {
            if let url = try? await viewModel.getExportCSVURL() {
                csvExportURL = url
                jsonExportURL = nil
                isExporting = true
            }
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
