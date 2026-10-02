//
//  NetworkMapView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import MapKit

/// Цвета качества сети: одни и те же на карте, в легенде и в полосках сводки
@MainActor
extension RouteQuality {
    var displayColor: Color {
        switch self {
        case .good: return NPTheme.semanticOK
        case .fair: return Color.yellow
        case .poor: return NPTheme.semanticWarn
        case .dead: return NPTheme.semanticCritical
        }
    }
}

/// Экран «Карта сети»: запись маршрута и карта, где сеть была быстрой, медленной или пропадала.
///
/// Запись начинается только по кнопке «Начать запись маршрута» и идёт, пока её не остановят. Маршруты хранятся
/// только на этом устройстве и удаляются прямо здесь.
@MainActor
public struct NetworkMapView: View {
    @State private var selectedID: UUID?
    @State private var showsDemo = false
    @State private var metric: RouteMetric = .latency
    /// Пока маршрута нет и во время записи карта смотрит на вас; у готового маршрута — на весь маршрут целиком
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var confirmDeleteAll = false
    @AppStorage("netpulse_map_satellite") private var satellite = false

    public init() {}

    private var recorder: RouteRecorder {
        RouteRecorder.shared
    }

    // MARK: - Какой маршрут показан

    /// Идущая запись, а если её нет — пример, выбранный или последний сохранённый маршрут
    private var displayedRoute: RouteRecord? {
        if let live = recorder.current { return live }
        if showsDemo { return RouteDemo.sample() }
        if let id = selectedID, let chosen = recorder.history.first(where: { $0.id == id }) { return chosen }
        return recorder.history.first
    }

    private var isShowingDemo: Bool {
        recorder.current == nil && showsDemo
    }

    private var hasSpeedData: Bool {
        guard let route = displayedRoute else { return false }
        return route.points.contains { ($0.downloadMbps ?? 0) > 0 }
    }

    // MARK: - Экран

    public var body: some View {
        ZStack {
            NPTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    mapCard
                    controlCard
                    if let notice = recorder.notice {
                        noticeCard(notice)
                    }
                    summaryCard
                    historySection
                    explanationCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Карта сети")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await recorder.reloadHistory()
        }
        .onAppear {
            updateCamera()
        }
        .onChange(of: displayedRoute?.id) { _, _ in
            updateCamera()
        }
        .onChange(of: recorder.isActive) { _, active in
            if active {
                showsDemo = false
                selectedID = nil
            }
        }
        .confirmationDialog("Удалить все маршруты?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Удалить все", role: .destructive) {
                recorder.deleteAllRoutes()
                selectedID = nil
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Записанные маршруты будут стёрты с этого устройства без возможности восстановления.")
        }
    }

    // MARK: - Карта

    private var hasRoutePoints: Bool {
        !(displayedRoute?.points.isEmpty ?? true)
    }

    /// Карта Apple Maps (MapKit) видна всегда: и до первой записи, чтобы экран выглядел как карта, а не как форма
    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                networkMap
                    .frame(height: 380)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(NPTheme.border, lineWidth: 1)
                    )
                    .accessibilityLabel("Карта маршрута")
                    .accessibilityIdentifier("networkMapMap")

                mapOverlays
            }

            if hasRoutePoints {
                legend
                if hasSpeedData {
                    Picker("Показатель", selection: $metric) {
                        ForEach(RouteMetric.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("networkMapMetricPicker")
                }
            }
        }
    }

    /// Куда смотрит карта: при записи и пока маршрута нет — на вас, иначе — на весь показанный маршрут
    private func updateCamera() {
        if recorder.current != nil || !hasRoutePoints {
            camera = .userLocation(fallback: .automatic)
        } else {
            camera = .automatic
        }
    }

    private var mapStyleValue: MapStyle {
        // Приглушённая схема без значков заведений: цветная линия маршрута читается лучше, чем на пёстрой карте
        satellite
            ? .hybrid(pointsOfInterest: .excludingAll)
            : .standard(emphasis: .muted, pointsOfInterest: .excludingAll)
    }

    private func coordinates(of segment: RouteSegment) -> [CLLocationCoordinate2D] {
        segment.path.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func coordinate(of point: RoutePoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }

    private var networkMap: some View {
        let points = displayedRoute?.points ?? []
        let segments = RouteAnalyzer.segments(for: points, metric: metric)
        let zones = RouteAnalyzer.deadZones(in: points)
        let isLive = recorder.current != nil
        let first = points.first
        let last = points.last
        // Синяя точка «вы здесь» нужна при записи и на пустой карте; у сохранённого маршрута она только отвлекала бы
        let showsUserDot = isLive || points.isEmpty

        return Map(position: $camera) {
            if showsUserDot {
                UserAnnotation()
            }

            // Тёмная подложка под линией: цвет виден и на светлых улицах, и на спутниковом снимке
            ForEach(segments) { segment in
                MapPolyline(coordinates: coordinates(of: segment))
                    .stroke(Color.black.opacity(0.55), style: StrokeStyle(lineWidth: 9.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(segments) { segment in
                MapPolyline(coordinates: coordinates(of: segment))
                    .stroke(
                        segment.quality.displayColor,
                        style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round, dash: segment.quality == .dead ? [1, 8] : [])
                    )
            }

            ForEach(zones) { zone in
                Annotation("Нет сети", coordinate: CLLocationCoordinate2D(latitude: zone.center.latitude, longitude: zone.center.longitude)) {
                    deadZoneMarker
                }
            }

            if let first, points.count > 1 {
                Marker("Старт", systemImage: "flag.fill", coordinate: coordinate(of: first))
                    .tint(.green)
            }

            if let last, !isLive, points.count > 1 {
                Marker("Финиш", systemImage: "flag.checkered", coordinate: coordinate(of: last))
                    .tint(.red)
            }
        }
        .mapStyle(mapStyleValue)
    }

    /// Плашка состояния слева сверху, кнопки «Схема / Спутник» и «К моему положению» справа, подсказка снизу
    private var mapOverlays: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                mapBadge
                Spacer(minLength: 8)
                VStack(spacing: 8) {
                    mapControlButton(
                        systemImage: satellite ? "map.fill" : "globe.europe.africa.fill",
                        label: satellite ? "Схема" : "Спутник",
                        identifier: "networkMapStyleButton"
                    ) {
                        satellite.toggle()
                        HapticManager.shared.selectionChanged()
                    }
                    mapControlButton(
                        systemImage: "location.fill",
                        label: "К моему положению",
                        identifier: "networkMapRecenterButton"
                    ) {
                        updateCamera()
                        HapticManager.shared.selectionChanged()
                    }
                }
            }
            Spacer(minLength: 0)
            if let hint = mapHint {
                Text(hint)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("networkMapHint")
            }
        }
        .padding(10)
    }

    private var mapHint: String? {
        if hasRoutePoints { return nil }
        return recorder.current != nil
            ? "Ждём первую точку GPS: выйдите на открытое место"
            : "Запишите маршрут: цвет линии покажет качество сети"
    }

    private func mapControlButton(
        systemImage: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var deadZoneMarker: some View {
        ZStack {
            Circle()
                .fill(NPTheme.semanticCritical)
                .frame(width: 28, height: 28)
            Image(systemName: "wifi.slash")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
    }

    @ViewBuilder
    private var mapBadge: some View {
        if recorder.current != nil {
            badge("ИДЁТ ЗАПИСЬ", color: NPTheme.semanticCritical)
        } else if isShowingDemo {
            badge("ПРИМЕР · ДЕМО-ДАННЫЕ", color: NPTheme.accentPrimary)
                .accessibilityIdentifier("networkMapDemoBadge")
        } else if let route = displayedRoute, !route.points.isEmpty {
            badge(route.startedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()), color: NPTheme.cardBackgroundTertiary)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.92))
            .clipShape(Capsule())
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(RouteQuality.allCases, id: \.self) { quality in
                HStack(spacing: 5) {
                    Circle()
                        .fill(quality.displayColor)
                        .frame(width: 8, height: 8)
                    Text(quality.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NPTheme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Управление записью

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch recorder.state {
            case .recording:
                recordingBlock
            case .waitingForPermission:
                waitingBlock
            default:
                idleBlock
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .npGlassCard(cornerRadius: 16)
    }

    private var idleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                HapticManager.shared.impactMedium()
                recorder.start()
            } label: {
                Label("Начать запись маршрута", systemImage: "record.circle")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("networkMapStartButton")

            Text("Запись покажет на карте, где сеть была быстрой, медленной или пропадала. Пока она идёт, приложение работает и в фоне: в строке состояния iOS виден значок геолокации, а Dynamic Island продолжает показывать скорость. Маршруты хранятся только на этом устройстве.")
                .font(.system(size: 11))
                .foregroundStyle(NPTheme.textSecondary)
                .lineSpacing(2)

            if recorder.state.needsAttention {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(NPTheme.semanticCritical)
                        .font(.system(size: 12))
                    Text(recorder.state.statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NPTheme.semanticCritical)
                        .accessibilityIdentifier("networkMapPermissionStatus")
                }
                if recorder.state == .denied {
                    Button("Открыть Настройки iOS") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NPTheme.accentPrimary)
                }
            }

            Toggle(isOn: Binding(
                get: { recorder.measuresSpeed },
                set: { recorder.measuresSpeed = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Замерять скорость на маршруте")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Раз в 30 секунд скачивается до 1,5 МБ. На мобильном интернете это расходует трафик, поэтому по умолчанию выключено.")
                        .font(.system(size: 11))
                        .foregroundStyle(NPTheme.textSecondary)
                }
            }
            .accessibilityIdentifier("networkMapSpeedToggle")

            if !showsDemo {
                Button {
                    showsDemo = true
                    HapticManager.shared.selectionChanged()
                } label: {
                    Label("Показать пример", systemImage: "play.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                }
                .accessibilityIdentifier("networkMapDemoButton")
            } else if showsDemo {
                Button {
                    showsDemo = false
                } label: {
                    Label("Скрыть пример", systemImage: "xmark.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
                .accessibilityIdentifier("networkMapDemoHideButton")
            }
        }
    }

    private var waitingBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                Text("Ждём разрешение на геолокацию")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)
            }
            Text(recorder.state.statusText)
                .font(.system(size: 12))
                .foregroundStyle(NPTheme.textSecondary)
                .accessibilityIdentifier("networkMapPermissionStatus")
            Button("Отменить") {
                recorder.stop()
            }
            .font(.system(size: 13, weight: .semibold))
        }
    }

    private var recordingBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(NPTheme.semanticCritical)
                    .frame(width: 10, height: 10)
                Text("Идёт запись маршрута")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)
                Spacer()
                if let since = recorder.recordingSince {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(RouteFormat.duration(context.date.timeIntervalSince(since)))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(NPTheme.textPrimary)
                    }
                }
            }

            Text(liveSummary)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NPTheme.textPrimary)
                .accessibilityIdentifier("networkMapStatus")

            if !recorder.progressLine.isEmpty {
                Text(recorder.progressLine)
                    .font(.system(size: 11))
                    .foregroundStyle(NPTheme.textSecondary)
            }

            Text(recorder.state.statusText)
                .font(.system(size: 11))
                .foregroundStyle(NPTheme.textSecondary)
                .lineSpacing(2)

            Button {
                HapticManager.shared.notificationSuccess()
                recorder.stop()
                selectedID = recorder.lastSaved?.id
            } label: {
                Label("Остановить и сохранить", systemImage: "stop.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(NPTheme.semanticCritical)
            .accessibilityIdentifier("networkMapStopButton")
        }
    }

    /// «Точек: 12 · 450 м · 85 мс · 4G (LTE)»
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

    private func noticeCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(NPTheme.accentPrimary)
                .font(.system(size: 14))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NPTheme.textPrimary)
                .lineSpacing(2)
                .accessibilityIdentifier("networkMapNotice")
            Spacer(minLength: 0)
            Button {
                recorder.dismissNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NPTheme.textSecondary)
            }
            .npMinHitTarget()
        }
        .padding(12)
        .npGlassCard(cornerRadius: 14)
    }

    // MARK: - Сводка по маршруту

    @ViewBuilder
    private var summaryCard: some View {
        if let route = displayedRoute, !route.points.isEmpty {
            let stats = RouteAnalyzer.stats(of: route)
            VStack(alignment: .leading, spacing: 12) {
                Text(recorder.current != nil ? "Сводка по идущей записи" : (isShowingDemo ? "Сводка по примеру" : "Сводка по маршруту"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)

                QualityBar(shares: stats.shares)

                HStack(spacing: 6) {
                    ForEach(RouteQuality.allCases, id: \.self) { quality in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(quality.displayColor)
                                .frame(width: 6, height: 6)
                            Text(RouteFormat.percent(stats.share(of: quality)))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(NPTheme.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }

                Text("Точек: \(stats.pointCount) · \(RouteFormat.distance(stats.distanceMeters)) · \(RouteFormat.duration(stats.duration))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NPTheme.textPrimary)
                    .accessibilityIdentifier("networkMapSummary")

                VStack(alignment: .leading, spacing: 6) {
                    if let average = stats.averageLatencyMs, let worst = stats.worstLatencyMs {
                        statRow("Задержка", "в среднем \(RouteFormat.latency(average)), хуже всего \(RouteFormat.latency(worst))")
                    }
                    if let speed = stats.averageDownloadMbps {
                        statRow("Скорость скачивания", "в среднем \(RouteFormat.speed(speed))")
                    }
                    if stats.deadZoneCount > 0 {
                        statRow("Зоны без сети", "\(stats.deadZoneCount), самая длинная — \(RouteFormat.distance(stats.longestDeadStretchMeters))")
                    } else {
                        statRow("Зоны без сети", "не найдены")
                    }
                }

                if route.interrupted {
                    Text("Запись оборвалась без остановки (приложение закрыла система): маршрут сохранён как есть.")
                        .font(.system(size: 11))
                        .foregroundStyle(NPTheme.semanticWarn)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .npGlassCard(cornerRadius: 16)
        }
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(NPTheme.textSecondary)
                .frame(width: 118, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NPTheme.textPrimary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - История

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Мои маршруты")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(NPTheme.textPrimary)
                Spacer()
                if !recorder.history.isEmpty {
                    Button("Удалить все", role: .destructive) {
                        confirmDeleteAll = true
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityIdentifier("networkMapDeleteAll")
                }
            }

            if recorder.history.isEmpty {
                Text("Сохранённых маршрутов пока нет.")
                    .font(.system(size: 12))
                    .foregroundStyle(NPTheme.textSecondary)
                    .accessibilityIdentifier("networkMapHistoryEmpty")
            } else {
                ForEach(recorder.history) { route in
                    historyRow(route)
                }
            }
        }
    }

    private func historyRow(_ route: RouteRecord) -> some View {
        let stats = RouteAnalyzer.stats(of: route)
        let isSelected = recorder.current == nil && !showsDemo && displayedRoute?.id == route.id

        return HStack(spacing: 10) {
            Button {
                showsDemo = false
                selectedID = route.id
                HapticManager.shared.selectionChanged()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(route.startedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NPTheme.textPrimary)
                        if route.interrupted {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(NPTheme.semanticWarn)
                        }
                        Spacer()
                        Text("\(RouteFormat.distance(stats.distanceMeters)) · \(RouteFormat.duration(stats.duration))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(NPTheme.textSecondary)
                    }
                    QualityBar(shares: stats.shares)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                recorder.deleteRoute(id: route.id)
                if selectedID == route.id { selectedID = nil }
                HapticManager.shared.impactLight()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NPTheme.semanticCritical)
            }
            .npMinHitTarget()
            .accessibilityLabel("Удалить маршрут")
        }
        .padding(12)
        .npGlassCard(cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? NPTheme.accentPrimary : Color.clear, lineWidth: 1.5)
        )
        .accessibilityIdentifier("networkMapHistoryRow")
    }

    // MARK: - Пояснение

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Как это работает")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(NPTheme.textPrimary)

            Text("Каждые несколько секунд приложение сохраняет, где вы находитесь, и проверяет сеть: за сколько устанавливается соединение с контрольным узлом 1.1.1.1. Не ответил узел — на карте «нет сети». Телефон стоит на месте — точки пишутся реже.")
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .npGlassCard(cornerRadius: 16)
    }
}

/// Полоска из долей качества сети: чем длиннее цвет, тем больше точек маршрута с таким качеством
private struct QualityBar: View {
    let shares: [RouteQuality: Double]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(RouteQuality.allCases, id: \.self) { quality in
                    let share = shares[quality] ?? 0
                    if share > 0 {
                        Rectangle()
                            .fill(quality.displayColor)
                            .frame(width: proxy.size.width * share)
                    }
                }
            }
        }
        .frame(height: 8)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }
}
