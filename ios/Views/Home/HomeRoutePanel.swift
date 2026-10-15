//
//  HomeRoutePanel.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Нижняя панель с итогом маршрута: когда и сколько, полоска качества, легенда, зоны без связи.
/// Показывается сразу после остановки записи, при выборе маршрута из списка и для примера (с пометкой «демо-данные»).
@MainActor
struct HomeRoutePanel: View {
    let route: RouteRecord
    let isDemo: Bool
    @Binding var metric: RouteMetric
    let onDone: () -> Void
    let onDelete: () -> Void

    /// Экспорт маршрута: файл GPX или картинка карты (входит в подписку PRO)
    @State private var sharePayload: SharePayload?
    @State private var isPreparingExport = false

    private var hasSpeedData: Bool {
        route.points.contains { ($0.downloadMbps ?? 0) > 0 }
    }

    var body: some View {
        let stats = RouteAnalyzer.stats(of: route)
        let zones = RouteAnalyzer.deadZones(in: route.points)

        VStack(alignment: .leading, spacing: 0) {
            header(stats)

            QualityBar(shares: stats.shares, height: 12)
                .padding(.top, 14)

            legend(stats)
                .padding(.top, 12)

            deadZoneRow(stats, zones)
                .padding(.top, 8)

            if route.interrupted {
                Text("Запись оборвалась без остановки (приложение закрыла система): маршрут сохранён как есть.")
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.semanticWarn)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            if hasSpeedData {
                Picker("Показатель", selection: $metric) {
                    ForEach(RouteMetric.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 12)
                .accessibilityIdentifier("networkMapMetricPicker")
            }

            buttons
                .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomePanelBackground())
        .sheet(item: $sharePayload) { payload in
            NPShareSheet(activityItems: payload.items)
        }
    }

    // MARK: - Экспорт

    private func exportGPX() {
        guard ProStore.shared.requirePro(.export) else { return }
        guard let url = RouteExport.writeGPX(for: route) else { return }
        sharePayload = SharePayload(items: [url])
    }

    private func exportImage() {
        guard ProStore.shared.requirePro(.export), !isPreparingExport else { return }
        isPreparingExport = true
        Task {
            let image = await RouteExport.mapImage(for: route)
            isPreparingExport = false
            if let image {
                sharePayload = SharePayload(items: [image])
            }
        }
    }

    // MARK: - Шапка

    private func header(_ stats: RouteStats) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isDemo ? "Пример · демо-данные" : RouteTitle.dateRange(of: route))
                    .font(.system(size: 13))
                    .foregroundStyle(NPTheme.textSecondary)
                Text("\(RouteFormat.distance(stats.distanceMeters)) · \(RouteFormat.duration(stats.duration))")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(NPTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(latencyLine(stats))
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.textSecondary)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Точек: \(stats.pointCount) · \(RouteFormat.distance(stats.distanceMeters)) · \(RouteFormat.duration(stats.duration))")
            .accessibilityIdentifier("networkMapSummary")

            Spacer(minLength: 0)
            badge
        }
    }

    /// «Задержка: в среднем 74 мс, хуже всего 310 мс · скорость в среднем 12.5 Мбит/с»
    private func latencyLine(_ stats: RouteStats) -> String {
        var parts: [String] = []
        if let average = stats.averageLatencyMs, let worst = stats.worstLatencyMs {
            parts.append("Задержка: в среднем \(RouteFormat.latency(average)), хуже всего \(RouteFormat.latency(worst))")
        }
        if let speed = stats.averageDownloadMbps {
            parts.append("скорость в среднем \(RouteFormat.speed(speed))")
        }
        if parts.isEmpty {
            return "Точек: \(stats.pointCount)"
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var badge: some View {
        if isDemo {
            Text("ПРИМЕР")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(NPTheme.backgroundDeep)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(NPTheme.accentPrimary))
                .accessibilityIdentifier("networkMapDemoBadge")
        } else {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                Text("Сохранён")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(RouteQuality.good.displayColor)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(RouteQuality.good.displayColor.opacity(0.14)))
        }
    }

    // MARK: - Легенда и зоны без связи

    private func legend(_ stats: RouteStats) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                legendItem(.good, stats)
                legendItem(.fair, stats)
            }
            GridRow {
                legendItem(.poor, stats)
                legendItem(.dead, stats)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendItem(_ quality: RouteQuality, _ stats: RouteStats) -> some View {
        HStack(spacing: 8) {
            QualitySwatch(quality: quality)
            Text(quality.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NPTheme.textPrimary)
            Text(RouteFormat.percent(stats.share(of: quality)))
                .font(.system(size: 14))
                .foregroundStyle(NPTheme.textSecondary)
        }
        .frame(minHeight: 22)
    }

    private func deadZoneRow(_ stats: RouteStats, _ zones: [DeadZone]) -> some View {
        HStack(spacing: 12) {
            if zones.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(RouteQuality.good.displayColor)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Зон без сети не найдено")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NPTheme.textPrimary)
                }
            } else {
                let total = zones.reduce(0) { $0 + $1.duration }
                let place = RussianPlural.form(zones.count, one: "место", few: "места", many: "мест")
                Image(systemName: "xmark.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(HomePalette.softRed)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Без связи \(RouteFormat.spokenDuration(total))")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NPTheme.textPrimary)
                    Text("\(zones.count) \(place) · самая длинная — \(RouteFormat.distance(stats.longestDeadStretchMeters))")
                        .font(.system(size: 13))
                        .foregroundStyle(NPTheme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .padding(.top, 6)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("homeDeadZones")
    }

    // MARK: - Кнопки

    @ViewBuilder
    private var buttons: some View {
        if isDemo {
            Button {
                onDone()
            } label: {
                Text("Скрыть пример")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(NPTheme.backgroundDeep)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(NPTheme.buttonGradient)
                    )
            }
            .buttonStyle(NPPressableButtonStyle(scale: 0.97))
            .accessibilityIdentifier("networkMapDemoHideButton")
        } else {
            HStack(spacing: 10) {
                Button {
                    onDelete()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Удалить")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(HomePalette.softRed)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(NPTheme.cardBackgroundTertiary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                }
                .buttonStyle(NPPressableButtonStyle(scale: 0.97))
                .accessibilityIdentifier("homeDeleteRouteButton")

                Menu {
                    Button {
                        exportGPX()
                    } label: {
                        Label("Файл GPX", systemImage: "doc.badge.arrow.up")
                    }
                    Button {
                        exportImage()
                    } label: {
                        Label("Картинка карты", systemImage: "photo")
                    }
                } label: {
                    Group {
                        if isPreparingExport {
                            ProgressView()
                                .tint(NPTheme.textPrimary)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(NPTheme.textPrimary)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(NPTheme.cardBackgroundTertiary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                }
                .accessibilityLabel("Поделиться маршрутом")
                .accessibilityIdentifier("homeRouteShareMenu")

                Button {
                    onDone()
                } label: {
                    Text("Готово")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NPTheme.backgroundDeep)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(NPTheme.buttonGradient)
                        )
                }
                .buttonStyle(NPPressableButtonStyle(scale: 0.97))
                .accessibilityIdentifier("homeDoneButton")
            }
        }
    }
}
