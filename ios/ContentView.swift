//
//  ContentView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import UIKit

/// Главный навигационный контейнер приложения NetPulse (Apple HIG 2026)
/// 5 разделов: Скорость, Узлы (Диагностика), Трафик, AI Диагност, Настройки.
public struct ContentView: View {
    @State private var viewModel = NetworkMonitorViewModel()
    @State private var selectedTab: Int = 0

    public var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                // 1. Скорость и возможности сети
                DashboardView(viewModel: viewModel)
                    .tabItem {
                        Label("Скорость", systemImage: "gauge.with.dots.needle.67percent")
                    }
                    .tag(0)

                // 2. Детальный мониторинг узлов и MTR-трассировка
                DiagnosticsView(viewModel: viewModel)
                    .tabItem {
                        Label("Узлы", systemImage: "network")
                    }
                    .tag(1)

                // 3. Аналитика трафика 24/7 и лимиты
                TrafficView(viewModel: viewModel)
                    .tabItem {
                        Label("Трафик", systemImage: "arrow.up.arrow.down.square.fill")
                    }
                    .tag(2)

                // 4. Интеллектуальный AI-Диагност
                AIDiagnosticsView(viewModel: viewModel)
                    .tabItem {
                        Label("AI Диагност", systemImage: "sparkles")
                    }
                    .tag(3)

                // 5. Настройки и темы оформления
                SettingsView(viewModel: viewModel)
                    .tabItem {
                        Label("Настройки", systemImage: "gearshape.fill")
                    }
                    .tag(4)
            }
            .tint(NPTheme.accentPrimary)
            .preferredColorScheme(.dark)
            .onChange(of: selectedTab) { _, _ in
                HapticManager.shared.selectionChanged()
            }
            .onAppear {
                configureTabBarAppearance()
            }

            // Невидимый системный якорь для выпадающего Picture-in-Picture окна поверх игр
            if viewModel.floatingHUDEnabled {
                PiPAnchorRepresentable(viewModel: viewModel)
                    .frame(width: 1, height: 1)
                    .opacity(0.001)

                // Плавающий игровой HUD внутри приложения
                FloatingGameOverlayView(
                    downloadSpeedText: viewModel.isSpeedtestRunning ? String(format: "%.1f Мбит/с", viewModel.liveDownloadSpeed) : viewModel.liveBandwidth.formattedDownloadSpeed,
                    uploadSpeedText: viewModel.isSpeedtestRunning ? String(format: "%.1f Мбит/с", viewModel.liveUploadSpeed) : viewModel.liveBandwidth.formattedUploadSpeed,
                    pingMs: viewModel.currentAveragePing,
                    jitterMs: viewModel.currentAverageJitter,
                    packetLossPct: viewModel.currentPacketLossPct,
                    onTogglePiP: {
                        PiPHUDManager.shared.togglePiP()
                    },
                    onClose: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            viewModel.floatingHUDEnabled = false
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
    }

    /// Настройка нативного полупрозрачного Glassmorphism таб-бара Apple
    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

/// Системный мост UIView для инициализации AVPictureInPictureController
private struct PiPAnchorRepresentable: UIViewRepresentable {
    var viewModel: NetworkMonitorViewModel

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        let rootView = AnyView(
            PiPHUDContentView(viewModel: viewModel)
        )
        PiPHUDManager.shared.setup(with: view, rootView: rootView)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let rootView = AnyView(
            PiPHUDContentView(viewModel: viewModel)
        )
        PiPHUDManager.shared.updateRootView(rootView)
    }
}

/// Выпадающее компактное Picture-in-Picture окно поверх игр и других приложений
private struct PiPHUDContentView: View {
    var viewModel: NetworkMonitorViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Скачивание
            HStack(spacing: 3) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(NPTheme.accentPrimary)
                Text(viewModel.isSpeedtestRunning ? String(format: "%.0fM", viewModel.liveDownloadSpeed) : viewModel.liveBandwidth.compactDownload)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            // Отдача
            HStack(spacing: 3) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(NPTheme.accentSilver)
                Text(viewModel.isSpeedtestRunning ? String(format: "%.0fM", viewModel.liveUploadSpeed) : viewModel.liveBandwidth.compactUpload)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            // Пинг
            if let ping = viewModel.currentAveragePing {
                HStack(spacing: 3) {
                    Circle()
                        .fill(ping < 45 ? NPTheme.semanticOK : (ping < 100 ? NPTheme.semanticWarn : NPTheme.semanticCritical))
                        .frame(width: 5, height: 5)
                    Text(String(format: "%.0fms", ping))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(NPTheme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.9))
        .clipShape(Capsule())
    }
}

