//
//  MetricsReporter.swift
//  NetPulse
//
//  Принимает от системы (MetricKit) отчёты о сбоях, зависаниях и причинах закрытия приложения и записывает краткую
//  сводку в журнал «Диагностика острова». Отчёты приходят не сразу, а при одном из следующих запусков (обычно в течение
//  суток). Данные остаются на устройстве и никуда не отправляются.
//

import Foundation
import MetricKit

final class MetricsReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricsReporter()

    private override init() {
        super.init()
    }

    /// Подписка на системные отчёты; вызывается один раз при запуске приложения
    @MainActor
    func start() {
        MXMetricManager.shared.add(self)
    }

    // MARK: - Суточные показатели

    func didReceive(_ payloads: [MXMetricPayload]) {
        var lines: [String] = []
        for payload in payloads {
            if let exits = payload.applicationExitMetrics?.foregroundExitData {
                lines.append(
                    "закрытия на экране за сутки: штатных \(exits.cumulativeNormalAppExitCount), "
                        + "по памяти \(exits.cumulativeMemoryResourceLimitExitCount), "
                        + "зависание (watchdog) \(exits.cumulativeAppWatchdogExitCount), "
                        + "аварийных \(exits.cumulativeAbnormalExitCount), "
                        + "ошибок доступа к памяти \(exits.cumulativeBadAccessExitCount)"
                )
            }
            if let memory = payload.memoryMetrics {
                let peak = Int(memory.peakMemoryUsage.converted(to: .megabytes).value.rounded())
                lines.append("пик памяти за сутки: \(peak) МБ")
            }
        }
        post(lines, kind: .info)
    }

    // MARK: - Сбои и зависания

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var lines: [String] = []
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                let signal = crash.signal.map { "\($0.intValue)" } ?? "—"
                let type = crash.exceptionType.map { "\($0.intValue)" } ?? "—"
                lines.append("сбой приложения: сигнал \(signal), тип исключения \(type), причина «\(crash.terminationReason ?? "—")», версия \(crash.applicationVersion)")
            }
            for hang in payload.hangDiagnostics ?? [] {
                let seconds = hang.hangDuration.converted(to: .seconds).value
                lines.append(String(format: "зависание интерфейса на %.1f с", seconds))
            }
            for cpu in payload.cpuExceptionDiagnostics ?? [] {
                let used = cpu.totalCPUTime.converted(to: .seconds).value
                let sampled = cpu.totalSampledTime.converted(to: .seconds).value
                lines.append(String(format: "слишком высокая загрузка процессора: %.0f с работы за %.0f с наблюдения", used, sampled))
            }
        }
        post(lines, kind: .error)
    }

    private func post(_ lines: [String], kind: IslandDiagnostics.Kind) {
        guard !lines.isEmpty else { return }
        Task { @MainActor in
            for line in lines {
                IslandDiagnostics.shared.log("Системный отчёт: \(line)", kind)
            }
        }
    }
}
