//
//  StabilityTestView.swift
//  NetPulse
//
//  Экран «Тест стабильности»: выбор длительности, ход теста, итог и прошлые тесты.
//

import SwiftUI
import Charts

// MARK: - Подписи и цвета

private func durationTitle(_ seconds: Int) -> String {
    seconds >= 3_600 ? "\(seconds / 3_600) час" : "\(seconds / 60) мин"
}

@MainActor
private extension StabilityLevel {
    var tint: Color {
        switch self {
        case .excellent: return RouteQuality.good.displayColor
        case .good: return RouteQuality.fair.displayColor
        case .unstable: return RouteQuality.poor.displayColor
        case .bad: return RouteQuality.dead.displayColor
        case .insufficient: return NPTheme.textSecondary
        }
    }

    var icon: String {
        switch self {
        case .excellent: return "checkmark.seal.fill"
        case .good: return "checkmark.circle.fill"
        case .unstable: return "exclamationmark.triangle.fill"
        case .bad: return "xmark.octagon.fill"
        case .insufficient: return "hourglass"
        }
    }
}

private struct StabilityCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(NPTheme.cardBackground.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private extension View {
    func stabilityCard() -> some View {
        modifier(StabilityCardBackground())
    }
}

@MainActor
private func sectionTitle(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11, weight: .bold))
        .tracking(0.5)
        .foregroundStyle(NPTheme.textTertiary)
}

// MARK: - Главный экран теста

@MainActor
struct StabilityTestView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    private let runner = StabilityTestRunner.shared
    private let history = StabilityHistoryStore.shared

    @State private var durationSeconds = StabilityTestRunner.durationOptions[0]

    var body: some View {
        ZStack {
            NPTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    switch runner.state {
                    case .idle:
                        idleContent
                    case .running:
                        runningContent
                    case .finished:
                        if let result = runner.result {
                            StabilityResultContent(result: result)
                            newTestButton
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("Тест стабильности")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Узлы

    private var gatewayAddress: String? {
        let info = viewModel.systemInfo
        guard info.connectionType == .wifi || info.connectionType == .ethernet else { return nil }
        return info.gatewayIP
    }

    private var testHosts: [StabilityHost] {
        StabilityHost.defaults(gateway: gatewayAddress)
    }

    private var isOffline: Bool {
        viewModel.systemInfo.connectionType == .unavailable
    }

    private var isCellular: Bool {
        viewModel.systemInfo.connectionType == .cellular
    }

    private var backgroundNote: String {
        if #available(iOS 26.0, *) {
            return "Приложение можно свернуть: iOS продолжит тест в фоне и покажет его ход в своём окне. Если закрыть приложение смахиванием, тест остановится."
        } else {
            return "Не сворачивайте приложение и не блокируйте экран до конца теста: свёрнутое приложение засыпает, и тест на это время останавливается."
        }
    }

    // MARK: Перед началом

    private var idleContent: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(NPTheme.accentPrimary)
                    Text("Насколько ровно держится связь")
                        .foregroundStyle(NPTheme.textPrimary)
                }
                .font(.system(size: 17, weight: .bold))

                Text("Несколько минут подряд раз в секунду приложение обращается к нескольким узлам и считает потери, задержку, джиттер и обрывы. Это не замер скорости: тест показывает, рвётся ли связь, например во время видеозвонка или игры.")
                    .font(.system(size: 13))
                    .foregroundStyle(NPTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .stabilityCard()

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("ДЛИТЕЛЬНОСТЬ")
                HStack(spacing: 8) {
                    ForEach(StabilityTestRunner.durationOptions, id: \.self) { seconds in
                        durationButton(seconds)
                    }
                }
                Text(backgroundNote)
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .stabilityCard()

            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("ЧТО ПРОВЕРЯЕМ")
                Text(hostsDescription)
                    .font(.system(size: 13))
                    .foregroundStyle(NPTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isCellular
                     ? "Тест тратит около 5 МБ за час. Экран будет включён, пока идёт тест."
                     : "Тест тратит около 5 МБ трафика за час. Экран будет включён, пока идёт тест.")
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .stabilityCard()

            startButton

            if isOffline {
                Text("Сейчас нет подключения к сети: тест начать нельзя.")
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.semanticWarn)
            }

            if !history.results.isEmpty {
                historyCard
            }
        }
    }

    private var hostsDescription: String {
        var names = testHosts.filter { !$0.isGateway }.map(\.name).joined(separator: ", ")
        if testHosts.contains(where: \.isGateway) {
            names += " и ваш роутер: так видно, где рвётся связь, в Wi-Fi или дальше"
        }
        return names
    }

    private func durationButton(_ seconds: Int) -> some View {
        let selected = durationSeconds == seconds
        return Button {
            durationSeconds = seconds
            HapticManager.shared.selectionChanged()
        } label: {
            Text(durationTitle(seconds))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(selected ? Color.black : NPTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Capsule().fill(selected ? NPTheme.accentPrimary : NPTheme.cardBackgroundTertiary))
        }
        .buttonStyle(NPPressableButtonStyle())
        .accessibilityIdentifier("stabilityDuration-\(seconds)")
    }

    private var startButton: some View {
        Button {
            HapticManager.shared.impactMedium()
            runner.start(
                durationSeconds: Double(durationSeconds),
                hosts: testHosts,
                connection: SpeedHistoryEntry.label(for: viewModel.systemInfo.connectionType)
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("Начать тест")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(NPTheme.accentPrimary)
            )
            .opacity(isOffline ? 0.4 : 1)
        }
        .buttonStyle(NPPressableButtonStyle(scale: 0.97))
        .disabled(isOffline)
        .accessibilityIdentifier("stabilityStartButton")
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("ПРОШЛЫЕ ТЕСТЫ")
            ForEach(history.results) { result in
                NavigationLink {
                    StabilityResultView(result: result)
                } label: {
                    historyRow(result)
                }
                .buttonStyle(.plain)
            }
        }
        .stabilityCard()
        .accessibilityIdentifier("stabilityHistory")
    }

    private func historyRow(_ result: StabilityResult) -> some View {
        let verdict = result.verdict
        return HStack(spacing: 10) {
            Image(systemName: verdict.level.icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(verdict.level.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(verdict.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)
                Text("\(result.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(result.connection) · \(StabilityReportText.duration(result.activeSeconds)) · потери \(StabilityAnalyzer.format(result.lossPercent)) %")
                    .font(.system(size: 11))
                    .foregroundStyle(NPTheme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NPTheme.textTertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: Ход теста

    private var runningContent: some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                Text(RouteFormat.duration(runner.remainingSeconds))
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(NPTheme.textPrimary)
                    .accessibilityIdentifier("stabilityRemaining")
                Text("осталось из \(durationTitle(Int(runner.plannedSeconds.rounded())))")
                    .font(.system(size: 13))
                    .foregroundStyle(NPTheme.textSecondary)
                ProgressView(value: runner.progress)
                    .tint(NPTheme.accentPrimary)
            }
            .frame(maxWidth: .infinity)
            .stabilityCard()

            if runner.isDownNow {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                    Text("Сейчас интернета нет")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(NPTheme.semanticCritical)
                .frame(maxWidth: .infinity, alignment: .leading)
                .stabilityCard()
            }

            HStack(spacing: 8) {
                liveTile(
                    title: "Задержка",
                    value: runner.currentLatencyMs.map { "\(Int($0.rounded())) мс" } ?? "нет ответа"
                )
                liveTile(title: "Потери", value: "\(StabilityAnalyzer.format(runner.lossPercent)) %")
                liveTile(title: "Обрывы", value: "\(runner.outageCount)")
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("ЗАДЕРЖКА, МС")
                if runner.liveBuckets.count < 2 {
                    Text("График появится через несколько секунд.")
                        .font(.system(size: 13))
                        .foregroundStyle(NPTheme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
                } else {
                    StabilityChart(
                        buckets: runner.liveBuckets,
                        outages: [],
                        bucketSeconds: StabilityAccumulator.bucketSeconds(forPlanned: runner.plannedSeconds)
                    )
                }
            }
            .stabilityCard()

            Text(runner.runsInBackground
                 ? "Тест идёт под защитой iOS: приложение можно свернуть, ход теста виден в системном окне."
                 : "Не сворачивайте приложение и не блокируйте экран: свёрнутое приложение засыпает, и тест на это время останавливается.")
                .font(.system(size: 12))
                .foregroundStyle(NPTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("stabilityBackgroundNote")

            if runner.pausedSeconds >= 3 {
                Text("Приложение не работало \(StabilityReportText.duration(runner.pausedSeconds)): эти секунды в тест не входят.")
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.semanticWarn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                HapticManager.shared.impactMedium()
                runner.stop()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text("Остановить тест")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(HomePalette.stopRed)
                )
            }
            .buttonStyle(NPPressableButtonStyle(scale: 0.97))
            .accessibilityIdentifier("stabilityStopButton")
        }
    }

    private func liveTile(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NPTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NPTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NPTheme.cardBackgroundTertiary)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Итог

    private var newTestButton: some View {
        Button {
            runner.reset()
        } label: {
            Text("Новый тест")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(NPTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(NPTheme.cardBackgroundTertiary)
                )
        }
        .buttonStyle(NPPressableButtonStyle())
        .accessibilityIdentifier("stabilityNewTestButton")
    }
}

// MARK: - Итог теста (после прогона и из истории)

@MainActor
struct StabilityResultView: View {
    let result: StabilityResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            NPTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    StabilityResultContent(result: result)

                    Button(role: .destructive) {
                        StabilityHistoryStore.shared.remove(id: result.id)
                        dismiss()
                    } label: {
                        Text("Удалить этот тест")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .accessibilityIdentifier("stabilityDeleteButton")
                }
                .padding(16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Итог теста")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
struct StabilityResultContent: View {
    let result: StabilityResult

    var body: some View {
        let verdict = result.verdict
        VStack(spacing: 14) {
            verdictCard(verdict)
            statsGrid
            chartCard
            if !result.hosts.isEmpty {
                hostsCard
            }
            notesCard
            ShareLink(item: StabilityReportText.text(for: result)) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Поделиться итогом")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NPTheme.accentPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
            }
            .accessibilityIdentifier("stabilityShareButton")
        }
        .accessibilityIdentifier("stabilityResult")
    }

    private func verdictCard(_ verdict: StabilityVerdict) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: verdict.level.icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(verdict.level.tint)
                Text(verdict.title)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(NPTheme.textPrimary)
            }
            Text(verdict.summary)
                .font(.system(size: 13))
                .foregroundStyle(NPTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let cause = verdict.cause {
                Text(cause)
                    .font(.system(size: 13))
                    .foregroundStyle(NPTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            Text("\(result.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(result.connection) · \(StabilityReportText.duration(result.activeSeconds))")
                .font(.system(size: 11))
                .foregroundStyle(NPTheme.textTertiary)
        }
        .stabilityCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stabilityVerdict")
    }

    private var statsGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 8) {
            statTile("Потери", "\(StabilityAnalyzer.format(result.lossPercent)) %")
            statTile("Обрывы", "\(result.outages.count)")
            statTile("Самый долгий", result.outages.isEmpty ? "—" : "\(Int(result.longestOutageSeconds.rounded())) с")
            statTile("Задержка", result.averageMs.map { "\(Int($0.rounded())) мс" } ?? "—")
            statTile("95 % быстрее", result.p95Ms.map { "\(Int($0.rounded())) мс" } ?? "—")
            statTile("Джиттер", result.jitterMs.map { "\(Int($0.rounded())) мс" } ?? "—")
        }
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NPTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NPTheme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NPTheme.cardBackgroundTertiary)
        )
        .accessibilityElement(children: .combine)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("ЗАДЕРЖКА ПО ХОДУ ТЕСТА, МС")
            if result.buckets.count < 2 {
                Text("Для графика тест шёл слишком мало.")
                    .font(.system(size: 13))
                    .foregroundStyle(NPTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else {
                StabilityChart(buckets: result.buckets, outages: result.outages, bucketSeconds: result.bucketSeconds)
                if !result.outages.isEmpty {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(NPTheme.semanticCritical.opacity(0.5))
                            .frame(width: 14, height: 8)
                        Text("красным отмечены обрывы")
                            .font(.system(size: 11))
                            .foregroundStyle(NPTheme.textSecondary)
                    }
                }
            }
        }
        .stabilityCard()
    }

    private var hostsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("ПО УЗЛАМ")
            ForEach(result.hosts) { host in
                HStack(spacing: 8) {
                    Image(systemName: host.isGateway ? "wifi.router.fill" : "globe")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NPTheme.accentPrimary)
                        .frame(width: 22)
                    Text(host.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NPTheme.textPrimary)
                    Spacer(minLength: 4)
                    Text("потери \(StabilityAnalyzer.format(host.lossPercent)) % · \(host.averageMs.map { "\(Int($0.rounded())) мс" } ?? "—")")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(NPTheme.textSecondary)
                }
            }
        }
        .stabilityCard()
    }

    @ViewBuilder
    private var notesCard: some View {
        let notes = noteLines
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(notes, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var noteLines: [String] {
        var lines: [String] = []
        if result.finishedEarly {
            lines.append("Тест остановлен до конца: шёл \(StabilityReportText.duration(result.activeSeconds)) из \(StabilityReportText.duration(result.plannedSeconds)).")
        }
        if result.pausedSeconds >= 5 {
            lines.append("Приложение не работало \(StabilityReportText.duration(result.pausedSeconds)) (его усыпила система): в эти секунды замеров нет.")
        }
        lines.append("Тест измеряет время соединения с узлами. Он показывает, рвётся ли связь, но не знает, почему: причина может быть у провайдера, дома или в сети самого узла.")
        return lines
    }
}

// MARK: - График

private struct StabilityChart: View {
    let buckets: [StabilityBucket]
    let outages: [StabilityOutage]
    let bucketSeconds: Double

    /// Верх шкалы: чуть выше самой большой средней задержки, но не выше 600 мс (редкий выброс не должен сплющить график)
    private var yMax: Double {
        let top = buckets.compactMap(\.averageMs).max() ?? 100
        return min(600, max(80, top * 1.15))
    }

    var body: some View {
        let ceiling = yMax
        Chart {
            ForEach(Array(outages.enumerated()), id: \.offset) { _, outage in
                RectangleMark(
                    xStart: .value("Начало", outage.start / 60),
                    xEnd: .value("Конец", (outage.start + max(outage.duration, bucketSeconds)) / 60),
                    yStart: .value("Низ", 0.0),
                    yEnd: .value("Верх", ceiling)
                )
                .foregroundStyle(NPTheme.semanticCritical.opacity(0.28))
            }

            ForEach(buckets) { bucket in
                if let ms = bucket.averageMs {
                    LineMark(
                        x: .value("Минуты", bucket.start / 60),
                        y: .value("мс", min(ms, ceiling))
                    )
                    .foregroundStyle(NPTheme.accentPrimary)
                    .interpolationMethod(.monotone)
                }
                if bucket.lossPercent > 0, !bucket.isDown {
                    PointMark(
                        x: .value("Минуты", bucket.start / 60),
                        y: .value("мс", 0.0)
                    )
                    .foregroundStyle(NPTheme.semanticWarn)
                    .symbolSize(28)
                }
            }
        }
        .chartYScale(domain: 0...ceiling)
        .chartXAxisLabel("минуты от начала")
        .frame(height: 180)
        .accessibilityLabel("График задержки по ходу теста")
        .accessibilityIdentifier("stabilityChart")
    }
}
