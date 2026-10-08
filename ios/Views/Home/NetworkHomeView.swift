//
//  NetworkHomeView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import MapKit

/// Что сейчас показывает главный экран
enum HomeMode: Equatable {
    /// Обычный режим: карта с вашим положением, внизу — скорость и две главные кнопки
    case idle
    /// Идёт запись маршрута (или ждёт ответа на запрос геолокации)
    case recording
    /// Показан готовый маршрут (только что записанный, выбранный из списка или пример)
    case route(RouteRecord, isDemo: Bool)
}

/// Главный экран «Сеть»: карта Apple Maps на весь экран и нижняя панель со скоростью сети.
///
/// Запись маршрута начинается только по кнопке «Записать маршрут» и идёт, пока её не остановят. Маршруты хранятся
/// только на этом устройстве и удаляются прямо на этом экране. Остальные возможности (инструменты, оценка сети,
/// справочник, настройки записи) лежат в нижней панели: её можно потянуть вверх.
@MainActor
public struct NetworkHomeView: View {
    @Bindable var viewModel: NetworkMonitorViewModel

    @State private var detent: HomePanelDetent = .medium
    @State private var selectedID: UUID?
    @State private var showsDemo = false
    @State private var metric: RouteMetric = .latency
    /// Пока маршрута нет и во время записи карта смотрит на вас; у готового маршрута — на весь маршрут целиком
    @State private var camera: MapCameraPosition = .userLocation(fallback: .region(HomeMapDefaults.region))
    @State private var showGlossary = false
    @State private var confirmDeleteAll = false
    @State private var pendingDeleteID: UUID?
    @State private var showDeleteRouteDialog = false
    @State private var dismissedAISummary: String?
    /// Линии прежних маршрутов: считаются один раз при изменении списка, а не при каждой перерисовке экрана
    @State private var coverageRuns: [CoverageRun] = []
    @AppStorage("netpulse_map_satellite") private var satellite = false
    /// Показывать ли на карте линии прежних маршрутов (ключ прежний, чтобы выбор пользователя сохранился)
    @AppStorage("netpulse_map_coverage") private var coverageOn = true
    /// Во время записи карта поворачивается по направлению движения (как навигатор), чтобы не крутить её руками
    @AppStorage("netpulse_map_follow_heading") private var followsHeading = true
    /// Отсчёт до возврата карты к пользователю после того, как он сдвинул её пальцем во время записи
    @State private var refollowTask: Task<Void, Never>?

    /// Через сколько секунд после касания карта сама возвращается к вам во время записи
    private static let refollowDelay: Duration = .seconds(8)

    private var recorder: RouteRecorder {
        RouteRecorder.shared
    }

    /// Сколько карта отступает от нижнего края строки состояния, чтобы кнопки сверху не закрывали маршрут:
    /// отступ 8 + кнопка 44 + промежуток 8 + кнопка 44, ещё около 30 на булавку «Финиш» над точкой и небольшой запас
    private static let topControlsClearance: CGFloat = 144

    // MARK: - Режим экрана

    private var mode: HomeMode {
        if recorder.isActive { return .recording }
        if showsDemo { return .route(RouteDemo.sample(), isDemo: true) }
        if let id = selectedID, let chosen = recorder.history.first(where: { $0.id == id }) {
            return .route(chosen, isDemo: false)
        }
        return .idle
    }

    /// Какой маршрут нарисован на карте: идущая запись, показанный маршрут или (в обычном режиме) последний сохранённый
    private var mapRoute: RouteRecord? {
        switch mode {
        case .recording:
            return recorder.current
        case .route(let route, _):
            return route
        case .idle:
            return recorder.history.first
        }
    }

    private var topBarStyle: HomeTopBarStyle {
        switch mode {
        case .idle: return .idle
        case .recording: return .recording
        case .route: return .route
        }
    }

    /// Подпись над картой: что за линия нарисована в обычном режиме
    private var lastRouteChip: String? {
        guard case .idle = mode, let last = recorder.history.first, !last.points.isEmpty else { return nil }
        let distance = RouteFormat.distance(RouteAnalyzer.distanceMeters(of: last.points))
        return "Последний маршрут · \(distance)"
    }

    private var isRouteMode: Bool {
        if case .route = mode { return true }
        return false
    }

    /// Нижняя панель обычного режима развёрнута почти на весь экран
    private var panelIsExpanded: Bool {
        mode == .idle && detent == .expanded
    }

    // MARK: - Прежние маршруты

    /// Легенда цветов нужна, пока на карте есть линии прежних маршрутов или последний маршрут
    private var showsCoverageLegend: Bool {
        mode == .idle && coverageOn && !recorder.history.isEmpty
    }

    /// Последний маршрут нарисован отдельно (толстой линией), остальные — тонкими
    private func refreshCoverage() {
        coverageRuns = CoverageBuilder.runs(from: Array(recorder.history.dropFirst()), metric: metric)
    }

    // MARK: - Экран

    public var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    // Карта идёт под строку состояния. Камера ставит маршрут и вас в свободную часть экрана: ниже
                    // кнопок сверху и выше панели снизу, поэтому флажки «Старт» и «Финиш» не прячутся под кнопками.
                    // Высоту строки состояния показывает только GeometryReader, который сам выходит за безопасную область.
                    GeometryReader { mapProxy in
                        HomeMapLayer(
                            route: mapRoute,
                            metric: metric,
                            isLive: recorder.current != nil,
                            showsUserDot: !isRouteMode,
                            satellite: satellite,
                            previousRoutes: mode == .idle && coverageOn ? coverageRuns : [],
                            showsEndpoints: mode != .idle,
                            camera: $camera,
                            onCameraSettled: { cameraSettled() }
                        )
                        .accessibilityLabel("Карта маршрута")
                        .accessibilityIdentifier("networkMapMap")
                        .safeAreaPadding(.top, mapProxy.safeAreaInsets.top + Self.topControlsClearance)
                    }
                    .ignoresSafeArea(.container, edges: .top)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        bottomStack(containerHeight: proxy.size.height)
                    }

                    HomeTopBar(
                        viewModel: viewModel,
                        recorder: recorder,
                        style: topBarStyle,
                        lastRouteChip: lastRouteChip,
                        compact: panelIsExpanded,
                        satellite: $satellite,
                        coverageOn: $coverageOn,
                        followsHeading: followsHeadingBinding,
                        onRecenter: { recenter() },
                        onBack: { closeRoute() }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .background(NPTheme.backgroundDeep.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await recorder.reloadHistory()
            }
            .onAppear {
                if !viewModel.isMonitoringActive {
                    viewModel.startMonitoring()
                }
                updateCamera()
                refreshCoverage()
            }
            .onChange(of: selectedID) { _, _ in
                updateCamera()
            }
            .onChange(of: showsDemo) { _, _ in
                updateCamera()
            }
            .onChange(of: recorder.history.first?.id) { _, _ in
                // Список маршрутов подгружается с диска уже после появления экрана
                updateCamera()
            }
            .onChange(of: recorder.history.map(\.id)) { _, _ in
                refreshCoverage()
            }
            .onChange(of: metric) { _, _ in
                refreshCoverage()
            }
            .onChange(of: recorder.isActive) { _, active in
                if active {
                    showsDemo = false
                    selectedID = nil
                    detent = .medium
                }
                updateCamera()
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
            .confirmationDialog("Удалить маршрут?", isPresented: $showDeleteRouteDialog, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if let id = pendingDeleteID {
                        recorder.deleteRoute(id: id)
                        if selectedID == id { selectedID = nil }
                    }
                    pendingDeleteID = nil
                }
                Button("Отмена", role: .cancel) {
                    pendingDeleteID = nil
                }
            } message: {
                Text("Маршрут будет стёрт с этого устройства без возможности восстановления.")
            }
            .sheet(isPresented: $showGlossary) {
                NetworkGlossarySheetView()
            }
        }
    }

    // MARK: - Нижняя часть

    private func bottomStack(containerHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            // У развёрнутой панели нет запаса по высоте: сообщения появятся, когда её свернут
            if !panelIsExpanded {
                HomeFloatingCards(
                    viewModel: viewModel,
                    recorder: recorder,
                    isIdle: mode == .idle,
                    dismissedAISummary: $dismissedAISummary
                )
                if showsCoverageLegend {
                    HomeCoverageLegend()
                }
            }
            panel(containerHeight: containerHeight)
        }
        // Сообщения над панелью появляются и исчезают плавно
        .npAnimation(value: viewModel.showRecordingHint)
        .npAnimation(value: viewModel.sleepTraffic)
        .npAnimation(value: viewModel.speedtestError)
        .npAnimation(value: recorder.notice)
    }

    @ViewBuilder
    private func panel(containerHeight: CGFloat) -> some View {
        switch mode {
        case .recording:
            HomeRecordingPanel(recorder: recorder, onStop: { finishRecording() })
        case .route(let route, let isDemo):
            HomeRoutePanel(
                route: route,
                isDemo: isDemo,
                metric: $metric,
                onDone: { closeRoute() },
                onDelete: {
                    pendingDeleteID = route.id
                    showDeleteRouteDialog = true
                }
            )
        case .idle:
            HomeIdlePanel(
                viewModel: viewModel,
                recorder: recorder,
                containerHeight: containerHeight,
                detent: $detent,
                selectedID: $selectedID,
                showsDemo: $showsDemo,
                confirmDeleteAll: $confirmDeleteAll,
                pendingDeleteID: $pendingDeleteID,
                showDeleteRouteDialog: $showDeleteRouteDialog,
                showGlossary: $showGlossary
            )
        }
    }

    // MARK: - Действия

    /// Останавливает запись и показывает только что сохранённый маршрут (если он сохранился)
    private func finishRecording() {
        let before = recorder.lastSaved?.id
        recorder.stop()
        HapticManager.shared.notificationSuccess()
        if let saved = recorder.lastSaved, saved.id != before {
            selectedID = saved.id
            detent = .medium
        }
    }

    /// Закрывает показанный маршрут (или пример) и возвращает обычный режим
    private func closeRoute() {
        selectedID = nil
        showsDemo = false
        HapticManager.shared.selectionChanged()
    }

    /// «К моему положению»; у готового маршрута та же кнопка возвращает вид на весь маршрут
    private func recenter() {
        updateCamera()
        HapticManager.shared.selectionChanged()
    }

    /// Переключатель «карта по направлению движения»; сразу применяется к карте
    private var followsHeadingBinding: Binding<Bool> {
        Binding(
            get: { followsHeading },
            set: { enabled in
                followsHeading = enabled
                updateCamera()
            }
        )
    }

    /// Камера остановилась. Если во время записи вы сдвинули карту пальцем, она теряет привязку к вашему положению:
    /// через несколько секунд после последнего касания карта возвращается к вам сама, чтобы не нажимать кнопку на ходу.
    private func cameraSettled() {
        refollowTask?.cancel()
        guard case .recording = mode, !camera.followsUserLocation else { return }
        refollowTask = Task { @MainActor in
            try? await Task.sleep(for: Self.refollowDelay)
            guard !Task.isCancelled, case .recording = mode else { return }
            updateCamera()
        }
    }

    /// Куда смотрит карта: у готового маршрута — на весь маршрут, во время записи — на вас (и по ходу движения),
    /// иначе — на вас, севером вверх
    private func updateCamera() {
        refollowTask?.cancel()
        switch mode {
        case .route:
            camera = .automatic
        case .recording:
            camera = .userLocation(followsHeading: followsHeading, fallback: .automatic)
        case .idle:
            camera = .userLocation(fallback: recorder.history.isEmpty ? .region(HomeMapDefaults.region) : .automatic)
        }
    }
}
