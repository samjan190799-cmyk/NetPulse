//
//  HomeRecordingPanel.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Нижняя панель, пока идёт запись маршрута: сколько пройдено, большая кнопка «Остановить и сохранить» и пояснение
/// о том, идёт ли запись в фоне (это задаётся в настройках). Если запись ждёт ответа на запрос геолокации,
/// панель показывает ожидание.
@MainActor
struct HomeRecordingPanel: View {
    let recorder: RouteRecorder
    let onStop: () -> Void

    private var points: [RoutePoint] {
        recorder.current?.points ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if recorder.state == .waitingForPermission {
                waitingBlock
            } else {
                statsRow
                if !recorder.progressLine.isEmpty {
                    Text(recorder.progressLine)
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                stopButton
                Text(recorder.recordsInBackground
                     ? "Запись идёт и в фоне. В строке состояния iOS виден значок геолокации. Данные остаются на телефоне."
                     : "Когда приложение свёрнуто, запись ждёт и продолжается при возвращении. Данные остаются на телефоне.")
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomePanelBackground())
    }

    // MARK: - Идёт запись

    /// Три плитки читаются как одна строка состояния: «Точек: 12 · 450 м · 85 мс · 4G (LTE)»
    private var statsRow: some View {
        HStack(spacing: 8) {
            HomeStatTile(
                title: "Расстояние",
                icon: nil,
                value: RouteFormat.distance(RouteAnalyzer.distanceMeters(of: points)),
                unit: nil
            )
            HomeStatTile(title: "Точек", icon: nil, value: "\(recorder.pointCount)", unit: nil)
            HomeStatTile(
                title: "Без связи",
                icon: nil,
                value: "\(RouteAnalyzer.deadZones(in: points).count)",
                unit: nil
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(liveSummary)
        .accessibilityIdentifier("networkMapStatus")
    }

    private var liveSummary: String {
        var parts = ["Точек: \(recorder.pointCount)"]
        if let route = recorder.current {
            parts.append(RouteFormat.distance(RouteAnalyzer.distanceMeters(of: route.points)))
        }
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

    private var stopButton: some View {
        Button {
            onStop()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("Остановить и сохранить")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(HomePalette.stopRed)
            )
        }
        .buttonStyle(NPPressableButtonStyle(scale: 0.97))
        .accessibilityIdentifier("networkMapStopButton")
    }

    // MARK: - Ждём разрешение

    private var waitingBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                Text("Ждём разрешение на геолокацию")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)
            }
            Text(recorder.state.statusText)
                .font(.system(size: 12))
                .foregroundStyle(NPTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("networkMapPermissionStatus")
            Button {
                recorder.stop()
            } label: {
                Text("Отменить")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NPTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(NPTheme.cardBackgroundTertiary)
                    )
            }
            .buttonStyle(NPPressableButtonStyle(scale: 0.97))
            .accessibilityIdentifier("networkMapCancelButton")
        }
    }
}
