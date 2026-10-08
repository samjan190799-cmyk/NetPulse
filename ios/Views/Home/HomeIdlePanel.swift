//
//  HomeIdlePanel.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Нижняя панель главного экрана в обычном режиме: скорость сети, две главные кнопки и ряд «Мои маршруты».
/// Её можно потянуть вверх (или нажать на ручку): под ней откроются маршруты, настройки записи, инструменты
/// и оценка возможностей сети.
@MainActor
struct HomeIdlePanel: View {
    let viewModel: NetworkMonitorViewModel
    let recorder: RouteRecorder
    let containerHeight: CGFloat
    @Binding var detent: HomePanelDetent
    @Binding var selectedID: UUID?
    @Binding var showsDemo: Bool
    @Binding var confirmDeleteAll: Bool
    @Binding var pendingDeleteID: UUID?
    @Binding var showDeleteRouteDialog: Bool
    @Binding var showGlossary: Bool

    @GestureState private var dragTranslation: CGFloat = 0

    /// Высота прокручиваемой области в обычном положении: ровно столько занимают скорость, плитки, кнопки и ряд маршрутов
    private static let mediumScrollHeight: CGFloat = 254
    /// Высота ручки панели
    private static let handleHeight: CGFloat = 24
    /// Метка начала прокручиваемой области: к ней возвращается прокрутка при сворачивании панели
    private static let topAnchor = "homePanelTop"

    // MARK: - Размеры и жест

    private var expandedScrollHeight: CGFloat {
        // Над панелью остаётся место для плашек и кнопок на карте
        max(Self.mediumScrollHeight + 120, containerHeight - 60 - Self.handleHeight - 56)
    }

    private var scrollHeight: CGFloat {
        let base = detent == .expanded ? expandedScrollHeight : Self.mediumScrollHeight
        let value = HomePanelLayout.height(
            base: Double(base),
            translation: Double(dragTranslation),
            lower: Double(Self.mediumScrollHeight),
            upper: Double(expandedScrollHeight)
        )
        return CGFloat(value)
    }

    private var handleDrag: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let next = HomePanelLayout.detent(
                    from: detent,
                    predictedTranslation: Double(value.predictedEndTranslation.height)
                )
                if next != detent {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        detent = next
                    }
                    HapticManager.shared.selectionChanged()
                }
            }
    }

    private func toggleDetent() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            detent = detent == .expanded ? .medium : .expanded
        }
        HapticManager.shared.selectionChanged()
    }

    // MARK: - Данные

    private var displayedDownload: Double {
        viewModel.liveDownloadSpeed > 0 ? viewModel.liveDownloadSpeed : (viewModel.lastSpeedtestResult?.downloadMbps ?? 0)
    }

    private var displayedUpload: Double {
        viewModel.liveUploadSpeed > 0 ? viewModel.liveUploadSpeed : (viewModel.lastSpeedtestResult?.uploadMbps ?? 0)
    }

    /// Во время замера на экране отдача, как только она пошла; иначе — скачивание
    private var shownSpeed: Double {
        if viewModel.isSpeedtestRunning {
            return viewModel.liveUploadSpeed > 0 ? viewModel.liveUploadSpeed : viewModel.liveDownloadSpeed
        }
        return displayedDownload
    }

    private var phaseLabel: String {
        if viewModel.isSpeedtestRunning, viewModel.liveUploadSpeed > 0 {
            return "ОТДАЧА"
        }
        return "СКАЧИВАНИЕ"
    }

    /// Цвет «пульса сети»: оценка связи сейчас; пока её нет, основной цвет приложения
    private var pulseColor: Color {
        viewModel.homeLinkQuality?.displayColor ?? NPTheme.accentPrimary
    }

    private var capabilities: [CapabilityItem] {
        NetworkCapabilityEvaluator(
            downloadMbps: displayedDownload,
            uploadMbps: displayedUpload,
            pingMs: viewModel.currentAveragePing,
            jitterMs: viewModel.currentAverageJitter
        ).evaluateAll()
    }

    // MARK: - Экран

    var body: some View {
        VStack(spacing: 0) {
            handle
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        speedHeader
                            .id(Self.topAnchor)
                        tiles
                            .padding(.top, 8)
                        actionButtons
                            .padding(.top, 10)
                        routesRow
                            .padding(.top, 8)
                        if detent == .expanded {
                            extras
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollDisabled(detent == .medium)
                .frame(height: scrollHeight)
                .onChange(of: detent) { _, newValue in
                    // После сворачивания панели прокрутка не должна остаться смещённой: в обычном положении она отключена
                    if newValue == .medium {
                        proxy.scrollTo(Self.topAnchor, anchor: .top)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(HomePanelBackground())
    }

    // MARK: - Ручка

    private var handle: some View {
        Capsule()
            .fill(Color.white.opacity(0.28))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: Self.handleHeight)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleDetent()
            }
            .gesture(handleDrag)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(detent == .expanded ? "Свернуть панель" : "Развернуть панель")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("homePanelHandle")
    }

    // MARK: - Скорость

    private var speedHeader: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(phaseLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(NPTheme.textSecondary)
                    .frame(height: 16, alignment: .leading)

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(shownSpeed > 0 ? String(format: "%.1f", shownSpeed) : "—")
                        .font(.system(size: 60, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(NPTheme.textPrimary)
                        .contentTransition(.numericText(value: shownSpeed))
                        .npAnimation(.spring(response: 0.35, dampingFraction: 0.8), value: shownSpeed)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .npBreathingGlow(color: NPTheme.accentPrimary, active: viewModel.isSpeedtestRunning)
                    Text("Мбит/с")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(NPTheme.textSecondary)
                }
                .frame(height: 60)
            }

            Spacer(minLength: 0)
            capabilityHint
        }
        .frame(height: 76)
        .background(alignment: .bottom) {
            // «Пульс сети»: бегущая линия за цифрами. Цвет — оценка связи, размах — скорость, без связи линия ровная
            NetworkPulseLine(
                color: pulseColor,
                intensity: min(max(shownSpeed / 150.0, 0), 1),
                isFlat: viewModel.homeLinkQuality == .dead,
                isBusy: viewModel.isSpeedtestRunning
            )
            .frame(height: 44)
            .opacity(0.55)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("homeSpeedValue")
    }

    @ViewBuilder
    private var capabilityHint: some View {
        if viewModel.isSpeedtestRunning {
            Text(viewModel.liveUploadSpeed > 0 ? "Замер отдачи…" : "Замер скачивания…")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NPTheme.accentPrimary)
                .padding(.bottom, 8)
        } else if displayedDownload > 0 {
            let tags = CapabilityTags.summary(capabilities)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Хватает для")
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.textSecondary)
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(RouteQuality.good.displayColor)
                    Text(tags.isEmpty ? "базовые задачи" : tags.joined(separator: " · "))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NPTheme.accentSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.bottom, 8)
        } else {
            Text("Нажмите «Замер скорости»")
                .font(.system(size: 12))
                .foregroundStyle(NPTheme.textSecondary)
                .padding(.bottom, 8)
        }
    }

    private var tiles: some View {
        HStack(spacing: 8) {
            HomeStatTile(
                title: "Отдача",
                icon: "arrow.up",
                value: displayedUpload > 0 ? String(format: "%.1f", displayedUpload) : "—",
                unit: "Мбит/с"
            )
            HomeStatTile(
                title: "Пинг",
                icon: "network",
                value: viewModel.currentAveragePing.map { String(format: "%.0f", $0) } ?? "—",
                unit: "мс"
            )
            HomeStatTile(
                title: "Джиттер",
                icon: "waveform.path.ecg",
                value: viewModel.currentAverageJitter.map { String(format: "%.1f", $0) } ?? "—",
                unit: "мс"
            )
        }
    }

    // MARK: - Кнопки

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                HapticManager.shared.impactMedium()
                viewModel.startSpeedtest()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSpeedtestRunning {
                        ProgressView()
                            .tint(NPTheme.backgroundDeep)
                        Text("Измерение…")
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Замер скорости")
                    }
                }
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(viewModel.isSpeedtestRunning ? NPTheme.textSecondary : NPTheme.backgroundDeep)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(viewModel.isSpeedtestRunning ? NPTheme.buttonDisabledGradient : NPTheme.buttonGradient)
                )
            }
            .buttonStyle(NPPressableButtonStyle(scale: 0.96))
            .disabled(viewModel.isSpeedtestRunning)
            .accessibilityLabel(displayedDownload > 0 ? "Повторить замер скорости" : "Начать замер скорости")
            .accessibilityIdentifier("homeSpeedButton")

            Button {
                HapticManager.shared.impactMedium()
                recorder.start()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HomePalette.softRed)
                    Text("Записать маршрут")
                }
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(NPTheme.textPrimary)
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
            .buttonStyle(NPPressableButtonStyle(scale: 0.96))
            .accessibilityIdentifier("networkMapStartButton")
        }
    }

    private var routesRow: some View {
        Button {
            toggleDetent()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NPTheme.textSecondary)
                Text("Мои маршруты")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NPTheme.textPrimary)
                Text("\(recorder.history.count)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NPTheme.accentSoft)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 24, minHeight: 22)
                    .background(Capsule().fill(NPTheme.cardBackgroundTertiary))
                Spacer(minLength: 0)
                Image(systemName: detent == .expanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NPTheme.textSecondary)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeRoutesRow")
    }

    // MARK: - Развёрнутая панель

    private var extras: some View {
        VStack(alignment: .leading, spacing: 22) {
            routesList
            recordingSettings
            toolsSection
            NetworkCapabilityCardView(items: capabilities)
            footer
        }
        .padding(.top, 14)
        .padding(.bottom, 28)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(NPTheme.textPrimary)
    }

    // Маршруты

    private var routesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if recorder.history.isEmpty {
                Text("Сохранённых маршрутов пока нет.")
                    .font(.system(size: 13))
                    .foregroundStyle(NPTheme.textSecondary)
                    .accessibilityIdentifier("networkMapHistoryEmpty")
            } else {
                ForEach(recorder.history) { route in
                    historyRow(route)
                }
                Button(role: .destructive) {
                    confirmDeleteAll = true
                } label: {
                    Text("Удалить все маршруты")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("networkMapDeleteAll")
            }
        }
    }

    private func historyRow(_ route: RouteRecord) -> some View {
        let stats = RouteAnalyzer.stats(of: route)

        return HStack(spacing: 10) {
            Button {
                showsDemo = false
                selectedID = route.id
                HapticManager.shared.selectionChanged()
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(RouteTitle.dateRange(of: route))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(NPTheme.textPrimary)
                        if route.interrupted {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(NPTheme.semanticWarn)
                        }
                        Spacer(minLength: 8)
                        Text("\(RouteFormat.distance(stats.distanceMeters)) · \(RouteFormat.duration(stats.duration))")
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(NPTheme.textSecondary)
                    }
                    QualityBar(shares: stats.shares, height: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                pendingDeleteID = route.id
                showDeleteRouteDialog = true
                HapticManager.shared.impactLight()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HomePalette.softRed)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Удалить маршрут")
        }
        .padding(.leading, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NPTheme.cardBackgroundTertiary.opacity(0.7))
        )
        .accessibilityIdentifier("networkMapHistoryRow")
    }

    // Настройки записи

    private var recordingSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Запись маршрута")

            Toggle(isOn: Binding(
                get: { recorder.measuresSpeed },
                set: { recorder.measuresSpeed = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Замерять скорость на маршруте")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NPTheme.textPrimary)
                    Text("Раз в 30 секунд скачивается до 1,5 МБ. На мобильном интернете это расходует трафик, поэтому по умолчанию выключено.")
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textSecondary)
                }
            }
            .accessibilityIdentifier("networkMapSpeedToggle")

            Toggle(isOn: Binding(
                get: { recorder.recordsInBackground },
                set: { recorder.recordsInBackground = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Записывать маршрут в фоне")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NPTheme.textPrimary)
                    Text(recorder.recordsInBackground
                         ? "Запись идёт, пока приложение свёрнуто. Значок геолокации в строке состояния, заряд тратится заметнее."
                         : "Когда приложение свёрнуто, запись ждёт и продолжается при возвращении. Заряд в фоне не тратится.")
                        .font(.system(size: 12))
                        .foregroundStyle(NPTheme.textSecondary)
                }
            }
            .accessibilityIdentifier("networkMapBackgroundToggle")

            Button {
                selectedID = nil
                showsDemo = true
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    detent = .medium
                }
                HapticManager.shared.selectionChanged()
            } label: {
                Label("Показать пример маршрута", systemImage: "play.rectangle")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("networkMapDemoButton")

            Text("Каждые несколько секунд приложение сохраняет, где вы находитесь, и проверяет сеть: за сколько устанавливается соединение с контрольным узлом 1.1.1.1. Не ответил узел — на карте «нет сети». Телефон стоит на месте — точки пишутся реже, а через 20 минут без движения запись останавливается сама. Если включено «Записывать маршрут в фоне», приложение работает и свёрнутым: в строке состояния iOS виден значок геолокации, а Dynamic Island продолжает показывать скорость.")
                .font(.system(size: 12))
                .foregroundStyle(NPTheme.textSecondary)
                .lineSpacing(2)

            Text("Хорошо — до \(Int(RouteQuality.goodMaxLatencyMs)) мс, средне — до \(Int(RouteQuality.fairMaxLatencyMs)) мс, плохо — дольше. При замере скорости: хорошо — от \(Int(RouteQuality.goodMinMbps)) Мбит/с, средне — от \(Int(RouteQuality.fairMinMbps)) Мбит/с.")
                .font(.system(size: 12))
                .foregroundStyle(NPTheme.textSecondary)
                .lineSpacing(2)

            Text("Маршруты хранятся только в памяти этого устройства: они не отправляются на серверы и не попадают в резервные копии. Удалить их можно здесь же. Остановить запись можно в любой момент.")
                .font(.system(size: 12))
                .foregroundStyle(NPTheme.textSecondary)
                .lineSpacing(2)
        }
    }

    // Инструменты

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Инструменты")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                NavigationLink(destination: DNSBenchmarkView(viewModel: viewModel)) {
                    toolLabel("DNS Гонка", icon: "bolt.shield.fill")
                }
                .buttonStyle(NPPressableButtonStyle())
                .accessibilityIdentifier("homeToolDNS")

                NavigationLink(destination: GamingRadarView(viewModel: viewModel)) {
                    toolLabel("Gaming Радар", icon: "gamecontroller.fill")
                }
                .buttonStyle(NPPressableButtonStyle())
                .accessibilityIdentifier("homeToolGaming")

                NavigationLink(destination: BufferbloatView(viewModel: viewModel)) {
                    toolLabel("Bufferbloat", icon: "gauge.with.dots.needle.67percent")
                }
                .buttonStyle(NPPressableButtonStyle())
                .accessibilityIdentifier("homeToolBufferbloat")

                NavigationLink(destination: LANScannerView(viewModel: viewModel)) {
                    toolLabel("LAN Сканер", icon: "wifi.router.fill")
                }
                .buttonStyle(NPPressableButtonStyle())
                .accessibilityIdentifier("homeToolLAN")
            }
        }
    }

    private func toolLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(NPTheme.accentPrimary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(NPTheme.cardBackgroundTertiary))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NPTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NPTheme.cardBackgroundTertiary.opacity(0.7))
        )
    }

    // Справка

    private var footer: some View {
        Button {
            showGlossary = true
            HapticManager.shared.impactLight()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 15, weight: .semibold))
                Text("Справочник терминов: пинг, джиттер, Bufferbloat…")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(NPTheme.textSecondary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeGlossaryButton")
    }
}
