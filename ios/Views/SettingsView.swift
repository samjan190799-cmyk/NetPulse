//
//  SettingsView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Экран настроек конфигурации NetPulse.
public struct SettingsView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    @State private var newHostName: String = ""
    @State private var newHostAddress: String = ""
    @State private var newHostPort: String = "443"
    @State private var showResetTrafficAlert: Bool = false

    public var body: some View {
        NavigationStack {
            Form {
                // Секция целевых узлов
                Section("Целевые узлы мониторинга") {
                    ForEach(viewModel.targets) { target in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.name)
                                    .font(.system(size: 15, weight: .semibold))
                                Text("\(target.address):\(target.tcpPort)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if target.isGateway {
                                Text("Шлюз")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.yellow)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.yellow.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .onDelete { indexSet in
                        viewModel.targets.remove(atOffsets: indexSet)
                    }

                    // Добавление нового узла
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Добавить новый узел")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.cyan)

                        TextField("Название (например: Мой Сервер)", text: $newHostName)
                        TextField("IP или Домен (например: 1.1.1.1)", text: $newHostAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("TCP Порт", text: $newHostPort)
                            .keyboardType(.numberPad)

                        Button("Добавить узел") {
                            guard !newHostAddress.isEmpty else { return }
                            let port = Int(newHostPort) ?? 443
                            let name = newHostName.isEmpty ? newHostAddress : newHostName
                            let newTarget = HostTarget(name: name, address: newHostAddress, tcpPort: port)
                            viewModel.targets.append(newTarget)
                            newHostName = ""
                            newHostAddress = ""
                            newHostPort = "443"
                            HapticManager.shared.impactMedium()
                        }
                        .disabled(newHostAddress.isEmpty)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.cyan)
                    }
                    .padding(.vertical, 4)
                }

                // Параметры тайминга
                Section("Параметры опроса") {
                    Picker("Интервал проверки", selection: $viewModel.pollingInterval) {
                        Text("0.5 сек").tag(0.5)
                        Text("1.0 сек (по умолч.)").tag(1.0)
                        Text("2.0 сек").tag(2.0)
                        Text("5.0 сек").tag(5.0)
                    }
                }

                // Пороги сетевых алертов
                Section("Пороги оповещений") {
                    HStack {
                        Text("Предупреждение RTT")
                        Spacer()
                        Text("\(Int(viewModel.latencyWarnThreshold)) мс")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.latencyWarnThreshold, in: 30...300, step: 10)

                    HStack {
                        Text("Критическая задержка RTT")
                        Spacer()
                        Text("\(Int(viewModel.latencyCritThreshold)) мс")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.latencyCritThreshold, in: 80...500, step: 10)

                    HStack {
                        Text("Критические потери пакетов")
                        Spacer()
                        Text("\(Int(viewModel.lossCritThreshold)) %")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.lossCritThreshold, in: 1...20, step: 1)
                }

                // Виджеты и Оверлеи
                Section("Виджеты и мониторинг") {
                    Toggle(isOn: Binding(
                        get: { viewModel.liveActivityEnabled },
                        set: { viewModel.toggleLiveActivity(enabled: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dynamic Island (Live Activity)")
                                .font(.system(size: 15, weight: .medium))
                            Text("Непрерывный показ скорости в вырезе экрана и на Lock Screen 24/7")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle(isOn: $viewModel.floatingHUDEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Плавающий игровой оверлей (HUD)")
                                .font(.system(size: 15, weight: .medium))
                            Text("Мини-виджет поверх экрана, который можно перемещать пальцем")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Обратная связь
                Section("Тактильная отдача и звуки") {
                    Toggle("Тактильный отклик (Haptics)", isOn: $viewModel.hapticsEnabled)
                    Toggle("Звуковые предупреждения", isOn: $viewModel.soundEnabled)
                }

                // Управление хранилищем трафика
                Section("Хранилище трафика") {
                    Button(role: .destructive) {
                        showResetTrafficAlert = true
                    } label: {
                        Label("Сбросить историю трафика", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Настройки")
            .confirmationDialog(
                "Сбросить историю трафика?",
                isPresented: $showResetTrafficAlert,
                titleVisibility: .visible
            ) {
                Button("Очистить все данные", role: .destructive) {
                    Task {
                        await viewModel.resetTrafficHistory()
                    }
                    HapticManager.shared.notificationWarning()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Все сохраненные сессии и графики расхода трафика будут безвозвратно удалены.")
            }
        }
    }
}
