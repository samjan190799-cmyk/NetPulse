//
//  AIDiagnosticsView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import UIKit

/// Главный экран AI-Диагноста 2026 с нейросферой (Neural Pulse Orb),
/// интерактивными смарт-чипами действий и стеклянным морфизмом.
public struct AIDiagnosticsView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    @State private var inputText: String = ""
    @State private var showSettingsSheet: Bool = false
    @State private var showCopiedReportToast: Bool = false
    @FocusState private var isInputFocused: Bool

    private let quickPrompts: [String] = [
        "🎮 Почему лагает онлайн-игра?",
        "📺 Хватит ли скорости для 4K/8K?",
        "🌐 Какой DNS самый быстрый?",
        "📊 Анализ Bufferbloat и джиттера",
        "💼 Оптимизация под Zoom и FaceTime",
        "📡 Как улучшить Wi-Fi 5/6 GHz?",
        "🔍 Анализ потерь пакетов"
    ]

    public var body: some View {
        NavigationStack {
            ZStack {
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 18) {
                            // 1. Провайдер и статус движка
                            providerStatusPill

                            // 2. Быстрые интеллектуальные действия (Мастер проблем и Отчет)
                            quickActionsHub

                            // 3. Главная карточка здоровья сети (Health Score 0-100) с нейросферой
                            networkHealthCard

                            // 4. Выявленные проблемы и рекомендации AI
                            if let report = viewModel.currentHealthReport, !report.identifiedIssues.isEmpty {
                                issuesAndRecommendationsSection(report: report)
                            }

                            // 5. Интерактивный диалог с AI
                            chatHistorySection

                            // Точка для автоскролла вниз
                            Color.clear
                                .frame(height: 1)
                                .id("bottomID")
                        }
                        .padding(.vertical)
                    }
                    .onChange(of: viewModel.aiMessages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo("bottomID", anchor: .bottom)
                        }
                    }
                }

                // Всплывающее уведомление о копировании отчета для ISP
                if showCopiedReportToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(NPTheme.accentPrimary)
                            Text("Технический отчет для провайдера скопирован")
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
            .navigationTitle("AI Диагност")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettingsSheet = true
                        HapticManager.shared.impactLight()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(NPTheme.accentPrimary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                chatInputBar
            }
            .sheet(isPresented: $showSettingsSheet) {
                AIProviderSettingsSheet(
                    config: viewModel.aiProviderConfig,
                    onSave: { newConfig in
                        viewModel.updateAIConfig(newConfig)
                    }
                )
            }
            .sheet(isPresented: $viewModel.showTroubleshootingSheet) {
                TroubleshootingWizardSheet(viewModel: viewModel)
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
                .fill(viewModel.aiProviderConfig.selectedProvider == .offlineSmart ? NPTheme.accentPrimary : NPTheme.accentSilver)
                .frame(width: 7, height: 7)

            Text(viewModel.aiProviderConfig.selectedProvider.rawValue)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NPTheme.textPrimary)

            Spacer()

            Button {
                Task {
                    await viewModel.runAIDiagnosticsAudit()
                }
                HapticManager.shared.impactLight()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                    Text("Обновить аудит")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(NPTheme.accentPrimary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(NPTheme.cardBackground.opacity(0.85))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(NPTheme.border, lineWidth: 1))
        .padding(.horizontal)
    }

    // MARK: - 2. Быстрые действия AI (Мастер проблем и Отчет)

    private var quickActionsHub: some View {
        HStack(spacing: 12) {
            // Кнопка мастера устранения проблем
            Button {
                Task {
                    await viewModel.runTroubleshootingWizard()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NPTheme.backgroundDeep)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Мастер проблем")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(NPTheme.backgroundDeep)
                        Text("Авто-поиск причин")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NPTheme.backgroundDeep.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NPTheme.backgroundDeep.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(NPTheme.buttonGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: NPTheme.glowActive, radius: 6, x: 0, y: 2)
            }

            // Кнопка генерации отчета для провайдера
            Button {
                _ = viewModel.copyISPSupportReport()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showCopiedReportToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation {
                        showCopiedReportToast = false
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NPTheme.accentPrimary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Отчет для ISP")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(NPTheme.textPrimary)
                        Text("Скопировать в буфер")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(NPTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "square.on.square")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NPTheme.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .npGlassCard(cornerRadius: 14)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - 3. Карточка здоровья сети (Health Score Card) с нейросферой

    private var networkHealthCard: some View {
        VStack(spacing: 16) {
            let report = viewModel.currentHealthReport ?? NetworkHealthReport(
                overallScore: 88,
                gamingScore: 92,
                streamingScore: 85,
                videoCallScore: 90,
                webBrowsingScore: 95,
                statusTitle: "Оценка состояния сети...",
                summaryText: "Идет сбор системных метрик и расчет стабильности узлов."
            )

            HStack(spacing: 18) {
                // Кольцевой индикатор общего балла с динамической нейросферой внутри
                ZStack {
                    AINeuralOrbView(isAnalyzing: viewModel.isAIAnalyzing)
                        .frame(width: 84, height: 84)

                    Circle()
                        .trim(from: 0.0, to: CGFloat(report.overallScore) / 100.0)
                        .stroke(
                            NPTheme.accentGradient,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 84, height: 84)
                        .shadow(color: NPTheme.glowActive, radius: 8)

                    VStack(spacing: 0) {
                        Text("\(report.overallScore)")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(NPTheme.textPrimary)
                        Text("/100")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(NPTheme.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(report.statusTitle)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(NPTheme.accentPrimary)

                    Text(report.summaryText)
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textSecondary)
                        .lineLimit(3)
                }

                Spacer()
            }

            Divider()
                .background(NPTheme.border)

            // Сетка готовности к сценариям (стеклянные бейджи)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                categoryHealthBadge(
                    title: "Гейминг (Ping/Loss)",
                    score: report.gamingScore,
                    icon: "gamecontroller.fill"
                )

                categoryHealthBadge(
                    title: "4K/8K Стриминг",
                    score: report.streamingScore,
                    icon: "play.tv.fill"
                )

                categoryHealthBadge(
                    title: "Видеозвонки (Zoom)",
                    score: report.videoCallScore,
                    icon: "video.fill"
                )

                categoryHealthBadge(
                    title: "Web & DNS Скорость",
                    score: report.webBrowsingScore,
                    icon: "globe"
                )
            }
        }
        .padding(18)
        .npGlassCard(cornerRadius: 20)
        .padding(.horizontal)
    }

    private func categoryHealthBadge(title: String, score: Int, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(NPTheme.accentSoft)
                .frame(width: 26, height: 26)
                .background(NPTheme.accentPrimary.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NPTheme.textSecondary)
                    .lineLimit(1)

                Text("\(score)%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(NPTheme.textPrimary)
            }
            Spacer()
        }
        .padding(8)
        .background(NPTheme.cardBackgroundTertiary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 4. Карточки проблем и рекомендаций

    private func issuesAndRecommendationsSection(report: NetworkHealthReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Обнаруженные факторы и советы AI")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(NPTheme.textPrimary)
                .padding(.horizontal)

            VStack(spacing: 10) {
                ForEach(report.identifiedIssues) { issue in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: issue.severity == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(issue.severity == .critical ? NPTheme.semanticCritical : NPTheme.semanticWarn)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(issue.title)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(NPTheme.textPrimary)

                                Spacer()

                                Text(issue.component)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(NPTheme.textSecondary)
                            }

                            Text(issue.description)
                                .font(.system(size: 12))
                                .foregroundStyle(NPTheme.textSecondary)
                        }
                    }
                    .padding(12)
                    .npGlassCard(cornerRadius: 14)
                }

                ForEach(report.recommendations) { rec in
                    HStack(spacing: 12) {
                        Image(systemName: rec.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(NPTheme.accentPrimary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(rec.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(NPTheme.textPrimary)

                            Text(rec.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(NPTheme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .npGlassCard(cornerRadius: 14)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - 5. Диалог с AI

    private var chatHistorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Чат с AI-консультантом")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(NPTheme.textPrimary)
                .padding(.horizontal)

            // Быстрые кнопки-промпты
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickPrompts, id: \.self) { prompt in
                        Button {
                            inputText = prompt
                            Task {
                                await viewModel.sendAIMessage(prompt)
                            }
                            HapticManager.shared.impactLight()
                        } label: {
                            Text(prompt)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NPTheme.accentPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(NPTheme.accentPrimary.opacity(0.10))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(NPTheme.accentPrimary.opacity(0.25), lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Список сообщений
            LazyVStack(spacing: 12) {
                if viewModel.aiMessages.isEmpty {
                    VStack(spacing: 12) {
                        AINeuralOrbView(isAnalyzing: false)
                            .frame(width: 54, height: 54)
                        Text("Задайте вопрос о качестве сети или выберите рекомендацию выше.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(NPTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(viewModel.aiMessages) { msg in
                        AIMessageBubble(message: msg)
                    }
                }

                if viewModel.isAIAnalyzing {
                    HStack(spacing: 10) {
                        AINeuralOrbView(isAnalyzing: true)
                            .frame(width: 24, height: 24)
                        Text("AI выполняет глубокий анализ метрик...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(NPTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Поле ввода сообщения

    private var chatInputBar: some View {
        HStack(spacing: 10) {
            TextField("Спросите AI о вашей сети...", text: $inputText)
                .focused($isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(NPTheme.cardBackgroundTertiary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(NPTheme.border, lineWidth: 1))

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
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isAIAnalyzing)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            NPTheme.cardBackground
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - 3D Нейросфера (Neural Pulse Orb) 2026

public struct AINeuralOrbView: View {
    public let isAnalyzing: Bool

    @State private var rotatePhase: Double = 0
    @State private var pulseScale: CGFloat = 1.0

    public init(isAnalyzing: Bool = false) {
        self.isAnalyzing = isAnalyzing
    }

    public var body: some View {
        ZStack {
            // Внешнее свечение
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

            // Внутренние вращающиеся световые волны
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

            // Внутреннее светящееся ядро
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

// MARK: - Пузырь сообщения чата со смарт-чипами

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
                    }
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
                        // Заголовок карточки
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(NPTheme.accentPrimary.opacity(0.1))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(NPTheme.accentPrimary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Мастер устранения проблем")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(NPTheme.textPrimary)
                                Text("Автоматическая пошаговая проверка каждого сетевого слоя")
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

                        // Итоговый вердикт и рецепт решения
                        if let report = viewModel.troubleshootingReport {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: report.isIssueFound ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(report.isIssueFound ? NPTheme.semanticWarn : NPTheme.accentPrimary)

                                    Text("План оптимизации от AI:")
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
                            .foregroundStyle(NPTheme.accentPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .npGlassCard(cornerRadius: 12)
                        }
                        .padding(.horizontal)
                        .padding(.top, 6)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Диагностика неполадок")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NPTheme.accentPrimary)
                }
            }
        }
    }

    private func troubleshootingStepRow(step: TroubleshootingStep) -> some View {
        HStack(spacing: 12) {
            Image(systemName: step.icon)
                .font(.system(size: 18))
                .foregroundStyle(statusColor(step.status))
                .frame(width: 32, height: 32)
                .background(statusColor(step.status).opacity(0.1))
                .clipShape(Circle())

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
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textSecondary)
                } else {
                    Text(step.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(NPTheme.textTertiary)
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
            }
        }
    }
}

// MARK: - Окно настроек провайдера AI

private struct AIProviderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProvider: AIProviderType
    @State private var apiKey: String
    @State private var customModel: String

    let onSave: (AIProviderConfig) -> Void

    init(config: AIProviderConfig, onSave: @escaping (AIProviderConfig) -> Void) {
        self._selectedProvider = State(initialValue: config.selectedProvider)
        self._apiKey = State(initialValue: config.apiKey)
        self._customModel = State(initialValue: config.customModel)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Выбор провайдера") {
                    Picker("Провайдер AI", selection: $selectedProvider) {
                        ForEach(AIProviderType.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .onChange(of: selectedProvider) { _, newProv in
                        customModel = newProv.defaultModelName
                    }
                }

                if selectedProvider != .offlineSmart {
                    Section(header: Text("Параметры API (\(selectedProvider.rawValue))"), footer: Text("API-ключ надежно сохраняется в локальной конфигурации вашего устройства.")) {
                        SecureField("API Key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("Название модели", text: $customModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } else {
                    Section(footer: Text("Встроенный AI выполняет глубокий эвристический анализ RFC 3550, Bufferbloat, DNS и задержек полностью локально без отправки данных в интернет.")) {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(NPTheme.accentPrimary)
                            Text("100% Приватность и работа офлайн")
                                .font(.system(size: 14))
                        }
                    }
                }
            }
            .navigationTitle("Настройки AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let newConfig = AIProviderConfig(
                            selectedProvider: selectedProvider,
                            apiKey: apiKey,
                            customModel: customModel
                        )
                        onSave(newConfig)
                        HapticManager.shared.notificationSuccess()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(NPTheme.accentPrimary)
                }
            }
        }
    }
}
