//
//  BufferbloatView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Экран анализатора Bufferbloat (задержка под нагрузкой)
public struct BufferbloatView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    @State private var isRunning: Bool = false
    @State private var currentPhase: BufferbloatPhase = .idle
    @State private var currentLivePing: Double = 0.0
    @State private var report: BufferbloatReport?
    @State private var errorMessage: String?
    @State private var testTask: Task<Void, Never>?
    @State private var showCellularConfirmation: Bool = false

    private var isCellular: Bool {
        viewModel.systemInfo.connectionType == .cellular
    }

    private var isOffline: Bool {
        viewModel.systemInfo.connectionType == .unavailable
    }

    public var body: some View {
        ZStack {
            NPTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // 1. Главная карточка с грейдом A+...F
                    gradeHeroCard

                    // 2. Фазы тестирования (Индикатор текущего этапа)
                    testingPhasesCard

                    // Рекламный баннер Яндекса на видном месте
                    YandexBannerView(contextTag: "Оборудование и роутеры")
                        .padding(.horizontal)

                    // 3. Детальное сравнение ненагруженного и нагруженного пинга
                    if let r = report {
                        metricsComparisonSection(report: r)
                    }

                    // 4. Персональные рекомендации по настройке роутера
                    if let r = report {
                        recommendationsCard(report: r)
                    } else {
                        bufferbloatIntroCard
                    }
                }
                .padding(.vertical)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Bufferbloat Тест")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar) // Скрываем таб-бар на детальном экране
        .onDisappear {
            // Тест создаёт сетевую нагрузку — при уходе с экрана он останавливается
            testTask?.cancel()
        }
        .confirmationDialog(
            "Тест на мобильной сети",
            isPresented: $showCellularConfirmation,
            titleVisibility: .visible
        ) {
            Button("Запустить тест") {
                startBufferbloatTest()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Тест создаёт нагрузку на канал и может передать до 120 МБ мобильного трафика (до 60 МБ на скачивание и на отдачу). Запустить через мобильную сеть?")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    requestStart()
                } label: {
                    if isRunning {
                        ProgressView()
                            .tint(NPTheme.accentPrimary)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(NPTheme.accentPrimary)
                    }
                }
                .disabled(isRunning)
                .npMinHitTarget()
            }
        }
    }

    // MARK: - 1. Карточка с грейдом (A+ ... F)

    private var gradeHeroCard: some View {
        VStack(spacing: 14) {
            if let r = report {
                ZStack {
                    Circle()
                        .fill((r.grade?.badgeColor ?? NPTheme.textTertiary).opacity(0.15))
                        .frame(width: 90, height: 90)

                    Text(r.grade?.rawValue ?? "—")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundStyle(r.grade?.badgeColor ?? NPTheme.textTertiary)
                }

                VStack(spacing: 4) {
                    Text(r.dynamicVerdictTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(NPTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(r.dynamicVerdictDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(NPTheme.accentPrimary.opacity(0.12))
                        .frame(width: 80, height: 80)

                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 34))
                        .foregroundStyle(NPTheme.accentPrimary)
                }

                VStack(spacing: 4) {
                    Text("Тест задержки под нагрузкой")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(NPTheme.textPrimary)

                    Text("Проверьте, переполняются ли буферы роутера при одновременном скачивании и звонках.")
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            if let errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(NPTheme.semanticWarn)
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NPTheme.semanticWarn.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if isRunning && currentLivePing > 0 {
                Text(String(format: "Задержка сейчас: %.0f мс", currentLivePing))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(NPTheme.textSecondary)
            }

            // Кнопка запуска
            Button {
                requestStart()
            } label: {
                HStack(spacing: 8) {
                    if isRunning {
                        ProgressView()
                            .tint(NPTheme.backgroundDeep)
                        Text(currentPhase.rawValue)
                    } else {
                        Image(systemName: "play.fill")
                        Text(report == nil ? "Запустить тест Bufferbloat" : "Повторить тест")
                    }
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(NPTheme.backgroundDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isRunning ? NPTheme.accentSoft : NPTheme.accentPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(NPPressableButtonStyle())
            .disabled(isRunning)
        }
        .padding(20)
        .npGlassCard(cornerRadius: 24)
        .padding(.horizontal)
    }

    // MARK: - 2. Индикатор фаз тестирования

    private var testingPhasesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ЭТАПЫ ИЗМЕРЕНИЯ:")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NPTheme.textTertiary)
                .tracking(0.5)

            VStack(spacing: 8) {
                phaseRow(
                    title: "1. Без нагрузки (Idle)",
                    subtitle: "Базовая задержка до опорного узла",
                    icon: "speedometer",
                    isActive: currentPhase == .unloadedLatency,
                    isDone: (report != nil && !isRunning) || currentPhase == .downloadSaturation || currentPhase == .uploadSaturation || currentPhase == .completed
                )

                phaseRow(
                    title: "2. Насыщение скачивания (Download)",
                    subtitle: "Замер роста RTT при максимальной загрузке",
                    icon: "arrow.down.circle.fill",
                    isActive: currentPhase == .downloadSaturation,
                    isDone: (report != nil && !isRunning) || currentPhase == .uploadSaturation || currentPhase == .completed
                )

                phaseRow(
                    title: "3. Насыщение отдачи (Upload)",
                    subtitle: "Замер задержки при исходящем потоке",
                    icon: "arrow.up.circle.fill",
                    isActive: currentPhase == .uploadSaturation,
                    isDone: (report != nil && !isRunning) || currentPhase == .completed
                )
            }
        }
        .padding(14)
        .npGlassCard(cornerRadius: 16)
        .padding(.horizontal)
    }

    private func phaseRow(title: String, subtitle: String, icon: String, isActive: Bool, isDone: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : (isActive ? "arrow.triangle.2.circlepath" : icon))
                .font(.system(size: 16))
                .foregroundStyle(isDone ? NPTheme.accentPrimary : (isActive ? NPTheme.semanticWarn : NPTheme.textTertiary))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isActive ? NPTheme.accentPrimary : NPTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(NPTheme.textSecondary)
            }

            Spacer()

            if isActive {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(10)
        .background(isActive ? NPTheme.accentPrimary.opacity(0.08) : Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 3. Сравнение метрик (Дельта задержки)

    private func metricsComparisonSection(report: BufferbloatReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("РЕЗУЛЬТАТЫ ЗАМЕРОВ И ДЕЛЬТА ЗАДЕРЖКИ:")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NPTheme.textTertiary)
                .tracking(0.5)

            HStack(spacing: 10) {
                metricBox(
                    title: "Базовый пинг",
                    value: String(format: "%.1f мс", report.unloadedPingMs),
                    delta: "0.0 мс",
                    color: NPTheme.accentPrimary
                )

                metricBox(
                    title: "При скачивании",
                    value: formatMs(report.loadedDownloadPingMs),
                    delta: formatDelta(report.downloadDeltaMs),
                    color: deltaColor(report.downloadDeltaMs, critical: NPTheme.semanticWarn)
                )

                metricBox(
                    title: "При отдаче",
                    value: formatMs(report.loadedUploadPingMs),
                    delta: formatDelta(report.uploadDeltaMs),
                    color: deltaColor(report.uploadDeltaMs, critical: NPTheme.semanticCritical)
                )
            }

            HStack(spacing: 10) {
                metricBox(
                    title: "Скорость ↓ в тесте",
                    value: formatSpeed(report.downloadSpeedMbps),
                    delta: formatLoss(report.downloadLossPercent),
                    color: lossColor(report.downloadLossPercent)
                )

                metricBox(
                    title: "Скорость ↑ в тесте",
                    value: formatSpeed(report.uploadSpeedMbps),
                    delta: formatLoss(report.uploadLossPercent),
                    color: lossColor(report.uploadLossPercent)
                )
            }

            if !report.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(report.notes.enumerated()), id: \.offset) { _, note in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(NPTheme.semanticWarn)
                            Text(note)
                                .font(.system(size: 11))
                                .foregroundStyle(NPTheme.textSecondary)
                        }
                    }
                }
                .padding(.top, 2)
            }

            Text("Задержка измеряется TCP-рукопожатием до \(BufferbloatConfiguration().probeHost):443 (медиана), нагрузка создаётся через speed.cloudflare.com. Результат ориентировочный.")
                .font(.system(size: 10))
                .foregroundStyle(NPTheme.textTertiary)
        }
        .padding(.horizontal)
    }

    private func formatMs(_ value: Double?) -> String {
        value.map { String(format: "%.1f мс", $0) } ?? "—"
    }

    private func formatDelta(_ value: Double?) -> String {
        value.map { "+\(String(format: "%.1f", $0)) мс" } ?? "нет данных"
    }

    private func formatSpeed(_ value: Double?) -> String {
        value.map { String(format: "%.1f Мбит/с", $0) } ?? "—"
    }

    private func formatLoss(_ value: Double?) -> String {
        value.map { String(format: "потери %.0f %%", $0) } ?? "потери: —"
    }

    private func deltaColor(_ delta: Double?, critical: Color) -> Color {
        guard let delta else { return NPTheme.textTertiary }
        return delta < 15 ? NPTheme.accentPrimary : critical
    }

    private func lossColor(_ loss: Double?) -> Color {
        guard let loss else { return NPTheme.textTertiary }
        return loss < BufferbloatReport.lossPenaltyThresholdPercent ? NPTheme.accentPrimary : NPTheme.semanticWarn
    }

    private func metricBox(title: String, value: String, delta: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NPTheme.textSecondary)

            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NPTheme.textPrimary)

            Text(delta)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .npGlassCard(cornerRadius: 14)
    }

    // MARK: - 4. Персональные рекомендации

    private func recommendationsCard(report: BufferbloatReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(NPTheme.accentPrimary)
                Text("Рекомендации по устранению задержек:")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(report.recommendations.enumerated()), id: \.offset) { idx, rec in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1).")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(NPTheme.accentPrimary)

                        Text(rec)
                            .font(.system(size: 12))
                            .foregroundStyle(NPTheme.textSecondary)
                    }
                }
            }
        }
        .padding(14)
        .npGlassCard(cornerRadius: 16)
        .padding(.horizontal)
    }

    private var bufferbloatIntroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(NPTheme.accentPrimary)
                Text("Что такое Bufferbloat?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)
            }

            Text("Bufferbloat — это нежелательная задержка, возникающая из-за того, что роутер буферизирует слишком много пакетов при интенсивной передаче данных. Из-за этого пинг в играх подскакивает с 20 мс до 300+ мс, когда кто-то в доме качает файл.")
                .font(.system(size: 11))
                .foregroundStyle(NPTheme.textSecondary)
        }
        .padding(14)
        .npGlassCard(cornerRadius: 14)
        .padding(.horizontal)
    }

    // MARK: - Запуск теста

    /// Проверки перед запуском: без сети тест невозможен, на мобильной сети нужно подтверждение (расход трафика)
    private func requestStart() {
        guard !isRunning else { return }
        if isOffline {
            errorMessage = "Нет подключения к сети — тест невозможен."
            HapticManager.shared.notificationWarning()
            return
        }
        if isCellular {
            showCellularConfirmation = true
        } else {
            startBufferbloatTest()
        }
    }

    private func startBufferbloatTest() {
        guard !isRunning else { return }
        isRunning = true
        errorMessage = nil
        currentPhase = .unloadedLatency
        currentLivePing = 0.0
        HapticManager.shared.impactMedium()

        let cellular = isCellular
        testTask = Task {
            let result = await BufferbloatEngine.shared.runBufferbloatTest(
                configuration: cellular ? BufferbloatConfiguration.cellular : BufferbloatConfiguration(),
                isCellular: cellular
            ) { phase, livePing in
                Task { @MainActor in
                    self.currentPhase = phase
                    self.currentLivePing = livePing
                }
            }

            switch result {
            case .success(let value):
                self.report = value
                self.currentPhase = .completed
                HapticManager.shared.notificationSuccess()
            case .failure(let error):
                self.currentPhase = .idle
                if error != .cancelled {
                    self.errorMessage = error.localizedDescription
                    HapticManager.shared.notificationError()
                }
            }
            self.isRunning = false
            self.testTask = nil
        }
    }
}
