//
//  SettingsView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Экран настроек приложения NetPulse 2026 с переключателем тем оформления
public struct SettingsView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    @State private var themeManager = ThemeManager.shared
    @State private var newHostName: String = ""
    @State private var newHostAddress: String = ""
    @State private var newHostPort: String = "443"
    @State private var showResetTrafficAlert: Bool = false

    public var body: some View {
        NavigationStack {
            Form {
                // 1. Внешний вид и темы оформления
                Section(
                    header: Label("Внешний вид и стиль", systemImage: "paintpalette.fill"),
                    footer: Text(themeManager.currentTheme.description)
                ) {
                    Picker("Тема интерфейса", selection: $themeManager.currentTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: themeManager.currentTheme) { _, _ in
                        HapticManager.shared.selectionChanged()
                    }

                    // Образцы палитр (Theme Swatches)
                    HStack(spacing: 8) {
                        ForEach(AppTheme.allCases) { theme in
                            ThemeSwatchButton(
                                theme: theme,
                                isSelected: themeManager.currentTheme == theme
                            ) {
                                themeManager.currentTheme = theme
                                HapticManager.shared.impactMedium()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 2. Статус и параметры опроса
                Section(header: Label("Мониторинг сети", systemImage: "waveform.path.ecg")) {
                    HStack {
                        Text("Статус службы")
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

                    Picker("Интервал проверки", selection: $viewModel.pollingInterval) {
                        Text("0.5 сек").tag(0.5)
                        Text("1.0 сек (по умолч.)").tag(1.0)
                        Text("2.0 сек").tag(2.0)
                        Text("5.0 сек").tag(5.0)
                    }
                    .onChange(of: viewModel.pollingInterval) { _, _ in
                        HapticManager.shared.selectionChanged()
                    }
                }

                // 3. Целевые узлы мониторинга
                Section(header: Text("Узлы мониторинга"), footer: Text("Добавьте IP-адреса или домены для постоянного мониторинга задержки, джиттера и потерь.")) {
                    ForEach(viewModel.targets) { target in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(NPTheme.textPrimary)
                                Text("\(target.address):\(target.tcpPort)")
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
                    .onDelete { indexSet in
                        viewModel.targets.remove(atOffsets: indexSet)
                        HapticManager.shared.notificationWarning()
                    }

                    // Добавление нового узла
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Добавить новый узел")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(NPTheme.accentPrimary)

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
                        .foregroundStyle(NPTheme.accentPrimary)
                    }
                    .padding(.vertical, 4)
                }

                // 4. Пороги сетевых алертов
                Section("Пороги оповещений") {
                    HStack {
                        Text("Предупреждение RTT")
                        Spacer()
                        Text("\(Int(viewModel.latencyWarnThreshold)) мс")
                            .foregroundStyle(NPTheme.textSecondary)
                    }
                    Slider(value: $viewModel.latencyWarnThreshold, in: 30...300, step: 10)

                    HStack {
                        Text("Критическая задержка RTT")
                        Spacer()
                        Text("\(Int(viewModel.latencyCritThreshold)) мс")
                            .foregroundStyle(NPTheme.textSecondary)
                    }
                    Slider(value: $viewModel.latencyCritThreshold, in: 80...500, step: 10)

                    HStack {
                        Text("Критические потери пакетов")
                        Spacer()
                        Text("\(Int(viewModel.lossCritThreshold)) %")
                            .foregroundStyle(NPTheme.textSecondary)
                    }
                    Slider(value: $viewModel.lossCritThreshold, in: 1...20, step: 1)
                }

                // 5. Фоновый мониторинг трафика (24/7)
                Section("Фоновая работа и учет трафика") {
                    Toggle(isOn: $viewModel.backgroundMonitoringEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Фоновый учет 24/7 (Zero-Loss)")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Непрерывный замер трафика при свернутом приложении и автоматическая сверка со счетчиками ядра iOS при закрытии.")
                                .font(.system(size: 12))
                                .foregroundStyle(NPTheme.textSecondary)
                        }
                    }

                    HStack {
                        Label("Счетчик сетевого адаптера", systemImage: "cpu")
                            .font(.system(size: 13))
                        Spacer()
                        Text("Darwin BSD Kernel")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(NPTheme.accentPrimary)
                    }
                }

                // 6. Виджеты и Оверлеи
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
                                .foregroundStyle(NPTheme.textSecondary)
                        }
                    }

                    Toggle(isOn: $viewModel.floatingHUDEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Плавающий игровой оверлей (HUD)")
                                .font(.system(size: 15, weight: .medium))
                            Text("Мини-виджет поверх экрана, который можно перемещать пальцем")
                                .font(.system(size: 12))
                                .foregroundStyle(NPTheme.textSecondary)
                        }
                    }
                }

                // 7. Обратная связь
                Section("Тактильная отдача и звуки") {
                    Toggle("Тактильный отклик (Haptics)", isOn: $viewModel.hapticsEnabled)
                    Toggle("Звуковые предупреждения", isOn: $viewModel.soundEnabled)
                }

                // 8. Управление хранилищем трафика
                Section("Хранилище трафика") {
                    Button(role: .destructive) {
                        showResetTrafficAlert = true
                    } label: {
                        Label("Сбросить историю трафика", systemImage: "trash")
                    }
                }

                // 9. О приложении
                Section("О приложении") {
                    HStack {
                        Text("Версия")
                        Spacer()
                        Text("2.2.0 (Build 2026.08)")
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

/// Кнопка быстрого выбора темы со свотчем
private struct ThemeSwatchButton: View {
    let theme: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(swatchBgColor)
                        .frame(height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? swatchAccentColor : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                        )

                    Circle()
                        .fill(swatchAccentColor)
                        .frame(width: 10, height: 10)
                }

                Text(theme.rawValue.components(separatedBy: " ").first ?? theme.rawValue)
                    .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? NPTheme.accentPrimary : NPTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(NPPressableButtonStyle(scale: 0.92))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Тема: \(theme.rawValue)")
        .accessibilityHint(isSelected ? "Активная тема" : "Дважды коснитесь для переключения")
    }

    private var swatchBgColor: Color {
        switch theme {
        case .obsidianMono: return Color(red: 0.027, green: 0.035, blue: 0.055)
        case .cyberNeon: return Color(red: 0.031, green: 0.027, blue: 0.063)
        case .titaniumFrost: return Color(red: 0.043, green: 0.051, blue: 0.067)
        case .oledBlack: return Color.black
        }
    }

    private var swatchAccentColor: Color {
        switch theme {
        case .obsidianMono: return Color.white
        case .cyberNeon: return Color(red: 0.0, green: 0.95, blue: 0.85)
        case .titaniumFrost: return Color(red: 0.40, green: 0.75, blue: 1.0)
        case .oledBlack: return Color.white
        }
    }
}
