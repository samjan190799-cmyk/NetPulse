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
    @State private var showGlossarySheet: Bool = false
    /// AI-аудит открывается отсюда (входит в подписку PRO)
    @State private var showAIAudit: Bool = false
    /// Экраны подписки PRO: доступность сервисов и история замеров
    @State private var showServices: Bool = false
    @State private var showSpeedHistory: Bool = false
    /// Отчёт для провайдера: собирается по нажатию и открывается в окне «Поделиться»
    @State private var reportShare: SharePayload?
    @State private var isBuildingReport: Bool = false

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
                            isMonitoring: viewModel.isMonitoringActive,
                            onInfoTap: {
                                showGlossarySheet = true
                            }
                        )

                        // 3. Pro-инструменты сети (DNS, Gaming Radar, Bufferbloat, LAN Scanner)
                        proUtilitiesHub

                        // 4. Блок быстрого пинга произвольного хоста / IP
                        quickPingSection

                        // 5. График задержки (Swift Charts)
                        LatencyChartView(hostMetrics: viewModel.hostMetrics)

                        // 6. Секция целевых узлов (DNS / Шлюз)
                        targetsSection
                    }
                    .padding(16)
                    .padding(.bottom, 110) // Безопасный отступ для закрепленного рекламного баннера и таб-бара
                }
                // Баннер лежит над содержимым, а не поверх него: карточка под ним не прячется
                .safeAreaInset(edge: .top, spacing: 8) {
                    alertBanner
                }
            }
            .navigationTitle("Инструменты")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showServices) {
                ServiceCheckView()
            }
            .navigationDestination(isPresented: $showSpeedHistory) {
                SpeedHistoryView()
            }
            .sheet(item: $reportShare) { payload in
                NPShareSheet(activityItems: payload.items)
            }
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

                // Кнопка справочника сети
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.shared.impactLight()
                        showGlossarySheet = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(NPTheme.textSecondary)
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
            .sheet(isPresented: $showGlossarySheet) {
                NetworkGlossarySheetView()
            }
            .sheet(isPresented: $viewModel.showTracerouteSheet) {
                TracerouteSheetView(
                    targetHost: viewModel.selectedTracerouteTarget,
                    hops: viewModel.tracerouteHops,
                    isRunning: viewModel.isTracerouteRunning,
                    errorMessage: viewModel.tracerouteError
                )
            }
            .sheet(isPresented: $isExporting) {
                if let url = jsonExportURL ?? csvExportURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .fullScreenCover(isPresented: $showAIAudit) {
                AIDiagnosticsView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Баннер оповещения

    /// Баннер только для серьёзных проблем (узел не отвечает, потери, высокая задержка) и сам исчезает через несколько
    /// секунд. Предупреждения вроде «задержка 118 мс» остаются цветом на карточках узлов и не отвлекают.
    @ViewBuilder
    private var alertBanner: some View {
        if let alert = viewModel.activeAlert, alert.severity == .critical {
            AlertsBannerView(alert: alert) {
                withAnimation {
                    viewModel.activeAlert = nil
                }
            }
            .task(id: alert.id) {
                try? await Task.sleep(for: .seconds(6))
                if !Task.isCancelled, viewModel.activeAlert?.id == alert.id {
                    withAnimation {
                        viewModel.activeAlert = nil
                    }
                }
            }
        }
    }

    // MARK: - 2. Секция Pro-утилит (DNS, Gaming Radar, Bufferbloat, LAN Scanner)

    private var proUtilitiesHub: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ПРОВЕРКИ СЕТИ")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NPTheme.textTertiary)
                    .tracking(0.5)

                Spacer()

                Button {
                    HapticManager.shared.impactLight()
                    showGlossarySheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                        Text("Справка")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NPTheme.accentPrimary)
                }
            }

            // AI-аудит: сводная оценка сети, причины проблем и обращение к провайдеру. Входит в подписку PRO.
            Button {
                HapticManager.shared.impactLight()
                if ProStore.shared.requirePro(.aiAudit) {
                    showAIAudit = true
                }
            } label: {
                proUtilityTile(
                    title: "AI-аудит сети",
                    subtitle: "Оценка 0–100, причины, обращение провайдеру",
                    icon: "sparkles",
                    color: NPTheme.accentPrimary
                )
                .overlay(alignment: .topTrailing) {
                    if !ProStore.shared.isPro {
                        ProBadge()
                            .padding(6)
                    }
                }
            }
            .buttonStyle(NPPressableButtonStyle())
            .accessibilityIdentifier("toolsAIAuditButton")

            // Возможности подписки PRO: отчёт провайдеру, доступность сервисов, история замеров
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                proToolButton(
                    feature: .report,
                    title: "Отчёт провайдеру",
                    subtitle: isBuildingReport ? "Готовим PDF…" : "PDF для претензии",
                    icon: "doc.text.fill",
                    color: Color.orange,
                    identifier: "toolsReportButton"
                ) {
                    buildReport()
                }

                proToolButton(
                    feature: .services,
                    title: "Сервисы",
                    subtitle: "Telegram, YouTube, WhatsApp",
                    icon: "antenna.radiowaves.left.and.right",
                    color: Color.pink,
                    identifier: "toolsServicesButton"
                ) {
                    showServices = true
                }

                proToolButton(
                    feature: .history,
                    title: "История замеров",
                    subtitle: "Графики и итоги",
                    icon: "chart.xyaxis.line",
                    color: Color.indigo,
                    identifier: "toolsHistoryButton"
                ) {
                    showSpeedHistory = true
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                NavigationLink(destination: DNSBenchmarkView(viewModel: viewModel)) {
                    proUtilityTile(
                        title: "Гонка DNS",
                        subtitle: "12+ Anycast узлов",
                        icon: "bolt.shield.fill",
                        color: NPTheme.accentPrimary
                    )
                }
                .buttonStyle(NPPressableButtonStyle())

                NavigationLink(destination: GamingRadarView(viewModel: viewModel)) {
                    proUtilityTile(
                        title: "Радар для игр",
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
                        title: "Сканер сети",
                        subtitle: "Устройства и порты",
                        icon: "wifi.router.fill",
                        color: Color.cyan
                    )
                }
                .buttonStyle(NPPressableButtonStyle())
            }
        }
    }

    /// Плитка возможности PRO: без подписки нажатие открывает окно подписки, с подпиской выполняет действие
    private func proToolButton(
        feature: ProFeature,
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.shared.impactLight()
            if ProStore.shared.requirePro(feature) {
                action()
            }
        } label: {
            proUtilityTile(title: title, subtitle: subtitle, icon: icon, color: color)
                .overlay(alignment: .topTrailing) {
                    if !ProStore.shared.isPro {
                        ProBadge()
                            .padding(4)
                    }
                }
        }
        .buttonStyle(NPPressableButtonStyle())
        .accessibilityIdentifier(identifier)
    }

    /// Собирает PDF-отчёт и открывает «Поделиться»
    private func buildReport() {
        guard !isBuildingReport else { return }
        isBuildingReport = true
        let data = ProReportData.gather(viewModel: viewModel)
        Task {
            let url = await Task.detached(priority: .userInitiated) {
                ProReportData.writePDF(data)
            }.value
            isBuildingReport = false
            if let url {
                reportShare = SharePayload(items: [url])
                HapticManager.shared.notificationSuccess()
            }
        }
    }

    private func proUtilityTile(title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 34, height: 34)

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(NPTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NPTheme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
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
                    viewModel.addCustomTarget(cleaned)
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

                Button {
                    HapticManager.shared.impactLight()
                    showGlossarySheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(NPTheme.textTertiary)
                }

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
