//
//  SettingsView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Экран настроек приложения NetPulse 2026
@MainActor
public struct SettingsView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    @State private var newHostName: String = ""
    @State private var newHostAddress: String = ""
    @State private var newHostPort: String = "443"
    @State private var showResetTrafficAlert: Bool = false
    @State private var showIslandDiagnostics: Bool = false
    @State private var addHostError: String?
    /// Настройки открываются поверх главного экрана (кнопка с ползунками): «Готово» закрывает их
    @Environment(\.dismiss) private var dismiss

    /// Версия и сборка из Info.plist (раньше выводилась выдуманная «2.2.0 (Build 2026.08)»)
    private var appVersionText: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "—"
        return "\(version) (\(build))"
    }

    /// Подсказка под островом: он в фоне обновляется только пока приложение остаётся активным из-за записи маршрута
    private var islandRecordingNote: String {
        let recorder = RouteRecorder.shared
        if !recorder.recordsInBackground {
            return "Остров в фоне обновляется, только если включена фоновая запись маршрута («Записывать маршрут в фоне» в разделе «Запись маршрута»)."
        }
        return recorder.isActive
            ? "Идёт запись маршрута: приложение активно и в фоне, остров обновляется"
            : "Остров в фоне обновляется, пока на главном экране идёт запись маршрута («Записать маршрут»)."
    }

    /// Строка подписки: статус и цена
    private var proRow: some View {
        let store = ProStore.shared
        return HStack(spacing: 10) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(NPTheme.accentPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("NetPulse PRO")
                    .font(.system(size: 15, weight: .semibold))
                Text(store.isPro
                     ? "Подписка активна: остров, HUD и AI-аудит"
                     : "Остров, игровой HUD и AI-аудит" + (store.priceText.map { " · \($0)" } ?? ""))
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settingsProRow")
    }

    public var body: some View {
        NavigationStack {
            Form {
                // 0. Подписка PRO
                Section(header: Label("Подписка", systemImage: "star.fill")) {
                    proRow
                    if ProStore.shared.isPro {
                        Link("Управлять подпиской", destination: AppLinks.manageSubscriptions)
                            .accessibilityIdentifier("settingsManageSubscription")
                    } else {
                        Button("Оформить NetPulse PRO") {
                            ProStore.shared.paywall = .general
                        }
                        .accessibilityIdentifier("settingsOpenPaywall")
                    }
                    Button("Восстановить покупки") {
                        Task {
                            await ProStore.shared.restore()
                        }
                    }
                    .accessibilityIdentifier("settingsRestorePurchases")
                }

                // 3. Статус и параметры опроса
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

                    Picker("Пауза между проверками", selection: $viewModel.pollingInterval) {
                        Text("1 сек").tag(1.0)
                        Text("2 сек").tag(2.0)
                        Text("4 сек (по умолч.)").tag(4.0)
                        Text("10 сек").tag(10.0)
                        Text("30 сек").tag(30.0)
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
                        // Вместе с узлом удаляются и его метрики (раньше они оставались и влияли на средние значения)
                        viewModel.removeTargets(atOffsets: indexSet)
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
                            // Порт обязан быть 1–65535: значение вне диапазона раньше приводило к аварийному
                            // завершению приложения при ближайшей проверке
                            guard let port = Int(newHostPort.trimmingCharacters(in: .whitespaces)), (1...65_535).contains(port) else {
                                addHostError = "Порт должен быть числом от 1 до 65535"
                                HapticManager.shared.notificationWarning()
                                return
                            }
                            switch viewModel.addTarget(name: newHostName, address: newHostAddress, port: port) {
                            case .added:
                                newHostName = ""
                                newHostAddress = ""
                                newHostPort = "443"
                                addHostError = nil
                                HapticManager.shared.impactMedium()
                            case .invalidAddress:
                                addHostError = "Введите корректный IP-адрес или доменное имя (без пробелов и спецсимволов)"
                                HapticManager.shared.notificationWarning()
                            case .invalidPort:
                                addHostError = "Порт должен быть числом от 1 до 65535"
                                HapticManager.shared.notificationWarning()
                            case .duplicate:
                                addHostError = "Такой узел уже есть в списке"
                                HapticManager.shared.notificationWarning()
                            }
                        }
                        .disabled(newHostAddress.isEmpty)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NPTheme.accentPrimary)

                        if let addHostError {
                            Text(addHostError)
                                .font(.system(size: 12))
                                .foregroundStyle(NPTheme.semanticCritical)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 4. Пороги сетевых алертов
                Section {
                    DisclosureGroup("Пороги оповещений") {
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
                }

                // 5. Фоновый мониторинг трафика (24/7)
                Section("Фоновая работа и учет трафика") {
                    Toggle(isOn: $viewModel.backgroundMonitoringEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Фоновый учет трафика")
                                .font(.system(size: 15, weight: .semibold))
                            Text("iOS приостанавливает свернутые приложения. Трафик за время «сна» NetPulse не теряет: при возвращении он сверяется со счетчиками сетевых интерфейсов ядра iOS и добавляется в статистику.")
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

                // 5.1 Запись маршрута: работа в фоне и расход заряда
                Section(
                    header: Label("Запись маршрута", systemImage: "map.fill"),
                    footer: Text("Запись идёт только по кнопке «Записать маршрут» на главном экране, маршруты хранятся на этом устройстве. В фоне и при включённом энергосбережении iOS точки пишутся реже: так запись тратит меньше заряда.")
                ) {
                    Toggle(isOn: Binding(
                        get: { RouteRecorder.shared.recordsInBackground },
                        set: { enabled in
                            RouteRecorder.shared.recordsInBackground = enabled
                            HapticManager.shared.selectionChanged()
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Записывать маршрут в фоне")
                                .font(.system(size: 15, weight: .medium))
                            Text(RouteRecorder.shared.recordsInBackground
                                 ? "Запись идёт, пока приложение свёрнуто или экран заблокирован; в строке состояния виден значок геолокации. Заряд тратится заметнее."
                                 : "Когда приложение свёрнуто, запись ждёт, а при возвращении продолжается. Заряд в фоне не тратится.")
                                .font(.system(size: 12))
                                .foregroundStyle(NPTheme.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("routeBackgroundToggle")

                    Toggle(isOn: Binding(
                        get: { RouteRecorder.shared.stopsWhenIdle },
                        set: { enabled in
                            RouteRecorder.shared.stopsWhenIdle = enabled
                            HapticManager.shared.selectionChanged()
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Останавливать, если телефон стоит на месте")
                                .font(.system(size: 15, weight: .medium))
                            Text("Если 20 минут нет движения, маршрут сохраняется и запись останавливается сама: забытая запись не посадит батарею.")
                                .font(.system(size: 12))
                                .foregroundStyle(NPTheme.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("routeAutoStopToggle")
                }

                // 6. Виджеты и Оверлеи
                Section("Виджеты и мониторинг") {
                    Toggle(isOn: Binding(
                        get: { viewModel.liveActivityEnabled },
                        set: { viewModel.toggleLiveActivity(enabled: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Dynamic Island (Спидометр скорости)")
                                    .font(.system(size: 15, weight: .medium))
                                if !ProStore.shared.isPro {
                                    ProBadge()
                                }
                            }
                            Text("Индикатор скорости передачи данных (↓ Скачивание / ↑ Отдача) в вырезе экрана и на Lock Screen")
                                .font(.system(size: 12))
                                .foregroundStyle(NPTheme.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("dynamicIslandToggle")

                    if !ActivityManager.shared.areActivitiesEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(NPTheme.semanticCritical)
                                Text("Live Activities отключены в системе")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(NPTheme.semanticCritical)
                            }
                            Text("Разрешите показ Live Activities для NetPulse в Настройках iOS, чтобы спидометр отображался в вырезе экрана.")
                                .font(.system(size: 11))
                                .foregroundStyle(NPTheme.textSecondary)

                            Button("Открыть Настройки iOS") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(NPTheme.accentPrimary)
                        }
                        .padding(.vertical, 4)
                    } else if viewModel.liveActivityEnabled {
                        HStack {
                            Circle()
                                .fill(ActivityManager.shared.isLiveActivityActive ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text("Статус: \(ActivityManager.shared.statusDescription)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(NPTheme.textSecondary)
                                .accessibilityIdentifier("islandStatus")
                            Spacer()
                            Button("Перезапустить") {
                                HapticManager.shared.impactMedium()
                                viewModel.restartLiveActivity()
                            }
                            .accessibilityIdentifier("islandRestartButton")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(NPTheme.accentPrimary)
                        }

                        // Запись маршрута (кнопка «Записать маршрут» на главном экране): пока она идёт,
                        // приложение активно в фоне и остров обновляется
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(NPTheme.accentPrimary)
                            Text(islandRecordingNote)
                                .font(.system(size: 12))
                                .foregroundStyle(NPTheme.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("islandRecordingNote")

                        // Журнал: что происходило с островом, пока приложение было свёрнуто
                        Button {
                            showIslandDiagnostics = true
                        } label: {
                            HStack {
                                Label("Диагностика острова", systemImage: "waveform.path.ecg")
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(NPTheme.textSecondary)
                            }
                        }
                        .accessibilityIdentifier("islandDiagnosticsButton")
                    }

                    // Плавающий игровой оверлей (HUD): входит в подписку PRO
                    Toggle(isOn: Binding(
                        get: { viewModel.floatingHUDEnabled },
                        set: { enabled in
                            if enabled && !ProStore.shared.requirePro(.hud) { return }
                            viewModel.floatingHUDEnabled = enabled
                            if enabled {
                                BackgroundTelemetryKeeper.shared.startKeepAlive()
                                viewModel.startBandwidthTask()
                                if viewModel.hapticsEnabled {
                                    HapticManager.shared.impactMedium()
                                }
                            } else if !viewModel.liveActivityEnabled && !viewModel.backgroundMonitoringEnabled {
                                BackgroundTelemetryKeeper.shared.stopKeepAlive()
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Плавающий игровой оверлей (HUD)")
                                    .font(.system(size: 15, weight: .medium))
                                if !ProStore.shared.isPro {
                                    ProBadge()
                                }
                            }
                            Text("Мини-панель пинга, джиттера, потерь и скорости поверх экранов NetPulse; остров переходит в игровой режим")
                                .font(.system(size: 12))
                                .foregroundStyle(NPTheme.textSecondary)
                        }
                    }
                }

                // 8. Обратная связь
                Section {
                    DisclosureGroup("Тактильная отдача и звуки") {
                    Toggle("Тактильный отклик (Haptics)", isOn: $viewModel.hapticsEnabled)
                    Toggle("Звуковые предупреждения", isOn: $viewModel.soundEnabled)
                                    }
                }

                // 8. Управление хранилищем трафика
                Section {
                    DisclosureGroup("Хранилище трафика") {
                    Button(role: .destructive) {
                        showResetTrafficAlert = true
                    } label: {
                        Label("Сбросить историю трафика", systemImage: "trash")
                    }
                                    }
                }

                // 9. О приложении
                Section("О приложении") {
                    HStack {
                        Text("Версия")
                            .foregroundStyle(NPTheme.textPrimary)
                        Spacer()
                        Text(appVersionText)
                            .foregroundStyle(NPTheme.textSecondary)
                    }

                    HStack {
                        Text("Метод проверки узлов")
                        Spacer()
                        Text("TCP-соединение (Network.framework)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NPTheme.accentPrimary)
                    }

                    HStack {
                        Text("Источник данных о трафике")
                        Spacer()
                        Text("Счётчики интерфейсов (getifaddrs)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NPTheme.accentPrimary)
                    }

                    Link(destination: AppLinks.privacyPolicy) {
                        HStack {
                            Text("Политика конфиденциальности")
                                .foregroundStyle(NPTheme.textPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NPTheme.textTertiary)
                        }
                    }
                    .accessibilityIdentifier("settingsPrivacyPolicyLink")

                    Link(destination: AppLinks.support) {
                        HStack {
                            Text("Поддержка")
                                .foregroundStyle(NPTheme.textPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NPTheme.textTertiary)
                        }
                    }
                    .accessibilityIdentifier("settingsSupportLink")
                }
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityIdentifier("settingsCloseButton")
                }
            }
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
            .sheet(isPresented: $showIslandDiagnostics) {
                IslandDiagnosticsView()
            }
        }
        // Настройки лежат в полноэкранном окне, поверх которого корневой экран ничего показать не может:
        // окно подписки из настроек показывают сами настройки
        .sheet(item: Binding(
            get: { ProStore.shared.paywallHost == .settings ? ProStore.shared.paywall : nil },
            set: { ProStore.shared.paywall = $0 }
        )) { feature in
            PaywallView(feature: feature)
        }
        .onAppear {
            ProStore.shared.paywallHost = .settings
        }
        .onDisappear {
            ProStore.shared.paywallHost = .root
        }
    }
}
