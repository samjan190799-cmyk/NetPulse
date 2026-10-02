//
//  RouteRecorder.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import Observation

/// Запись маршрута для «Карты сети»: пока идёт запись, приложение через каждые несколько секунд сохраняет, где
/// находится телефон и какой там была сеть (задержка до контрольного узла, вид связи, по желанию — скорость).
///
/// Зачем фоновая геолокация. Запись должна идти, пока телефон лежит в кармане, пока едешь, идёшь или гуляешь:
/// без этого карта покрывала бы только те места, где держишь приложение открытым. Именно для этого, и ни для чего
/// другого, приложению нужна постоянная геолокация. Побочный эффект записи: приложение остаётся активным,
/// и Dynamic Island показывает скорость и в фоне.
///
/// Что нужно знать:
/// - запись начинается только по нажатию «Начать запись» и останавливается по «Остановить»; в строке состояния iOS
///   всё это время виден значок геолокации, а в приложении — плашка «Идёт запись маршрута»;
/// - маршруты хранятся только на этом устройстве (`RouteStorage`), никуда не отправляются и удаляются из приложения;
/// - если запись нужно продолжить в фоне, в запросе разрешения нужно выбрать «При использовании приложения»:
///   вариант «Однократно» iOS отзывает вскоре после сворачивания;
/// - закрытое смахиванием приложение не запускается само: прерванная запись восстанавливается при следующем открытии.
@MainActor
@Observable
public final class RouteRecorder {
    public static let shared = RouteRecorder(
        session: CoreLocationSession(),
        probe: LiveNetworkProbe(),
        storage: RouteStorage.shared
    )

    public enum State: Equatable, Sendable {
        /// Запись не идёт
        case idle
        /// Ждём ответа пользователя на запрос геолокации
        case waitingForPermission
        /// Запись идёт
        case recording
        /// Пользователь запретил геолокацию (или службы геолокации выключены в системе)
        case denied
        /// Геолокация ограничена на устройстве (например, родительским контролем)
        case restricted
        /// В приложении не включён фоновый режим геолокации (ошибка сборки)
        case unavailable

        /// Подпись состояния для экрана «Карта сети»
        public var statusText: String {
            switch self {
            case .idle:
                return ""
            case .waitingForPermission:
                return "Ожидается ответ на запрос геолокации. Выберите «При использовании приложения»: вариант «Однократно» iOS отзывает вскоре после сворачивания."
            case .recording:
                return "Идёт запись маршрута. Приложение остаётся активным и в фоне, в строке состояния виден значок геолокации."
            case .denied:
                return "Нет доступа к геолокации. Разрешите «При использовании приложения» в Настройках iOS."
            case .restricted:
                return "Геолокация ограничена на этом устройстве (например, родительским контролем)."
            case .unavailable:
                return "Запись недоступна: в этой сборке не включён фоновый режим геолокации."
            }
        }

        /// Короткое название для журнала и сводки
        public var logLabel: String {
            switch self {
            case .idle: return "не идёт"
            case .waitingForPermission: return "ждёт разрешения на геолокацию"
            case .recording: return "идёт"
            case .denied: return "нет доступа к геолокации"
            case .restricted: return "геолокация ограничена на устройстве"
            case .unavailable: return "недоступна: в сборке нет фонового режима location"
            }
        }

        /// Требует действий пользователя или исправления сборки
        public var needsAttention: Bool {
            switch self {
            case .denied, .restricted, .unavailable:
                return true
            case .idle, .waitingForPermission, .recording:
                return false
            }
        }
    }

    // MARK: - Состояние для интерфейса

    public private(set) var state: State = .idle {
        didSet {
            guard state != oldValue else { return }
            IslandDiagnostics.shared.log("Запись маршрута: \(state.logLabel)", .location)
        }
    }
    /// Идущая запись (`nil`, если запись не идёт)
    public private(set) var current: RouteRecord?
    /// Сохранённые маршруты, новые первыми
    public private(set) var history: [RouteRecord] = []
    /// Последний сохранённый маршрут (для показа на карте сразу после остановки)
    public private(set) var lastSaved: RouteRecord?
    /// Сообщение о том, что произошло с записью (слишком короткий маршрут, восстановление после обрыва и т. д.)
    public private(set) var notice: String?
    /// Что делает запись сейчас: «Ждём сигнал GPS», «Телефон стоит на месте» и т. д.
    public private(set) var progressLine: String = ""
    public private(set) var lastQuality: RouteQuality?
    public private(set) var lastLatencyMs: Double?
    public private(set) var lastLink: LinkKind?
    /// С какого момента идёт запись
    public private(set) var recordingSince: Date?
    /// Сколько раз приложение приостанавливали в фоне, пока запись шла (с запуска приложения)
    public private(set) var pausesWhileRecording = 0

    private static let measureSpeedKey = "netpulse_route_measure_speed"
    /// Замерять ли скорость скачивания на маршруте (расходует до ~3 МБ в минуту, по умолчанию выключено)
    public var measuresSpeed: Bool {
        didSet { defaults.set(measuresSpeed, forKey: Self.measureSpeedKey) }
    }

    // MARK: - Настройки записи

    /// Маршрут короче не сохраняется: из одной точки пути не получится
    public static let minPointsToSave = 2
    /// Предел точек в одной записи; по его достижении запись останавливается
    public static let maxPoints = 6_000
    /// Как часто измерять скорость, секунд
    public static let speedProbeInterval: TimeInterval = 30
    /// Как часто сохранять идущую запись на диск, секунд
    private static let persistInterval: TimeInterval = 20

    // MARK: - Зависимости и внутреннее состояние

    private let session: any LocationSessionProviding
    private let probe: any NetworkProbing
    private let storage: RouteStorage
    private let defaults: UserDefaults
    private let policy = RouteSamplingPolicy()
    /// Крутить ли цикл записи сам; тесты выключают его и вызывают `tick(now:)` по одному шагу
    private let startsLoop: Bool
    /// Запись включена: от неё зависит интерфейс (`isActive`), поэтому свойство наблюдаемое
    private var wantsRecording = false
    @ObservationIgnored private var latestFix: LocationFix?
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var lastPersistAt = Date.distantPast
    @ObservationIgnored private var lastSpeedProbeAt = Date.distantPast

    public init(
        session: any LocationSessionProviding,
        probe: any NetworkProbing,
        storage: RouteStorage,
        defaults: UserDefaults = .standard,
        startsLoop: Bool = true
    ) {
        self.session = session
        self.probe = probe
        self.storage = storage
        self.defaults = defaults
        self.startsLoop = startsLoop
        self.measuresSpeed = defaults.bool(forKey: Self.measureSpeedKey)

        session.onFix = { [weak self] fix in
            self?.receive(fix)
        }
        session.onAuthorizationChange = { [weak self] in
            self?.authorizationChanged()
        }
    }

    // MARK: - Управление записью

    /// Запись включена (идёт или ждёт разрешения на геолокацию)
    public var isActive: Bool {
        wantsRecording
    }

    /// Сколько точек записано в идущем маршруте
    public var pointCount: Int {
        current?.points.count ?? 0
    }

    /// Начинает запись. Вызывать нужно при открытом приложении: запрос разрешения и запуск геолокации из фона
    /// система не принимает.
    public func start() {
        guard !wantsRecording else { return }
        notice = nil
        progressLine = ""
        lastQuality = nil
        lastLatencyMs = nil
        lastLink = nil
        latestFix = nil
        lastSpeedProbeAt = .distantPast
        lastPersistAt = .distantPast

        let now = Date()
        wantsRecording = true
        current = RouteRecord(startedAt: now, measuredSpeed: measuresSpeed)
        recordingSince = now
        IslandDiagnostics.shared.log("Запись маршрута начата", .location)
        applyDesiredState()
    }

    /// Останавливает запись и сохраняет маршрут
    public func stop() {
        guard wantsRecording || current != nil else { return }
        wantsRecording = false
        stopLoop()
        session.stop()

        let finished = current
        current = nil
        recordingSince = nil
        state = .idle
        IslandDiagnostics.shared.log("Запись маршрута остановлена", .location)

        guard var record = finished else { return }
        record.endedAt = Date()
        finalize(record, interrupted: false)
    }

    /// Вызывать, когда приложение стало активным: система могла остановить сеанс геолокации, пока оно было свёрнуто
    public func appDidBecomeActive() {
        if wantsRecording {
            applyDesiredState()
        }
    }

    /// Учитывает паузу приложения в фоне, если она случилась во время записи
    public func noteBackgroundPause(seconds: TimeInterval, now: Date = Date()) {
        guard state == .recording, let since = recordingSince else { return }
        // Пауза началась до запуска записи — не считается
        guard now.addingTimeInterval(-seconds) >= since else { return }
        pausesWhileRecording += 1
    }

    /// Сводка для журнала и экрана диагностики
    public var summaryDescription: String {
        state == .recording ? "идёт, точек: \(pointCount)" : state.logLabel
    }

    /// Обстоятельства для записи о паузе в журнале
    public func diagnosticContext() -> String {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled ? "вкл" : "выкл"
        return "Запись маршрута: \(summaryDescription); энергосбережение: \(lowPower)."
    }

    // MARK: - История

    public func reloadHistory() async {
        history = await storage.loadAll()
    }

    public func deleteRoute(id: UUID) {
        history.removeAll { $0.id == id }
        if lastSaved?.id == id { lastSaved = nil }
        Task { [storage] in
            await storage.delete(id: id)
        }
    }

    public func deleteAllRoutes() {
        history = []
        lastSaved = nil
        Task { [storage] in
            await storage.deleteAll()
        }
    }

    /// Подбирает запись, которую оборвала система (например, приложение закрыли посреди маршрута):
    /// она сохраняется как прерванный маршрут, а не пропадает.
    public func recoverInterruptedRoute() async {
        guard !wantsRecording, var record = await storage.loadActive() else { return }
        // Пока читался файл, пользователь мог начать новую запись: её не трогаем
        guard !wantsRecording else { return }

        record.interrupted = true
        record.endedAt = record.points.last?.time ?? record.startedAt
        if record.points.count >= Self.minPointsToSave {
            try? await storage.save(record)
            notice = "Запись была прервана: приложение закрыла система. Сохранено точек: \(record.points.count)."
            IslandDiagnostics.shared.log("Прерванная запись маршрута восстановлена (\(record.points.count) точек)", .location)
        }
        await storage.clearActive()
        history = await storage.loadAll()
    }

    // MARK: - Источник положения и разрешения

    func receive(_ fix: LocationFix) {
        if let known = latestFix, fix.timestamp < known.timestamp { return }
        latestFix = fix
    }

    private func authorizationChanged() {
        if wantsRecording {
            applyDesiredState()
        }
    }

    private static var hasLocationBackgroundMode: Bool {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        return modes.contains("location")
    }

    private func applyDesiredState() {
        guard wantsRecording else {
            session.stop()
            stopLoop()
            state = .idle
            return
        }

        // Без значения `location` в UIBackgroundModes включение фоновых обновлений завершает приложение исключением
        guard Self.hasLocationBackgroundMode else {
            abort(into: .unavailable)
            return
        }

        switch session.authorization {
        case .notDetermined:
            state = .waitingForPermission
            session.requestPermission()
        case .authorized:
            session.start()
            state = .recording
            startLoopIfNeeded()
        case .restricted:
            abort(into: .restricted)
        case .denied:
            abort(into: .denied)
        }
    }

    /// Запись невозможна (нет доступа к геолокации). Если точки уже были записаны, маршрут не теряется.
    private func abort(into newState: State) {
        wantsRecording = false
        stopLoop()
        session.stop()

        let unfinished = current
        current = nil
        recordingSince = nil
        state = newState

        // Ни одной точки не записано (разрешения не было с самого начала) — сохранять нечего
        guard var record = unfinished, !record.points.isEmpty else { return }
        record.endedAt = record.points.last?.time ?? Date()
        finalize(record, interrupted: true)
    }

    // MARK: - Цикл записи

    private func startLoopIfNeeded() {
        guard startsLoop, loopTask == nil else { return }
        loopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.wantsRecording else { break }
                let started = Date()
                await self.tick(now: started)
                let spent = Date().timeIntervalSince(started)
                let pause = max(0.5, self.policy.tickInterval - spent)
                try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
            }
        }
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    /// Один шаг записи: решает, нужна ли новая точка, и если нужна — проверяет сеть и добавляет её
    func tick(now: Date) async {
        guard state == .recording, let recordID = current?.id else { return }

        switch policy.decide(lastPoint: current?.points.last, fix: latestFix, now: now) {
        case .skipNoFix:
            progressLine = "Ждём сигнал GPS…"
            return
        case .skipPoorAccuracy:
            progressLine = "Слабый сигнал GPS: точность низкая…"
            return
        case .skipStationary:
            progressLine = "Телефон стоит на месте: новые точки не пишутся"
            return
        case .record:
            break
        }
        guard let fix = latestFix else { return }

        let wantsSpeed = measuresSpeed && now.timeIntervalSince(lastSpeedProbeAt) >= Self.speedProbeInterval
        if wantsSpeed {
            lastSpeedProbeAt = now
        }
        let result = await probe.measure(withSpeed: wantsSpeed)

        // Пока шла проверка сети, запись могли остановить
        guard state == .recording, current?.id == recordID else { return }

        let point = RoutePoint(
            time: now,
            latitude: fix.latitude,
            longitude: fix.longitude,
            accuracy: fix.horizontalAccuracy,
            speedMps: fix.speed >= 0 ? fix.speed : nil,
            latencyMs: result.reachable ? result.latencyMs : nil,
            reachable: result.reachable,
            link: result.link,
            downloadMbps: result.downloadMbps
        )
        current?.points.append(point)
        lastQuality = point.quality
        lastLatencyMs = point.latencyMs
        lastLink = point.link
        progressLine = "Записано точек: \(pointCount)"

        persistIfNeeded(now: now)

        if pointCount >= Self.maxPoints {
            notice = "Достигнут предел записи (\(Self.maxPoints) точек): маршрут сохранён."
            stop()
        }
    }

    // MARK: - Сохранение

    private func persistIfNeeded(now: Date) {
        guard now.timeIntervalSince(lastPersistAt) >= Self.persistInterval, let snapshot = current else { return }
        lastPersistAt = now
        Task { [storage] in
            try? await storage.saveActive(snapshot)
        }
    }

    /// Сохраняет готовый маршрут; слишком короткий отбрасывается
    private func finalize(_ record: RouteRecord, interrupted: Bool) {
        var saved = record
        saved.interrupted = interrupted

        guard saved.points.count >= Self.minPointsToSave else {
            if notice == nil {
                notice = "Маршрут слишком короткий: записано меньше двух точек, он не сохранён."
            }
            Task { [storage] in
                await storage.clearActive()
            }
            return
        }

        lastSaved = saved
        history.insert(saved, at: 0)
        Task { [weak self, storage] in
            try? await storage.save(saved)
            await storage.clearActive()
            let all = await storage.loadAll()
            self?.history = all
        }
    }
}
