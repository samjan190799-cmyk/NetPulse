//
//  AINetworkAnomalyDetector.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Выявление отклонений по текущим измерениям сети.
///
/// Анализируется только текущий снимок данных: истории по часам приложение не ведёт, поэтому детектор не
/// «прогнозирует» и не называет причин, которых не измерял. Раньше он заявлял «задержка повышена на 35–60 % из-за
/// перегрузки магистральных портов провайдера» (без базового значения для сравнения), считал нормой RTT до роутера
/// не больше 6 мс и строил «прогноз исчерпания лимита» по календарному месяцу для 30-дневного окна.
public final class AINetworkAnomalyDetector: Sendable {
    public static let shared = AINetworkAnomalyDetector()

    /// Данные узла считаются свежими, если проверка была не позже этого срока, секунд
    private static let freshnessSeconds: TimeInterval = 15.0

    public init() {}

    /// Аудит текущих измерений.
    ///
    /// - Parameters:
    ///   - trafficSummary: расход за период квоты (не за период, выбранный в интерфейсе).
    ///   - budget: лимит трафика; учитывается, только если он включён.
    public func analyzeAnomalies(
        context: NetworkDiagnosticsContext,
        hostMetrics: [String: HostMetrics],
        trafficSummary: TrafficSummary?,
        budget: TrafficBudget?
    ) -> NetworkAnomalyReport {
        var anomalies: [NetworkAnomalyItem] = []
        let now = Date()

        func isFresh(_ metric: HostMetrics) -> Bool {
            guard let updated = metric.lastUpdated else { return false }
            return now.timeIntervalSince(updated) < Self.freshnessSeconds
        }

        // 1. Нестабильная связь с роутером (только Wi-Fi и только по свежим данным шлюза)
        if context.connectionType.contains("Wi-Fi"),
           let gateway = hostMetrics.values.first(where: { $0.isGateway && isFresh($0) }),
           gateway.sentCount >= 5 {
            let latency = gateway.lastLatencyMs
            let jitter = gateway.jitterMs
            let loss = gateway.lossWindowPct
            let isUnstable = loss >= 2.0 || jitter > 15.0 || (latency ?? 0) > 30.0

            if isUnstable {
                let isSevere = loss >= 10.0 || (latency ?? 0) > 100.0
                var details: [String] = []
                if let latency { details.append(String(format: "задержка %.0f мс", latency)) }
                details.append(String(format: "джиттер %.1f мс", jitter))
                details.append(String(format: "потери %.0f %%", loss))

                anomalies.append(
                    NetworkAnomalyItem(
                        type: .wifiInterference,
                        title: "Нестабильная связь с роутером",
                        description: "Соединение с роутером нестабильно: \(details.joined(separator: ", ")). Возможные причины — слабый сигнал, помехи от соседних сетей или перегруженный канал Wi-Fi; по этим данным точную причину определить нельзя.",
                        severity: isSevere ? .critical : .warning,
                        metricValue: latency.map { String(format: "%.0f мс до роутера", $0) } ?? String(format: "потери %.0f %%", loss),
                        suggestedFix: "Подойдите ближе к роутеру или перейдите на диапазон 5 ГГц; для проверки подключитесь по кабелю или к другой сети."
                    )
                )
            }
        }

        // 2. Повышенная задержка в вечерние часы — наблюдение, а не вывод о причине
        let hour = Calendar.current.component(.hour, from: now)
        if (19...23).contains(hour), context.hasLiveData, let ping = context.averagePingMs, ping > 60.0 {
            anomalies.append(
                NetworkAnomalyItem(
                    type: .eveningCongestion,
                    title: "Повышенная задержка в вечерние часы",
                    description: String(format: "Сейчас вечернее время, когда сети операторов обычно загружены сильнее, а средняя задержка — %.0f мс. Сравните с замером в другое время суток: если разница заметна, вероятная причина — загрузка сети провайдера.", ping),
                    severity: .info,
                    metricValue: String(format: "%.0f мс", ping),
                    suggestedFix: "Повторите замер утром или днём; для задач, чувствительных к задержке, используйте проводное подключение."
                )
            )
        }

        // 3. Лимит трафика (только если квота включена; расход берётся за период квоты)
        if let budget, budget.isEnabled, budget.limitBytes > 0, let summary = trafficSummary {
            let used = summary.totalTraffic
            let limit = budget.limitBytes
            let periodName = budget.period.rawValue.lowercased()

            if used >= limit {
                let overageMB = Double(used - limit) / 1_048_576.0
                anomalies.append(
                    NetworkAnomalyItem(
                        type: .budgetExhaustion,
                        title: "Лимит трафика исчерпан",
                        description: "Заданный лимит (\(String(format: "%.1f", Double(limit) / 1_073_741_824.0)) ГБ за период «\(periodName)») израсходован. Превышение: \(String(format: "%.0f", overageMB)) МБ.",
                        severity: .critical,
                        metricValue: "100 % лимита",
                        suggestedFix: "Подключите дополнительный пакет трафика у оператора или переключитесь на Wi-Fi."
                    )
                )
            } else if budget.isWarning(usedBytes: used) {
                let percent = Int((Double(used) / Double(limit) * 100.0).rounded())
                anomalies.append(
                    NetworkAnomalyItem(
                        type: .budgetExhaustion,
                        title: "Расход близок к лимиту",
                        description: "Израсходовано \(percent) % заданного лимита за период «\(periodName)» (\(String(format: "%.1f", Double(used) / 1_073_741_824.0)) из \(String(format: "%.1f", Double(limit) / 1_073_741_824.0)) ГБ).",
                        severity: percent >= 95 ? .critical : .warning,
                        metricValue: "\(percent) % лимита",
                        suggestedFix: "Ограничьте фоновые загрузки или увеличьте лимит пакета у оператора."
                    )
                )
            }
        }

        // 4. Медленный отклик или потери до публичных DNS-серверов.
        // Это задержка TCP-соединения с серверами, а не скорость разрешения имён.
        let publicDNSHosts = hostMetrics.values.filter { metric in
            guard isFresh(metric), !metric.isGateway else { return false }
            return metric.name.contains("DNS") || metric.name.contains("Cloudflare") || metric.name.contains("Google") || metric.name.contains("Quad9")
        }
        let problematicDNS = publicDNSHosts.filter { ($0.lastLatencyMs ?? 0.0) > 100.0 || $0.lossWindowPct >= 5.0 }
        if !problematicDNS.isEmpty {
            let names = problematicDNS.map { $0.name }.sorted().joined(separator: ", ")
            anomalies.append(
                NetworkAnomalyItem(
                    type: .dnsDegradation,
                    title: "Медленный отклик публичных DNS-серверов",
                    description: "Серверы отвечают медленно (дольше 100 мс) или теряют соединения: \(names). Это задержка сети до серверов, а не скорость разрешения имён; для точной проверки запустите «DNS Бенчмарк».",
                    severity: .warning,
                    metricValue: "\(problematicDNS.count) из \(publicDNSHosts.count) узлов",
                    suggestedFix: "Запустите «DNS Бенчмарк» и при необходимости выберите более быстрый сервер."
                )
            )
        }

        // 5. Потери пакетов (только при наличии свежих данных)
        if context.hasLiveData, context.packetLossPct > 0.5 {
            anomalies.append(
                NetworkAnomalyItem(
                    type: .packetLossSpike,
                    title: "Потери пакетов",
                    description: String(format: "В окне последних проверок потеряно %.1f %% пакетов. Это может вызывать фризы в играх и прерывания звука в звонках; где именно теряются пакеты, покажет трассировка.", context.packetLossPct),
                    severity: context.packetLossPct > 2.0 ? .critical : .warning,
                    metricValue: String(format: "%.1f %% потерь", context.packetLossPct),
                    suggestedFix: "Запустите трассировку, чтобы увидеть, на каком участке маршрута пропадают ответы; при необходимости подготовьте обращение провайдеру."
                )
            )
        }

        let hasCritical = anomalies.contains { $0.severity == .critical }
        let hasWarning = anomalies.contains { $0.severity == .warning }
        let overallRisk: IssueSeverity = hasCritical ? .critical : (hasWarning ? .warning : .info)

        return NetworkAnomalyReport(
            anomalies: anomalies,
            overallRiskLevel: overallRisk,
            analyzedHours: 0,
            generatedAt: now
        )
    }
}
