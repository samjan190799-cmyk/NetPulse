//
//  AIDiagnosticsView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import UIKit

/// Главный экран AI-Диагноста 2026 с нейросферой (Neural Pulse Orb),
/// агентским Tool Calling, предиктивными аномалиями и мастером траблшутинга. Входит в подписку PRO и открывается
/// из «Инструментов».
public struct AIDiagnosticsView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    @State private var inputText: String = ""
    @State private var showCopiedReportToast: Bool = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool

    public var body: some View {
        NavigationStack {
            ZStack {
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 18) {
                            // 1. Провайдер и статус движка AI
                            providerStatusPill

                            // 2. Баннер активного вызова инструментов агента (Tool Execution Banner)
                            if let toolCall = viewModel.activeToolCall {
                                activeToolExecutionBanner(toolCall: toolCall)
                            }

                            // 3. Быстрые интеллектуальные действия (Мастер проблем и Претензия ISP)
                            quickActionsHub

                            // 3.1 Глубокий AI-аудит: доступен всем; если реклама включена, перед ним может быть ролик
                            rewardedAIAnalysisCard

                            // 4. Карточка здоровья сети (Health Score 0-100) с нейросферой
                            networkHealthCard

                            // 5. Предиктивные сетевые аномалии и вечерние просадки
                            if let anomalyReport = viewModel.currentAnomalyReport, !anomalyReport.anomalies.isEmpty {
                                predictiveAnomaliesCard(report: anomalyReport)
                            }

                            // 6. Выявленные проблемы и рекомендации AI
                            if let report = viewModel.currentHealthReport, !report.identifiedIssues.isEmpty {
                                issuesAndRecommendationsSection(report: report)
                            }

                            // 8. Сценарии интерактивного мастера траблшутинга
                            troubleshootingScenariosSection

                            // 9. Интерактивный диалог с AI
                            chatHistorySection

                            // Точка для автоскролла вниз
                            Color.clear
                                .frame(height: 1)
                                .id("bottomID")
                        }
                        .padding(.vertical)
                        .padding(.bottom, 70) // Безопасный отступ для закрепленного рекламного баннера и таб-бара
                    }
                    .onChange(of: viewModel.aiMessages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo("bottomID", anchor: .bottom)
                        }
                    }
                }

                // Всплывающее уведомление о копировании претензии/отчета для ISP
                if showCopiedReportToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(NPTheme.accentPrimary)
                            Text("Обращение для провайдера скопировано")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(NPTheme.textPrimary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(NPTheme.cardBackground)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(NPTheme.accentPrimary.opacity(0.35), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.4), radius: 10, y: 5)
                        .padding(.bottom, 70)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .zIndex(10)
                }
            }
            .navigationTitle("AI-аудит")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NPTheme.accentPrimary)
                    .accessibilityIdentifier("aiAuditCloseButton")
                }
            }
            .safeAreaInset(edge: .bottom) {
                chatInputBar
            }
            .sheet(isPresented: $viewModel.showTroubleshootingSheet) {
                TroubleshootingWizardSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showDisputeSheet) {
                ISPDisputeLetterSheet(viewModel: viewModel, onCopied: {
                    withAnimation { showCopiedReportToast = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation { showCopiedReportToast = false }
                    }
                })
            }
            .task {
                if viewModel.currentHealthReport == nil {
                    await viewModel.runAIDiagnosticsAudit()
                }
            }
        }
    }

    // MARK: - 1. Статус выбранного AI-провайдера

    private var providerStatusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(NPTheme.accentPrimary)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text("Встроенный AI")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NPTheme.textPrimary)
                Text("Работает на устройстве, данные никуда не отправляются")
                    .font(.system(size: 10))
                    .foregroundStyle(NPTheme.textSecondary)
            }

            Spacer()

            Button {
                Task {
                    await viewModel.runAIDiagnosticsAudit()
                }
                HapticManager.shared.impactLight()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Обновить аудит")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NPTheme.accentPrimary)
            }
            .buttonStyle(NPPressableButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .npGlassCard(cornerRadius: 12)
        .padding(.horizontal)
    }

    // MARK: - 2. Баннер исполнения сетевого инструмента агентом

    private func activeToolExecutionBanner(toolCall: AIToolCall) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(NPTheme.accentPrimary)
                .scaleEffect(0.8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: toolCall.toolType.icon)
                        .font(.system(size: 11, weight: .bold))
                    Text("AI-Агент запускает: \(toolCall.toolType.displayName)")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(NPTheme.accentPrimary)

                Text("Целевой узел: \(toolCall.target)")
                    .font(.system(size: 11))
                    .foregroundStyle(NPTheme.textSecondary)
            }

            Spacer()
        }
        .padding(12)
        .background(NPTheme.accentPrimary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NPTheme.accentPrimary.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - 3. Быстрые интеллектуальные действия

    private var quickActionsHub: some View {
        HStack(spacing: 10) {
            // Кнопка запуска мастера проблем
            Button {
                Task {
                    await viewModel.runTroubleshootingWizard()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NPTheme.accentPrimary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Мастер проблем")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(NPTheme.textPrimary)
                        Text("Пошаговый анализ")
                            .font(.system(size: 10))
                            .foregroundStyle(NPTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NPTheme.textTertiary)
                }
                .padding(12)
                .npGlassCard(cornerRadius: 14)
            }
            .buttonStyle(NPPressableButtonStyle())

            // Кнопка официальной претензии провайдеру
            Button {
                viewModel.showDisputeSheet = true
                HapticManager.shared.impactLight()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.badge.plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NPTheme.semanticWarn)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Обращение провайдеру")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(NPTheme.textPrimary)
                        Text("Текст для техподдержки")
                            .font(.system(size: 10))
                            .foregroundStyle(NPTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NPTheme.textTertiary)
                }
                .padding(12)
                .npGlassCard(cornerRadius: 14)
            }
            .buttonStyle(NPPressableButtonStyle())
        }
        .padding(.horizontal)
    }

    // MARK: - 3.1 Глубокий AI-аудит

    /// Запуск полного аудита. Аудит локальный (его же запускает «Обновить аудит»).
    private func runDeepAudit() {
        Task {
            await viewModel.runAIDiagnosticsAudit()
            HapticManager.shared.notificationSuccess()
        }
    }

    private var rewardedAIAnalysisCard: some View {
        Button {
            runDeepAudit()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.0, green: 0.55, blue: 1.0),
                                    Color(red: 0.6, green: 0.1, blue: 0.9)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)

                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Глубокий AI-аудит сети")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NPTheme.textPrimary)

                    Text("Запустить полный анализ параметров сети")
                        .font(.system(size: 11))
                        .foregroundStyle(NPTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.yellow)
            }
            .padding(12)
            .npGlassCard(cornerRadius: 14)
        }
        .buttonStyle(NPPressableButtonStyle(scale: 0.98))
        .padding(.horizontal)
    }

    // MARK: - 4. Главная карточка здоровья сети с нейросферой

    private var networkHealthCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                AINeuralOrbView(isAnalyzing: viewModel.isAIAnalyzing)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Индекс здоровья сети")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NPTheme.textSecondary)
                        Spacer()
                        if let report = viewModel.currentHealthReport {
                            Text(report.overallScore.map { "\($0)/100" } ?? "—")
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(report.statusBadgeColor)
                        }
                    }

                    if let report = viewModel.currentHealthReport {
                        Text(report.statusTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(NPTheme.textPrimary)

                        Text(report.summaryText)
                            .font(.system(size: 12))
                            .foregroundStyle(NPTheme.textSecondary)
                            .lineLimit(3)
                    } else {
                        Text("Инициализация телеметрии...")
                            .font(.system(size: 14))
                            .foregroundStyle(NPTheme.textTertiary)
                    }
                }
            }

            // Шкалы готовности к ключевым сценариям
            if let report = viewModel.currentHealthReport {
                Divider()
                    .background(NPTheme.border)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    healthScorePill(title: "Гейминг", score: report.gamingScore, icon: "gamecontroller.fill")
                    healthScorePill(title: "4K Видео", score: report.streamingScore, icon: "tv.fill")
                    healthScorePill(title: "Звонки", score: report.videoCallScore, icon: "video.fill")
                    healthScorePill(title: "Сайты", score: report.webBrowsingScore, icon: "globe")
                }
            }
        }
        .padding(16)
        .npGlassCard(cornerRadius: 20)
        .padding(.horizontal)
    }

    /// `score == nil` — для этой категории нет измерений: показывается «—», а не выдуманное значение
    private func healthScorePill(title: String, score: Int?, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(
                    score.map { $0 >= 80 ? NPTheme.accentPrimary : ($0 >= 50 ? NPTheme.semanticWarn : NPTheme.semanticCritical) }
                        ?? NPTheme.textTertiary
                )
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NPTheme.textSecondary)
            Text(score.map { "\($0)%" } ?? "—")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NPTheme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 5. Предиктивные сетевые аномалии (AI Anomaly Detector)

    private func predictiveAnomaliesCard(report: NetworkAnomalyReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(report.overallRiskLevel == .critical ? NPTheme.semanticCritical : NPTheme.semanticWarn)
                    Text("Отклонения по текущим измерениям")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NPTheme.textPrimary)
                }
                Spacer()
                Text("Найдено: \(report.anomalies.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(report.overallRiskLevel == .critical ? NPTheme.semanticCritical : NPTheme.semanticWarn)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((report.overallRiskLevel == .critical ? NPTheme.semanticCritical : NPTheme.semanticWarn).opacity(0.15))
                    .clipShape(Capsule())
            }

            ForEach(report.anomalies) { anomaly in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: anomaly.type.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(anomaly.severity == .critical ? NPTheme.semanticCritical : NPTheme.semanticWarn)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(anomaly.title)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(NPTheme.textPrimary)
                            Spacer()
                            Text(anomaly.metricValue)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(NPTheme.accentPrimary)
                        }

                        Text(anomaly.description)
                            .font(.system(size: 11))
                            .foregroundStyle(NPTheme.textSecondary)

                        Text("Решение: \(anomaly.suggestedFix)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NPTheme.accentPrimary)
                            .padding(.top, 2)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(14)
        .npGlassCard(cornerRadius: 16)
        .padding(.horizontal)
    }

    // MARK: - 6. Выявленные проблемы и рекомендации

    private func issuesAndRecommendationsSection(report: NetworkHealthReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ОБНАРУЖЕННЫЕ ФАКТОРЫ ЗАМЕДЛЕНИЯ")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NPTheme.textTertiary)
                .tracking(0.5)
                .padding(.horizontal)

            VStack(spacing: 8) {
                ForEach(report.identifiedIssues) { issue in
                    HStack(spacing: 10) {
                        Image(systemName: issue.severity == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(issue.severity == .critical ? NPTheme.semanticCritical : NPTheme.semanticWarn)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(NPTheme.textPrimary)
                            Text(issue.description)
                                .font(.system(size: 11))
                                .foregroundStyle(NPTheme.textSecondary)
                        }
                        Spacer()
                        Text(issue.component)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(NPTheme.textTertiary)
                    }
                    .padding(12)
                    .npGlassCard(cornerRadius: 12)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - 7. Сценарии мастера траблшутинга (4 сценария)

    private var troubleshootingScenariosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ПОШАГОВЫЙ МАСТЕР ДИАГНОСТИКИ")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NPTheme.textTertiary)
                .tracking(0.5)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(TroubleshootingScenarioType.allCases) { scenario in
                        Button {
                            Task {
                                await viewModel.runTroubleshootingWizard(scenario: scenario)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: scenario.icon)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(NPTheme.accentPrimary)
                                    Spacer()
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(NPTheme.textTertiary)
                                }

                                Text(scenario.rawValue)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(NPTheme.textPrimary)
                                    .lineLimit(1)

                                Text(scenario.description)
                                    .font(.system(size: 10))
                                    .foregroundStyle(NPTheme.textSecondary)
                                    .lineLimit(2)
                            }
                            .frame(width: 170, alignment: .leading)
                            .padding(12)
                            .npGlassCard(cornerRadius: 14)
                        }
                        .buttonStyle(NPPressableButtonStyle())
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - 8. Интерактивный диалог с AI

    private var chatHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ДИАЛОГ С AI-ДИАГНОСТОМ")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NPTheme.textTertiary)
                .tracking(0.5)
                .padding(.horizontal)

            VStack(spacing: 10) {
                ForEach(viewModel.aiMessages) { msg in
                    AIMessageBubble(message: msg)
                }

                if viewModel.isAIAnalyzing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("AI анализирует сетевые интерфейсы...")
                            .font(.system(size: 12))
                            .foregroundStyle(NPTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - 9. Нижняя панель ввода со смарт-чипами

    private var chatInputBar: some View {
        VStack(spacing: 8) {
            // Адаптивные динамические смарт-чипы
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.smartContextChips, id: \.self) { prompt in
                        Button {
                            inputText = prompt
                            isInputFocused = true
                            HapticManager.shared.impactLight()
                        } label: {
                            Text(prompt)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(NPTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        }
                        .buttonStyle(NPPressableButtonStyle())
                    }
                }
                .padding(.horizontal)
            }

            HStack(spacing: 8) {
                // Текстовое поле
                TextField("Спросите AI или введите хост...", text: $inputText)
                    .font(.system(size: 14))
                    .foregroundStyle(NPTheme.textPrimary)
                    .focused($isInputFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(NPTheme.border, lineWidth: 1))

                // Кнопка отправки
                Button {
                    guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    let text = inputText
                    inputText = ""
                    isInputFocused = false
                    HapticManager.shared.impactLight()
                    Task {
                        await viewModel.sendAIMessage(text)
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(inputText.isEmpty ? NPTheme.textTertiary : NPTheme.accentPrimary)
                }
                .npMinHitTarget()
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isAIAnalyzing)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(NPTheme.cardBackground.ignoresSafeArea(edges: .bottom))
        }
    }
}

// MARK: - 3D Нейросфера (Neural Pulse Orb)

public struct AINeuralOrbView: View {
    public let isAnalyzing: Bool

    @State private var rotatePhase: Double = 0
    @State private var pulseScale: CGFloat = 1.0

    public init(isAnalyzing: Bool = false) {
        self.isAnalyzing = isAnalyzing
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [NPTheme.accentPrimary.opacity(isAnalyzing ? 0.35 : 0.15), Color.clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 40
                    )
                )
                .scaleEffect(pulseScale)

            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            NPTheme.accentPrimary.opacity(0.8),
                            NPTheme.accentSoft.opacity(0.2),
                            NPTheme.accentSilver.opacity(0.6),
                            NPTheme.accentPrimary.opacity(0.8)
                        ],
                        center: .center
                    ),
                    lineWidth: 2.5
                )
                .rotationEffect(.degrees(rotatePhase))

            Circle()
                .fill(NPTheme.accentPrimary.opacity(isAnalyzing ? 0.25 : 0.12))
                .frame(width: 28, height: 28)
        }
        .onAppear {
            withAnimation(.linear(duration: isAnalyzing ? 3.0 : 8.0).repeatForever(autoreverses: false)) {
                rotatePhase = 360
            }
            withAnimation(.easeInOut(duration: isAnalyzing ? 0.8 : 2.0).repeatForever(autoreverses: true)) {
                pulseScale = isAnalyzing ? 1.25 : 1.05
            }
        }
    }
}

// MARK: - Пузырь сообщения чата с бейджами вызова инструментов

private struct AIMessageBubble: View {
    let message: AIMessage
    @State private var showCopiedNotification: Bool = false

    var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if !isUser {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NPTheme.accentPrimary)
                        Text("NetPulse AI")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NPTheme.accentPrimary)

                        Spacer()

                        Button {
                            UIPasteboard.general.string = message.content
                            HapticManager.shared.notificationSuccess()
                            withAnimation {
                                showCopiedNotification = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation {
                                    showCopiedNotification = false
                                }
                            }
                        } label: {
                            Image(systemName: showCopiedNotification ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(showCopiedNotification ? NPTheme.accentPrimary : NPTheme.textTertiary)
                        }
                        .npMinHitTarget()
                    }
                }

                // Бейдж исполненного инструмента агента
                if let tool = message.toolCall, let result = message.toolResult {
                    HStack(spacing: 6) {
                        Image(systemName: tool.toolType.icon)
                            .font(.system(size: 10, weight: .bold))
                        Text("\(tool.toolType.displayName): \(tool.target)")
                            .font(.system(size: 10, weight: .bold))
                        Spacer()
                        Text("\(Int(result.executionTimeMs)) мс")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(NPTheme.accentPrimary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(NPTheme.accentPrimary)
                }

                Text(LocalizedStringKey(message.content))
                    .font(.system(size: 14))
                    .foregroundStyle(isUser ? NPTheme.backgroundDeep : NPTheme.textPrimary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isUser ? NPTheme.accentPrimary : NPTheme.cardBackground.opacity(0.9)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isUser ? Color.clear : NPTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Интерактивный мастер устранения неполадок (Sheet)

private struct TroubleshootingWizardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: NetworkMonitorViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(NPTheme.accentPrimary.opacity(0.1))
                                    .frame(width: 44, height: 44)
                                Image(systemName: viewModel.selectedTroubleshootingScenario.icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(NPTheme.accentPrimary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewModel.selectedTroubleshootingScenario.rawValue)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(NPTheme.textPrimary)
                                Text(viewModel.selectedTroubleshootingScenario.description)
                                    .font(.system(size: 12))
                                    .foregroundStyle(NPTheme.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        // Шаги проверки
                        VStack(spacing: 10) {
                            if let steps = viewModel.troubleshootingReport?.steps {
                                ForEach(steps) { step in
                                    troubleshootingStepRow(step: step)
                                }
                            } else {
                                ProgressView("Анализ сетевых узлов...")
                                    .padding(.vertical, 30)
                            }
                        }
                        .padding(.horizontal)

                        // Итоговый план действий
                        if let report = viewModel.troubleshootingReport {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: report.isIssueFound ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(report.isIssueFound ? NPTheme.semanticWarn : NPTheme.accentPrimary)

                                    Text("План действий:")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(NPTheme.textPrimary)
                                }

                                Text(report.conclusion)
                                    .font(.system(size: 13))
                                    .foregroundStyle(NPTheme.textSecondary)

                                Divider()
                                    .background(NPTheme.border)

                                ForEach(Array(report.actionPlan.enumerated()), id: \.offset) { idx, action in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(idx + 1).")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(NPTheme.accentPrimary)

                                        Text(action)
                                            .font(.system(size: 13))
                                            .foregroundStyle(NPTheme.textPrimary)
                                    }
                                }
                            }
                            .padding(16)
                            .npGlassCard(cornerRadius: 16)
                            .padding(.horizontal)
                        }

                        // Кнопка повторного запуска
                        Button {
                            Task {
                                await viewModel.runTroubleshootingWizard()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text("Повторить проверку")
                            }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(NPTheme.backgroundDeep)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(NPTheme.accentPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(NPPressableButtonStyle())
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Мастер траблшутинга")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NPTheme.accentPrimary)
                }
            }
        }
    }

    private func troubleshootingStepRow(step: TroubleshootingStep) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor(step.status).opacity(0.12))
                    .frame(width: 36, height: 36)

                Image(systemName: step.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(statusColor(step.status))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(step.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NPTheme.textPrimary)
                    Spacer()
                    statusBadge(step.status)
                }

                if let detail = step.resultDetail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(statusColor(step.status))
                } else {
                    Text(step.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(NPTheme.textSecondary)
                }
            }
        }
        .padding(12)
        .npGlassCard(cornerRadius: 14)
    }

    private func statusColor(_ status: TroubleshootingStepStatus) -> Color {
        switch status {
        case .pending: return NPTheme.textTertiary
        case .running: return NPTheme.accentPrimary
        case .success: return NPTheme.accentPrimary
        case .warning: return NPTheme.semanticWarn
        case .critical: return NPTheme.semanticCritical
        case .skipped: return NPTheme.textTertiary
        }
    }

    private func statusBadge(_ status: TroubleshootingStepStatus) -> some View {
        Group {
            switch status {
            case .pending:
                Text("Ожидание")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NPTheme.textTertiary)
            case .running:
                ProgressView()
                    .scaleEffect(0.6)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(NPTheme.accentPrimary)
                    .font(.system(size: 12))
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(NPTheme.semanticWarn)
                    .font(.system(size: 12))
            case .critical:
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(NPTheme.semanticCritical)
                    .font(.system(size: 12))
            case .skipped:
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(NPTheme.textTertiary)
                    .font(.system(size: 12))
            }
        }
    }
}

// MARK: - Лист официальной претензии интернет-провайдеру (ISP Dispute Letter Sheet)

private struct ISPDisputeLetterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: NetworkMonitorViewModel
    let onCopied: () -> Void

    @State private var selectedTemplate: ISPDisputeTemplate = .packetLossAndLatency

    var body: some View {
        NavigationStack {
            ZStack {
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Выбор шаблона претензии
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ШАБЛОН ОБРАЩЕНИЯ")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(NPTheme.textTertiary)
                                .tracking(0.5)

                            Picker("Шаблон обращения", selection: $selectedTemplate) {
                                ForEach(ISPDisputeTemplate.allCases) { t in
                                    Text(t.rawValue).tag(t)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.horizontal)

                        // Предпросмотр сформированного текста
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .foregroundStyle(NPTheme.accentPrimary)
                                Text("Текст обращения:")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(NPTheme.textPrimary)
                                Spacer()
                            }

                            Text(viewModel.buildDiagnosticsContext().generateISPSupportReport(template: selectedTemplate))
                                .font(.system(size: 11, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(NPTheme.textPrimary)
                                .padding(12)
                                .background(Color.black.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .textSelection(.enabled)
                        }
                        .padding(14)
                        .npGlassCard(cornerRadius: 16)
                        .padding(.horizontal)

                        // Кнопки копирования и экспорта
                        VStack(spacing: 10) {
                            Button {
                                _ = viewModel.copyISPSupportReport(template: selectedTemplate)
                                onCopied()
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.on.doc.fill")
                                    Text("Скопировать текст обращения")
                                }
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(NPTheme.backgroundDeep)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(NPTheme.accentPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(NPPressableButtonStyle())
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Обращение провайдеру")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { dismiss() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NPTheme.accentPrimary)
                }
            }
        }
    }
}
