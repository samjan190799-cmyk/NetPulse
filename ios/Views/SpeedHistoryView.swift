//
//  SpeedHistoryView.swift
//  NetPulse
//
//  Экран «История замеров»: все замеры скорости с графиком и итогами. Входит в подписку PRO.
//

import SwiftUI
import Charts

@MainActor
struct SpeedHistoryView: View {
    private let store = SpeedHistoryStore.shared

    @State private var filter: HistoryFilter = .all
    @State private var confirmClear = false

    enum HistoryFilter: String, CaseIterable, Identifiable {
        case all
        case wifi
        case cellular

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "Все"
            case .wifi: return "Wi-Fi"
            case .cellular: return "Сотовая"
            }
        }

        /// Какое подключение оставить (`nil` — все)
        var connection: String? {
            switch self {
            case .all: return nil
            case .wifi: return "Wi-Fi"
            case .cellular: return "Сотовая"
            }
        }
    }

    private var shown: [SpeedHistoryEntry] {
        store.entries(connection: filter.connection)
    }

    /// Точки графика: последние замеры, от старых к новым
    private var chartEntries: [SpeedHistoryEntry] {
        Array(shown.prefix(40).reversed())
    }

    var body: some View {
        ZStack {
            NPTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    Picker("Подключение", selection: $filter) {
                        ForEach(HistoryFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("speedHistoryFilter")

                    if shown.isEmpty {
                        emptyState
                    } else {
                        summaryTiles
                        chartCard
                        entriesList
                        clearButton
                    }
                }
                .padding(16)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("История замеров")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Удалить всю историю замеров?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                store.clear()
                HapticManager.shared.notificationWarning()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Замеры будут стёрты с этого телефона без возможности восстановления.")
        }
    }

    // MARK: - Пустая история

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(NPTheme.accentPrimary)
            Text("Замеров пока нет")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(NPTheme.textPrimary)
            Text(filter == .all
                 ? "Сделайте замер скорости на вкладке «Сеть»: он сохранится здесь и появится на графике."
                 : "Для этого вида подключения замеров ещё нет.")
                .font(.system(size: 13))
                .foregroundStyle(NPTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(card)
        .accessibilityIdentifier("speedHistoryEmpty")
    }

    // MARK: - Итоги

    private var summaryTiles: some View {
        let summary = SpeedHistorySummary.make(from: shown)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tile(title: "В среднем", value: speedText(summary?.averageDownloadMbps), icon: "arrow.down.circle.fill", color: NPTheme.download)
            tile(title: "Лучший", value: speedText(summary?.bestDownloadMbps), icon: "arrow.up.right.circle.fill", color: RouteQuality.good.displayColor)
            tile(title: "Худший", value: speedText(summary?.worstDownloadMbps), icon: "arrow.down.right.circle.fill", color: NPTheme.semanticWarn)
            tile(title: "Замеров", value: "\(summary?.count ?? 0)", icon: "number.circle.fill", color: NPTheme.accentPrimary)
        }
        .accessibilityIdentifier("speedHistorySummary")
    }

    private func speedText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f Мбит/с", value)
    }

    private func tile(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.textSecondary)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(NPTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    // MARK: - График

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("СКОРОСТЬ ПО ЗАМЕРАМ")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(NPTheme.textTertiary)

            if chartEntries.count < 2 {
                Text("Для графика нужно хотя бы два замера.")
                    .font(.system(size: 13))
                    .foregroundStyle(NPTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else {
                Chart {
                    ForEach(chartEntries) { entry in
                        LineMark(
                            x: .value("Время", entry.date),
                            y: .value("Мбит/с", entry.downloadMbps),
                            series: .value("Показатель", "Скачивание")
                        )
                        .foregroundStyle(NPTheme.download)
                        .interpolationMethod(.monotone)

                        PointMark(
                            x: .value("Время", entry.date),
                            y: .value("Мбит/с", entry.downloadMbps)
                        )
                        .foregroundStyle(NPTheme.download)
                        .symbolSize(24)

                        if entry.uploadMbps > 0 {
                            LineMark(
                                x: .value("Время", entry.date),
                                y: .value("Мбит/с", entry.uploadMbps),
                                series: .value("Показатель", "Отдача")
                            )
                            .foregroundStyle(NPTheme.upload)
                            .interpolationMethod(.monotone)
                        }
                    }
                }
                .chartYAxisLabel("Мбит/с")
                .frame(height: 190)

                HStack(spacing: 14) {
                    legendDot(color: NPTheme.download, title: "Скачивание")
                    legendDot(color: NPTheme.upload, title: "Отдача")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
        .accessibilityIdentifier("speedHistoryChart")
    }

    private func legendDot(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(NPTheme.textSecondary)
        }
    }

    // MARK: - Список

    private var entriesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ПОСЛЕДНИЕ ЗАМЕРЫ")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(NPTheme.textTertiary)
                .padding(.bottom, 8)

            ForEach(Array(shown.prefix(30))) { entry in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(NPTheme.textPrimary)
                        Text(entry.connection)
                            .font(.system(size: 12))
                            .foregroundStyle(NPTheme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "↓ %.1f  ↑ %.1f", entry.downloadMbps, entry.uploadMbps))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(NPTheme.textPrimary)
                        if let ping = entry.pingMs {
                            Text("пинг \(Int(ping.rounded())) мс")
                                .font(.system(size: 12))
                                .foregroundStyle(NPTheme.textSecondary)
                        }
                    }
                }
                .padding(.vertical, 8)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private var clearButton: some View {
        Button {
            confirmClear = true
        } label: {
            Label("Удалить историю", systemImage: "trash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HomePalette.softRed)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .accessibilityIdentifier("speedHistoryClearButton")
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(NPTheme.cardBackground.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}
