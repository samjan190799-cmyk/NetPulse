//
//  SettingsView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Экран настроек приложения NetPulse в стиле «Obsidian Mono»
public struct SettingsView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    public var body: some View {
        NavigationStack {
            Form {
                // 1. Секция мониторинга и интервалов
                Section(header: Text("Мониторинг"), footer: Text("Интервал определяет частоту отправки ICMP Echo Request пакетов на все целевые узлы")) {
                    HStack {
                        Text("Статус")
                        Spacer()
                        HStack(spacing: 5) {
                            Circle()
                                .fill(viewModel.isMonitoringActive ? NPTheme.accentPrimary : NPTheme.textTertiary)
                                .frame(width: 8, height: 8)
                            Text(viewModel.isMonitoringActive ? "Активен" : "Остановлен")
                                .foregroundStyle(viewModel.isMonitoringActive ? NPTheme.accentPrimary : NPTheme.textSecondary)
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }

                    HStack {
                        Text("Интервал пинга")
                        Spacer()
                        Text("\(String(format: "%.1f", viewModel.pingInterval)) сек")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(NPTheme.accentPrimary)
                    }
                    Slider(value: $viewModel.pingInterval, in: 0.5...10.0, step: 0.5)
                        .onChange(of: viewModel.pingInterval) { _, _ in
                            HapticManager.shared.selectionChanged()
                        }

                    Stepper("Макс. история (\(viewModel.maxHistorySize))", value: $viewModel.maxHistorySize, in: 20...200, step: 10)
                }

                // 2. Целевые узлы мониторинга
                Section(header: Text("Узлы мониторинга"), footer: Text("Добавьте IP-адреса или домены для постоянного мониторинга задержки, джиттера и потерь.")) {
                    ForEach(viewModel.targets) { target in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(target.name)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(target.address)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(NPTheme.textSecondary)
                            }

                            Spacer()

                            if target.isGateway {
                                Text("ШЛЮЗ")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(NPTheme.accentSoft)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(NPTheme.accentSoft.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .onDelete { offsets in
                        viewModel.removeTargets(at: offsets)
                        HapticManager.shared.notificationWarning()
                    }

                    Button {
                        viewModel.addDefaultTarget()
                        HapticManager.shared.notificationSuccess()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(NPTheme.accentPrimary)
                            Text("Добавить узел")
                                .foregroundStyle(NPTheme.accentPrimary)
                        }
                    }
                }

                // 3. Live Activity (Dynamic Island)
                Section(header: Text("Live Activity"), footer: Text("Мониторинг скорости в реальном времени на экране блокировки и Dynamic Island (iPhone 14+).")) {
                    Toggle(isOn: $viewModel.liveActivityEnabled) {
                        HStack {
                            Image(systemName: "pip.enter")
                                .foregroundStyle(NPTheme.accentPrimary)
                            Text("Dynamic Island Мониторинг")
                        }
                    }
                    .onChange(of: viewModel.liveActivityEnabled) { _, newValue in
                        viewModel.toggleLiveActivity(enabled: newValue)
                        HapticManager.shared.impactMedium()
                    }
                }

                // 4. Уведомления и алерты
                Section(header: Text("Уведомления")) {
                    Toggle(isOn: $viewModel.alertsEnabled) {
                        HStack {
                            Image(systemName: "bell.badge.fill")
                                .foregroundStyle(viewModel.alertsEnabled ? NPTheme.accentPrimary : NPTheme.textSecondary)
                            Text("Уведомления о проблемах")
                        }
                    }
                    .onChange(of: viewModel.alertsEnabled) { _, _ in
                        HapticManager.shared.selectionChanged()
                    }

                    if viewModel.alertsEnabled {
                        HStack {
                            Text("Порог задержки (мс)")
                            Spacer()
                            Text("\(Int(viewModel.latencyAlertThreshold))")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(NPTheme.accentPrimary)
                        }
                        Slider(value: $viewModel.latencyAlertThreshold, in: 50...500, step: 10)

                        HStack {
                            Text("Порог потерь (%)")
                            Spacer()
                            Text("\(Int(viewModel.lossAlertThreshold))%")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(NPTheme.accentPrimary)
                        }
                        Slider(value: $viewModel.lossAlertThreshold, in: 1...50, step: 1)
                    }
                }

                // 5. О приложении
                Section(header: Text("О приложении")) {
                    HStack {
                        Text("Версия")
                        Spacer()
                        Text("2.1.0 (Build 2026.08)")
                            .foregroundStyle(NPTheme.textSecondary)
                    }

                    HStack {
                        Text("Движок сети")
                        Spacer()
                        Text("ICMP v4/v6 • Darwin BSD")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NPTheme.accentPrimary)
                    }

                    HStack {
                        Text("Движок анализатора трафика")
                        Spacer()
                        Text("nstat + IOKitBSD")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NPTheme.accentPrimary)
                    }
                }
            }
            .navigationTitle("Настройки")
        }
    }
}
