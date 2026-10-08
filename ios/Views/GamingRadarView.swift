//
//  GamingRadarView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Экран «Gaming Радар»: задержка до региональных узлов AWS (ориентир для онлайн-игр) и её оценка по жанру выбранной игры
public struct GamingRadarView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    @State private var selectedGame: GameTitle = .cs2
    @State private var isScanning: Bool = false
    // Заготовки строк сразу: раньше список был пуст, и обновления по ходу замера некуда было записывать
    @State private var clusterResults: [GameClusterResult] = GameClusterInfo.referenceRegions.map {
        GameClusterResult(cluster: $0)
    }
    @State private var scanTask: Task<Void, Never>?
    @State private var errorMessage: String?

    /// Регион с наименьшей задержкой среди ответивших
    private var bestCluster: GameClusterResult? {
        clusterResults
            .filter { $0.isTested && $0.isReachable && $0.latencyMs != nil }
            .min(by: { ($0.latencyMs ?? .infinity) < ($1.latencyMs ?? .infinity) })
    }

    public var body: some View {
        ZStack {
            NPTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // 1. Селектор игр (Горизонтальная карусель)
                    gameSelectorCarousel

                    // 2. Карточка лучшего сервера для матча (Matchmaking Advisor)
                    bestServerHeroCard

                    // 4. Список дата-центров выбранной игры
                    clustersListSection

                    // 5. Пояснение киберспортивных критериев задержки (RFC 3550)
                    gamingAdviceCard
                }
                .padding(.vertical)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Gaming Радар")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear {
            scanTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    scanClusters()
                } label: {
                    if isScanning {
                        ProgressView()
                            .tint(NPTheme.accentPrimary)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(NPTheme.accentPrimary)
                    }
                }
                .disabled(isScanning)
                .npMinHitTarget()
            }
        }
        .task {
            if !clusterResults.contains(where: { $0.isTested }) {
                scanClusters()
            }
        }
    }

    // MARK: - 1. Горизонтальный селектор игр

    private var gameSelectorCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(GameTitle.allCases) { game in
                    Button {
                        selectedGame = game
                        HapticManager.shared.impactLight()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: game.icon)
                                .font(.system(size: 13, weight: .bold))
                            Text(game.rawValue)
                                .font(.system(size: 13, weight: .bold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(selectedGame == game ? NPTheme.accentPrimary : Color.white.opacity(0.06))
                        .foregroundStyle(selectedGame == game ? NPTheme.backgroundDeep : NPTheme.textPrimary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(selectedGame == game ? Color.clear : NPTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(NPPressableButtonStyle())
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - 2. Главная карточка лучшего сервера

    private var bestServerHeroCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(NPTheme.accentPrimary.opacity(0.15))
                        .frame(width: 50, height: 50)

                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(NPTheme.accentPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedGame.rawValue)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(NPTheme.textPrimary)

                    Text("\(selectedGame.publisher) • \(selectedGame.genreTitle)")
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textSecondary)
                }

                Spacer()

                if let best = bestCluster {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(best.formattedLatency)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(best.badgeColor(for: selectedGame))

                        Text("Ближайший регион")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NPTheme.textTertiary)
                    }
                }
            }

            if let best = bestCluster {
                Divider()
                    .background(NPTheme.border)

                HStack {
                    HStack(spacing: 6) {
                        Text(best.cluster.flagEmoji)
                            .font(.system(size: 16))
                        Text("\(best.cluster.regionName): \(best.quality(for: selectedGame).rawValue)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(best.badgeColor(for: selectedGame))
                    }
                    Spacer()
                }
            } else if isScanning {
                Text("Замер задержки до регионов...")
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.textSecondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.semanticWarn)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .npGlassCard(cornerRadius: 20)
        .padding(.horizontal)
    }

    // MARK: - 3. Список дата-центров

    private var clustersListSection: some View {
        VStack(spacing: 10) {
            ForEach(clusterResults) { item in
                clusterRow(item: item)
            }
        }
        .padding(.horizontal)
    }

    private func clusterRow(item: GameClusterResult) -> some View {
        HStack(spacing: 12) {
            Text(item.cluster.flagEmoji)
                .font(.system(size: 24))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.cluster.regionName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NPTheme.textPrimary)

                    if item.isTested {
                        Text(item.quality(for: selectedGame).rawValue)
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(item.badgeColor(for: selectedGame))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(item.badgeColor(for: selectedGame).opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Text("\(item.cluster.cityName) • \(item.cluster.regionID)")
                        .font(.system(size: 11))
                        .foregroundStyle(NPTheme.textSecondary)

                    if let j = item.jitterMs, item.isReachable {
                        Text("• Джиттер: ±\(String(format: "%.1f", j)) мс")
                            .font(.system(size: 10, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(NPTheme.textTertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.formattedLatency)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(item.badgeColor(for: selectedGame))

                if item.isTested && item.isReachable && item.packetLossPct > 0 {
                    Text("потеряно: \(Int(item.packetLossPct))%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(NPTheme.semanticCritical)
                }
            }
        }
        .padding(14)
        .npGlassCard(cornerRadius: 16)
    }

    // MARK: - 4. Пояснение

    private var gamingAdviceCard: some View {
        let profile = selectedGame.latencyProfile
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(NPTheme.accentPrimary)
                Text("Как читать результаты")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)
            }

            Text("Замер показывает задержку до публичных узлов облачных регионов AWS, в которых размещаются многие онлайн-игры и сервисы, а не до серверов конкретной игры: адреса игровых серверов не публикуются. Реальный пинг в игре может отличаться — точное значение показывает сама игра.")
                .font(.system(size: 11))
                .foregroundStyle(NPTheme.textSecondary)

            Text("Ориентиры для жанра «\(selectedGame.genreTitle)»: отлично — до \(Int(profile.excellentMs)) мс, хорошо — до \(Int(profile.goodMs)) мс, приемлемо — до \(Int(profile.playableMs)) мс. Потеря даже 1–2 % пакетов заметна в динамичных играх.")
                .font(.system(size: 11))
                .foregroundStyle(NPTheme.textSecondary)
        }
        .padding(14)
        .npGlassCard(cornerRadius: 14)
        .padding(.horizontal)
    }

    // MARK: - Сканирование

    private func scanClusters() {
        guard !isScanning else { return }
        if viewModel.systemInfo.connectionType == .unavailable {
            errorMessage = "Нет подключения к сети — замер невозможен."
            HapticManager.shared.notificationWarning()
            return
        }
        isScanning = true
        errorMessage = nil
        HapticManager.shared.impactMedium()
        clusterResults = GameClusterInfo.referenceRegions.map { GameClusterResult(cluster: $0) }

        scanTask = Task {
            let results = await GamingRadarEngine.shared.scanRegions { updated in
                Task { @MainActor in
                    if let idx = clusterResults.firstIndex(where: { $0.id == updated.id }) {
                        clusterResults[idx] = updated
                    }
                }
            }

            if !Task.isCancelled {
                self.clusterResults = results
                if results.contains(where: { $0.isReachable }) {
                    HapticManager.shared.notificationSuccess()
                } else {
                    self.errorMessage = "Ни один регион не ответил. Проверьте подключение к интернету."
                    HapticManager.shared.notificationWarning()
                }
            }
            self.isScanning = false
            self.scanTask = nil
        }
    }
}
