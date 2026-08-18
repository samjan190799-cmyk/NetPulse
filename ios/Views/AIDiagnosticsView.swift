//
//  AIDiagnosticsView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Главный экран AI-Диагноста в стиле «Obsidian Mono»
public struct AIDiagnosticsView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    @State private var inputText: String = ""
    @State private var showSettingsSheet: Bool = false
    @FocusState private var isInputFocused: Bool

    private let quickPrompts: [String] = [
        "🎮 Почему лагает онлайн-игра?",
        "📺 Хватит ли скорости для 4K?",
        "🌐 Какой DNS самый быстрый?",
        "📡 Как улучшить сигнал Wi-Fi?",
        "🔍 Анализ потерь пакетов"
    ]

    public var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Провайдер и статус движка
                        providerStatusPill

                        // 2. Главная карточка здоровья сети (Health Score 0-100)
                        networkHealthCard

                        // 3. Выявленные проблемы и рекомендации AI
                        if let report = viewModel.currentHealthReport, !report.identifiedIssues.isEmpty {
                            issuesAndRecommendationsSection(report: report)
                        }

                        // 4. Интерактивный диалог с AI
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
            .npScreenBackground()
            .navigationTitle("AI Диагност")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettingsSheet = true
                        HapticManager.shared.impactLight()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16))
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
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                    Text("Обновить аудит")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(NPTheme.accentPrimary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(NPTheme.cardBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(NPTheme.border, lineWidth: 1))
        .padding(.horizontal)
    }

    // MARK: - 2. Карточка здоровья сети (Health Score Card)

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
                // Кольцевой индикатор общего балла — белое кольцо с glow
                ZStack {
                    Circle()
                        .stroke(NPTheme.cardBackgroundTertiary, lineWidth: 8)
                        .frame(width: 84, height: 84)

                    Circle()
                        .trim(from: 0.0, to: CGFloat(report.overallScore) / 100.0)
                        .stroke(
                            NPTheme.accentPrimary,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 84, height: 84)
                        .shadow(color: NPTheme.glow, radius: 8)

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
                        .font(.system(size: 18, weight: .bold))
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

            // Сетка готовности к сценариям (монохромные бейджи)
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
        .npCardStyle(cornerRadius: 20)
        .padding(.horizontal)
    }

    private func categoryHealthBadge(title: String, score: Int, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(NPTheme.accentSoft)
                .frame(width: 24, height: 24)
                .background(NPTheme.accentPrimary.opacity(0.08))
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
        .background(NPTheme.cardBackgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 3. Карточки проблем и рекомендаций

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
                    .npCardStyle(cornerRadius: 14)
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
                    .npCardStyle(cornerRadius: 14)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - 4. Диалог с AI

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
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(NPTheme.accentPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(NPTheme.accentPrimary.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Список сообщений
            LazyVStack(spacing: 12) {
                if viewModel.aiMessages.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 28))
                            .foregroundStyle(NPTheme.accentPrimary)
                        Text("Задайте вопрос о вашем интернет-соединении или выберите подсказку выше.")
                            .font(.system(size: 13))
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
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(NPTheme.accentPrimary)
                        Text("AI анализирует сетевые метрики...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(NPTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal)
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

// MARK: - Пузырь сообщения чата (Obsidian Mono)

private struct AIMessageBubble: View {
    let message: AIMessage

    var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(NPTheme.accentPrimary)
                        Text("NetPulse AI")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NPTheme.accentPrimary)
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
                isUser ? NPTheme.accentPrimary : NPTheme.cardBackground
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isUser ? Color.clear : NPTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)

            if !isUser { Spacer(minLength: 40) }
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
                }
            }
        }
    }
}
