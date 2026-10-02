//
//  IslandDiagnosticsView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Экран «Диагностика острова»: состояние конвейера обновления, паузы приложения в фоне и журнал событий.
///
/// Остров замирает по причинам, которые снаружи не видны: приложение усыпили, его закрыла система, обновление
/// «зависло». Журнал показывает, что именно происходило и когда; его можно скопировать или отправить.
/// Координаты и сетевые адреса в журнал не попадают.
struct IslandDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                // Раз в секунду перечитываем состояние: «последнее обновление» должно идти вживую
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    content
                }
            }
            .navigationTitle("Диагностика острова")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") {
                        dismiss()
                    }
                    .accessibilityIdentifier("islandDiagnosticsClose")
                }
            }
        }
    }

    private var content: some View {
        let journal = IslandDiagnostics.shared
        let summary = journal.summaryText(
            health: ActivityManager.shared.health,
            recording: RouteRecorder.shared.summaryDescription
        )
        let exported = journal.exportText(summary: summary)
        let lines = Array(journal.displayLines().prefix(200))

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("СЕЙЧАС")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(NPTheme.textSecondary)

                Text(summary)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(NPTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("islandDiagnosticsSummary")

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = exported
                        copied = true
                    } label: {
                        Label(copied ? "Скопировано" : "Скопировать журнал", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("islandDiagnosticsCopy")

                    ShareLink(item: exported) {
                        Label("Поделиться", systemImage: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(role: .destructive) {
                        journal.clear()
                        copied = false
                    } label: {
                        Text("Очистить")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                }

                Text("СОБЫТИЯ (НОВЫЕ СВЕРХУ)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(NPTheme.textSecondary)
                    .padding(.top, 6)

                if lines.isEmpty {
                    Text("Событий пока нет.")
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(NPTheme.textPrimary.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .accessibilityIdentifier("islandDiagnosticsLog")
                }
            }
            .padding(16)
        }
    }
}
