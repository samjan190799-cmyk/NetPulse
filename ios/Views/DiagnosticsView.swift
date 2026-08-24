//
//  DiagnosticsView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Экран детальной сетевой диагностики, мониторинга узлов, MTR-трассировки и Pro-утилит (2026).
public struct DiagnosticsView: View {
    @Bindable var viewModel: NetworkMonitorViewModel
    @State private var jsonExportURL: URL?
    @State private var csvExportURL: URL?
    @State private var isExporting = false
    @State private var quickHostInput: String = ""

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // 1. Системная сетевая карточка
                        NetworkInfoCardView(
                            info: viewModel.systemInfo,
                            isMonitoring: viewModel.isMonitoringActive
                        )

                        // 2. Pro-инструменты сети (DNS, Gaming Radar, Bufferbloat, LAN Scanner)
                        proUtilitiesHub

                        // 3. Блок быстрого пинга произвольного хоста / IP
                        quickPingSection

                        // 4. График задержки (Swift Charts)
                        LatencyChartView(hostMetrics: viewModel.hostMetrics)

                        // 5. Секция целевых узлов (DNS / Шлюз)
                        targetsSection
                    }
                    .padding(16)
                    .padding(.bottom, 90)
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
                    .npMinHitTarget()
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
                    .npMinHitTarget()
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
                    .npMinHitTarget()
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

    // MARK: - 2. Секция Pro-утилит (DNS, Gaming Radar, Bufferbloat, LAN Scanner)

    private var proUtilitiesHub: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ПРОФЕССИОНАЛЬНЫЕ УТИЛИТЫ")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NPTheme.textTertiary)
                .tracking(0.5)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                NavigationLink(destination: DNSBenchmarkView(viewModel: viewModel)) {
                    proUtilityTile(
                        title: "DNS Гонка",
                        subtitle: "12+ Anycast узлов",
                        icon: "bolt.shield.fill",
                        color: NPTheme.accentPrimary
                    )
                }
                .buttonStyle(NPPressableButtonStyle())

                NavigationLink(destination: GamingRadarView(viewModel: viewModel)) {
                    proUtilityTile(
                        title: "Gaming Радар",
                        subtitle: "CS2, Dota, Valorant",
                        icon: "gamecontroller.fill",
                        color: Color.mint
                    )
                }
                .buttonStyle(NPPressableButtonStyle())

                NavigationLink(destination: BufferbloatView(viewModel: viewModel)) {
                    proUtilityTile(
                        title: "Bufferbloat",
                        subtitle: "RFC 8290 SQM тест",
                        icon: "gauge.with.dots.needle.67percent",
                        color: Color.yellow
                    )
                }
                .buttonStyle(NPPressableButtonStyle())

                NavigationLink(destination: LANScannerView(viewModel: viewModel)) {
                    proUtilityTile(
                        title: "LAN Сканер",
                        subtitle: "Устройства и порты",
                        icon: "wifi.router.fill",
                        color: Color.cyan
                    )
                }
                .buttonStyle(NPPressableButtonStyle())
            }
        }
    }

    private func proUtilityTile(title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(NPTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NPTheme.textTertiary)
        }
        .padding(12)
        .npGlassCard(cornerRadius: 14)
    }

    // MARK: - 3. Быстрый пинг любого узла

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

    // MARK: - 5. Секция целевых узлов

    private var targetsSection: some View {
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
