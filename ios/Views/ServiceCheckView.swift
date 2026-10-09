//
//  ServiceCheckView.swift
//  NetPulse
//
//  Экран «Доступность сервисов»: отвечают ли Telegram, YouTube, WhatsApp и другие, и как быстро.
//

import SwiftUI

@MainActor
struct ServiceCheckView: View {
    @State private var results: [ServiceCheckResult] = []
    @State private var isChecking = false
    @State private var lastChecked: Date?

    private let history = ServiceHistoryStore.shared

    var body: some View {
        ZStack {
            NPTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    verdictCard

                    VStack(spacing: 10) {
                        ForEach(ServiceCheckEngine.targets) { target in
                            row(target)
                        }
                    }

                    checkButton

                    Text("Проверка показывает, отвечает ли сервис с вашей сети. Почему он не отвечает, приложение определить не может: дело может быть в сервисе, в провайдере или в маршруте. Запросы идут напрямую к сервисам, мы их не получаем и ничего не сохраняем, кроме отметок «работает / нет» на этом телефоне.")
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("Доступность сервисов")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await runCheck()
        }
    }

    // MARK: - Проверка

    private func runCheck() async {
        guard !isChecking else { return }
        isChecking = true
        let output = await ServiceCheckEngine.checkAll()
        history.record(output)
        results = output
        lastChecked = Date()
        isChecking = false
    }

    // MARK: - Вывод

    private var verdictCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if isChecking {
                    ProgressView()
                        .tint(NPTheme.accentPrimary)
                    Text("Проверяем…")
                } else {
                    Image(systemName: overallIcon)
                        .foregroundStyle(overallColor)
                    Text(overallTitle)
                }
            }
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(NPTheme.textPrimary)

            Text(isChecking && results.isEmpty ? "Это займёт несколько секунд." : ServiceCheckEngine.verdict(results))
                .font(.system(size: 13))
                .foregroundStyle(NPTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let lastChecked, !isChecking {
                Text("Проверено в \(lastChecked.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(NPTheme.cardBackground.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("serviceVerdict")
    }

    private var overallTitle: String {
        guard !results.isEmpty else { return "Сервисы" }
        let down = results.filter { $0.state == .down }.count
        let slow = results.filter { $0.state == .slow }.count
        if down == results.count { return "Нет ответа ни от одного" }
        if down > 0 { return "Не отвечают: \(down) из \(results.count)" }
        if slow > 0 { return "Есть медленные: \(slow)" }
        return "Всё работает"
    }

    private var overallIcon: String {
        if results.contains(where: { $0.state == .down }) { return "exclamationmark.triangle.fill" }
        if results.contains(where: { $0.state == .slow }) { return "tortoise.fill" }
        return "checkmark.seal.fill"
    }

    private var overallColor: Color {
        if results.contains(where: { $0.state == .down }) { return NPTheme.semanticCritical }
        if results.contains(where: { $0.state == .slow }) { return NPTheme.semanticWarn }
        return RouteQuality.good.displayColor
    }

    private func color(for state: ServiceState?) -> Color {
        switch state {
        case .ok: return RouteQuality.good.displayColor
        case .slow: return NPTheme.semanticWarn
        case .down: return NPTheme.semanticCritical
        case nil: return NPTheme.textTertiary
        }
    }

    private func row(_ target: ServiceTarget) -> some View {
        let result = results.first { $0.targetID == target.id }
        let tint = color(for: result?.state)
        return HStack(spacing: 12) {
            Image(systemName: target.icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(NPTheme.accentPrimary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(NPTheme.accentPrimary.opacity(0.14)))

            VStack(alignment: .leading, spacing: 3) {
                Text(target.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)
                Text(result?.detail ?? (isChecking ? "Проверяем…" : "Не проверялся"))
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(result?.state.title ?? "—")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(tint.opacity(0.14)))
                dots(for: target.id)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(NPTheme.cardBackgroundTertiary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("serviceRow-\(target.id)")
    }

    /// Полоска последних проверок: старые слева, новые справа
    private func dots(for id: String) -> some View {
        let states = history.recentStates(for: id)
        return HStack(spacing: 3) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                Circle()
                    .fill(color(for: state))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    private var checkButton: some View {
        Button {
            HapticManager.shared.impactMedium()
            Task {
                await runCheck()
            }
        } label: {
            HStack(spacing: 8) {
                if isChecking {
                    ProgressView()
                        .tint(NPTheme.backgroundDeep)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text(isChecking ? "Проверяем…" : "Проверить снова")
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(NPTheme.backgroundDeep)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NPTheme.buttonGradient)
            )
            .opacity(isChecking ? 0.6 : 1)
        }
        .buttonStyle(NPPressableButtonStyle(scale: 0.97))
        .disabled(isChecking)
        .accessibilityIdentifier("serviceCheckButton")
    }
}
