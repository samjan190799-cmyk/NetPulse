//
//  DNSBenchmarkView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import UniformTypeIdentifiers

/// Главный экран DNS-бенчмарка с параллельной гонкой 12+ мировых Anycast-серверов
public struct DNSBenchmarkView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    @State private var isRunning: Bool = false
    @State private var benchmarkResults: [DNSBenchmarkResult] = []
    @State private var selectedCategory: DNSFilterCategory = .all
    @State private var selectedProviderForConfig: DNSProviderInfo?
    @State private var showConfigSheet: Bool = false
    @State private var showCopiedToast: Bool = false

    private var filteredResults: [DNSBenchmarkResult] {
        if selectedCategory == .all {
            return benchmarkResults
        }
        return benchmarkResults.filter { $0.provider.category == selectedCategory }
    }

    private var fastestProvider: DNSBenchmarkResult? {
        benchmarkResults.first(where: { $0.isReachable })
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // 1. Верхний интерактивный подиум и кнопка старта
                        benchmarkHeaderCard

                        // 2. Селектор категорий (Смарт-фильтры)
                        categoryFilterSelector

                        // 3. Список серверов в реальном времени с медалями
                        serversListSection

                        // 4. Пояснительная карточка DoH/DoT и безопасности
                        securityExplanationCard
                    }
                    .padding(.vertical)
                }

                // Всплывающий тост об успешном копировании IP
                if showCopiedToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(NPTheme.accentPrimary)
                            Text("DNS-адрес скопирован в буфер обмена")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(NPTheme.textPrimary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(NPTheme.cardBackground)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(NPTheme.accentPrimary.opacity(0.35), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.4), radius: 10, y: 5)
                        .padding(.bottom, 30)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .zIndex(10)
                }
            }
            .navigationTitle("DNS Бенчмарк")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        startBenchmark()
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
            .sheet(item: $selectedProviderForConfig) { provider in
                DNSConfigExportSheet(provider: provider)
            }
            .task {
                if benchmarkResults.isEmpty {
                    // Инициализация дефолтного каталога
                    benchmarkResults = DNSProviderInfo.defaultCatalog.map {
                        DNSBenchmarkResult(provider: $0)
                    }
                    startBenchmark()
                }
            }
        }
    }

    // MARK: - 1. Карточка победителя и запуск

    private var benchmarkHeaderCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(NPTheme.accentPrimary.opacity(0.12))
                        .frame(width: 54, height: 54)

                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(NPTheme.accentPrimary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Глобальная гонка DNS")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(NPTheme.textPrimary)

                    if let fastest = fastestProvider {
                        HStack(spacing: 4) {
                            Text("Лидер:")
                                .font(.system(size: 12))
                                .foregroundStyle(NPTheme.textSecondary)
                            Text(fastest.provider.name)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(NPTheme.accentPrimary)
                            Text("(\(fastest.formattedLatency))")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(NPTheme.accentPrimary)
                        }
                    } else {
                        Text("Параллельное тестирование 12+ Anycast-узлов")
                            .font(.system(size: 12))
                            .foregroundStyle(NPTheme.textSecondary)
                    }
                }

                Spacer()
            }

            // Кнопка запуска полной гонки
            Button {
                startBenchmark()
            } label: {
                HStack(spacing: 8) {
                    if isRunning {
                        ProgressView()
                            .tint(NPTheme.backgroundDeep)
                        Text("Тестирование серверов...")
                    } else {
                        Image(systemName: "play.fill")
                        Text("Запустить замер DNS")
                    }
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(NPTheme.backgroundDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isRunning ? NPTheme.accentSoft : NPTheme.accentPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(NPPressableButtonStyle())
            .disabled(isRunning)
        }
        .padding(16)
        .npGlassCard(cornerRadius: 20)
        .padding(.horizontal)
    }

    // MARK: - 2. Селектор категорий

    private var categoryFilterSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DNSFilterCategory.allCases) { cat in
                    Button {
                        selectedCategory = cat
                        HapticManager.shared.impactLight()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 11))
                            Text(cat.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(selectedCategory == cat ? NPTheme.accentPrimary : Color.white.opacity(0.06))
                        .foregroundStyle(selectedCategory == cat ? NPTheme.backgroundDeep : NPTheme.textPrimary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(selectedCategory == cat ? Color.clear : NPTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(NPPressableButtonStyle())
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - 3. Список серверов в реальном времени

    private var serversListSection: some View {
        VStack(spacing: 10) {
            ForEach(filteredResults) { item in
                dnsServerRow(item: item)
            }
        }
        .padding(.horizontal)
    }

    private func dnsServerRow(item: DNSBenchmarkResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // Медаль или логотип
                ZStack {
                    Circle()
                        .fill(badgeBgColor(rank: item.rank))
                        .frame(width: 38, height: 38)

                    if let rank = item.rank, rank <= 3 {
                        Text(medalForRank(rank))
                            .font(.system(size: 16))
                    } else if let rank = item.rank {
                        Text("#\(rank)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(NPTheme.textSecondary)
                    } else {
                        Image(systemName: item.provider.logoSystemIcon)
                            .font(.system(size: 14))
                            .foregroundStyle(NPTheme.accentPrimary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.provider.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(NPTheme.textPrimary)

                        if item.provider.supportsDNSSEC {
                            Text("DNSSEC")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(NPTheme.accentPrimary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(NPTheme.accentPrimary.opacity(0.15))
                                .clipShape(Capsule())
                        }

                        if item.provider.dohURL != nil {
                            Text("DoH")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(NPTheme.accentSilver)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }

                    Text(item.provider.primaryIPv4)
                        .font(.system(size: 11, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(NPTheme.textTertiary)
                }

                Spacer()

                // Значение пинга
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.formattedLatency)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(item.statusBadgeColor)

                    if let j = item.jitterMs, item.isReachable {
                        Text("±\(String(format: "%.1f", j)) мс")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(NPTheme.textTertiary)
                    }
                }
            }

            Text(item.provider.descriptionText)
                .font(.system(size: 11))
                .foregroundStyle(NPTheme.textSecondary)

            Divider()
                .background(NPTheme.border)

            // Быстрые действия (Копировать IP / Установить профиль)
            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = item.provider.primaryIPv4
                    HapticManager.shared.notificationSuccess()
                    withAnimation { showCopiedToast = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation { showCopiedToast = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Копировать IP")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NPTheme.accentPrimary)
                }
                .npMinHitTarget()

                Spacer()

                if item.provider.dohURL != nil {
                    Button {
                        selectedProviderForConfig = item.provider
                        HapticManager.shared.impactLight()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.doc.fill")
                            Text("Профиль DoH (.mobileconfig)")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NPTheme.accentPrimary)
                    }
                    .npMinHitTarget()
                }
            }
        }
        .padding(14)
        .npGlassCard(cornerRadius: 16)
    }

    // MARK: - 4. Карточка безопасности

    private var securityExplanationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NPTheme.accentPrimary)
                Text("Зачем менять DNS на iOS?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)
            }

            Text("Стандартный DNS провайдера часто ведет логи посещаемых сайтов и может задерживать открытие страниц. Использование шифрованного DoH (DNS-over-HTTPS) защищает от перехвата трафика и ускоряет загрузку сайтов на 30–50%.")
                .font(.system(size: 11))
                .foregroundStyle(NPTheme.textSecondary)
        }
        .padding(14)
        .npGlassCard(cornerRadius: 14)
        .padding(.horizontal)
    }

    // MARK: - Вспомогательные методы

    private func startBenchmark() {
        guard !isRunning else { return }
        isRunning = true
        HapticManager.shared.impactMedium()

        Task {
            let results = await DNSBenchmarkEngine.shared.runBenchmark { updatedResult in
                Task { @MainActor in
                    if let idx = benchmarkResults.firstIndex(where: { $0.id == updatedResult.id }) {
                        benchmarkResults[idx] = updatedResult
                    }
                }
            }

            self.benchmarkResults = results
            self.isRunning = false
            HapticManager.shared.notificationSuccess()
        }
    }

    private func badgeBgColor(rank: Int?) -> Color {
        guard let rank = rank else { return Color.white.opacity(0.04) }
        switch rank {
        case 1: return Color.yellow.opacity(0.18)
        case 2: return Color.gray.opacity(0.18)
        case 3: return Color.orange.opacity(0.18)
        default: return Color.white.opacity(0.04)
        }
    }

    private func medalForRank(_ rank: Int) -> String {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return ""
        }
    }
}

// MARK: - Экспорт конфигурационного профиля Apple (.mobileconfig)

private struct DNSConfigExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let provider: DNSProviderInfo

    @State private var configText: String = ""
    @State private var showCopiedToast: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Заголовок
                        HStack(spacing: 12) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 28))
                                .foregroundStyle(NPTheme.accentPrimary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Профиль Apple DoH")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(NPTheme.textPrimary)
                                Text(provider.name)
                                    .font(.system(size: 13))
                                    .foregroundStyle(NPTheme.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        // Инструкция по установке
                        VStack(alignment: .leading, spacing: 8) {
                            Text("КАК УСТАНОВИТЬ НА IPHONE:")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(NPTheme.textTertiary)
                                .tracking(0.5)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("1. Сохраните файл профиля через кнопку «Поделиться».")
                                Text("2. Откройте **Настройки** -> **Профиль загружен**.")
                                Text("3. Нажмите **Установить** и подтвердите паролем устройства.")
                                Text("4. Теперь все приложения используют зашифрованный \(provider.name)!")
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(NPTheme.textSecondary)
                        }
                        .padding(14)
                        .npGlassCard(cornerRadius: 14)
                        .padding(.horizontal)

                        // Предпросмотр XML
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ПРОФИЛЬ .MOBILECONFIG:")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(NPTheme.textTertiary)

                            Text(configText)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(NPTheme.textPrimary)
                                .padding(12)
                                .background(Color.black.opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .textSelection(.enabled)
                        }
                        .padding(14)
                        .npGlassCard(cornerRadius: 14)
                        .padding(.horizontal)

                        // Кнопка экспорта
                        if let fileURL = createTempConfigFile() {
                            ShareLink(item: fileURL) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up.fill")
                                    Text("Сохранить и Установить Профиль")
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
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Установка DNS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NPTheme.accentPrimary)
                }
            }
            .onAppear {
                Task {
                    self.configText = await DNSBenchmarkEngine.shared.generateMobileConfig(for: provider)
                }
            }
        }
    }

    private func createTempConfigFile() -> URL? {
        let text = configText.isEmpty ? "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" : configText
        let sanitizedName = provider.id.replacingOccurrences(of: ".", with: "_")
        let fileName = "NetPulse_\(sanitizedName).mobileconfig"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }
}
