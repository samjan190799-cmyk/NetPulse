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
    @State private var showSettings = false
    @State private var showGlossary = false
    @State private var confirmDeleteAll = false
    @State private var pendingDeleteID: UUID?
    @State private var showDeleteRouteDialog = false
    @State private var dismissedAISummary: String?
    @AppStorage("netpulse_map_satellite") private var satellite = false

    private var recorder: RouteRecorder {
        RouteRecorder.shared
    }

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

    // MARK: - Экран

    public var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    HomeMapLayer(
                        route: mapRoute,
                        metric: metric,
                        isLive: recorder.current != nil,
                        showsUserDot: !isRouteMode,
                        satellite: satellite,
                        camera: $camera
                    )
                    .accessibilityLabel("Карта маршрута")
                    .accessibilityIdentifier("networkMapMap")
                    .ignoresSafeArea(.container, edges: .top)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        bottomStack(containerHeight: proxy.size.height)
                    }

                    HomeTopBar(
                        viewModel: viewModel,
                        recorder: recorder,
                        style: topBarStyle,
                        lastRouteChip: lastRouteChip,
                        satellite: $satellite,
                        onSettings: { showSettings = true },
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
            }
            .onChange(of: selectedID) { _, _ in
                updateCamera()
            }
            .onChange(of: showsDemo) { _, _ in
                updateCamera()
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
            .fullScreenCover(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
            .sheet(isPresented: $showGlossary) {
                NetworkGlossarySheetView()
            }
        }
    }

    // MARK: - Нижняя часть

    private func bottomStack(containerHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            HomeFloatingCards(
                viewModel: viewModel,
                recorder: recorder,
                isIdle: mode == .idle,
                dismissedAISummary: $dismissedAISummary
            )
            panel(containerHeight: containerHeight)
        }
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
        if isRouteMode {
            camera = .automatic
        } else {
            camera = .userLocation(fallback: .automatic)
        }
        HapticManager.shared.selectionChanged()
    }

    /// Куда смотрит карта: у готового маршрута — на весь маршрут, иначе — на вас
    private func updateCamera() {
        switch mode {
        case .route:
            camera = .automatic
        case .recording:
            camera = .userLocation(fallback: .automatic)
        case .idle:
            camera = .userLocation(fallback: recorder.history.isEmpty ? .region(HomeMapDefaults.region) : .automatic)
        }
    }
}
