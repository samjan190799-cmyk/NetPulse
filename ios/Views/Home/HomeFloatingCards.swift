//
//  HomeFloatingCards.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import UIKit

/// Сообщения над нижней панелью: ошибка замера, нет доступа к геолокации, итог записи, подсказка про остров,
/// трафик за время сна приложения, AI-вердикт. Показывается одно сообщение за раз — самое важное. Когда сообщений нет, места они не занимают.
@MainActor
struct HomeFloatingCards: View {
    let viewModel: NetworkMonitorViewModel
    let recorder: RouteRecorder
    /// Обычный режим (не идёт запись и не показан маршрут): подсказки и вердикт показываются только в нём
    let isIdle: Bool
    @Binding var dismissedAISummary: String?

    var body: some View {
        if let message = viewModel.speedtestError, !viewModel.isSpeedtestRunning {
            speedErrorCard(message)
        } else if isIdle, recorder.state.needsAttention {
            permissionCard
        } else if let notice = recorder.notice {
            noticeCard(notice)
        } else if isIdle, viewModel.showRecordingHint {
            recordingHintCard
        } else if isIdle, let note = viewModel.sleepTraffic {
            sleepTrafficCard(note)
        } else if isIdle, !viewModel.isSpeedtestRunning,
                  let summary = viewModel.instantAISummary, dismissedAISummary != summary {
            aiVerdictCard(summary)
        }
    }

    // MARK: - Общая оболочка

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .homeGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func closeButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NPTheme.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    // MARK: - Сообщения

    private func speedErrorCard(_ message: String) -> some View {
        card {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(NPTheme.semanticWarn)
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NPTheme.textPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("homeSpeedError")
                Spacer(minLength: 0)
                closeButton(label: "Скрыть сообщение") {
                    viewModel.speedtestError = nil
                }
            }
        }
    }

    private var permissionCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(HomePalette.softRed)
                    Text(recorder.state.statusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NPTheme.textPrimary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("networkMapPermissionStatus")
                }
                if recorder.state == .denied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Открыть Настройки iOS")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(NPTheme.accentPrimary)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                }
            }
        }
    }

    private func noticeCard(_ text: String) -> some View {
        card {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(NPTheme.accentPrimary)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NPTheme.textPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("networkMapNotice")
                Spacer(minLength: 0)
                closeButton(label: "Скрыть сообщение") {
                    recorder.dismissNotice()
                }
            }
        }
    }

    /// Заметка «пока приложение спало, устройство передало столько-то»: остров стоял (iOS усыпила приложение),
    /// а сеть работала. Цифры берутся из системных счётчиков интерфейсов и охватывают весь трафик устройства.
    private func sleepTrafficCard(_ note: SleepTrafficNote) -> some View {
        card {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(NPTheme.accentPrimary)
                Text(note.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NPTheme.textPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("homeSleepTraffic")
                Spacer(minLength: 0)
                closeButton(label: "Скрыть сообщение") {
                    viewModel.dismissSleepTraffic()
                }
            }
        }
    }

    /// Свёрнутое приложение iOS усыпляет, и остров не может обновляться: он показывает, что данные устарели, а не
    /// застывшие цифры. Пока идёт запись маршрута, приложение остаётся активным, и остров обновляется и в фоне.
    private var recordingHintCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(NPTheme.semanticWarn)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("iOS усыпила приложение, пока оно было свёрнуто")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(NPTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(recorder.recordsInBackground
                             ? "Пока приложение спит, остров обновляться не может: это правило iOS, а сеть при этом работает как обычно. Чтобы остров показывал скорость и в фоне, запишите маршрут: приложение остаётся активным, в строке состояния виден значок геолокации."
                             : "Пока приложение спит, остров обновляться не может: это правило iOS, а сеть при этом работает как обычно. Чтобы остров обновлялся в фоне, включите в настройках «Записывать маршрут в фоне» и начните запись: тогда приложение остаётся активным. Для записи используется геолокация, в строке состояния появится её значок.")
                            .font(.system(size: 12))
                            .foregroundStyle(NPTheme.textSecondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let note = viewModel.sleepTraffic {
                            Text(note.text)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NPTheme.textPrimary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                                .accessibilityIdentifier("homeSleepTraffic")
                        }
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button {
                        viewModel.dismissRecordingHint(forever: false)
                        HapticManager.shared.impactMedium()
                        recorder.start()
                    } label: {
                        Text("Записать маршрут")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(NPTheme.backgroundDeep)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(NPTheme.buttonGradient))
                    }
                    .accessibilityIdentifier("recordingHintStart")

                    Button {
                        viewModel.dismissRecordingHint(forever: false)
                    } label: {
                        Text("Позже")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NPTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("recordingHintLater")

                    Button {
                        viewModel.dismissRecordingHint(forever: true)
                    } label: {
                        Text("Не показывать")
                            .font(.system(size: 13))
                            .foregroundStyle(NPTheme.textSecondary)
                            .padding(.horizontal, 8)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("recordingHintNever")
                }
            }
        }
    }

    private func aiVerdictCard(_ summary: String) -> some View {
        card {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NPTheme.accentPrimary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(NPTheme.accentPrimary.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI-вердикт")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(NPTheme.accentPrimary)
                    Text(summary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NPTheme.textPrimary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                closeButton(label: "Скрыть вердикт") {
                    dismissedAISummary = summary
                }
            }
        }
    }
}
