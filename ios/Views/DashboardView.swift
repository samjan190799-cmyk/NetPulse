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

    /// Пинг и джиттер — единые для всего приложения (среднее по узлам, отвечающим прямо сейчас).
    /// Раньше экран брал пинг до шлюза, остров и виджеты — среднее по узлам, и при отказе всех узлов подставлялся
    /// пинг прошлого speedtest или выдуманные «28 мс» / «1,5 мс».
    private var currentPing: Double? {
        viewModel.currentAveragePing
    }

    private var currentJitter: Double? {
        viewModel.currentAverageJitter
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

    @State private var showGlossarySheet: Bool = false
    @State private var showMapFromHint: Bool = false

    /// Подсказка после возвращения в приложение: свёрнутое приложение iOS усыпляет, и остров стоит на последних цифрах.
    /// Пока идёт запись маршрута на «Карте сети», приложение остаётся активным, и остров обновляется и в фоне.
    private var recordingHintCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(NPTheme.semanticWarn)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Остров замирал, пока приложение было свёрнуто")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NPTheme.textPrimary)

                    Text("iOS усыпляет свёрнутое приложение, и остров стоит на последних цифрах. Пока идёт запись маршрута на «Карте сети», приложение остаётся активным и остров обновляется и в фоне. Для записи используется геолокация, в строке состояния появится её значок.")
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textSecondary)
                        .lineSpacing(2)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.dismissRecordingHint(forever: false)
                    showMapFromHint = true
                } label: {
                    Text("Открыть карту сети")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("recordingHintOpenMap")

                Button {
                    viewModel.dismissRecordingHint(forever: false)
                } label: {
                    Text("Позже")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("recordingHintLater")

                Button {
                    viewModel.dismissRecordingHint(forever: true)
                } label: {
                    Text("Не показывать")
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .npGlassCard(cornerRadius: 14)
    }

    /// Плашка, пока идёт запись маршрута: пользователь всегда видит, что геолокация используется, и может открыть карту
    private var recordingBanner: some View {
        NavigationLink(destination: NetworkMapView()) {
            HStack(spacing: 10) {
                Circle()
                    .fill(NPTheme.semanticCritical)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Идёт запись маршрута")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NPTheme.textPrimary)
                    Text("Точек: \(RouteRecorder.shared.pointCount) · приложение активно и в фоне")
                        .font(.system(size: 11))
                        .foregroundStyle(NPTheme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NPTheme.textTertiary)
            }
            .padding(14)
            .npGlassCard(cornerRadius: 14)
        }
        .buttonStyle(NPPressableButtonStyle())
        .accessibilityIdentifier("recordingBanner")
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Фон: динамический градиент активной темы
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        // 0. Идёт запись маршрута, либо остров замирал, пока приложение было свёрнуто, а запись не шла
                        if RouteRecorder.shared.isActive {
                            recordingBanner
                        } else if viewModel.showRecordingHint {
                            recordingHintCard
                        }

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

                        // Ошибка или неполный результат замера: значения не выдумываются, причина показывается явно
                        if let speedError = viewModel.speedtestError, !viewModel.isSpeedtestRunning {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(NPTheme.semanticWarn)

                                Text(speedError)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(NPTheme.textPrimary)
                                    .lineSpacing(2)

                                Spacer()
                            }
                            .padding(14)
                            .npGlassCard(cornerRadius: 14)
                        }

                        // 2. Рекламный баннер Meta Audience Network на самом видном месте
                        MetaBannerView(contextTag: "Сетевые утилиты")

                        // 3. Быстрые карточки Pro-инструментов (DNS, Gaming, Bufferbloat, LAN, Карта сети)
                        quickToolsSection

                        // 4. Блок оценки применимости скорости (Для чего подходит сеть)
                        NetworkCapabilityCardView(items: capabilities)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 110) // Безопасный отступ для закрепленного баннера Meta и таб-бара
                }
            }
            .navigationTitle("NetPulse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        HapticManager.shared.impactMedium()
                        if !ActivityManager.shared.isLiveActivityActive {
                            viewModel.toggleLiveActivity(enabled: true)
                        } else {
                            viewModel.restartLiveActivity()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(ActivityManager.shared.isLiveActivityActive ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            Text(ActivityManager.shared.isLiveActivityActive ? "Островок" : "Старт островка")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(NPTheme.textPrimary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                }

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
            }
            .sheet(isPresented: $showGlossarySheet) {
                NetworkGlossarySheetView()
            }
            .navigationDestination(isPresented: $showMapFromHint) {
                NetworkMapView()
            }
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

                NavigationLink(destination: NetworkMapView()) {
                    quickDashboardChip(
                        title: "Карта сети",
                        icon: "map.fill",
                        color: Color.orange
                    )
                }
                .buttonStyle(NPPressableButtonStyle())
                .accessibilityIdentifier("networkMapChip")
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
