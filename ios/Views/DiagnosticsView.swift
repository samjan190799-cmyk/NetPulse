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
                // Фон: градиент «Obsidian Mono»
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // 1. Системная сетевая карточка
                        NetworkInfoCardView(
                            info: viewModel.systemInfo,
                            isMonitoring: viewModel.isMonitoringActive
                        )

                        // 2. Блок быстрого пинга произвольного хоста / IP
                        quickPingSection

                        // 3. График задержки (Swift Charts)
                        LatencyChartView(hostMetrics: viewModel.hostMetrics)

                        // 4. Секция целевых узлов (DNS / Шлюз)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("ЦЕЛЕВЫЕ УЗЛЫ МОНИТОРИНГА")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(NPTheme.textSecondary)
                                    .tracking(0.5)

                                Spacer()

                                Text("\(viewModel.targets.count) узлов")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(NPTheme.textSecondary)
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
                            .foregroundStyle(viewModel.isMonitoringActive ? NPTheme.semanticWarn : NPTheme.accentPrimary)
                    }
                }

                // Кнопка быстрого AI-анализа
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await viewModel.runAIDiagnosticsAudit()
                        }
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(NPTheme.accentPrimary)
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
                            .foregroundStyle(NPTheme.textPrimary)
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

    // MARK: - Быстрый пинг любого узла (Apple HIG 2026)

    @State private var quickHostInput: String = ""

    private var quickPingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NPTheme.accentPrimary)

                TextField("Быстрый пинг (например: google.com, 1.1.1.1)", text: $quickHostInput)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(NPTheme.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !quickHostInput.isEmpty {
                    Button {
                        quickHostInput = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(NPTheme.textTertiary)
                    }
                    .npMinHitTarget()
                }

                Button {
                    let cleaned = quickHostInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleaned.isEmpty else { return }
                    HapticManager.shared.impactMedium()
                    if !viewModel.targets.contains(where: { $0.address.lowercased() == cleaned.lowercased() }) {
                        let newTarget = HostTarget(name: cleaned, address: cleaned, tcpPort: 443)
                        viewModel.targets.append(newTarget)
                    }
                    viewModel.startTraceroute(for: cleaned)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Пинг")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(quickHostInput.isEmpty ? NPTheme.cardBackgroundTertiary : NPTheme.accentPrimary)
                    .foregroundStyle(quickHostInput.isEmpty ? NPTheme.textTertiary : NPTheme.backgroundDeep)
                    .clipShape(Capsule())
                }
                .buttonStyle(NPPressableButtonStyle(scale: 0.94))
                .disabled(quickHostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .npGlassCard(cornerRadius: 14)
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

