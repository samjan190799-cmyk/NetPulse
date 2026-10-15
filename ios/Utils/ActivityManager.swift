//
//  ActivityManager.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Управление жизненным циклом Live Activity (Dynamic Island).
///
/// Что изменено по сравнению с прежней версией, из-за которой остров замирал:
/// - отправка кадров идёт через `IslandUpdatePipeline` со сроком: «зависший» вызов `activity.update` больше не
///   блокирует все следующие обновления навсегда;
/// - «Перезапустить» действительно создаёт активность заново (раньше подключалась к старой и упиралась в тот же флаг);
/// - после возврата в приложение, если остров не обновился за несколько секунд, он пересоздаётся сам;
/// - у каждого кадра есть `staleDate`: если обновления прекратились (приложение усыпили), iOS помечает остров
///   устаревшим, и он показывает «спит» и возраст данных, а не застывшие цифры, выдаваемые за живые;
/// - неудачный запуск активности повторяется не чаще раза в 10 секунд, а не каждую секунду;
/// - важные события пишутся в журнал (`IslandDiagnostics`).
@MainActor
public final class ActivityManager {
    public static let shared = ActivityManager()

    /// Через сколько секунд без обновлений iOS пометит остров устаревшим (виджет покажет, что приложение спит)
    public static let staleAfter: TimeInterval = 20
    /// Сколько секунд ждать ответа системы на отправку кадра, прежде чем считать её зависшей
    public static let sendTimeout: TimeInterval = 5
    /// Как часто повторять отправку, если видимые значения не менялись
    public static let unchangedResendInterval: TimeInterval = 2.5
    /// Пауза между неудачными попытками запустить активность
    static let startRetryBackoff: TimeInterval = 10
    /// Сколько секунд после возврата в приложение ждать обновления острова, прежде чем пересоздать его
    static let foregroundCheckDelay: TimeInterval = 4

    public private(set) var isLiveActivityActive: Bool = false

    #if canImport(ActivityKit)
    private var currentActivity: Activity<NetPulseAttributes>?
    private var lastRenderedState: NetPulseAttributes.ContentState?
    private var lastRenderedAt: Date?
    private var lastSubmittedState: NetPulseAttributes.ContentState?
    private var stateObservationTask: Task<Void, Never>?
    private var foregroundCheckTask: Task<Void, Never>?
    private var nextStartAttemptAt: Date?
    private var reportedMissingInBackground = false
    private let pipeline = IslandUpdatePipeline<NetPulseAttributes.ContentState>(sendTimeout: ActivityManager.sendTimeout)
    #endif

    private init() {
        #if canImport(ActivityKit)
        pipeline.onCompleted = { [weak self] state in
            self?.lastRenderedState = state
            self?.lastRenderedAt = Date()
        }
        pipeline.onAbandoned = { age in
            IslandDiagnostics.shared.log(
                "Отправка кадра в остров не завершилась за \(Int(age.rounded())) с: система не ответила. "
                + "Отправка забыта, дальше шлю самый свежий кадр.",
                .warning
            )
        }
        #endif
    }

    // MARK: - Состояние

    /// Проверка системного разрешения Live Activity в iOS Settings
    public var areActivitiesEnabled: Bool {
        #if canImport(ActivityKit)
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }

    /// Текстовое описание статуса для настроек и UI
    public var statusDescription: String {
        guard areActivitiesEnabled else {
            return "Отключено в Настройках iOS"
        }
        guard isLiveActivityActive else {
            return "В режиме ожидания"
        }
        #if canImport(ActivityKit)
        if let age = secondsSinceLastRender, age > Self.staleAfter {
            return "Активен, но не обновляется (\(IslandDiagnostics.formatAge(age)))"
        }
        #endif
        return "Активен в Dynamic Island"
    }

    /// Снимок состояния конвейера обновления для экрана диагностики
    public var health: IslandHealthSnapshot {
        #if canImport(ActivityKit)
        let stats = pipeline.stats
        var activityText = "нет"
        if let activity = currentActivity {
            activityText = Self.describe(activity.activityState)
        }
        return IslandHealthSnapshot(
            activityText: activityText,
            secondsSinceLastUpdate: secondsSinceLastRender,
            sent: stats.completed,
            abandoned: stats.abandoned,
            lateReplies: stats.lateReplies,
            longestSendSeconds: stats.longestDuration,
            inFlightSeconds: pipeline.inFlightAge
        )
        #else
        return IslandHealthSnapshot()
        #endif
    }

    // MARK: - Запуск, восстановление, перезапуск

    /// Восстановление или немедленный запуск сессии Dynamic Island
    public func checkAndRestoreActivity(
        downloadSpeedText: String = "0 Мбит/с",
        uploadSpeedText: String = "0 Мбит/с",
        compactDownloadText: String = "0",
        compactUploadText: String = "0",
        pingMs: Double? = nil,
        jitterMs: Double? = nil,
        isTesting: Bool = false,
        connectionType: String = "—",
        ispName: String = "Интернет",
        isGamingMode: Bool = false,
        gameTitle: String? = nil,
        gameRegion: String? = nil,
        packetLossPct: Double? = nil
    ) {
        #if canImport(ActivityKit)
        let state = Self.makeState(
            downloadSpeedText: downloadSpeedText, uploadSpeedText: uploadSpeedText,
            compactDownloadText: compactDownloadText, compactUploadText: compactUploadText,
            pingMs: pingMs, jitterMs: jitterMs, isTesting: isTesting,
            connectionType: connectionType, ispName: ispName, isGamingMode: isGamingMode,
            gameTitle: gameTitle, gameRegion: gameRegion, packetLossPct: packetLossPct
        )
        attachOrRequest(state: state, reason: "запуск или восстановление")
        #endif
    }

    /// Запуск Live Activity в Dynamic Island: подключается к уже существующей активности или создаёт новую
    public func startActivity(
        downloadSpeedText: String = "0 Мбит/с",
        uploadSpeedText: String = "0 Мбит/с",
        compactDownloadText: String = "0",
        compactUploadText: String = "0",
        pingMs: Double? = nil,
        jitterMs: Double? = nil,
        isTesting: Bool = false,
        connectionType: String = "—",
        ispName: String = "Интернет",
        isGamingMode: Bool = false,
        gameTitle: String? = nil,
        gameRegion: String? = nil,
        packetLossPct: Double? = nil
    ) {
        #if canImport(ActivityKit)
        let state = Self.makeState(
            downloadSpeedText: downloadSpeedText, uploadSpeedText: uploadSpeedText,
            compactDownloadText: compactDownloadText, compactUploadText: compactUploadText,
            pingMs: pingMs, jitterMs: jitterMs, isTesting: isTesting,
            connectionType: connectionType, ispName: ispName, isGamingMode: isGamingMode,
            gameTitle: gameTitle, gameRegion: gameRegion, packetLossPct: packetLossPct
        )
        attachOrRequest(state: state, reason: "включение острова")
        #endif
    }

    /// Настоящий перезапуск: создаёт новую активность, затем завершает старые. Если создать новую не удалось
    /// (например, приложение в фоне), хотя бы отправляет свежий кадр в прежнюю.
    public func restartActivity(
        downloadSpeedText: String = "0 Мбит/с",
        uploadSpeedText: String = "0 Мбит/с",
        compactDownloadText: String = "0",
        compactUploadText: String = "0",
        pingMs: Double? = nil,
        jitterMs: Double? = nil,
        isTesting: Bool = false,
        connectionType: String = "—",
        ispName: String = "Интернет",
        isGamingMode: Bool = false,
        gameTitle: String? = nil,
        gameRegion: String? = nil,
        packetLossPct: Double? = nil
    ) {
        #if canImport(ActivityKit)
        let state = Self.makeState(
            downloadSpeedText: downloadSpeedText, uploadSpeedText: uploadSpeedText,
            compactDownloadText: compactDownloadText, compactUploadText: compactUploadText,
            pingMs: pingMs, jitterMs: jitterMs, isTesting: isTesting,
            connectionType: connectionType, ispName: ispName, isGamingMode: isGamingMode,
            gameTitle: gameTitle, gameRegion: gameRegion, packetLossPct: packetLossPct
        )
        lastSubmittedState = state
        recreateActivity(with: state, reason: "по запросу пользователя")
        #endif
    }

    // MARK: - Обновление

    /// Обновление живых данных реальной скорости в Dynamic Island
    public func updateActivity(
        downloadSpeedText: String,
        uploadSpeedText: String,
        compactDownloadText: String,
        compactUploadText: String,
        pingMs: Double? = nil,
        jitterMs: Double? = nil,
        isTesting: Bool,
        connectionType: String,
        ispName: String,
        isGamingMode: Bool = false,
        gameTitle: String? = nil,
        gameRegion: String? = nil,
        packetLossPct: Double? = nil,
        force: Bool = false
    ) {
        #if canImport(ActivityKit)
        let state = Self.makeState(
            downloadSpeedText: downloadSpeedText, uploadSpeedText: uploadSpeedText,
            compactDownloadText: compactDownloadText, compactUploadText: compactUploadText,
            pingMs: pingMs, jitterMs: jitterMs, isTesting: isTesting,
            connectionType: connectionType, ispName: ispName, isGamingMode: isGamingMode,
            gameTitle: gameTitle, gameRegion: gameRegion, packetLossPct: packetLossPct
        )
        submit(state: state, force: force)
        #endif
    }

    /// Остановка Live Activity
    public func stopActivity() {
        #if canImport(ActivityKit)
        stateObservationTask?.cancel()
        stateObservationTask = nil
        foregroundCheckTask?.cancel()
        foregroundCheckTask = nil
        pipeline.reset()
        lastRenderedState = nil
        lastRenderedAt = nil
        lastSubmittedState = nil
        currentActivity = nil
        isLiveActivityActive = false

        let all = Activity<NetPulseAttributes>.activities
        Task {
            for activity in all {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        IslandDiagnostics.shared.log("Остров выключен", .island)
        #endif
    }

    /// Проверка после возврата в приложение: если остров не обновился за несколько секунд, он пересоздаётся.
    /// Пока приложение было свёрнуто, обновить остров из фона нельзя, а создать его заново можно только при открытом
    /// приложении, поэтому именно здесь он «оживает» (раньше для этого приходилось нажимать «Перезапустить»).
    public func scheduleForegroundHealthCheck() {
        #if canImport(ActivityKit)
        guard areActivitiesEnabled, lastSubmittedState != nil else { return }
        foregroundCheckTask?.cancel()
        let completedBefore = pipeline.stats.completed
        let delay = UInt64(Self.foregroundCheckDelay * 1_000_000_000)
        foregroundCheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else { return }
            self.finishForegroundCheck(completedBefore: completedBefore)
        }
        #endif
    }

    // MARK: - Внутренняя кухня

    #if canImport(ActivityKit)

    private static func makeState(
        downloadSpeedText: String,
        uploadSpeedText: String,
        compactDownloadText: String,
        compactUploadText: String,
        pingMs: Double?,
        jitterMs: Double?,
        isTesting: Bool,
        connectionType: String,
        ispName: String,
        isGamingMode: Bool,
        gameTitle: String?,
        gameRegion: String?,
        packetLossPct: Double?
    ) -> NetPulseAttributes.ContentState {
        NetPulseAttributes.ContentState(
            downloadSpeedText: downloadSpeedText,
            uploadSpeedText: uploadSpeedText,
            compactDownloadText: compactDownloadText,
            compactUploadText: compactUploadText,
            pingMs: pingMs.map { $0.rounded() },
            jitterMs: jitterMs.map { ($0 * 10).rounded() / 10.0 },
            isTesting: isTesting,
            connectionType: connectionType,
            ispName: ispName,
            isGamingMode: isGamingMode,
            gameTitle: gameTitle,
            gameRegion: gameRegion,
            packetLossPct: packetLossPct
        )
    }

    private static func relevance(for state: NetPulseAttributes.ContentState) -> Double {
        state.isTesting ? 100.0 : (state.isGamingMode ? 90.0 : 80.0)
    }

    private static func describe(_ state: ActivityState) -> String {
        switch state {
        case .active: return "активна"
        case .stale: return "устарела (нет обновлений)"
        case .ended: return "завершена"
        case .dismissed: return "закрыта"
        @unknown default: return "неизвестно"
        }
    }

    private static func isAlive(_ activity: Activity<NetPulseAttributes>) -> Bool {
        activity.activityState != .ended && activity.activityState != .dismissed
    }

    /// Видимое пользователю изменение: цифры в компактном виде или режим замера
    private static func hasVisibleChange(from old: NetPulseAttributes.ContentState, to new: NetPulseAttributes.ContentState) -> Bool {
        old.compactDownloadText != new.compactDownloadText
            || old.compactUploadText != new.compactUploadText
            || old.isTesting != new.isTesting
    }

    private var secondsSinceLastRender: TimeInterval? {
        lastRenderedAt.map { Date().timeIntervalSince($0) }
    }

    private var canAttemptStart: Bool {
        guard let next = nextStartAttemptAt else { return true }
        return Date() >= next
    }

    /// Живая активность: текущая, а если её нет — подхваченная из списка системы (лишние дубликаты завершаются)
    private func liveActivity() -> Activity<NetPulseAttributes>? {
        if let current = currentActivity, Self.isAlive(current) {
            return current
        }

        let alive = Activity<NetPulseAttributes>.activities.filter { Self.isAlive($0) }
        guard let first = alive.first else {
            currentActivity = nil
            return nil
        }
        for duplicate in alive.dropFirst() {
            Task { await duplicate.end(nil, dismissalPolicy: .immediate) }
        }
        adopt(first)
        return first
    }

    private func adopt(_ activity: Activity<NetPulseAttributes>) {
        if currentActivity?.id != activity.id {
            // Ответы на отправки в прежнюю активность больше не важны
            pipeline.reset()
            lastRenderedState = nil
        }
        currentActivity = activity
        isLiveActivityActive = true
        reportedMissingInBackground = false
        monitorActivityState(activity)
    }

    /// Подключается к существующей активности или создаёт новую
    private func attachOrRequest(state: NetPulseAttributes.ContentState, reason: String) {
        lastSubmittedState = state
        guard areActivitiesEnabled else {
            isLiveActivityActive = false
            IslandDiagnostics.shared.log("Live Activities отключены в Настройках iOS — остров не запускается", .warning)
            return
        }

        if liveActivity() != nil {
            submit(state: state, force: true)
        } else {
            requestNewActivity(state: state, reason: reason)
        }
    }

    @discardableResult
    private func requestNewActivity(state: NetPulseAttributes.ContentState, reason: String) -> Activity<NetPulseAttributes>? {
        guard areActivitiesEnabled else {
            isLiveActivityActive = false
            return nil
        }

        let attributes = NetPulseAttributes(sessionTitle: "Мониторинг NetPulse")
        var stamped = state
        stamped.updatedAt = Date()
        let content = ActivityContent(
            state: stamped,
            staleDate: Date().addingTimeInterval(Self.staleAfter),
            relevanceScore: Self.relevance(for: state)
        )

        do {
            let activity = try Activity<NetPulseAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            adopt(activity)
            lastRenderedState = state
            lastRenderedAt = Date()
            nextStartAttemptAt = nil
            IslandDiagnostics.shared.log("Live Activity запущена (\(reason))", .island)
            return activity
        } catch {
            nextStartAttemptAt = Date().addingTimeInterval(Self.startRetryBackoff)
            isLiveActivityActive = false
            IslandDiagnostics.shared.log(
                "Не удалось запустить Live Activity (\(reason)): \(error.localizedDescription)",
                .error
            )
            return nil
        }
    }

    /// Создаёт новую активность и завершает прежние
    private func recreateActivity(with state: NetPulseAttributes.ContentState, reason: String) {
        guard areActivitiesEnabled else {
            isLiveActivityActive = false
            return
        }

        IslandDiagnostics.shared.log("Пересоздаю Live Activity: \(reason)", .island)
        let previous = Activity<NetPulseAttributes>.activities
        pipeline.reset()
        lastRenderedState = nil

        if let fresh = requestNewActivity(state: state, reason: reason) {
            // Сначала новая, потом конец старых: остров не исчезает даже на мгновение
            for old in previous where old.id != fresh.id {
                Task { await old.end(nil, dismissalPolicy: .immediate) }
            }
        } else if liveActivity() != nil {
            // Создать новую не вышло (например, приложение в фоне): хотя бы свежий кадр в прежнюю
            submit(state: state, force: true)
        }
    }

    private func submit(state: NetPulseAttributes.ContentState, force: Bool) {
        lastSubmittedState = state

        guard areActivitiesEnabled else {
            isLiveActivityActive = false
            return
        }

        // Зависшая отправка забывается и тогда, когда новых видимых изменений нет
        pipeline.pump()

        guard let activity = liveActivity() else {
            isLiveActivityActive = false
            if UIApplication.shared.applicationState != .background {
                if canAttemptStart {
                    requestNewActivity(state: state, reason: "остров пропал, приложение на экране")
                }
            } else {
                noteMissingInBackground()
            }
            return
        }

        currentActivity = activity
        isLiveActivityActive = true

        // Защита от перегрева и лишних обращений к системе: если видимые значения не менялись и с прошлой
        // отправки прошло меньше 2,5 секунды — кадр пропускается
        if !force, let last = lastRenderedState, !Self.hasVisibleChange(from: last, to: state) {
            if let renderedAt = lastRenderedAt, Date().timeIntervalSince(renderedAt) < Self.unchangedResendInterval {
                return
            }
        }

        pipeline.submit(state, send: makeSender(for: activity))
    }

    private func makeSender(for activity: Activity<NetPulseAttributes>) -> IslandUpdatePipeline<NetPulseAttributes.ContentState>.Sender {
        return { state in
            // staleDate продлевается с каждым кадром: если кадры прекратятся, iOS сама пометит остров устаревшим.
            // Метка времени кадра нужна, чтобы устаревший остров показывал «данные N назад»
            var stamped = state
            stamped.updatedAt = Date()
            let content = ActivityContent(
                state: stamped,
                staleDate: Date().addingTimeInterval(ActivityManager.staleAfter),
                relevanceScore: ActivityManager.relevance(for: state)
            )
            await activity.update(content)
        }
    }

    private func noteMissingInBackground() {
        guard !reportedMissingInBackground else { return }
        reportedMissingInBackground = true
        IslandDiagnostics.shared.log(
            "Острова нет, а приложение в фоне: создать его можно только при открытом приложении. "
            + "Остров вернётся при следующем открытии.",
            .warning
        )
    }

    private func finishForegroundCheck(completedBefore: Int) {
        guard pipeline.stats.completed == completedBefore, let state = lastSubmittedState else { return }
        guard areActivitiesEnabled else { return }

        IslandDiagnostics.shared.log(
            "После возврата в приложение остров не обновился за \(Int(Self.foregroundCheckDelay)) с — пересоздаю его.",
            .warning
        )
        recreateActivity(with: state, reason: "остров не обновлялся после возврата в приложение")
    }

    private func monitorActivityState(_ activity: Activity<NetPulseAttributes>) {
        stateObservationTask?.cancel()
        stateObservationTask = Task { [weak self, activityId = activity.id] in
            var wasStale = false
            for await state in activity.activityStateUpdates {
                guard let self, self.currentActivity?.id == activityId else { break }

                switch state {
                case .ended, .dismissed:
                    self.handleActivityGone(dismissedByUser: state == .dismissed)
                    return
                case .stale:
                    wasStale = true
                    IslandDiagnostics.shared.log(
                        "iOS пометила остров устаревшим: обновления не приходят дольше \(Int(Self.staleAfter)) с.",
                        .warning
                    )
                    // Если приложение работает, свежий кадр уходит немедленно
                    if let latest = self.lastSubmittedState {
                        self.submit(state: latest, force: true)
                    }
                case .active:
                    if wasStale {
                        wasStale = false
                        IslandDiagnostics.shared.log("Остров снова обновляется", .island)
                    }
                @unknown default:
                    break
                }
            }
        }
    }

    private func handleActivityGone(dismissedByUser: Bool) {
        currentActivity = nil
        lastRenderedState = nil
        pipeline.reset()
        isLiveActivityActive = false
        IslandDiagnostics.shared.log(
            dismissedByUser
                ? "Остров закрыт пользователем."
                : "Остров завершён системой (например, истёк лимит 8 часов или приложение закрыли).",
            .island
        )
    }

    #endif
}
