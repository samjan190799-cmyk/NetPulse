//
//  DashboardView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Главный экран мониторинга качества сетевого соединения.
public struct DashboardView: View {
    @Bindable var viewModel: NetworkMonitorViewModel
    @State private var jsonExportURL: URL?
    @State private var csvExportURL: URL?
    @State private var isExporting = false

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Фоновый градиент
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.06, blue: 0.11), Color(red: 0.08, green: 0.10, blue: 0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Системная сетевая карточка
                        NetworkInfoCardView(
                            info: viewModel.systemInfo,
                            isMonitoring: viewModel.isMonitoringActive
                        )

                        // График задержки в реальном времени (Swift Charts)
                        LatencyChartView(hostMetrics: viewModel.hostMetrics)

                        // Секция целевых узлов
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("ЦЕЛЕВЫЕ УЗЛЫ")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(viewModel.targets.count) узлов")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.cyan)
                            }
                            .padding(.horizontal, 4)

                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.targets) { target in
                                    if let metrics = viewModel.hostMetrics[target.address] {
                                        HostMetricCardView(metrics: metrics) {
                                            viewModel.startTraceroute(for: target.address)
                                        }
                                    }
                                }
                            }
                        }

                        // Спидометр скорости (Speedtest)
                        SpeedtestGaugeView(
                            isRunning: viewModel.isSpeedtestRunning,
                            downloadMbps: viewModel.liveDownloadSpeed,
                            uploadMbps: viewModel.liveUploadSpeed
                        ) {
                            viewModel.runSpeedtest()
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
                        Image(systemName: viewModel.isMonitoringActive ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(viewModel.isMonitoringActive ? .orange : .green)
                    }
                }

                // Меню экспорта отчетов
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            prepareJSONExport()
                        } label: {
                            Label("Экспорт отчета JSON", systemImage: "arrow.down.doc")
                        }

                        Button {
                            prepareCSVExport()
                        } label: {
                            Label("Экспорт метрик CSV", systemImage: "tablecells")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.cyan)
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
