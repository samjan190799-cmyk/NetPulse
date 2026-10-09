//
//  ContentView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import UIKit

/// Главный навигационный контейнер приложения NetPulse (Apple HIG 2026)
/// 4 раздела: Сеть (карта, скорость и запись маршрута), Инструменты (узлы, утилиты и AI-аудит), Трафик, Настройки.
public struct ContentView: View {
    @State private var viewModel = NetworkMonitorViewModel.shared
    /// Подписка PRO: окно подписки открывается поверх любого экрана
    @Bindable private var pro = ProStore.shared
    @State private var selectedTab: Int = 0

    public var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                // 1. Карта сети на весь экран, скорость, запись маршрута, инструменты
                NetworkHomeView(viewModel: viewModel)
                    .tabItem {
                        Label("Сеть", systemImage: "map.fill")
                    }
                    .tag(0)

                // 2. Инструменты: мониторинг узлов, MTR-трассировка, утилиты и AI-аудит (входит в подписку PRO)
                DiagnosticsView(viewModel: viewModel)
                    .npAppear()
                    .tabItem {
                        Label("Инструменты", systemImage: "wrench.and.screwdriver.fill")
                    }
                    .tag(1)

                // 3. Аналитика трафика 24/7 и лимиты
                TrafficView(viewModel: viewModel)
                    .npAppear()
                    .tabItem {
                        Label("Трафик", systemImage: "arrow.up.arrow.down.square.fill")
                    }
                    .tag(2)

                // 4. Настройки (подписка, остров, запись маршрута, пороги)
                SettingsView(viewModel: viewModel)
                    .npAppear()
                    .tabItem {
                        Label("Настройки", systemImage: "gearshape.fill")
                    }
                    .tag(3)
            }
            .tint(NPTheme.accentPrimary)
            .preferredColorScheme(.dark)
            .onChange(of: selectedTab) { _, _ in
                HapticManager.shared.selectionChanged()
            }
            .onReceive(NotificationCenter.default.publisher(for: .netPulseShowHome)) { _ in
                selectedTab = 0
            }
            .onAppear {
                configureTabBarAppearance()
            }

            // Плавающий игровой HUD внутри приложения
            if viewModel.floatingHUDEnabled {
                FloatingGameOverlayView(
                    isCollapsed: $viewModel.isFloatingHUDCollapsed,
                    downloadSpeedText: viewModel.isSpeedtestRunning ? String(format: "%.1f Мбит/с", viewModel.liveDownloadSpeed) : viewModel.liveBandwidth.formattedDownloadSpeed,
                    uploadSpeedText: viewModel.isSpeedtestRunning ? String(format: "%.1f Мбит/с", viewModel.liveUploadSpeed) : viewModel.liveBandwidth.formattedUploadSpeed,
                    pingMs: viewModel.currentAveragePing,
                    jitterMs: viewModel.currentAverageJitter,
                    packetLossPct: viewModel.currentPacketLossPct,
                    onClose: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            viewModel.floatingHUDEnabled = false
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            // Короткая заставка при запуске: касания проходят сквозь неё, показывается один раз за запуск
            NPIntroOverlay()
        }
        .npMotionPolicy()
        .sheet(item: $pro.paywall) { feature in
            PaywallView(feature: feature)
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
