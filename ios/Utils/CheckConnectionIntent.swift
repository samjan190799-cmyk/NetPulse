//
//  CheckConnectionIntent.swift
//  NetPulse
//
//  «Проверить связь» без открытия приложения: Siri, Команды, кнопка Action Button, кнопка в Пункте управления
//  и кнопка «Проверить» в виджетах. Проверка занимает пару секунд, итог записывается в общий журнал и в снимок
//  для виджетов. Файл входит и в приложение, и в расширение виджетов, поэтому intent работает там, где его запустила
//  система.
//

import AppIntents
import Foundation
import UserNotifications

/// Сама проверка с записью итога: общая для всех способов запуска
enum QuickCheckService {
    /// Снимок виджета после проверки: пинг, потери, тип сети и узлы берутся из проверки, а скорость, трафик и
    /// остальное остаются прежними (их знает только приложение)
    static func merged(_ result: QuickCheckResult, into old: NetPulseWidgetData) -> NetPulseWidgetData {
        let hasOldData = old.lastUpdated != .distantPast
        return NetPulseWidgetData(
            downloadSpeedMbps: old.downloadSpeedMbps,
            uploadSpeedMbps: old.uploadSpeedMbps,
            pingMs: result.medianMs,
            jitterMs: nil,
            lossPercent: result.lossPercent,
            ispName: hasOldData ? old.ispName : result.connection,
            connectionType: result.connection,
            todayTrafficBytes: old.todayTrafficBytes,
            budgetTotalBytes: old.budgetTotalBytes,
            budgetUsedBytes: old.budgetUsedBytes,
            healthScore: result.verdict.healthScore,
            dnsHosts: result.probes.map {
                WidgetDNSHost(name: $0.host.name, address: $0.host.host, latencyMs: $0.latencyMs, isOK: $0.latencyMs != nil)
            },
            lastUpdated: result.time
        )
    }

    /// Проверяет связь, записывает итог в журнал и в снимок виджета и пересчитывает утреннюю сводку.
    /// `reloadWidgets: false` — для вызова из самого виджета: перезагрузка внутри обновления виджета зациклилась бы.
    @discardableResult
    static func runAndRecord(
        reloadWidgets: Bool = true,
        connector: any QuickCheckConnecting = TCPQuickCheckConnector(),
        now: Date = Date()
    ) async -> QuickCheckResult {
        let result = await QuickCheck.run(connector: connector, now: now)
        QuickCheckLog.shared.append(result.sample)
        let snapshot = merged(result, into: WidgetDataManager.shared.loadLatestSnapshot())
        WidgetDataManager.shared.saveSnapshot(snapshot, reloadTimelines: reloadWidgets)
        await MorningSummaryScheduler.reschedule(now: now)
        return result
    }

    /// Уведомление с итогом: нужно кнопке в Пункте управления, у которой нет места для ответа.
    /// Приходит только если уведомления уже разрешены (разрешение просит экран «Настройки»).
    static func postResult(_ result: QuickCheckResult) async {
        guard await SystemNotificationScheduler().isAuthorized() else { return }
        let content = UNMutableNotificationContent()
        content.title = result.notificationTitle
        content.body = result.notificationBody
        content.sound = nil
        content.interruptionLevel = .passive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "netpulse.check.result", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// Для Siri, Команд и Action Button: проверяет и отвечает фразой
struct CheckConnectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Проверить связь"
    static let description = IntentDescription("Быстро проверяет интернет за пару секунд, не открывая приложение.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await QuickCheckService.runAndRecord()
        return .result(dialog: "\(result.spokenText)")
    }
}

/// Кнопка в Пункте управления: ответ приходит уведомлением и новыми числами в виджетах
struct ControlCheckConnectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Проверить связь"
    static let description = IntentDescription("Проверяет интернет и присылает итог уведомлением.")
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        let result = await QuickCheckService.runAndRecord()
        await QuickCheckService.postResult(result)
        return .result()
    }
}

/// Кнопка «Проверить» в виджете: ответ видно прямо в виджете, который перерисовывается
struct WidgetCheckConnectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Проверить связь"
    static let description = IntentDescription("Обновляет данные виджета быстрой проверкой связи.")
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await QuickCheckService.runAndRecord()
        return .result()
    }
}
