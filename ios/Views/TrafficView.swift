//
//  TrafficView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import Charts

/// Главный экран аналитики трафика: где, когда и сколько потрачено (Wi-Fi vs Cellular, история сессий, графики, квоты)
public struct TrafficView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    @State private var selectedPeriod: TrafficPeriod = .today
    @State private var showBudgetSheet: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var exportURL: URL?
    @State private var showResetConfirmation: Bool = false
    @State private var filterType: SessionFilter = .all

    enum SessionFilter: String, CaseIterable, Identifiable {
        case all = "Все"
        case wifi = "Wi-Fi"
        case cellular = "Сотовая"

        var id: String { rawValue }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. Выбор периода анализа
                    Picker("Период", selection: $selectedPeriod) {
                        ForEach(TrafficPeriod.allCases) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: selectedPeriod) { _, _ in
                        HapticManager.shared.selectionChanged()
                        Task {
                            await viewModel.refreshTrafficData(period: selectedPeriod)
                        }
                    }

                    // Баннер фонового мониторинга
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.cyan)

                        Text("Фоновый учет 24/7 активен")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("Ядро Darwin BSD")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    // 2. Карточка текущей активной сессии (Live)
                    activeLiveSessionCard

                    // 3. Главная сводная карточка расхода трафика
                    heroSummaryCard

                    // 4. На что потрачен трафик (Категории сетевой активности)
                    trafficCategoriesSection

                    // 5. График расхода трафика во времени
                    trafficChartsSection

                    // 6. Контроль бюджета и лимитов трафика
                    budgetQuotaSection

                    // 7. История сессий («Где и сколько потратил»)
                    sessionsHistorySection
                }
                .padding(.vertical)
                .padding(.bottom, 40)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Трафик")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task {
                                if let url = await viewModel.exportTrafficCSV() {
                                    exportURL = url
                                    showShareSheet = true
                                }
                            }
                        } label: {
                            Label("Экспорт отчета (CSV)", systemImage: "doc.text")
                        }

                        Button {
                            Task {
                                if let url = await viewModel.exportTrafficJSON() {
                                    exportURL = url
                                    showShareSheet = true
                                }
                            }
                        } label: {
                            Label("Экспорт отчета (JSON)", systemImage: "curlybraces")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showResetConfirmation = true
                        } label: {
                            Label("Очистить историю трафика", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(.cyan)
                    }
                }
            }
            .sheet(isPresented: $showBudgetSheet) {
                TrafficBudgetSheet(
                    budget: viewModel.trafficBudget,
                    onSave: { newBudget in
                        Task {
                            await viewModel.updateTrafficBudget(newBudget)
                        }
                    }
                )
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .confirmationDialog(
                "Сбросить всю историю трафика?",
                isPresented: $showResetConfirmation,
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
                Text("Это действие удалит всю накопленную историю сессий и точки замеров расхода трафика.")
            }
            .task {
                await viewModel.refreshTrafficData(period: selectedPeriod)
            }
        }
    }

    // MARK: - Карточка текущей активной сессии в реальном времени

    private var activeLiveSessionCard: some View {
        let isConnected = viewModel.systemInfo.connectionType != .unavailable
        let activeSession = viewModel.trafficSessions.first(where: { $0.isActive })

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(isConnected ? "АКТИВНОЕ ПОДКЛЮЧЕНИЕ" : "НЕТ ПОДКЛЮЧЕНИЯ")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isConnected ? .green : .red)
                }

                Spacer()

                Text(isConnected ? viewModel.systemInfo.connectionType.rawValue : "Офлайн")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isConnected ? .cyan : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isConnected ? Color.cyan.opacity(0.12) : Color(uiColor: .tertiarySystemFill))
                    .clipShape(Capsule())
            }

            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            isConnected
                                ? (viewModel.systemInfo.connectionType == .wifi ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                                : Color.secondary.opacity(0.15)
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: iconForConnectionType(viewModel.systemInfo.connectionType))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(
                            isConnected
                                ? (viewModel.systemInfo.connectionType == .wifi ? Color.blue : Color.green)
                                : Color.secondary
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.currentNetworkTitle)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)

                    if isConnected {
                        Text("IP: \(viewModel.systemInfo.localIP) • \(viewModel.systemInfo.ispName ?? "Активно")")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Подключите Wi-Fi или сотовые данные")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            Divider()

            // Живой объем трафика в текущей активной сессии (с момента подключения)
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.blue)
                        Text("СКАЧАНО В СЕССИИ")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(TrafficFormatter.formatBytes(activeSession?.downloadedBytes ?? 0))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("ОТДАНО В СЕССИИ")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.cyan)
                    }
                    Text(TrafficFormatter.formatBytes(activeSession?.uploadedBytes ?? 0))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
        )
        .padding(.horizontal)
    }

    private func iconForConnectionType(_ type: NetworkConnectionType) -> String {
        switch type {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .ethernet: return "cable.connector"
        case .loopback: return "arrow.triangle.2.circlepath"
        case .unavailable: return "wifi.slash"
        }
    }

    // MARK: - Главная сводная карточка (Hero Card)

    private var heroSummaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ИТОГО ЗА ПЕРИОД: \(selectedPeriod.rawValue.uppercased())")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    Text(TrafficFormatter.formatBytes(viewModel.trafficSummary.totalTraffic))
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(viewModel.trafficSummary.totalSessionsCount) сессий")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("Всего точек")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            // Двухцветный прогресс-бар: Wi-Fi vs Сотовые данные
            VStack(spacing: 6) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        let wifiWidth = geo.size.width * CGFloat(viewModel.trafficSummary.wifiPercentage / 100.0)
                        let cellWidth = geo.size.width * CGFloat(viewModel.trafficSummary.cellularPercentage / 100.0)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue)
                            .frame(width: max(wifiWidth, 0))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.orange)
                            .frame(width: max(cellWidth, 0))
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
                .background(Color(uiColor: .tertiarySystemFill).clipShape(Capsule()))

                // Легенда
                HStack {
                    HStack(spacing: 4) {
                        Circle().fill(Color.blue).frame(width: 7, height: 7)
                        Text("Wi-Fi: \(TrafficFormatter.formatBytes(viewModel.trafficSummary.totalWifi)) (\(String(format: "%.0f", viewModel.trafficSummary.wifiPercentage))%)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 7, height: 7)
                        Text("Сотовая: \(TrafficFormatter.formatBytes(viewModel.trafficSummary.totalCellular)) (\(String(format: "%.0f", viewModel.trafficSummary.cellularPercentage))%)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // Сетка Скачивание / Отдача
            HStack(spacing: 12) {
                metricTile(
                    title: "Скачивание (Down)",
                    value: TrafficFormatter.formatBytes(viewModel.trafficSummary.totalDownload),
                    icon: "arrow.down.circle.fill",
                    color: .blue
                )

                metricTile(
                    title: "Отдача (Up)",
                    value: TrafficFormatter.formatBytes(viewModel.trafficSummary.totalUpload),
                    icon: "arrow.up.circle.fill",
                    color: .cyan
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
        )
        .padding(.horizontal)
    }

    private func metricTile(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Детализация категорий расхода трафика

    private var trafficCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("НА ЧТО ПОТРАЧЕН ТРАФИК")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    Text("Категории сетевой активности")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                    Text("AI-анализ")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.cyan.opacity(0.12))
                .clipShape(Capsule())
            }

            if viewModel.trafficSummary.categoryBreakdown.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Ожидание передачи сетевых пакетов...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // Мульти-градиентная сегментированная полоса
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(viewModel.trafficSummary.categoryBreakdown) { item in
                                let segmentWidth = geo.size.width * CGFloat(item.percentage / 100.0)
                                if segmentWidth > 2 {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(item.category.swiftUIColor)
                                        .frame(width: segmentWidth)
                                }
                            }
                        }
                    }
                    .frame(height: 10)
                    .clipShape(Capsule())
                    .background(Color(uiColor: .tertiarySystemFill).clipShape(Capsule()))
                }

                // Список категорий
                VStack(spacing: 8) {
                    ForEach(viewModel.trafficSummary.categoryBreakdown) { item in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(item.category.swiftUIColor.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: item.category.iconName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(item.category.swiftUIColor)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.category.rawValue)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)

                                Text(item.category.categoryDescription)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(TrafficFormatter.formatBytes(item.totalBytes))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)

                                Text(String(format: "%.1f%%", item.percentage))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(item.category.swiftUIColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(item.category.swiftUIColor.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(10)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
        )
        .padding(.horizontal)
    }

    // MARK: - График расхода трафика (SwiftUI Charts)

    private var trafficChartsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Динамика расхода данных")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(selectedPeriod.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if viewModel.trafficDataPoints.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Накопление данных для графика...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
            } else {
                Chart {
                    ForEach(viewModel.trafficDataPoints) { pt in
                        BarMark(
                            x: .value("Время", pt.timestamp, unit: selectedPeriod == .today ? .hour : .day),
                            y: .value("Wi-Fi", Double(pt.wifiBytes) / 1_048_576.0)
                        )
                        .foregroundStyle(Color.blue.gradient)
                        .position(by: .value("Тип", "Wi-Fi"))

                        BarMark(
                            x: .value("Время", pt.timestamp, unit: selectedPeriod == .today ? .hour : .day),
                            y: .value("Сотовая", Double(pt.cellularBytes) / 1_048_576.0)
                        )
                        .foregroundStyle(Color.orange.gradient)
                        .position(by: .value("Тип", "Сотовая"))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let mb = value.as(Double.self) {
                                Text("\(Int(mb)) МБ")
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
                .frame(height: 180)
                .clipped()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
        )
        .padding(.horizontal)
    }

    // MARK: - Секция лимитов и квоты

    private var budgetQuotaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Лимит трафика (Квота)")
                        .font(.system(size: 16, weight: .bold))
                    Text(viewModel.trafficBudget.isEnabled ? "Контроль расхода включен" : "Лимит не установлен")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showBudgetSheet = true
                    HapticManager.shared.impactLight()
                } label: {
                    Text(viewModel.trafficBudget.isEnabled ? "Изменить" : "Настроить")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.cyan.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if viewModel.trafficBudget.isEnabled {
                let used = viewModel.trafficSummary.totalTraffic
                let pct = viewModel.trafficBudget.usagePercentage(usedBytes: used)
                let isWarn = viewModel.trafficBudget.isWarning(usedBytes: used)
                let isExceeded = viewModel.trafficBudget.isExceeded(usedBytes: used)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(TrafficFormatter.formatBytes(used)) из \(TrafficFormatter.formatBytes(viewModel.trafficBudget.limitBytes))")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isExceeded ? .red : (isWarn ? .yellow : .primary))

                        Spacer()

                        Text("\(String(format: "%.1f", pct))%")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(isExceeded ? .red : (isWarn ? .yellow : .secondary))
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(uiColor: .tertiarySystemFill))
                                .frame(height: 8)

                            Capsule()
                                .fill(isExceeded ? Color.red : (isWarn ? Color.yellow : Color.cyan))
                                .frame(width: min(geo.size.width * CGFloat(pct / 100.0), geo.size.width), height: 8)
                        }
                    }
                    .frame(height: 8)

                    if isExceeded {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                            Text("Установленный лимит трафика превышен!")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.red)
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
        )
        .padding(.horizontal)
    }

    // MARK: - История сессий («Где и сколько потрачено»)

    private var sessionsHistorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Где и сколько потрачено")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Picker("Фильтр", selection: $filterType) {
                    ForEach(SessionFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 13))
            }

            let filteredSessions = viewModel.trafficSessions.filter { s in
                switch filterType {
                case .all: return true
                case .wifi: return s.connectionType.contains("Wi-Fi")
                case .cellular: return !s.connectionType.contains("Wi-Fi")
                }
            }

            if filteredSessions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("В выбранном периоде нет сохраненных сессий")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredSessions) { session in
                        SessionRowCard(session: session)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
        )
        .padding(.horizontal)
    }
}

// MARK: - Карточка одной сессии подключения

private struct SessionRowCard: View {
    let session: TrafficSession

    private var isWifi: Bool {
        session.connectionType.contains("Wi-Fi")
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isWifi ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: isWifi ? "wifi" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isWifi ? .blue : .orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.networkName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)

                        if session.isActive {
                            Text("LIVE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    Text("\(formatDate(session.startDate)) • \(session.formattedDuration)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(TrafficFormatter.formatBytes(session.totalBytes))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(session.interfaceName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Разбивка Download / Upload для сессии
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.blue)
                    Text("↓ \(TrafficFormatter.formatBytes(session.downloadedBytes))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.cyan)
                    Text("↑ \(TrafficFormatter.formatBytes(session.uploadedBytes))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if session.peakDownloadBps > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                        Text(TrafficFormatter.formatSpeedBps(session.peakDownloadBps))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Доминирующие категории трафика в сессии
            if !session.categoryUsages.isEmpty {
                HStack(spacing: 6) {
                    ForEach(session.categoryUsages.prefix(3)) { usage in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(usage.category.swiftUIColor)
                                .frame(width: 6, height: 6)
                            Text("\(usage.category.rawValue) • \(TrafficFormatter.formatBytes(usage.totalBytes))")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(usage.category.swiftUIColor.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        df.locale = Locale(identifier: "ru_RU")
        return df.string(from: date)
    }
}

// MARK: - Модальное окно настройки лимита трафика

private struct TrafficBudgetSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isEnabled: Bool
    @State private var limitGB: Double
    @State private var warningThresholdPct: Double
    @State private var period: TrafficPeriod

    let onSave: (TrafficBudget) -> Void

    init(budget: TrafficBudget, onSave: @escaping (TrafficBudget) -> Void) {
        self._isEnabled = State(initialValue: budget.isEnabled)
        self._limitGB = State(initialValue: Double(budget.limitBytes) / 1_073_741_824.0)
        self._warningThresholdPct = State(initialValue: budget.warningThresholdPct)
        self._period = State(initialValue: budget.period)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Контроль квоты") {
                    Toggle("Включить лимит трафика", isOn: $isEnabled)
                }

                if isEnabled {
                    Section("Параметры лимита") {
                        HStack {
                            Text("Лимит трафика")
                            Spacer()
                            Text("\(String(format: "%.1f", limitGB)) ГБ")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.cyan)
                        }
                        Slider(value: $limitGB, in: 1.0...100.0, step: 1.0)

                        Picker("Период квоты", selection: $period) {
                            Text("В день (Сегодня)").tag(TrafficPeriod.today)
                            Text("В неделю (7 дней)").tag(TrafficPeriod.week)
                            Text("В месяц (30 дней)").tag(TrafficPeriod.month)
                        }

                        HStack {
                            Text("Порог предупреждения")
                            Spacer()
                            Text("\(Int(warningThresholdPct))%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $warningThresholdPct, in: 50...95, step: 5)
                    }
                }
            }
            .navigationTitle("Лимит трафика")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let bytes = UInt64(limitGB * 1_073_741_824.0)
                        let newBudget = TrafficBudget(
                            isEnabled: isEnabled,
                            limitBytes: bytes,
                            period: period,
                            warningThresholdPct: warningThresholdPct
                        )
                        onSave(newBudget)
                        HapticManager.shared.notificationSuccess()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                }
            }
        }
    }
}

// MARK: - Системный ShareSheet для выгрузки файлов отчета

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Расширение цветов категорий для SwiftUI

extension TrafficCategory {
    public var swiftUIColor: Color {
        switch self {
        case .videoStreaming: return .red
        case .messagingSocial: return .blue
        case .webBrowsing: return .purple
        case .gamingVoip: return .green
        case .speedtestDiagnostics: return .orange
        case .systemBackground: return .gray
        }
    }
}

