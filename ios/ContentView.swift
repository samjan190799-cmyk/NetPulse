//
//  ContentView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Главный навигационный контейнер приложения с 3 разделами.
public struct ContentView: View {
    @State private var viewModel = NetworkMonitorViewModel()

    public var body: some View {
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
    }
}
