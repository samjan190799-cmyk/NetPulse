//
//  GamingRadarView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Экран киберспортивного радара игровых серверов (Gaming Radar)
public struct GamingRadarView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    @State private var selectedGame: GameTitle = .cs2
    @State private var isScanning: Bool = false
    @State private var clusterResults: [GameClusterResult] = []

    private var bestCluster: GameClusterResult? {
        clusterResults.first(where: { $0.isReachable })
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // 1. Селектор игр (Горизонтальная карусель)
                        gameSelectorCarousel

                        // 2. Карточка лучшего сервера для матча (Matchmaking Advisor)
                        bestServerHeroCard

                        // 3. Список дата-центров выбранной игры
                        clustersListSection

                        // 4. Пояснение киберспортивных критериев задержки (RFC 3550)
                        gamingAdviceCard
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Gaming Радар")
            .navigationBarTitleDisplayMode(.inline)
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
                        scanClusters()
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

                    Text(selectedGame.publisher)
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textSecondary)
                }

                Spacer()

                if let best = bestCluster {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(best.formattedLatency)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(best.quality.badgeColor)

                        Text("Лучший пинг")
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
                        Text("\(best.cluster.regionName): \(best.quality.rawValue)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(best.quality.badgeColor)
                    }
                    Spacer()
                    Text("Рекомендован для матча")
                        .font(.system(size: 11))
                        .foregroundStyle(NPTheme.textSecondary)
                }
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

                    Text(item.quality.rawValue)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(item.quality.badgeColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(item.quality.badgeColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                HStack(spacing: 6) {
                    Text("Узел: \(item.cluster.cityName)")
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
                    .foregroundStyle(item.quality.badgeColor)

                if item.packetLossPct > 0 {
                    Text("Loss: \(Int(item.packetLossPct))%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(NPTheme.semanticCritical)
                }
            }
        }
        .padding(14)
        .npGlassCard(cornerRadius: 16)
    }

    // MARK: - 4. Пояснение киберспортивных стандартов

    private var gamingAdviceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "cross.vial.fill")
                    .foregroundStyle(NPTheme.accentPrimary)
                Text("Киберспортивные критерии связи")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)
            }

            Text("Для соревновательных шутеров (CS2, Valorant) идеальный RTT составляет **до 35 мс** с джиттером **< 2 мс**. Для MOBA (Dota 2) комфортным является пинг **до 60 мс**. Потери пакетов даже в 1% вызывают рассинхронизацию хитбоксов.")
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
        isScanning = true
        HapticManager.shared.impactMedium()

        Task {
            let results = await GamingRadarEngine.shared.scanGameClusters(for: selectedGame) { updated in
                Task { @MainActor in
                    if let idx = clusterResults.firstIndex(where: { $0.id == updated.id }) {
                        clusterResults[idx] = updated
                    }
                }
            }

            self.clusterResults = results
            self.isScanning = false
            HapticManager.shared.notificationSuccess()
        }
    }
}
