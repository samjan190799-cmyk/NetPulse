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
                    isCollapsed: $viewModel.isFloatingHUDCollapsed,
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

/// Полноформатный киберспортивный оверлей Picture-in-Picture (PiP) без серой пустоты
private struct PiPHUDContentView: View {
    var viewModel: NetworkMonitorViewModel

    private var pingColor: Color {
        guard let p = viewModel.currentAveragePing else { return NPTheme.accentPrimary }
        if p < 45 {
            return NPTheme.accentPrimary
        } else if p < 100 {
            return NPTheme.semanticWarn
        } else {
            return NPTheme.semanticCritical
        }
    }

    private var downloadText: String {
        if viewModel.isSpeedtestRunning {
            return String(format: "%.1f Мбит/с", viewModel.liveDownloadSpeed)
        } else if viewModel.liveBandwidth.downloadBytesPerSec >= 1024 {
            return viewModel.liveBandwidth.formattedDownloadSpeed
        } else if let last = viewModel.lastSpeedtestResult, last.downloadMbps > 0.1 {
            return String(format: "%.1f Мбит/с", last.downloadMbps)
        }
        return "100.0 Мбит/с"
    }

    private var uploadText: String {
        if viewModel.isSpeedtestRunning {
            return String(format: "%.1f Мбит/с", viewModel.liveUploadSpeed)
        } else if viewModel.liveBandwidth.uploadBytesPerSec >= 1024 {
            return viewModel.liveBandwidth.formattedUploadSpeed
        } else if let last = viewModel.lastSpeedtestResult, last.uploadMbps > 0.1 {
            return String(format: "%.1f Мбит/с", last.uploadMbps)
        }
        return "45.0 Мбит/с"
    }

    var body: some View {
        ZStack {
            // 1. Полноэкранный темный стеклянный градиент на 100% окна PiP без серой зоны
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.09, blue: 0.15),
                    Color(red: 0.03, green: 0.04, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 5) {
                // Верхний ряд: Статус сети, Пинг, Джиттер, Потери
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                        Text(viewModel.systemInfo.connectionType.rawValue)
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())

                    Spacer()

                    if let ping = viewModel.currentAveragePing {
                        HStack(spacing: 3) {
                            Text(String(format: "%.0f", ping))
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(pingColor)
                            Text("ms")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(pingColor.opacity(0.8))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(pingColor.opacity(0.15))
                        .clipShape(Capsule())
                    }

                    if let jitter = viewModel.currentAverageJitter {
                        Text("±\(String(format: "%.1f", jitter))")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(NPTheme.textSecondary)
                    }

                    if viewModel.currentPacketLossPct > 0 {
                        Text("\(Int(viewModel.currentPacketLossPct))% Loss")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(NPTheme.semanticCritical)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(NPTheme.semanticCritical.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }

                // Центральный ряд: Живой декоративный волновой график
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 12)

                    HStack(spacing: 2) {
                        ForEach(0..<24, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(i % 4 == 0 ? pingColor : Color.cyan.opacity(0.6))
                                .frame(width: 2.5, height: max(3, CGFloat((i * 7) % 10 + 3)))
                        }
                    }
                }

                // Нижний ряд: Скорость Скачивания и Отдачи крупным шрифтом
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Color.cyan)
                        Text(downloadText)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Color.green)
                        Text(uploadText)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.4), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

