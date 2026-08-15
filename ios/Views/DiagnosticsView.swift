//
//  DiagnosticsView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Экран детальной сетевой диагностики, мониторинга узлов и MTR-трассировки.
public struct DiagnosticsView: View {
    @Bindable var viewModel: NetworkMonitorViewModel
    @State private var jsonExportURL: URL?
    @State private var csvExportURL: URL?
    @State private var isExporting = false

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // 1. Системная сетевая карточка
                        NetworkInfoCardView(
                            info: viewModel.systemInfo,
                            isMonitoring: viewModel.isMonitoringActive
                        )

                        // 2. График задержки (Swift Charts)
                        LatencyChartView(hostMetrics: viewModel.hostMetrics)

                        // 3. Секция целевых узлов (DNS / Шлюз)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("ЦЕЛЕВЫЕ УЗЛЫ МОНИТОРИНГА")
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
            .navigationTitle("Диагностика")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Кнопка паузы / запуска пинга
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

                // Экспорт отчетов
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
