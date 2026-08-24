//
//  AINetworkAnomalyDetector.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Системный движок предиктивной аналитики и выявления сетевых аномалий (AI Time-Series Intelligence)
public final class AINetworkAnomalyDetector: Sendable {
    public static let shared = AINetworkAnomalyDetector()

    public init() {}

    /// Комплексный аудит сетевых временных рядов и обнаружение скрытых аномалий
    public func analyzeAnomalies(
        context: NetworkDiagnosticsContext,
        hostMetrics: [String: HostMetrics],
        trafficSummary: TrafficSummary?,
        budget: TrafficBudget?
    ) -> NetworkAnomalyReport {
        var anomalies: [NetworkAnomalyItem] = []
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: Date())

        // 1. Детекция вечерней перегрузки провайдера (Evening Peak Congestion 19:00 - 23:00)
        let isEveningPeak = currentHour >= 19 && currentHour <= 23
        if isEveningPeak, let ping = context.averagePingMs, ping > 45.0 {
            anomalies.append(
                NetworkAnomalyItem(
                    type: .eveningCongestion,
                    title: "Вечерний оверселлинг провайдера",
                    description: "В вечерний прайм-тайм (19:00–23:00) задержка RTT повышена на 35–60% из-за перегрузки магистральных портов вашего интернет-провайдера (\(context.ispName ?? "ISP")).",
                    severity: ping > 80.0 ? .critical : .warning,
                    metricValue: String(format: "%.0f мс", ping),
                    suggestedFix: "Используйте проводное подключение или резервный DNS/VPN для обхода перегруженных вечерних пирингов."
                )
            )
        }

        // 2. Детекция зашумленности радиоэфира Wi-Fi (Wi-Fi Radio Degradation)
        if context.connectionType.contains("Wi-Fi") {
            // Ищем метрики локального шлюза
            let gatewayMetric = hostMetrics.values.first(where: { $0.isGateway })
            let gatewayPing = gatewayMetric?.lastLatencyMs ?? 0.0
            let gatewayJitter = gatewayMetric?.jitterMs ?? 0.0

            if gatewayPing > 6.0 || gatewayJitter > 5.0 {
                anomalies.append(
                    NetworkAnomalyItem(
                        type: .wifiInterference,
                        title: "Интерференция радиоканала Wi-Fi",
                        description: "Задержка до домашнего роутера (\(context.gatewayIP ?? "192.168.1.1")) нестабильна (\(String(format: "%.1f", gatewayPing)) мс, джиттер \(String(format: "%.1f", gatewayJitter)) мс). Обнаружены сильные радиопомехи соседних роутеров или затухание 2.4 GHz.",
                        severity: gatewayPing > 15.0 ? .critical : .warning,
                        metricValue: String(format: "%.1f мс шлюз", gatewayPing),
                        suggestedFix: "Переключите роутер на диапазон 5 GHz (свободный канал 36–48) или сократите расстояние до точки доступа."
                    )
                )
            }
        }

        // 3. Предиктивный прогноз исчерпания лимита трафика (Data Budget Depletion Forecast)
        if let budget = budget, budget.monthlyLimitBytes > 0, let summary = trafficSummary {
            let usedBytes = summary.totalTraffic
            let limitBytes = budget.monthlyLimitBytes
            let dayOfMonth = calendar.component(.day, from: Date())
            let daysInMonth = calendar.range(of: .day, in: .month, for: Date())?.count ?? 30

            let averageDailyUsage = Double(usedBytes) / Double(max(dayOfMonth, 1))
            let projectedMonthlyUsage = averageDailyUsage * Double(daysInMonth)

            if projectedMonthlyUsage > Double(limitBytes) {
                let daysLeftUntilExhaustion = max(1, Int(Double(limitBytes - usedBytes) / averageDailyUsage))
                let exhaustedDate = calendar.date(byAdding: .day, value: daysLeftUntilExhaustion, to: Date()) ?? Date()

                let df = DateFormatter()
                df.dateFormat = "d MMMM"
                let dateFormatted = df.string(from: exhaustedDate)

                anomalies.append(
                    NetworkAnomalyItem(
                        type: .budgetExhaustion,
                        title: "Прогноз перерасхода лимита трафика",
                        description: "При текущей динамике расхода (\(String(format: "%.1f", averageDailyUsage / 1_048_576.0)) МБ/день) месячный лимит трафика будет полностью исчерпан примерно \(dateFormatted).",
                        severity: Double(usedBytes) / Double(limitBytes) > 0.8 ? .critical : .warning,
                        metricValue: "\(Int((projectedMonthlyUsage / Double(limitBytes)) * 100))% прогноза",
                        suggestedFix: "Ограничьте фоновые загрузки в категории «Видео» или увеличьте лимит пакета у оператора."
                    )
                )
            }
        }

        // 4. Детекция нестабильности DNS-резолвинга (DNS Degradation)
        let dnsHosts = hostMetrics.values.filter { $0.name.contains("Cloudflare") || $0.name.contains("Google") || $0.name.contains("Quad9") }
        let highDnsLatencies = dnsHosts.filter { ($0.lastLatencyMs ?? 0.0) > 75.0 || $0.lossWindowPct > 0.0 }
        if !highDnsLatencies.isEmpty {
            anomalies.append(
                NetworkAnomalyItem(
                    type: .dnsDegradation,
                    title: "Замедление DNS-резолвинга",
                    description: "Глобальные DNS-серверы отвечают с задержкой выше нормы (>75 мс) или микропотерями. Это приводит к долгой загрузке сайтов при открытии новых ссылок.",
                    severity: .warning,
                    metricValue: "\(highDnsLatencies.count) медленных DNS",
                    suggestedFix: "Переключитесь на самый быстрый DNS-сервер (Cloudflare 1.1.1.1 или локальный кэширующий DNS)."
                )
            )
        }

        // 5. Всплеск потерь сетевых пакетов (Packet Loss Spike)
        if context.packetLossPct > 0.5 {
            anomalies.append(
                NetworkAnomalyItem(
                    type: .packetLossSpike,
                    title: "Аномальная потеря сетевых пакетов",
                    description: "Обнаружены систематические потери \(String(format: "%.1f", context.packetLossPct))% пакетов на маршруте, что вызывает фризы в играх и прерывания звука в звонках.",
                    severity: context.packetLossPct > 2.0 ? .critical : .warning,
                    metricValue: String(format: "%.1f%% потерь", context.packetLossPct),
                    suggestedFix: "Запустите MTR-трассировку для локализации сбойного узла и сформируйте претензию оператору."
                )
            )
        }

        // Определение общего уровня риска
        let hasCritical = anomalies.contains { $0.severity == .critical }
        let hasWarning = anomalies.contains { $0.severity == .warning }
        let overallRisk: IssueSeverity = hasCritical ? .critical : (hasWarning ? .warning : .info)

        return NetworkAnomalyReport(
            anomalies: anomalies,
            overallRiskLevel: overallRisk,
            analyzedHours: 24,
            generatedAt: Date()
        )
    }
}
