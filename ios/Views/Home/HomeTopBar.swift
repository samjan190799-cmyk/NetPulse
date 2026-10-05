//
//  HomeTopBar.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Как выглядит верхняя полоса главного экрана
enum HomeTopBarStyle: Equatable {
    /// Обычный вид: связь сейчас, остров, настройки
    case idle
    /// Идёт запись маршрута: значок записи и живая оценка связи
    case recording
    /// Показан готовый маршрут: кнопка «Назад» вместо плашек
    case route
}

/// Верхняя полоса поверх карты: слева — состояние, справа — круглые кнопки
@MainActor
struct HomeTopBar: View {
    let viewModel: NetworkMonitorViewModel
    let recorder: RouteRecorder
    let style: HomeTopBarStyle
    let lastRouteChip: String?
    /// Нижняя панель развёрнута: над ней остаётся только первый ряд (связь и настройки)
    let compact: Bool
    @Binding var satellite: Bool
    /// Показывать ли покрытие сети (цветная зона вокруг вас и полосы прежних маршрутов) в обычном режиме
    @Binding var coverageOn: Bool
    let onSettings: () -> Void
    let onRecenter: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                leading
                Spacer(minLength: 8)
                trailing
            }
            if style == .recording {
                HomeLiveQualityCard(recorder: recorder)
                HStack {
                    Spacer(minLength: 0)
                    recenterButton
                }
            }
        }
    }

    // MARK: - Слева

    @ViewBuilder
    private var leading: some View {
        switch style {
        case .idle:
            VStack(alignment: .leading, spacing: 4) {
                HomeLinkPill(connection: connectionName, icon: connectionIcon, quality: linkQuality)
                if !compact {
                    HomeIslandPill(viewModel: viewModel)
                    if let lastRouteChip {
                        HomeChip(text: lastRouteChip)
                    }
                }
            }
        case .recording:
            HomeRecordingPill(recorder: recorder)
        case .route:
            GlassCircleButton(
                systemImage: "chevron.left",
                label: "Назад",
                identifier: "homeRouteBackButton",
                action: onBack
            )
        }
    }

    /// Вид подключения для плашки: «Wi-Fi», «Сотовая»…
    private var connectionName: String {
        switch viewModel.systemInfo.connectionType {
        case .wifi: return "Wi-Fi"
        case .cellular: return "Сотовая"
        case .ethernet: return "Ethernet"
        case .loopback: return "Локальная"
        case .unavailable: return "Нет сети"
        }
    }

    private var connectionIcon: String {
        switch viewModel.systemInfo.connectionType {
        case .wifi: return "wifi"
        case .cellular: return "cellularbars"
        case .ethernet: return "cable.connector"
        case .loopback: return "network"
        case .unavailable: return "wifi.slash"
        }
    }

    private var linkQuality: RouteQuality? {
        viewModel.homeLinkQuality
    }

    // MARK: - Справа

    /// Во время записи кнопки лежат в одну строку (под ними — карточка связи), в остальных режимах — столбцом
    @ViewBuilder
    private var trailing: some View {
        if style == .recording {
            HStack(spacing: 8) {
                settingsButton
                styleButton
            }
        } else {
            VStack(spacing: 8) {
                if style == .idle {
                    settingsButton
                }
                if !(style == .idle && compact) {
                    styleButton
                    if style == .idle {
                        coverageButton
                    }
                    recenterButton
                }
            }
        }
    }

    private var settingsButton: some View {
        GlassCircleButton(
            systemImage: "slider.horizontal.3",
            label: "Настройки",
            identifier: "homeSettingsButton",
            action: onSettings
        )
    }

    private var styleButton: some View {
        GlassCircleButton(
            systemImage: satellite ? "map.fill" : "globe.europe.africa.fill",
            label: satellite ? "Схема" : "Спутник",
            identifier: "networkMapStyleButton"
        ) {
            satellite.toggle()
            HapticManager.shared.selectionChanged()
        }
    }

    /// Включает и выключает на карте линии прежних маршрутов; идущая запись и готовый маршрут показываются всегда
    private var coverageButton: some View {
        GlassCircleButton(
            systemImage: coverageOn ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash",
            label: "Прежние маршруты",
            value: coverageOn ? "Показаны" : "Скрыты",
            identifier: "homeCoverageButton"
        ) {
            coverageOn.toggle()
            HapticManager.shared.selectionChanged()
        }
    }

    private var recenterButton: some View {
        GlassCircleButton(
            systemImage: style == .route ? "arrow.up.left.and.arrow.down.right" : "location.fill",
            label: style == .route ? "Показать весь маршрут" : "К моему положению",
            identifier: "networkMapRecenterButton",
            action: onRecenter
        )
    }
}

// MARK: - Плашки

/// «Wi-Fi · Хорошо»: вид подключения и оценка связи по пингу. Оценка — значок и слово, а не только цвет.
@MainActor
struct HomeLinkPill: View {
    let connection: String
    let icon: String
    let quality: RouteQuality?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
            Text(connection)
                .font(.system(size: 15, weight: .semibold))
            if let quality {
                Rectangle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 1, height: 16)
                Image(systemName: quality.systemIcon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(quality.displayColor)
                Text(quality.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(quality.displayColor)
            }
        }
        .foregroundStyle(NPTheme.textPrimary)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .homeGlass(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("homeLinkPill")
    }
}

/// «Островок»: включает Live Activity, а если она уже работает — перезапускает её
@MainActor
struct HomeIslandPill: View {
    let viewModel: NetworkMonitorViewModel

    var body: some View {
        let active = ActivityManager.shared.isLiveActivityActive
        Button {
            HapticManager.shared.impactMedium()
            if !ActivityManager.shared.isLiveActivityActive {
                viewModel.toggleLiveActivity(enabled: true)
            } else {
                viewModel.restartLiveActivity()
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(active ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(active ? "Островок" : "Старт островка")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NPTheme.textPrimary)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .homeGlass(Capsule())
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(NPPressableButtonStyle(scale: 0.96))
        .accessibilityIdentifier("homeIslandButton")
    }
}

/// Красная точка, слово «Запись» и таймер: пока идёт запись, это видно на любом экране приложения
@MainActor
struct HomeRecordingPill: View {
    let recorder: RouteRecorder

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(NPTheme.semanticCritical)
                .frame(width: 10, height: 10)
                .shadow(color: NPTheme.semanticCritical.opacity(0.6), radius: 4)
            Text("Запись")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(NPTheme.textPrimary)
            if let since = recorder.recordingSince {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(RouteFormat.duration(context.date.timeIntervalSince(since)))
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(NPTheme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .homeGlass(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Идёт запись маршрута")
        .accessibilityIdentifier("recordingBanner")
    }
}

/// «Связь хорошая · 38 мс · 5G»: оценка последней точки записи и полоски последних замеров
@MainActor
struct HomeLiveQualityCard: View {
    let recorder: RouteRecorder

    /// Сколько последних точек рисуется полосками
    private static let barCount = 14

    private var recentPoints: [RoutePoint] {
        Array((recorder.current?.points ?? []).suffix(Self.barCount))
    }

    var body: some View {
        HStack(spacing: 14) {
            if let quality = recorder.lastQuality {
                Image(systemName: quality.systemIcon)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(quality.displayColor)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(quality.displayColor, lineWidth: 3))

                VStack(alignment: .leading, spacing: 2) {
                    Text(quality.liveTitle)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(NPTheme.textPrimary)
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(NPTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
                bars
            } else {
                ProgressView()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ждём первую точку")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(NPTheme.textPrimary)
                    Text(recorder.progressLine.isEmpty ? "Проверяем положение и связь" : recorder.progressLine)
                        .font(.system(size: 13))
                        .foregroundStyle(NPTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .homeGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("homeLiveQuality")
    }

    /// «38 мс · 5G»
    private var detail: String {
        var parts: [String] = []
        if let latency = recorder.lastLatencyMs {
            parts.append(RouteFormat.latency(latency))
        } else if recorder.lastQuality == .dead {
            parts.append("нет ответа")
        }
        if let link = recorder.lastLink {
            parts.append(link.title)
        }
        return parts.joined(separator: " · ")
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(recentPoints.enumerated()), id: \.offset) { _, point in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(point.quality.displayColor)
                    .frame(width: 4, height: barHeight(for: point))
            }
        }
        .frame(height: 36, alignment: .bottom)
        .accessibilityHidden(true)
    }

    /// Чем дольше ответа ждали, тем выше полоска; «нет ответа» — на всю высоту
    private func barHeight(for point: RoutePoint) -> CGFloat {
        guard point.reachable, let latency = point.latencyMs else { return 36 }
        let scaled = CGFloat(latency / RouteQuality.fairMaxLatencyMs) * 36
        return min(36, max(6, scaled))
    }
}
