//
//  AIDiagnosticsEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Системный движок для сетевой диагностики: оценка здоровья сети, мастер траблшутинга, агент с инструментами
/// и встроенный AI: он работает на устройстве и ничего никуда не отправляет.
///
/// Принцип: все выводы строятся по реальным измерениям. Если данных нет, движок говорит об этом, а не подставляет
/// «нормальные» значения (раньше при отсутствии данных отчёт сообщал «Идеальное качество сети», а мастер
/// траблшутинга «выполнял» шаги с эмуляцией задержки и одним и тем же вердиктом для всех сценариев).
public final class AIDiagnosticsEngine: Sendable {
    public static let shared = AIDiagnosticsEngine()

    private let pingEngine = PingEngine(timeout: 2.0)
    private let tracerouteEngine = TracerouteEngine()

    public init() {}

    // MARK: - 1. Отчет здоровья сети (Health Assessment)

    public func evaluateNetworkHealth(context: NetworkDiagnosticsContext) -> NetworkHealthReport {
        let isWifi = context.connectionType.contains("Wi-Fi")
        let download = context.speedtestDownloadMbps.flatMap { $0 > 0 ? $0 : nil }
        let upload = context.measuredUploadMbps

        // Данных нет совсем: ни свежих проверок, ни замера скорости
        guard context.hasLiveData || download != nil else {
            return NetworkHealthReport(
                overallScore: nil,
                gamingScore: nil,
                streamingScore: nil,
                videoCallScore: nil,
                webBrowsingScore: nil,
                statusTitle: "Недостаточно данных",
                summaryText: "Оценить сеть пока нечем: нет свежих результатов мониторинга и замера скорости. Включите мониторинг на главном экране и запустите замер скорости.",
                identifiedIssues: [],
                recommendations: [
                    NetworkRecommendation(
                        icon: "play.circle.fill",
                        title: "Запустите мониторинг и замер скорости",
                        detail: "Оценка строится по пингу, джиттеру, потерям пакетов и скорости. Пока их нет, индекс здоровья не рассчитывается.",
                        actionType: .general
                    )
                ]
            )
        }

        // Мониторинг идёт, но ни один узел не отвечает — это отсутствие связи, а не «идеальное качество»
        if context.hasLiveData && context.averagePingMs == nil {
            return NetworkHealthReport(
                overallScore: 10,
                gamingScore: 10,
                streamingScore: 10,
                videoCallScore: 10,
                webBrowsingScore: 10,
                statusTitle: "Нет связи с проверяемыми узлами",
                summaryText: "Ни один из проверяемых узлов не отвечает. Проверьте подключение к интернету, Wi-Fi или мобильную сеть.",
                identifiedIssues: [
                    NetworkIssue(
                        severity: .critical,
                        title: "Узлы не отвечают",
                        description: "Все проверки последних секунд завершились без ответа.",
                        component: "Подключение к сети"
                    )
                ],
                recommendations: [
                    NetworkRecommendation(
                        icon: isWifi ? "arrow.counterclockwise.circle.fill" : "airplane.circle.fill",
                        title: isWifi ? "Проверьте роутер и кабель провайдера" : "Переподключитесь к сети",
                        detail: isWifi
                            ? "Если другие устройства тоже без интернета, перезагрузите роутер или обратитесь к провайдеру."
                            : "Включите и выключите авиарежим на несколько секунд либо смените место приёма.",
                        actionType: .restartRouter
                    )
                ]
            )
        }

        let ping: Double? = context.hasLiveData ? context.averagePingMs : nil
        let jitter: Double? = context.hasLiveData ? context.jitterMs : nil
        let loss: Double? = context.hasLiveData ? context.packetLossPct : nil

        // Индексы считаются только по тем показателям, которые измерены
        var gamingScore: Int?
        var videoCallScore: Int?
        var webScore: Int?
        var streamingScore: Int?

        if let ping {
            var gaming = 100.0
            if ping > 120 { gaming -= 50 } else if ping > 60 { gaming -= 25 } else if ping > 35 { gaming -= 10 }
            if let jitter {
                if jitter > 25 { gaming -= 30 } else if jitter > 10 { gaming -= 15 }
            }
            if let loss {
                if loss > 5.0 { gaming -= 40 } else if loss > 0.5 { gaming -= 20 }
            }
            gamingScore = max(min(Int(gaming), 100), 10)

            var videoCall = 100.0
            if ping > 80 { videoCall -= 35 }
            if let jitter, jitter > 15 { videoCall -= 30 }
            if let loss, loss > 1.0 { videoCall -= 25 }
            if let upload {
                if upload < 2.0 { videoCall -= 40 } else if upload < 5.0 { videoCall -= 20 }
            }
            videoCallScore = max(min(Int(videoCall), 100), 15)

            var web = 100.0
            if ping > 150 { web -= 30 }
            if let loss, loss > 3.0 { web -= 30 }
            webScore = max(min(Int(web), 100), 20)
        }

        // Стриминг зависит от пропускной способности: нужен замер скорости (текущий трафик устройства — не ёмкость канала)
        if let download {
            var streaming = 100.0
            if download < 5.0 { streaming -= 70 } else if download < 15.0 { streaming -= 40 } else if download < 30.0 { streaming -= 15 }
            if let loss, loss > 2.0 { streaming -= 20 }
            streamingScore = max(min(Int(streaming), 100), 15)
        }

        // Общий индекс — средневзвешенное по доступным категориям (нужно не меньше двух)
        let weighted: [(score: Int, weight: Double)] = [
            (gamingScore, 0.35), (streamingScore, 0.25), (videoCallScore, 0.25), (webScore, 0.15)
        ].compactMap { item in item.0.map { (score: $0, weight: item.1) } }

        var overallScore: Int?
        if weighted.count >= 2 {
            let totalWeight = weighted.reduce(0.0) { $0 + $1.weight }
            let sum = weighted.reduce(0.0) { $0 + Double($1.score) * $1.weight }
            overallScore = Int((sum / totalWeight).rounded())
        }

        // Статус и пояснение
        var missingParts: [String] = []
        if !context.hasLiveData { missingParts.append("мониторинг сети") }
        if download == nil { missingParts.append("замер скорости") }
        let missingNote = missingParts.isEmpty ? "" : " Не хватает данных: " + missingParts.joined(separator: ", ") + " — часть индексов не рассчитана."

        let statusTitle: String
        let summaryText: String
        if let overall = overallScore {
            let facts = Self.factsLine(ping: ping, jitter: jitter, loss: loss)
            if overall >= 85 {
                statusTitle = "Отличное качество сети"
                summaryText = "Показатели в норме: \(facts)." + missingNote
            } else if overall >= 65 {
                statusTitle = "Хорошая стабильность"
                summaryText = "Соединение пригодно для большинства повседневных задач: \(facts). Заметных проблем нет, но есть небольшие отклонения." + missingNote
            } else if overall >= 45 {
                statusTitle = "Умеренная нестабильность"
                summaryText = "Есть отклонения (\(facts)). В играх возможны фризы, а в видеозвонках — рассинхронизация звука." + missingNote
            } else {
                statusTitle = "Критическое состояние соединения"
                summaryText = "Показатели плохие (\(facts)). Подробности — в списке проблем ниже." + missingNote
            }
        } else {
            statusTitle = "Недостаточно данных для общей оценки"
            summaryText = "Есть только часть измерений, общий индекс не рассчитан." + missingNote
        }

        // Проблемы и рекомендации — только по измеренным значениям
        var issues: [NetworkIssue] = []
        var recommendations: [NetworkRecommendation] = []

        if let loss, loss > 0.5 {
            issues.append(NetworkIssue(
                severity: loss > 3.0 ? .critical : .warning,
                title: "Потеря сетевых пакетов (\(String(format: "%.1f", loss))%)",
                description: "Часть проверок до публичных узлов остаётся без ответа. Источник потерь (Wi-Fi, провайдер, удалённый узел) определит трассировка.",
                component: "Сеть (источник уточняет трассировка)"
            ))
            recommendations.append(NetworkRecommendation(
                icon: isWifi ? "arrow.counterclockwise.circle.fill" : "airplane.circle.fill",
                title: isWifi ? "Перезагрузка роутера" : "Переподключение к сети (авиарежим)",
                detail: isWifi
                    ? "Иногда помогает при сбоях NAT и перегруженном канале Wi-Fi. Если потери остались, запустите трассировку."
                    : "Включите и выключите авиарежим на 5 секунд — устройство может подключиться к менее загруженной вышке.",
                actionType: .restartRouter
            ))
        }

        if let jitter, jitter > 12.0 {
            issues.append(NetworkIssue(
                severity: .warning,
                title: "Высокий джиттер (\(String(format: "%.1f", jitter)) мс)",
                description: "Неравномерная задержка вызывает микрофризы в играх и прерывания звука в звонках.",
                component: "Канал связи"
            ))
            if isWifi {
                recommendations.append(NetworkRecommendation(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Диапазон 5 ГГц и меньшее расстояние до роутера",
                    detail: "Диапазон 2.4 ГГц чаще подвержен помехам от соседних сетей и Bluetooth.",
                    actionType: .switchBand
                ))
            }
        }

        if let ping, ping > 70.0 {
            issues.append(NetworkIssue(
                severity: ping > 120.0 ? .critical : .warning,
                title: "Повышенная задержка (\(Int(ping)) мс)",
                description: "Задержка до проверяемых узлов выше обычной. Причиной может быть Wi-Fi, провайдер или удалённость узлов.",
                component: "Сеть (источник уточняет мастер траблшутинга)"
            ))
            recommendations.append(NetworkRecommendation(
                icon: "network",
                title: "Найдите, где возникает задержка",
                detail: "Запустите мастер траблшутинга (сценарий «Wi-Fi помехи»): он сравнит задержку до роутера и до интернета.",
                actionType: .general
            ))
        }

        if recommendations.isEmpty {
            recommendations.append(NetworkRecommendation(
                icon: "checkmark.seal.fill",
                title: overallScore == nil ? "Дополните данные" : "Сеть работает штатно",
                detail: overallScore == nil
                    ? "Запустите мониторинг и замер скорости, чтобы получить полную оценку."
                    : "По измеренным показателям проблем не выявлено.",
                actionType: .general
            ))
        }

        return NetworkHealthReport(
            overallScore: overallScore,
            gamingScore: gamingScore,
            streamingScore: streamingScore,
            videoCallScore: videoCallScore,
            webBrowsingScore: webScore,
            statusTitle: statusTitle,
            summaryText: summaryText,
            identifiedIssues: issues,
            recommendations: recommendations,
            timestamp: Date()
        )
    }

    private static func factsLine(ping: Double?, jitter: Double?, loss: Double?) -> String {
        var parts: [String] = []
        if let ping { parts.append("пинг \(Int(ping)) мс") }
        if let jitter { parts.append("джиттер \(String(format: "%.1f", jitter)) мс") }
        if let loss { parts.append("потери \(String(format: "%.1f", loss)) %") }
        return parts.isEmpty ? "данных мониторинга нет" : parts.joined(separator: ", ")
    }

    // MARK: - 2. Мгновенный вердикт после замера скорости

    public func generateSpeedtestSummary(
        downloadMbps: Double,
        uploadMbps: Double,
        pingMs: Double?,
        jitterMs: Double?,
        packetLossPct: Double
    ) -> String {
        let download = String(format: "%.0f", downloadMbps)
        // 0 означает «не измерено» (отдачу измерить не удалось) — такое значение не показывается
        let uploadPart = uploadMbps > 0 ? ", отдача \(String(format: "%.0f", uploadMbps)) Мбит/с" : ", отдачу измерить не удалось"
        let pingPart = pingMs.map { ", пинг \(Int($0)) мс" } ?? ""

        if packetLossPct > 1.0 {
            return "⚠️ Обнаружена потеря пакетов (\(String(format: "%.1f", packetLossPct))%). Скорость \(download) Мбит/с\(uploadPart), но в онлайн-играх и звонках возможны задержки."
        }

        if downloadMbps >= 250.0, let ping = pingMs, ping <= 30.0, (jitterMs ?? 0) <= 4.0 {
            return "✨ Очень быстрое соединение (\(download) Мбит/с\(pingPart)). Скорости хватит для 4K-видео и быстрой загрузки больших файлов."
        } else if downloadMbps >= 70.0 {
            return "⚡ Высокая скорость (\(download) Мбит/с\(uploadPart)\(pingPart)). Хватает для 4K-стриминга."
        } else if downloadMbps >= 25.0 {
            return "📶 Достаточная скорость (\(download) Мбит/с\(pingPart)). Подходит для Full HD и 4K-видео в одном потоке, видеозвонков и веб-серфинга."
        } else if downloadMbps >= 10.0 {
            return "📶 Скорость умеренная (\(download) Мбит/с\(pingPart)). Для Full HD достаточно, для 4K может не хватать."
        } else {
            return "⚠️ Низкая скорость (\(String(format: "%.1f", downloadMbps)) Мбит/с). Попробуйте подойти ближе к роутеру или повторить замер позже."
        }
    }

    // MARK: - 3. Мастер траблшутинга: шаги с реальными измерениями

    /// Что проверяет каждый шаг. Один и тот же вердикт для разных шагов (как было раньше) невозможен:
    /// у каждой проверки своя логика и свои данные.
    private enum WizardCheck {
        case gatewayRTT
        case jitter(warn: Double, crit: Double)
        case packetLoss(warn: Double, crit: Double)
        case bufferbloatNotMeasured
        case uploadSpeed
        case downloadSpeed
        case dnsResponse
        case internetLatency
        case wifiBandNotAvailable
        case radioStability
        case latencyLocation
    }

    private struct WizardStepPlan {
        let title: String
        let subtitle: String
        let icon: String
        let check: WizardCheck
    }

    private struct LatencyStats: Sendable {
        let medianMs: Double?
        let jitterMs: Double?
        let lossPct: Double
        let answeredCount: Int
    }

    private func wizardPlan(for scenario: TroubleshootingScenarioType, context: NetworkDiagnosticsContext) -> [WizardStepPlan] {
        switch scenario {
        case .gaming:
            return [
                WizardStepPlan(title: "Задержка до роутера (LAN RTT)", subtitle: "Отклик домашней точки доступа", icon: "wifi", check: .gatewayRTT),
                WizardStepPlan(title: "Джиттер и микрофризы", subtitle: "Стабильность задержки по данным мониторинга (RFC 3550)", icon: "waveform.path.ecg", check: .jitter(warn: 5, crit: 15)),
                WizardStepPlan(title: "Потери пакетов до публичных узлов", subtitle: "Данные мониторинга за последние проверки", icon: "gamecontroller.fill", check: .packetLoss(warn: 0, crit: 1.5)),
                WizardStepPlan(title: "Задержка под нагрузкой (Bufferbloat)", subtitle: "Измеряется отдельным тестом", icon: "gauge.with.dots.needle.67percent", check: .bufferbloatNotMeasured)
            ]
        case .videoCalls:
            return [
                WizardStepPlan(title: "Скорость отдачи (Upload)", subtitle: "Исходящий канал для HD-видео, по замеру скорости", icon: "arrow.up.circle.fill", check: .uploadSpeed),
                WizardStepPlan(title: "Потери пакетов до публичных узлов", subtitle: "Данные мониторинга: потери слышны в звонках как «роботизация»", icon: "mic.fill", check: .packetLoss(warn: 0.5, crit: 2.0)),
                WizardStepPlan(title: "Скорость ответа DNS", subtitle: "Реальные DNS-запросы к 1.1.1.1 и 8.8.8.8", icon: "globe", check: .dnsResponse),
                WizardStepPlan(title: "Джиттер", subtitle: "Плавность поступления пакетов по данным мониторинга", icon: "waveform.path", check: .jitter(warn: 10, crit: 20))
            ]
        case .streaming4K:
            return [
                WizardStepPlan(title: "Скорость входящего канала (Download)", subtitle: "Для 4K нужно около 25 Мбит/с на поток; по замеру скорости", icon: "arrow.down.circle.fill", check: .downloadSpeed),
                WizardStepPlan(title: "Задержка до публичных узлов", subtitle: "Время отклика Cloudflare и Google", icon: "play.tv.fill", check: .internetLatency),
                WizardStepPlan(title: "Потери пакетов", subtitle: "Данные мониторинга: потери ведут к буферизации видео", icon: "sparkles.tv.fill", check: .packetLoss(warn: 0.5, crit: 2.0)),
                WizardStepPlan(title: "Скорость ответа DNS", subtitle: "Реальные DNS-запросы к 1.1.1.1 и 8.8.8.8", icon: "network", check: .dnsResponse)
            ]
        case .wifiInterference:
            return [
                WizardStepPlan(title: "Отклик роутера", subtitle: "Замер задержки до шлюза сети", icon: "wifi", check: .gatewayRTT),
                WizardStepPlan(title: "Диапазон частот (2.4 vs 5/6 ГГц)", subtitle: "iOS не сообщает приложениям диапазон Wi-Fi", icon: "antenna.radiowaves.left.and.right", check: .wifiBandNotAvailable),
                WizardStepPlan(title: "Стабильность радиоканала", subtitle: "Джиттер и потери при обмене с роутером", icon: "waveform.path.badge.plus", check: .radioStability),
                WizardStepPlan(title: "Где возникает задержка", subtitle: "Сравнение задержки до роутера и до интернета", icon: "square.stack.3d.up.fill", check: .latencyLocation)
            ]
        }
    }

    public func runTroubleshootingWizard(
        scenario: TroubleshootingScenarioType,
        context: NetworkDiagnosticsContext,
        hostMetrics: [String: HostMetrics],
        onStepUpdate: @escaping @Sendable (TroubleshootingStep) -> Void
    ) async -> TroubleshootingReport {
        let plan = wizardPlan(for: scenario, context: context)
        var steps: [TroubleshootingStep] = plan.enumerated().map { index, item in
            TroubleshootingStep(order: index + 1, title: item.title, subtitle: item.subtitle, status: .pending, icon: item.icon)
        }

        // Общие измерения выполняются один раз за запуск и используются в нескольких шагах
        var gatewayStats: LatencyStats?
        var internetStats: LatencyStats?
        var dnsBestMs: Double?
        var dnsMeasured = false
        var internetMeasured = false
        var gatewayMeasured = false

        let isLocalNetwork = context.connectionType.contains("Wi-Fi") || context.connectionType.contains("Ethernet")

        func measureGatewayIfNeeded() async {
            guard !gatewayMeasured else { return }
            gatewayMeasured = true
            guard isLocalNetwork, let gateway = context.gatewayIP, !gateway.isEmpty else { return }
            gatewayStats = await measureLatency(
                target: HostTarget(name: "Роутер", address: gateway, tcpPort: 53, isGateway: true),
                samples: 5
            )
        }

        func measureInternetIfNeeded() async -> LatencyStats {
            if internetMeasured, let cached = internetStats { return cached }
            internetMeasured = true
            let cloudflare = await measureLatency(target: HostTarget(name: "Cloudflare", address: "1.1.1.1"), samples: 4)
            let google = await measureLatency(target: HostTarget(name: "Google", address: "8.8.8.8"), samples: 4)
            let medians = [cloudflare.medianMs, google.medianMs].compactMap { $0 }
            let answered = cloudflare.answeredCount + google.answeredCount
            let total = 8
            let stats = LatencyStats(
                medianMs: medians.isEmpty ? nil : medians.reduce(0, +) / Double(medians.count),
                jitterMs: [cloudflare.jitterMs, google.jitterMs].compactMap { $0 }.max(),
                lossPct: Double(total - answered) / Double(total) * 100.0,
                answeredCount: answered
            )
            internetStats = stats
            return stats
        }

        func measureDNSIfNeeded() async {
            guard !dnsMeasured else { return }
            dnsMeasured = true
            let providers = DNSProviderInfo.defaultCatalog.filter { ["1.1.1.1", "8.8.8.8"].contains($0.primaryIPv4) }
            let results = await DNSBenchmarkEngine.shared.runBenchmark(providers: providers)
            dnsBestMs = results.filter { $0.isReachable }.compactMap { $0.latencyMs }.min()
        }

        for index in 0..<steps.count {
            steps[index].status = .running
            onStepUpdate(steps[index])

            let outcome: (TroubleshootingStepStatus, String)

            switch plan[index].check {
            case .gatewayRTT:
                await measureGatewayIfNeeded()
                if !isLocalNetwork {
                    outcome = (.skipped, "Роутер доступен только при подключении по Wi-Fi или Ethernet; на мобильной сети этот шаг не применяется.")
                } else if context.gatewayIP == nil {
                    outcome = (.skipped, "Система не сообщила адрес роутера.")
                } else if let median = gatewayStats?.medianMs {
                    let lossText = (gatewayStats?.lossPct ?? 0) > 0 ? ", потери \(Int(gatewayStats?.lossPct ?? 0))%" : ""
                    if median > 100 {
                        outcome = (.critical, "Отклик роутера \(Int(median)) мс\(lossText) — очень высокий: слабый сигнал или перегруженный канал Wi-Fi.")
                    } else if median > 30 {
                        outcome = (.warning, "Повышенный отклик роутера: \(Int(median)) мс\(lossText). Возможны слабый сигнал или помехи.")
                    } else {
                        outcome = (.success, "Отклик роутера \(String(format: "%.1f", median)) мс\(lossText) — в норме.")
                    }
                } else {
                    outcome = (.skipped, "Роутер не ответил на проверку (порт 53). Часть роутеров не отвечает на такие соединения, поэтому вывод сделать нельзя.")
                }

            case .jitter(let warn, let crit):
                if !context.hasLiveData || context.jitterMs == nil {
                    outcome = (.skipped, "Нет свежих данных мониторинга: включите мониторинг сети.")
                } else if let jitter = context.jitterMs {
                    if jitter > crit {
                        outcome = (.critical, "Высокий джиттер: \(String(format: "%.1f", jitter)) мс. Возможны микрофризы и прерывания звука.")
                    } else if jitter > warn {
                        outcome = (.warning, "Заметный разброс задержки: \(String(format: "%.1f", jitter)) мс.")
                    } else {
                        outcome = (.success, "Джиттер \(String(format: "%.1f", jitter)) мс — в норме.")
                    }
                } else {
                    outcome = (.skipped, "Нет данных.")
                }

            case .packetLoss(let warn, let crit):
                if !context.hasLiveData {
                    outcome = (.skipped, "Нет свежих данных мониторинга: включите мониторинг сети.")
                } else if context.packetLossPct > crit {
                    outcome = (.critical, "Потери пакетов \(String(format: "%.1f", context.packetLossPct))% — сеть теряет заметную часть пакетов.")
                } else if context.packetLossPct > warn {
                    outcome = (.warning, "Потери пакетов \(String(format: "%.1f", context.packetLossPct))% в окне последних проверок.")
                } else {
                    outcome = (.success, "Потерь в окне последних проверок не зафиксировано.")
                }

            case .bufferbloatNotMeasured:
                outcome = (.skipped, "Задержка под нагрузкой здесь не измеряется. Запустите «Bufferbloat Тест» на вкладке «Инструменты».")

            case .uploadSpeed:
                if let upload = context.measuredUploadMbps {
                    if upload < 2.0 {
                        outcome = (.critical, "Скорость отдачи \(String(format: "%.1f", upload)) Мбит/с — мало для видеозвонков.")
                    } else if upload < 5.0 {
                        outcome = (.warning, "Скорость отдачи \(String(format: "%.1f", upload)) Мбит/с — хватает для 720p, для HD может быть мало.")
                    } else {
                        outcome = (.success, "Скорость отдачи \(String(format: "%.1f", upload)) Мбит/с — достаточно для HD-видео.")
                    }
                } else {
                    outcome = (.skipped, "Скорость отдачи не измерена: запустите замер скорости на главном экране.")
                }

            case .downloadSpeed:
                if let download = context.speedtestDownloadMbps, download > 0 {
                    if download < 10.0 {
                        outcome = (.critical, "Скорость загрузки \(String(format: "%.1f", download)) Мбит/с — мало даже для Full HD без пауз.")
                    } else if download < 25.0 {
                        outcome = (.warning, "Скорость загрузки \(String(format: "%.1f", download)) Мбит/с — для 4K обычно рекомендуют около 25 Мбит/с на поток.")
                    } else {
                        outcome = (.success, "Скорость загрузки \(String(format: "%.1f", download)) Мбит/с — достаточно для 4K.")
                    }
                } else {
                    outcome = (.skipped, "Скорость загрузки не измерена: запустите замер скорости на главном экране.")
                }

            case .dnsResponse:
                await measureDNSIfNeeded()
                if let best = dnsBestMs {
                    if best > 150 {
                        outcome = (.warning, "Публичные DNS отвечают медленно: лучший результат \(Int(best)) мс.")
                    } else {
                        outcome = (.success, "Публичные DNS отвечают быстро: лучший результат \(String(format: "%.1f", best)) мс.")
                    }
                } else {
                    outcome = (.skipped, "Публичные DNS (1.1.1.1, 8.8.8.8) не ответили: возможно, сеть блокирует сторонние DNS-запросы. Это не означает, что DNS вашего провайдера не работает.")
                }

            case .internetLatency:
                let stats = await measureInternetIfNeeded()
                if let median = stats.medianMs {
                    if median > 150 {
                        outcome = (.critical, "Задержка до публичных узлов \(Int(median)) мс — очень высокая.")
                    } else if median > 80 {
                        outcome = (.warning, "Повышенная задержка до публичных узлов: \(Int(median)) мс.")
                    } else {
                        outcome = (.success, "Задержка до публичных узлов \(String(format: "%.1f", median)) мс — в норме.")
                    }
                } else {
                    outcome = (.critical, "Публичные узлы (Cloudflare, Google) не отвечают: похоже, нет доступа в интернет.")
                }

            case .wifiBandNotAvailable:
                outcome = (.skipped, "iOS не сообщает приложениям диапазон и канал Wi-Fi. Посмотрите их в настройках роутера и по возможности используйте 5 ГГц.")

            case .radioStability:
                await measureGatewayIfNeeded()
                if let stats = gatewayStats, stats.medianMs != nil {
                    let jitter = stats.jitterMs ?? 0
                    if jitter > 15 || stats.lossPct >= 5 {
                        outcome = (.critical, "Нестабильный обмен с роутером: джиттер \(String(format: "%.1f", jitter)) мс, потери \(Int(stats.lossPct))%.")
                    } else if jitter > 5 || stats.lossPct > 0 {
                        outcome = (.warning, "Небольшие колебания: джиттер \(String(format: "%.1f", jitter)) мс, потери \(Int(stats.lossPct))%.")
                    } else {
                        outcome = (.success, "Обмен с роутером стабилен: джиттер \(String(format: "%.1f", jitter)) мс, потерь нет.")
                    }
                } else {
                    outcome = (.skipped, "Нет данных об обмене с роутером (мобильная сеть, адрес шлюза неизвестен или роутер не отвечает на проверку).")
                }

            case .latencyLocation:
                await measureGatewayIfNeeded()
                let internet = await measureInternetIfNeeded()
                if let gateway = gatewayStats?.medianMs, let web = internet.medianMs {
                    if gateway > 30 {
                        outcome = (.warning, "Основная часть задержки возникает в Wi-Fi или роутере: до роутера \(Int(gateway)) мс, до интернета \(Int(web)) мс.")
                    } else if web > 80 && gateway <= 15 {
                        outcome = (.warning, "Wi-Fi в порядке (до роутера \(String(format: "%.1f", gateway)) мс), а до интернета \(Int(web)) мс: задержка возникает дальше — у провайдера или на маршруте.")
                    } else {
                        outcome = (.success, "Задержка распределена нормально: до роутера \(String(format: "%.1f", gateway)) мс, до интернета \(Int(web)) мс.")
                    }
                } else {
                    outcome = (.skipped, "Для сравнения нужны замеры и до роутера, и до интернета; одного из них нет.")
                }
            }

            steps[index].status = outcome.0
            steps[index].resultDetail = outcome.1
            onStepUpdate(steps[index])
        }

        // План действий строится по шагам, которые выявили отклонения
        var actionPlan: [String] = []
        func addAction(_ text: String) {
            if !actionPlan.contains(text) { actionPlan.append(text) }
        }

        for (index, step) in steps.enumerated() where step.status == .warning || step.status == .critical {
            switch plan[index].check {
            case .gatewayRTT, .radioStability:
                addAction("Подойдите ближе к роутеру, по возможности переключитесь на диапазон 5 ГГц; если не помогает — перезагрузите роутер.")
            case .jitter:
                addAction("Закройте приложения, которые загружают или выгружают файлы: при перегрузке канала джиттер растёт. Если не помогло, проверьте сигнал Wi-Fi.")
            case .packetLoss:
                addAction("Запустите трассировку на вкладке «Инструменты», чтобы увидеть, где пропадают ответы. При стабильных потерях подготовьте обращение к провайдеру.")
            case .uploadSpeed:
                addAction("Закройте приложения, использующие исходящий канал (облачные копии, загрузки), и повторите замер. Если отдача остаётся низкой, сверьте её с тарифом.")
            case .downloadSpeed:
                addAction("Повторите замер ближе к роутеру. Если скорость остаётся ниже 25 Мбит/с, 4K-видео будет подгружаться с паузами — проверьте тариф.")
            case .dnsResponse:
                addAction("Откройте «DNS Бенчмарк» и сравните серверы: быстрый DNS экономит десятки миллисекунд при первом обращении к сайту.")
            case .internetLatency, .latencyLocation:
                addAction("Сравните задержку до роутера и до интернета (сценарий «Wi-Fi помехи»): если до роутера она низкая, причина дальше — у провайдера или на маршруте; тогда поможет трассировка.")
            case .bufferbloatNotMeasured, .wifiBandNotAvailable:
                break
            }
        }

        let measuredCount = steps.filter { $0.status != .skipped }.count
        let isIssueFound = !actionPlan.isEmpty
        let skippedTitles = steps.filter { $0.status == .skipped }.map { $0.title }

        if !isIssueFound {
            if measuredCount == 0 {
                actionPlan.append("Выполнить проверку не удалось: ни один шаг не получил данных. Включите мониторинг, запустите замер скорости и повторите.")
            } else {
                actionPlan.append("Среди проверенных шагов проблем не выявлено.")
                if !skippedTitles.isEmpty {
                    actionPlan.append("Не проверено: " + skippedTitles.joined(separator: "; ") + ".")
                }
            }
        }

        let conclusion: String
        if measuredCount == 0 {
            conclusion = "Данных для вывода недостаточно: ни один шаг сценария «\(scenario.rawValue)» не удалось измерить."
        } else if isIssueFound {
            conclusion = "Мастер выявил отклонения. Выполните шаги плана ниже и повторите проверку."
        } else {
            conclusion = "Проверенные шаги сценария «\(scenario.rawValue)» в норме (\(measuredCount) из \(steps.count))."
        }

        return TroubleshootingReport(
            scenario: scenario,
            steps: steps,
            conclusion: conclusion,
            actionPlan: actionPlan,
            isIssueFound: isIssueFound,
            timestamp: Date()
        )
    }

    // MARK: - Замер задержки (несколько проб)

    /// Серия проб до узла. Первая проба прогревочная (ARP, радиомодуль) и в статистику не входит.
    private func measureLatency(target: HostTarget, samples: Int) async -> LatencyStats {
        var values: [Double] = []
        var lost = 0

        for index in 0...samples {
            if Task.isCancelled { break }
            let record = await pingEngine.pingTarget(target)
            if index == 0 { continue }
            if record.isSuccess, let latency = record.latencyMs {
                values.append(latency)
            } else {
                lost += 1
            }
        }

        let total = values.count + lost
        guard !values.isEmpty else {
            return LatencyStats(medianMs: nil, jitterMs: nil, lossPct: total > 0 ? 100.0 : 0.0, answeredCount: 0)
        }

        let sorted = values.sorted()
        let middle = sorted.count / 2
        let median = sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2.0 : sorted[middle]

        var jitter: Double?
        if values.count > 1 {
            var differences = 0.0
            for index in 1..<values.count {
                differences += abs(values[index] - values[index - 1])
            }
            jitter = differences / Double(values.count - 1)
        }

        return LatencyStats(
            medianMs: median,
            jitterMs: jitter,
            lossPct: Double(lost) / Double(total) * 100.0,
            answeredCount: values.count
        )
    }

    // MARK: - 4. Сетевой AI-агент с инструментами

    /// Какой инструмент нужен по тексту запроса. Ключевые слова ищутся как целые слова: раньше «ping» находился
    /// внутри слова «shopping», а цель трассировки и DNS-проверки выбиралась из нескольких захардкоженных имён.
    private func detectTool(in prompt: String, context: NetworkDiagnosticsContext) -> (tool: AIToolType, target: String)? {
        let lower = prompt.lowercased()

        func matches(_ pattern: String) -> Bool {
            lower.range(of: pattern, options: .regularExpression) != nil
        }
        let wordStart = "(?<![\\p{L}\\p{N}])"

        let host = Self.extractHost(from: lower)

        if matches(wordStart + "(ping(?![\\p{L}])|пинг(?!вин)|отклик до)") {
            let fallback = context.gatewayIP ?? "1.1.1.1"
            return (.pingHost, host ?? fallback)
        }
        if matches(wordStart + "(трассировк|traceroute|mtr(?![\\p{L}])|где теряются)") {
            return (.tracerouteHost, host ?? "1.1.1.1")
        }
        if matches(wordStart + "(dns|днс|бенчмарк)") {
            return (.dnsBenchmark, "1.1.1.1, 8.8.8.8, 9.9.9.9")
        }
        if matches(wordStart + "(bufferbloat|буферблот)") {
            return (.checkBufferbloat, "1.1.1.1")
        }
        if matches(wordStart + "(аномали|сканируй)") {
            return (.scanAnomalies, "Текущие измерения")
        }
        return nil
    }

    /// Адрес узла из текста запроса: IPv4, домен или известное имя сервиса. Только безопасные символы.
    private static func extractHost(from lowercasedPrompt: String) -> String? {
        let ipv4Pattern = "(?<![\\d.])(?:\\d{1,3}\\.){3}\\d{1,3}(?![\\d.])"
        if let range = lowercasedPrompt.range(of: ipv4Pattern, options: .regularExpression) {
            let candidate = String(lowercasedPrompt[range])
            let octets = candidate.split(separator: ".").compactMap { Int($0) }
            if octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) {
                return candidate
            }
        }

        let domainPattern = "(?<![\\p{L}\\p{N}.-])(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,24}(?![\\p{L}\\p{N}-])"
        if let range = lowercasedPrompt.range(of: domainPattern, options: .regularExpression) {
            let candidate = String(lowercasedPrompt[range])
            if candidate.count <= 253 { return candidate }
        }

        let aliases: [(keyword: String, host: String)] = [
            ("google", "8.8.8.8"),
            ("cloudflare", "1.1.1.1"),
            ("yandex", "ya.ru"),
            ("яндекс", "ya.ru"),
            ("discord", "discord.com")
        ]
        return aliases.first(where: { lowercasedPrompt.contains($0.keyword) })?.host
    }

    public func executeAgenticQuery(
        prompt: String,
        context: NetworkDiagnosticsContext,
        history: [AIMessage] = [],
        anomalyReport: NetworkAnomalyReport? = nil,
        onToolCall: (@Sendable (AIToolCall) -> Void)? = nil
    ) async -> (response: String, toolCall: AIToolCall?, toolResult: AIToolResult?) {
        var toolCall: AIToolCall?
        var toolResult: AIToolResult?

        if let detected = detectTool(in: prompt, context: context) {
            let call = AIToolCall(
                toolType: detected.tool,
                target: detected.target,
                argumentsDescription: "Запуск инструмента NetPulse: \(detected.tool.displayName)"
            )
            toolCall = call
            onToolCall?(call)
            toolResult = await runTool(call, context: context, anomalyReport: anomalyReport)
        }

        // Результат инструмента передаётся ответу вместе с вопросом
        var enrichedPrompt = prompt
        if let result = toolResult {
            enrichedPrompt += "\n\n[РЕЗУЛЬТАТ ИЗМЕРЕНИЯ ИНСТРУМЕНТОМ NETPULSE: \(result.outputText)]"
        }

        let response = askAI(prompt: enrichedPrompt, context: context, anomalyReport: anomalyReport)
        return (response, toolCall, toolResult)
    }

    /// Запуск инструмента. Каждый инструмент выполняет реальное измерение (раньше «Bufferbloat» вычислялся как
    /// «джиттер × 1,5», «анализ аномалий 24 ч» смотрел только на текущий пинг, а DNS-проверка делала два TCP-подключения).
    private func runTool(
        _ call: AIToolCall,
        context: NetworkDiagnosticsContext,
        anomalyReport: NetworkAnomalyReport?
    ) async -> AIToolResult {
        let start = ContinuousClock().now
        func elapsedMs() -> Double {
            let elapsed = ContinuousClock().now - start
            return Double(elapsed.components.seconds) * 1000.0 + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0
        }
        func result(_ text: String, success: Bool) -> AIToolResult {
            AIToolResult(toolCallId: call.id, toolType: call.toolType, outputText: text, isSuccess: success, executionTimeMs: elapsedMs())
        }

        // Инструменты, которым нужна сеть
        if context.connectionType == NetworkConnectionType.unavailable.rawValue && call.toolType != .scanAnomalies {
            return result("Инструмент не запущен: нет подключения к сети.", success: false)
        }

        switch call.toolType {
        case .pingHost:
            let isGateway = (call.target == context.gatewayIP)
            let target = HostTarget(name: call.target, address: call.target, tcpPort: isGateway ? 53 : 443, isGateway: isGateway)
            let stats = await measureLatency(target: target, samples: 5)
            guard let median = stats.medianMs else {
                return result("Замер до \(call.target): ответа нет ни на одну из 5 проб (потери 100 %). Узел недоступен или не принимает TCP-соединения на порту \(isGateway ? 53 : 443).", success: false)
            }
            let jitterText = stats.jitterMs.map { String(format: ", джиттер %.1f мс", $0) } ?? ""
            return result(String(format: "Замер до %@ (время установления TCP-соединения, 5 проб): медиана %.1f мс%@, потери %.0f %%.", call.target, median, jitterText, stats.lossPct), success: true)

        case .tracerouteHost:
            let hops = await tracerouteEngine.traceRoute(to: call.target)
            if let error = await tracerouteEngine.lastError, hops.isEmpty {
                return result("Трассировка до \(call.target) не выполнена: \(error)", success: false)
            }
            let answered = hops.filter { $0.ipAddress != nil }
            let summary = hops.prefix(6).map { hop -> String in
                let address = hop.ipAddress ?? "*"
                let latency = hop.latencyMs.map { String(format: "%.1f мс", $0) } ?? "нет ответа"
                return "#\(hop.hopNumber) \(address): \(latency)"
            }.joined(separator: "; ")
            return result("Трассировка до \(call.target): всего хопов \(hops.count), ответили \(answered.count) (часть маршрутизаторов не отвечает на ICMP). Первые узлы: \(summary).", success: !answered.isEmpty)

        case .dnsBenchmark:
            let wanted = ["1.1.1.1", "8.8.8.8", "9.9.9.9"]
            let providers = DNSProviderInfo.defaultCatalog.filter { wanted.contains($0.primaryIPv4) }
            let results = await DNSBenchmarkEngine.shared.runBenchmark(providers: providers)
            let lines = results.map { item -> String in
                if item.isReachable, let latency = item.latencyMs {
                    return "\(item.provider.name): \(String(format: "%.1f", latency)) мс (ответов \(item.queriesSucceeded) из \(item.queriesTotal))"
                }
                return "\(item.provider.name): нет ответа"
            }
            return result("Замер реальных DNS-запросов: " + lines.joined(separator: "; ") + ".", success: results.contains { $0.isReachable })

        case .checkBufferbloat:
            if context.connectionType.contains("Мобильная") {
                return result("Тест Bufferbloat автоматически на мобильной сети не запускается: он передаёт до ~100 МБ трафика. Запустите его вручную на экране «Bufferbloat Тест».", success: false)
            }
            var configuration = BufferbloatConfiguration()
            configuration.loadWindowSeconds = 5.0
            configuration.maxBytesPerPhase = 100_000_000
            switch await BufferbloatEngine.shared.runBufferbloatTest(configuration: configuration) {
            case .success(let report):
                func format(_ value: Double?) -> String { value.map { String(format: "%.0f мс", $0) } ?? "нет данных" }
                let grade = report.grade?.rawValue ?? "не определён"
                return result("Bufferbloat: задержка без нагрузки \(format(report.unloadedPingMs)), при скачивании \(format(report.loadedDownloadPingMs)), при отдаче \(format(report.loadedUploadPingMs)); оценка \(grade). Скорость в тесте: ↓ \(report.downloadSpeedMbps.map { String(format: "%.0f", $0) } ?? "—") / ↑ \(report.uploadSpeedMbps.map { String(format: "%.0f", $0) } ?? "—") Мбит/с.", success: report.grade != nil)
            case .failure(let error):
                return result("Bufferbloat не измерен: \(error.localizedDescription)", success: false)
            }

        case .scanAnomalies:
            guard let report = anomalyReport else {
                return result("Отчёт об отклонениях ещё не сформирован: откройте экран AI-диагноста и обновите аудит.", success: false)
            }
            if report.anomalies.isEmpty {
                return result("Отклонений по текущим измерениям не найдено (анализируется только текущий снимок данных, история по часам не ведётся).", success: true)
            }
            let titles = report.anomalies.map { "\($0.title) (\($0.metricValue))" }.joined(separator: "; ")
            return result("Отклонения по текущим измерениям: \(titles).", success: true)
        }
    }

    // MARK: - 5. Контекстные смарт-чипы

    public func generateSmartContextChips(
        context: NetworkDiagnosticsContext,
        anomalyReport: NetworkAnomalyReport?
    ) -> [String] {
        var chips: [String] = []

        if context.hasLiveData && context.packetLossPct > 0.5 {
            chips.append("🔍 Где теряются сетевые пакеты?")
        }
        if let jitter = context.jitterMs, jitter > 8.0 {
            chips.append("📡 Как снизить джиттер Wi-Fi?")
        }
        if let ping = context.averagePingMs, ping > 60.0 {
            chips.append("⚡ Почему высокий пинг в играх?")
        }
        if let report = anomalyReport, !report.anomalies.isEmpty {
            chips.append("📈 Объясни найденные аномалии")
        }

        // Тексты содержат ключевые слова, по которым агент запускает инструменты
        chips.append("🎮 Проверь сеть для CS2 и Dota")
        chips.append("🌐 Сравни DNS: 1.1.1.1 и 8.8.8.8")
        chips.append("📺 Хватит ли канала для 4K?")
        chips.append("📊 Тест Bufferbloat и очередей")

        return Array(chips.prefix(6))
    }

    // MARK: - 6. Ответы AI (встроенный, на устройстве)

    /// Ответ строится на устройстве по измеренным данным; внешних AI-сервисов приложение не использует
    public func askAI(
        prompt: String,
        context: NetworkDiagnosticsContext,
        anomalyReport: NetworkAnomalyReport? = nil
    ) -> String {
        generateOfflineSmartResponse(prompt: prompt, context: context, anomalyReport: anomalyReport)
    }

    // MARK: - 7. Встроенный автономный AI (Offline Smart)

    /// Ответ строится только по измеренным данным. Если данных нет, об этом говорится прямо
    /// (раньше подставлялись «пинг 30 мс», «джиттер 2 мс» и выдавался вердикт «идеально подходит для киберспорта»).
    private func generateOfflineSmartResponse(
        prompt: String,
        context: NetworkDiagnosticsContext,
        anomalyReport: NetworkAnomalyReport?
    ) -> String {
        let lower = prompt.lowercased()
        let conn = context.connectionType
        let isWifi = conn.contains("Wi-Fi")

        let pingText = context.hasLiveData ? (context.averagePingMs.map { "\(Int($0)) мс" } ?? "узлы не отвечают") : "нет данных"
        let jitterText = context.hasLiveData ? (context.jitterMs.map { String(format: "%.1f мс", $0) } ?? "нет данных") : "нет данных"
        let lossText = context.hasLiveData ? String(format: "%.1f %%", context.packetLossPct) : "нет данных"
        let downloadText = context.speedtestDownloadMbps.flatMap { $0 > 0 ? String(format: "%.1f Мбит/с", $0) : nil } ?? "не измерялась"

        func containsAny(_ words: [String]) -> Bool {
            words.contains { lower.contains($0) }
        }

        if containsAny(["игр", "лаг", "gaming", "cs2", "dota", "valorant"]) {
            guard context.hasLiveData, let ping = context.averagePingMs else {
                return """
                ### 🎮 Сеть для онлайн-игр

                Для оценки нужны свежие измерения: сейчас данных мониторинга нет. Включите мониторинг на главном экране и повторите вопрос.
                Также можно открыть «Радар для игр» — он измерит задержку до облачных регионов.
                """
            }
            let jitter = context.jitterMs
            let isGood = ping < 45 && (jitter ?? 0) < 5.0 && context.packetLossPct < 0.5
            return """
            ### 🎮 Сеть для онлайн-игр

            **Текущие показатели:**
            * ⚡ **Пинг до проверяемых узлов:** \(pingText)
            * 📊 **Джиттер:** \(jitterText)
            * 📉 **Потери пакетов:** \(lossText)
            * 🌐 **Тип сети:** \(conn)

            **Вывод:**
            \(isGood ? "✅ По этим показателям соединение подходит для динамичных игр. Учтите: замер идёт до публичных узлов, а не до игрового сервера — пинг в игре покажет сама игра." : "⚠️ Есть показатели, из-за которых в играх возможны лаги: смотрите значения выше.")

            **Что можно сделать:**
            1. \(isWifi ? "По возможности используйте диапазон Wi-Fi 5 ГГц и сядьте ближе к роутеру." : "Если есть выбор, подключитесь по Wi-Fi 5 ГГц или кабелю: на мобильной сети задержка обычно нестабильнее.")
            2. Закройте фоновые загрузки, торренты и облачные синхронизации.
            3. Запустите «Bufferbloat Тест»: он покажет, растёт ли задержка при загруженном канале.
            """
        } else if containsAny(["стрим", "видео", "youtube", "4k", "8k", "канал"]) {
            guard let download = context.speedtestDownloadMbps, download > 0 else {
                return """
                ### 📺 Стриминг и 4K

                Скорость канала пока не измерена. Запустите замер скорости на главном экране: текущий трафик устройства ёмкость канала не показывает.
                """
            }
            let enough = download >= 25.0
            return """
            ### 📺 Стриминг и 4K

            **Скорость по последнему замеру:** \(downloadText)

            **Вывод:**
            \(enough ? "✅ Для одного потока 4K обычно рекомендуют около 25 Мбит/с — скорости достаточно." : "⚠️ Для 4K обычно рекомендуют около 25 Мбит/с на поток — скорости может не хватать, возможны паузы на подгрузку.")

            Если видео всё равно подвисает, проверьте потери пакетов (сейчас: \(lossText)) и качество Wi-Fi.
            """
        } else if containsAny(["bufferbloat", "буферблот", "очеред"]) {
            return """
            ### 📊 Bufferbloat

            Bufferbloat — рост задержки, когда канал загружен (кто-то качает файл, идёт видеозвонок). В покое он не виден, поэтому джиттер (сейчас: \(jitterText)) его не показывает.

            Чтобы проверить, откройте «Bufferbloat Тест» на вкладке «Инструменты»: тест создаст нагрузку и сравнит задержку до и во время неё. Если задержка заметно растёт, на роутере стоит включить SQM (fq_codel или CAKE), если он это поддерживает.
            """
        } else if containsAny(["dns", "днс"]) {
            let known = context.dnsServers.isEmpty ? "iOS не сообщает приложениям, какие DNS-серверы используются" : context.dnsServers.joined(separator: ", ")
            return """
            ### 🌐 DNS

            **Используемые серверы:** \(known)

            Чтобы сравнить серверы, откройте «DNS Бенчмарк»: он отправляет настоящие DNS-запросы и показывает время ответа каждого сервера. Быстрый DNS экономит десятки миллисекунд при первом обращении к сайту; на скорость загрузки страниц он влияет слабо. Шифрованный DNS (DoH) защищает запросы от просмотра посторонними.
            """
        } else if containsAny(["аномали", "вечер", "отклонени"]) {
            guard let report = anomalyReport else {
                return """
                ### 📈 Отклонения

                Отчёт ещё не сформирован. Обновите аудит на экране AI-диагноста (кнопка «Обновить аудит»).
                """
            }
            if report.anomalies.isEmpty {
                return """
                ### 📈 Отклонения

                По текущим измерениям отклонений не найдено. Приложение анализирует только текущий снимок данных, историю по часам оно не ведёт.
                """
            }
            let list = report.anomalies.map { "* **\($0.title)** (\($0.metricValue)): \($0.description)" }.joined(separator: "\n")
            return """
            ### 📈 Отклонения по текущим измерениям

            \(list)
            """
        } else {
            let live = String(format: "%.1f", context.liveDownloadMbps)
            return """
            ### 🧠 Сетевой аудит NetPulse

            **Состояние сети:**
            * 📡 **Подключение:** \(conn)
            * ⚡ **Пинг до проверяемых узлов:** \(pingText)
            * 📊 **Джиттер:** \(jitterText)
            * 📉 **Потери пакетов:** \(lossText)
            * 📥 **Скорость по замеру:** \(downloadText)
            * 🔄 **Текущий трафик устройства:** \(live) Мбит/с

            Вы можете спросить про игры, стриминг, DNS или Bufferbloat, либо попросить измерить пинг до любого узла (например: *«Проверь пинг до 8.8.8.8»*).
            """
        }
    }
}
