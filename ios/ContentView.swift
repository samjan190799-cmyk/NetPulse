//
//  ContentView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Главный навигационный контейнер приложения с 3 разделами и плавающим игровым HUD.
public struct ContentView: View {
    @State private var viewModel = NetworkMonitorViewModel()

    public var body: some View {
        ZStack {
            TabView {
                DashboardView(viewModel: viewModel)
                    .tabItem {
                        Label("Скорость", systemImage: "gauge.with.dots.needle.67percent")
                    }

                DiagnosticsView(viewModel: viewModel)
                    .tabItem {
                        Label("Диагностика", systemImage: "waveform.path.ecg")
                    }

                SettingsView(viewModel: viewModel)
                    .tabItem {
                        Label("Настройки", systemImage: "gearshape.fill")
                    }
            }
            .tint(.blue)
            .preferredColorScheme(.dark)

            // Плавающий игровой HUD поверх экранов
            if viewModel.floatingHUDEnabled {
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
                        withAnimation {
                            viewModel.floatingHUDEnabled = false
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
    }
}
