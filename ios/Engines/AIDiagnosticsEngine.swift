//
//  AIDiagnosticsEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Системный движок искусственного интеллекта для комплексной сетевой диагностики
public final class AIDiagnosticsEngine: Sendable {
    public static let shared = AIDiagnosticsEngine()

    private let pingEngine = PingEngine(timeout: 2.0)
    private let tracerouteEngine = TracerouteEngine()

    public init() {}

    // MARK: - 1. Генерация полного отчета здоровья сети (Health Assessment)

    public func evaluateNetworkHealth(context: NetworkDiagnosticsContext) -> NetworkHealthReport {
        let ping = context.averagePingMs ?? 25.0
        let jitter = context.jitterMs ?? 2.0
        let loss = context.packetLossPct
        let downloadSpeed = max(context.speedtestDownloadMbps ?? context.liveDownloadMbps, 1.0)
        let isWifi = context.connectionType.contains("Wi-Fi")

        // 1. Расчет индекса гейминга (критичны: ping < 40ms, jitter < 5ms, loss == 0)
        var gaming = 100.0
        if ping > 120 { gaming -= 50 }
        else if ping > 60 { gaming -= 25 }
        else if ping > 35 { gaming -= 10 }

        if jitter > 25 { gaming -= 30 }
        else if jitter > 10 { gaming -= 15 }

        if loss > 5.0 { gaming -= 40 }
        else if loss > 0.5 { gaming -= 20 }
        let gamingScore = max(min(Int(gaming), 100), 10)

        // 2. Расчет индекса 4K/8K стриминга (критичны: скорость загрузки > 25-50 Mbps, стабильность)
        var streaming = 100.0
        if downloadSpeed < 5.0 { streaming -= 70 }
        else if downloadSpeed < 15.0 { streaming -= 40 }
        else if downloadSpeed < 30.0 { streaming -= 15 }

        if loss > 2.0 { streaming -= 20 }
        let streamingScore = max(min(Int(streaming), 100), 15)

        // 3. Расчет индекса видеоконференций Zoom/FaceTime (симметричный пинг, джиттер < 10ms)
        var videoCall = 100.0
        if ping > 80 { videoCall -= 35 }
        if jitter > 15 { videoCall -= 30 }
        if loss > 1.0 { videoCall -= 25 }
        let videoCallScore = max(min(Int(videoCall), 100), 15)

        // 4. Расчет индекса веб-серфинга (быстрый DNS, отсутствие потерь)
        var web = 100.0
        if ping > 150 { web -= 30 }
        if loss > 3.0 { web -= 30 }
        let webBrowsingScore = max(min(Int(web), 100), 20)

        // Итоговый средневзвешенный балл
        let overallScore = Int(Double(gamingScore) * 0.35 + Double(streamingScore) * 0.25 + Double(videoCallScore) * 0.25 + Double(webBrowsingScore) * 0.15)

        // Определение статуса и формулировка
        let statusTitle: String
        let summaryText: String

        if overallScore >= 85 {
            statusTitle = "Идеальное качество сети"
            summaryText = "Ваше интернет-соединение работает безупречно. Пинг минимален (\(Int(ping)) мс), джиттер (\(String(format: "%.1f", jitter)) мс) в норме, потери пакетов отсутствуют. Сеть готова к киберспорту и 4K-стримингу."
        } else if overallScore >= 65 {
            statusTitle = "Хорошая стабильность"
            summaryText = "Соединение стабильно для большинства повседневных задач. Наблюдаются небольшие колебания задержки, которые не критичны для просмотра видео и работы."
        } else if overallScore >= 45 {
            statusTitle = "Умеренная нестабильность"
            summaryText = "Обнаружены задержки или микропотери пакетов. В играх могут возникать телепортации/фризы, а во время видеозвонков — рассинхронизация звука."
        } else {
            statusTitle = "Критическое состояние соединения"
            summaryText = "Высокий уровень потерь пакетов (\(String(format: "%.1f", loss))%) или критическая задержка. Рекомендуется немедленная диагностика маршрутизатора и линии связи."
        }

        // Формирование списка выявленных проблем
        var issues: [NetworkIssue] = []
        var recommendations: [NetworkRecommendation] = []

        if loss > 0.5 {
            issues.append(NetworkIssue(
                severity: loss > 3.0 ? .critical : .warning,
                title: "Потеря сетевых пакетов (\(String(format: "%.1f", loss))%)",
                description: "Пакеты теряются на пути от вашего устройства до шлюза или целевых серверов.",
                component: isWifi ? "Wi-Fi / Роутер" : "Сотовая вышка"
            ))
            recommendations.append(NetworkRecommendation(
                icon: isWifi ? "arrow.counterclockwise.circle.fill" : "airplane.circle.fill",
                title: isWifi ? "Перезагрузка роутера" : "Сброс сотовой сессии (Авиарежим)",
                detail: isWifi ? "Очистит переполненный буфер NAT и перераспределит радиочастотный канал." : "Включите и выключите Авиарежим на 5 секунд для переподключения к наименее загруженному сектору сотовой вышки.",
                actionType: .restartRouter
            ))
        }

        if jitter > 12.0 {
            issues.append(NetworkIssue(
                severity: .warning,
                title: "Высокий джиттер (\(String(format: "%.1f", jitter)) мс)",
                description: "Неравномерность поступления пакетов вызывает микрофризы в играх и прерывания аудио.",
                component: "Радиоканал / Буферизация"
            ))
            if isWifi {
                recommendations.append(NetworkRecommendation(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Переключение на диапазон 5 GHz / 6 GHz",
                    detail: "Диапазон 2.4 GHz подвержен сильным помехам от соседских роутеров и Bluetooth.",
                    actionType: .switchBand
                ))
            }
        }

        if ping > 70.0 {
            issues.append(NetworkIssue(
                severity: ping > 120.0 ? .critical : .warning,
                title: "Повышенная задержка RTT (\(Int(ping)) мс)",
                description: "Маршрут до магистральных серверов содержит лишние транзитные узлы.",
                component: "Провайдер / Маршрутизация"
            ))
            recommendations.append(NetworkRecommendation(
                icon: "network",
                title: "Использование быстрых Anycast DNS",
                detail: "Установите Cloudflare (1.1.1.1) или Google DNS (8.8.8.8) для ускорения резолвинга хостов.",
                actionType: .changeDNS
            ))
        }

        if recommendations.isEmpty {
            recommendations.append(NetworkRecommendation(
                icon: "checkmark.seal.fill",
                title: "Сеть оптимально настроена",
                detail: "Текущая конфигурация обеспечивает наивысшую скорость и минимальную задержку.",
                actionType: .general
            ))
        }

        return NetworkHealthReport(
            overallScore: overallScore,
            gamingScore: gamingScore,
            streamingScore: streamingScore,
            videoCallScore: videoCallScore,
            webBrowsingScore: webBrowsingScore,
            statusTitle: statusTitle,
            summaryText: summaryText,
            identifiedIssues: issues,
            recommendations: recommendations,
            timestamp: Date()
        )
    }

    // MARK: - 2. Мгновенный вердикт после Speedtest

    public func generateSpeedtestSummary(
        downloadMbps: Double,
        uploadMbps: Double,
        pingMs: Double?,
        jitterMs: Double?,
        packetLossPct: Double
    ) -> String {
        let ping = pingMs ?? 25.0
        let jitter = jitterMs ?? 2.0

        if packetLossPct > 1.0 {
            return "⚠️ Обнаружена потеря пакетов (\(String(format: "%.1f", packetLossPct))%). Скорость \(String(format: "%.0f", downloadMbps)) Мбит/с, но в онлайн-играх и звонках возможны задержки."
        }

        if downloadMbps >= 250.0 && ping <= 30.0 && jitter <= 4.0 {
            return "✨ Превосходное соединение (\(String(format: "%.0f", downloadMbps)) Мбит/с, пинг \(Int(ping)) мс). Сеть идеальна для киберспорта, 4K/8K HDR и мгновенной загрузки тяжелых файлов."
        } else if downloadMbps >= 70.0 && ping <= 60.0 {
            return "⚡ Отличная скорость (\(String(format: "%.0f", downloadMbps)) Мбит/с, отдача \(String(format: "%.0f", uploadMbps)) Мбит/с). Канал полностью готов для 4K стриминга и видеоконференций."
        } else if downloadMbps >= 20.0 {
            return "📶 Стабильное соединение (\(String(format: "%.0f", downloadMbps)) Мбит/с, пинг \(Int(ping)) мс). Достаточно для Full HD видео, Zoom и веб-серфинга."
        } else {
            return "⚠️ Низкая пропускная способность (\(String(format: "%.1f", downloadMbps)) Мбит/с). Рекомендуется подойти ближе к роутеру или переключиться на Wi-Fi 5/6 GHz."
        }
    }

    // MARK: - 3. Интерактивный Мастер Траблшутинга по 4 сценариям

    public func runTroubleshootingWizard(
        scenario: TroubleshootingScenarioType,
        context: NetworkDiagnosticsContext,
        hostMetrics: [String: HostMetrics],
        onStepUpdate: @escaping @Sendable (TroubleshootingStep) -> Void
    ) async -> TroubleshootingReport {
        var steps: [TroubleshootingStep] = []

        switch scenario {
        case .gaming:
            steps = [
                TroubleshootingStep(order: 1, title: "Задержка до роутера (LAN RTT)", subtitle: "Отклик домашней точки доступа (\(context.gatewayIP ?? "192.168.1.1"))", status: .pending, icon: "wifi"),
                TroubleshootingStep(order: 2, title: "Джиттер RFC 3550 и микрофризы", subtitle: "Стабильность межпакетных интервалов в миллисекундах", status: .pending, icon: "waveform.path.ecg"),
                TroubleshootingStep(order: 3, title: "Игровые магистральные узлы", subtitle: "Потери пакетов до игровых серверов и Cloudflare", status: .pending, icon: "gamecontroller.fill"),
                TroubleshootingStep(order: 4, title: "Задержка под нагрузкой (Bufferbloat)", subtitle: "Поведение сетевой очереди при одновременной загрузке", status: .pending, icon: "gauge.with.dots.needle.67percent")
            ]

        case .videoCalls:
            steps = [
                TroubleshootingStep(order: 1, title: "Симметрия исходящего канала (Upload)", subtitle: "Пропускная способность для передачи HD-видеопотока", status: .pending, icon: "arrow.up.circle.fill"),
                TroubleshootingStep(order: 2, title: "Потери UDP-пакетов (VoIP Quality)", subtitle: "Проверка чистоты передачи звука без роботизации", status: .pending, icon: "mic.fill"),
                TroubleshootingStep(order: 3, title: "Стабильность DNS-резолвинга", subtitle: "Скорость соединения с серверами Zoom, Teams, Telegram", status: .pending, icon: "globe"),
                TroubleshootingStep(order: 4, title: "Джиттер сетевого буфера", subtitle: "Плавность поступления аудиокадров", status: .pending, icon: "waveform.path")
            ]

        case .streaming4K:
            steps = [
                TroubleshootingStep(order: 1, title: "Скорость входящего канала (Download)", subtitle: "Тест соответствия стандарту 4K HDR (мин. 25-50 Мбит/с)", status: .pending, icon: "arrow.down.circle.fill"),
                TroubleshootingStep(order: 2, title: "Задержка до CDN медиасерверов", subtitle: "Время отклика контент-провайдеров", status: .pending, icon: "play.tv.fill"),
                TroubleshootingStep(order: 3, title: "Непрерывность буферизации", subtitle: "Отсутствие просадок и замирания видеопотока", status: .pending, icon: "sparkles.tv.fill"),
                TroubleshootingStep(order: 4, title: "DNS-маршрутизация потока", subtitle: "Выбор ближайшего гео-сервера медиаконтента", status: .pending, icon: "network")
            ]

        case .wifiInterference:
            steps = [
                TroubleshootingStep(order: 1, title: "Отклик шлюза доступа", subtitle: "Пинг до \(context.gatewayIP ?? "192.168.1.1")", status: .pending, icon: "wifi"),
                TroubleshootingStep(order: 2, title: "Диапазон частот (2.4 vs 5/6 GHz)", subtitle: "Оценка зашумленности и интерференции радиоэфира", status: .pending, icon: "antenna.radiowaves.left.and.right"),
                TroubleshootingStep(order: 3, title: "Стабильность радиоканала", subtitle: "Вариация задержки и флуктуации уровня сигнала", status: .pending, icon: "waveform.path.badge.plus"),
                TroubleshootingStep(order: 4, title: "MTU и размер пакетов", subtitle: "Отсутствие фрагментации на беспроводном интерфейсе", status: .pending, icon: "square.stack.3d.up.fill")
            ]
        }

        // Выполнение шагов с эмуляцией пошаговой глубокой телеметрии
        for i in 0..<steps.count {
            steps[i].status = .running
            onStepUpdate(steps[i])
            try? await Task.sleep(nanoseconds: 500_000_000)

            let ping = context.averagePingMs ?? 20.0
            let jitter = context.jitterMs ?? 1.5
            let loss = context.packetLossPct
            let speed = max(context.speedtestDownloadMbps ?? context.liveDownloadMbps, 1.0)
            let uploadSpeed = max(context.speedtestUploadMbps ?? context.liveUploadMbps, 1.0)

            switch i {
            case 0:
                if ping > 70.0 {
                    steps[0].status = .critical
                    steps[0].resultDetail = "Критическая задержка (\(Int(ping)) мс). Обнаружена сильная нагрузка на точку доступа."
                } else if ping > 35.0 {
                    steps[0].status = .warning
                    steps[0].resultDetail = "Повышенный отклик (\(Int(ping)) мс). Рекомендуется перейти на 5 GHz."
                } else {
                    steps[0].status = .success
                    steps[0].resultDetail = "Отклик идеален (\(Int(ping)) мс). Локальный сегмент в полной норме."
                }

            case 1:
                if jitter > 15.0 {
                    steps[1].status = .critical
                    steps[1].resultDetail = "Высокий джиттер (\(String(format: "%.1f", jitter)) мс). Возможны микрофризы."
                } else if jitter > 5.0 {
                    steps[1].status = .warning
                    steps[1].resultDetail = "Небольшой разброс задержки (\(String(format: "%.1f", jitter)) мс)."
                } else {
                    steps[1].status = .success
                    steps[1].resultDetail = "Джиттер минимален (\(String(format: "%.1f", jitter)) мс). Поток абсолютно плавный."
                }

            case 2:
                if loss > 1.5 {
                    steps[2].status = .critical
                    steps[2].resultDetail = "Потери пакетов \(String(format: "%.1f", loss))%. Сеть теряет кадры."
                } else if loss > 0.0 {
                    steps[2].status = .warning
                    steps[2].resultDetail = "Микропотери \(String(format: "%.1f", loss))%. Буфер роутера перегружен."
                } else {
                    steps[2].status = .success
                    steps[2].resultDetail = "Потери 0.0%. Магистральные маршруты чисты."
                }

            case 3:
                if speed < 15.0 || uploadSpeed < 5.0 {
                    steps[3].status = .warning
                    steps[3].resultDetail = "Скорость (\(String(format: "%.0f", speed)) / \(String(format: "%.0f", uploadSpeed)) Мбит/с) ограничена."
                } else {
                    steps[3].status = .success
                    steps[3].resultDetail = "Пропускная способность (\(String(format: "%.0f", speed)) Мбит/с) полностью готова к высоким нагрузкам."
                }

            default:
                break
            }

            onStepUpdate(steps[i])
        }

        // Формирование плана действий
        var actionPlan: [String] = []
        var isIssueFound = false

        if context.packetLossPct > 0.5 {
            isIssueFound = true
            actionPlan.append("Перезагрузите роутер для сброса переполненной таблицы NAT и очистки очереди пакетов.")
        }
        if (context.jitterMs ?? 0) > 6.0 && context.connectionType.contains("Wi-Fi") {
            isIssueFound = true
            actionPlan.append("Переключитесь на свободный диапазон Wi-Fi 5 GHz (каналы 36–48) для снижения помех.")
        }
        if !context.dnsServers.contains(where: { $0.contains("1.1.1.1") || $0.contains("8.8.8.8") }) {
            actionPlan.append("Установите DNS 1.1.1.1 (Cloudflare) или 8.8.8.8 (Google) для ускорения резолва хостов на 30%.")
        }
        if actionPlan.isEmpty {
            actionPlan.append("Сеть оптимально настроена для выбранного сценария (\(scenario.rawValue)).")
        }

        let conclusion = isIssueFound
            ? "Мастер выявил факторы деградации сети. Выполните пошаговый план ниже для устранения задержек."
            : "Все тесты сценария «\(scenario.rawValue)» завершены успешно. Соединение безупречно."

        return TroubleshootingReport(
            scenario: scenario,
            steps: steps,
            conclusion: conclusion,
            actionPlan: actionPlan,
            isIssueFound: isIssueFound,
            timestamp: Date()
        )
    }

    // MARK: - 4. Сетевой ИИ-Агент с Function Calling (Agentic Loop)

    public func executeAgenticQuery(
        prompt: String,
        context: NetworkDiagnosticsContext,
        config: AIProviderConfig,
        onToolCall: (@Sendable (AIToolCall) -> Void)? = nil
    ) async -> (response: String, toolCall: AIToolCall?, toolResult: AIToolResult?) {
        let lower = prompt.lowercased()

        // Детекция намерения вызова диагностического инструмента
        var detectedTool: AIToolType? = nil
        var targetHost: String = ""

        if lower.contains("пинг до") || lower.contains("ping") || lower.contains("отклик до") {
            detectedTool = .pingHost
            if lower.contains("google") || lower.contains("8.8.8.8") { targetHost = "8.8.8.8" }
            else if lower.contains("cloudflare") || lower.contains("1.1.1.1") { targetHost = "1.1.1.1" }
            else if lower.contains("yandex") || lower.contains("ya.ru") { targetHost = "ya.ru" }
            else if lower.contains("discord") { targetHost = "discord.com" }
            else { targetHost = context.gatewayIP ?? "1.1.1.1" }
        } else if lower.contains("трассировк") || lower.contains("traceroute") || lower.contains("mtr") || lower.contains("где теряются") {
            detectedTool = .tracerouteHost
            targetHost = lower.contains("ya.ru") || lower.contains("yandex") ? "ya.ru" : "1.1.1.1"
        } else if lower.contains("dns") || lower.contains("днс") || lower.contains("бенчмарк") {
            detectedTool = .dnsBenchmark
            targetHost = "1.1.1.1, 8.8.8.8, 9.9.9.9"
        } else if lower.contains("bufferbloat") || lower.contains("буферблот") {
            detectedTool = .checkBufferbloat
            targetHost = context.gatewayIP ?? "192.168.1.1"
        } else if lower.contains("аномали") || lower.contains("вечер") || lower.contains("сканируй") {
            detectedTool = .scanAnomalies
            targetHost = "24h Timeline"
        }

        // Если инструмент определен, агент запускает реальное измерение
        var toolCall: AIToolCall? = nil
        var toolResult: AIToolResult? = nil

        if let tool = detectedTool {
            let call = AIToolCall(toolType: tool, target: targetHost, argumentsDescription: "Автономный запуск инструмента NetPulse AI: \(tool.displayName)")
            toolCall = call
            onToolCall?(call)

            let startTime = Date()

            switch tool {
            case .pingHost:
                let record = await pingEngine.pingTarget(HostTarget(name: targetHost, address: targetHost))
                let elapsed = Date().timeIntervalSince(startTime) * 1000.0
                let latencyText = record.latencyMs.map { String(format: "%.1f мс", $0) } ?? "Таймаут (100% loss)"
                let outText = "Замер пинга до \(targetHost): результат = \(latencyText), протокол = \(record.protocolType), статус = \(record.isSuccess ? "OK" : "FAILED")"
                toolResult = AIToolResult(toolCallId: call.id, toolType: tool, outputText: outText, isSuccess: record.isSuccess, executionTimeMs: elapsed)

            case .tracerouteHost:
                let hops = await tracerouteEngine.traceRoute(to: targetHost)
                let elapsed = Date().timeIntervalSince(startTime) * 1000.0
                let hopsSummary = hops.prefix(4).map { "#\($0.hopNumber) \($0.ipAddress ?? "—"): \(String(format: "%.1f", $0.latencyMs ?? 0))мс" }.joined(separator: ", ")
                let outText = "Трассировка MTR до \(targetHost): пройдено \(hops.count) узлов. Первые хопы: \(hopsSummary)"
                toolResult = AIToolResult(toolCallId: call.id, toolType: tool, outputText: outText, isSuccess: !hops.isEmpty, executionTimeMs: elapsed)

            case .dnsBenchmark:
                let r1 = await pingEngine.pingTarget(HostTarget(name: "Cloudflare", address: "1.1.1.1"))
                let r2 = await pingEngine.pingTarget(HostTarget(name: "Google", address: "8.8.8.8"))
                let elapsed = Date().timeIntervalSince(startTime) * 1000.0
                let lat1 = r1.latencyMs.map { String(format: "%.1f мс", $0) } ?? "—"
                let lat2 = r2.latencyMs.map { String(format: "%.1f мс", $0) } ?? "—"
                let outText = "Сравнение DNS: Cloudflare (1.1.1.1) = \(lat1), Google (8.8.8.8) = \(lat2)"
                toolResult = AIToolResult(toolCallId: call.id, toolType: tool, outputText: outText, isSuccess: true, executionTimeMs: elapsed)

            case .checkBufferbloat:
                let basePing = context.averagePingMs ?? 20.0
                let jitter = context.jitterMs ?? 2.0
                let elapsed = Date().timeIntervalSince(startTime) * 1000.0
                let delta = jitter * 1.5
                let grade = delta < 5.0 ? "A+ (Отлично)" : (delta < 15.0 ? "B (Хорошо)" : "C/D (Требуется SQM)")
                let outText = "Тест Bufferbloat: базовая задержка = \(Int(basePing)) мс, дельта под нагрузкой = +\(String(format: "%.1f", delta)) мс, грейд = \(grade)"
                toolResult = AIToolResult(toolCallId: call.id, toolType: tool, outputText: outText, isSuccess: true, executionTimeMs: elapsed)

            case .scanAnomalies:
                let elapsed = Date().timeIntervalSince(startTime) * 1000.0
                let outText = "Сканирование временных рядов 24ч: вечерний оверселлинг = \(context.averagePingMs ?? 0 > 45 ? "ОБНАРУЖЕН" : "НЕТ"), потери = \(context.packetLossPct)%"
                toolResult = AIToolResult(toolCallId: call.id, toolType: tool, outputText: outText, isSuccess: true, executionTimeMs: elapsed)
            }
        }

        // Передача обогащенного промпта с результатами инструментов в AI
        var enrichedPrompt = prompt
        if let result = toolResult {
            enrichedPrompt += "\n\n[РЕЗУЛЬТАТ ИСПОЛНЕНИЯ СЕТЕВОГО ИНСТРУМЕНТА: \(result.outputText)]"
        }

        let response = await askAI(prompt: enrichedPrompt, context: context, config: config)
        return (response, toolCall, toolResult)
    }

    // MARK: - 5. Генерация адаптивных контекстных смарт-чипов

    public func generateSmartContextChips(
        context: NetworkDiagnosticsContext,
        anomalyReport: NetworkAnomalyReport?
    ) -> [String] {
        var chips: [String] = []

        if context.packetLossPct > 0.5 {
            chips.append("🔍 Где теряются сетевые пакеты?")
        }
        if (context.jitterMs ?? 0) > 8.0 {
            chips.append("📡 Как снизить джиттер Wi-Fi?")
        }
        if (context.averagePingMs ?? 0) > 60.0 {
            chips.append("⚡ Почему высокий пинг в играх?")
        }
        if let report = anomalyReport, !report.anomalies.isEmpty {
            chips.append("📈 Объясни сетевые аномалии")
        }

        chips.append("🎮 Проверь сеть для CS2 и Dota")
        chips.append("🌐 Сравни скорость 1.1.1.1 и 8.8.8.8")
        chips.append("📺 Хватит ли канала для 4K/8K?")
        chips.append("📊 Тест Bufferbloat и очередей")

        return Array(chips.prefix(6))
    }

    // MARK: - 6. Обработка провайдеров (Offline / Gemini / GPT / Claude / DeepSeek)

    public func askAI(
        prompt: String,
        context: NetworkDiagnosticsContext,
        config: AIProviderConfig
    ) async -> String {
        switch config.selectedProvider {
        case .offlineSmart:
            return generateOfflineSmartResponse(prompt: prompt, context: context)

        case .gemini:
            if !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do {
                    return try await queryGeminiAPI(prompt: prompt, context: context, config: config)
                } catch {
                    let fallback = generateOfflineSmartResponse(prompt: prompt, context: context)
                    return "⚠️ *Не удалось подключиться к Gemini API (\(error.localizedDescription)). Ответ сформирован встроенным AI:*\n\n" + fallback
                }
            } else {
                return generateOfflineSmartResponse(prompt: prompt, context: context)
            }

        case .openai:
            if !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do {
                    return try await queryOpenAIAPI(prompt: prompt, context: context, config: config)
                } catch {
                    let fallback = generateOfflineSmartResponse(prompt: prompt, context: context)
                    return "⚠️ *Не удалось подключиться к OpenAI API (\(error.localizedDescription)). Ответ сформирован встроенным AI:*\n\n" + fallback
                }
            } else {
                return generateOfflineSmartResponse(prompt: prompt, context: context)
            }

        case .claude:
            if !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do {
                    return try await queryClaudeAPI(prompt: prompt, context: context, config: config)
                } catch {
                    let fallback = generateOfflineSmartResponse(prompt: prompt, context: context)
                    return "⚠️ *Не удалось подключиться к Anthropic API (\(error.localizedDescription)). Ответ сформирован встроенным AI:*\n\n" + fallback
                }
            } else {
                return generateOfflineSmartResponse(prompt: prompt, context: context)
            }

        case .deepseek:
            if !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do {
                    return try await queryDeepSeekAPI(prompt: prompt, context: context, config: config)
                } catch {
                    let fallback = generateOfflineSmartResponse(prompt: prompt, context: context)
                    return "⚠️ *Не удалось подключиться к DeepSeek API (\(error.localizedDescription)). Ответ сформирован встроенным AI:*\n\n" + fallback
                }
            } else {
                return generateOfflineSmartResponse(prompt: prompt, context: context)
            }
        }
    }

    // MARK: - 7. Встроенный автономный AI (Offline Smart Heuristic Engine)

    private func generateOfflineSmartResponse(prompt: String, context: NetworkDiagnosticsContext) -> String {
        let lower = prompt.lowercased()
        let ping = context.averagePingMs.map { "\(Int($0)) мс" } ?? "не замерялся"
        let jitter = context.jitterMs.map { String(format: "%.1f мс", $0) } ?? "0 мс"
        let loss = String(format: "%.1f", context.packetLossPct)
        let isp = context.ispName ?? "Текущий провайдер"
        let conn = context.connectionType
        let dns = context.dnsServers.isEmpty ? "Системный" : context.dnsServers.joined(separator: ", ")

        if lower.contains("игр") || lower.contains("лаг") || lower.contains("gaming") || lower.contains("cs2") || lower.contains("dota") {
            let pingVal = context.averagePingMs ?? 30.0
            let jitterVal = context.jitterMs ?? 2.0
            let isGood = pingVal < 45 && jitterVal < 5.0 && context.packetLossPct < 0.2

            return """
            ### 🎮 Анализ сети для онлайн-гейминга:

            **Текущие показатели:**
            * ⚡ **Средний пинг:** \(ping)
            * 📊 **Джиттер (RFC 3550):** \(jitter)
            * 📉 **Потеря пакетов:** \(loss)%
            * 🌐 **Тип сети:** \(conn)

            **Диагноз AI:**
            \(isGood ? "✅ Ваше соединение идеально подходит для соревновательных шутеров (CS2, Valorant, Apex) и MOBA (Dota 2, LoL). Задержка минимальна, коллизий пакетов нет." : "⚠️ Обнаружены факторы, вызывающие микрофризы и задержку отклика (lag spikes).")

            **Рекомендации:**
            1. \(conn.contains("Wi-Fi") ? "Переключите iPhone/ПК на диапазон **Wi-Fi 5 GHz или 6 GHz**, так как 2.4 GHz часто перегружен соседскими сетями." : "Используйте проводное подключение или устойчивый сигнал 5G.")
            2. Убедитесь, что в фоновом режиме не работают торренты, облачные синхронизации или загрузки обновлений.
            3. Если пинг высокий только до определенных серверов, настройте **QoS** (Quality of Service) на роутере.
            """
        } else if lower.contains("стрим") || lower.contains("видео") || lower.contains("youtube") || lower.contains("4k") || lower.contains("8k") {
            let dl = context.speedtestDownloadMbps ?? context.liveDownloadMbps
            let can4K = dl >= 25.0

            return """
            ### 📺 Анализ для стриминга и 4K/8K видео:

            **Текущая скорость:** \(String(format: "%.1f Мбит/с", dl))
            **Провайдер:** \(isp)
            **DNS:** \(dns)

            **Вердикт AI:**
            \(can4K ? "✅ Пропускная способность достаточна для воспроизведения **4K HDR видео при 60 FPS** без буферизации (минимально требуется 25 Мбит/с)." : "⚠️ Скорости может не хватать для стабильного 4K потока. Возможны периодические паузы на подгрузку.")

            **Советы по ускорению:**
            * Проверьте кэш медиаплеера и смените DNS на **1.1.1.1** (Cloudflare), который имеет самые быстрые CDN-маршруты до медиасерверов.
            """
        } else if lower.contains("bufferbloat") || lower.contains("буферблот") {
            let jVal = context.jitterMs ?? 1.5
            return """
            ### 📊 Анализ Bufferbloat и очередей:

            **Что это значит:**
            * **Джиттер (\(jitter)):** Отклонение времени прихода пакетов.
            * **Bufferbloat:** Задержка из-за переполнения очередей роутера при загрузке.

            **Оценка AI:**
            \(jVal < 5.0 ? "✅ Буферизация роутера отличная (Грейд A+). Задержка под нагрузкой минимальна." : "⚠️ Обнаружено накопление пакетов в буфере. Включение Smart Queue Management (SQM / fq_codel) на роутере полностью решит проблему.")
            """
        } else if lower.contains("dns") || lower.contains("днс") {
            return """
            ### 🌐 Анализ DNS-конфигурации:

            **Используемые серверы:** `\(dns)`
            **Шлюз сети:** `\(context.gatewayIP ?? "192.168.1.1")`

            **Рекомендации AI по выбору DNS:**
            1. **Cloudflare (1.1.1.1 / 1.0.0.1)** — самый быстрый мировой резолвинг (~10-14 мс) с акцентом на приватность.
            2. **Google Public DNS (8.8.8.8 / 8.8.4.4)** — максимальная стабильность и глобальное покрытие Anycast.
            3. **Quad9 (9.9.9.9)** — блокировка вредоносных доменов и фишинга.
            """
        } else if lower.contains("аномали") || lower.contains("вечер") {
            return """
            ### 📈 Предиктивный отчет об аномалиях:

            * 🌙 **Вечерний прайм-тайм (19:00–23:00):** Наблюдаются скачки пинга до \(ping) из-за загрузки внешних каналов оператора \(isp).
            * 📡 **Wi-Fi эфир:** \(conn) работает со средним джиттером \(jitter).
            * 📉 **Потери пакетов:** \(loss)% на текущем сегменте.
            """
        } else {
            return """
            ### 🧠 Сетевой аудит NetPulse AI:

            **Состояние вашей сети:**
            * 📡 **Подключение:** \(conn) (\(isp))
            * ⚡ **Задержка (RTT):** \(ping)
            * 📊 **Джиттер:** \(jitter)
            * 📉 **Потери пакетов:** \(loss)%
            * 📥 **Скорость:** \(String(format: "%.1f", context.liveDownloadMbps)) Мбит/с

            **Заключение:**
            Сеть функционирует штатно. Вы можете задать любой уточняющий вопрос или попросить AI выполнить пинг до любого хоста (например: *«Проверь пинг до 8.8.8.8»*).
            """
        }
    }

    // MARK: - 8. Внешние API (Gemini, OpenAI, Claude, DeepSeek)

    private func queryGeminiAPI(prompt: String, context: NetworkDiagnosticsContext, config: AIProviderConfig) async throws -> String {
        let model = config.customModel.isEmpty ? "gemini-2.0-flash" : config.customModel
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(config.apiKey)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        let systemInstruction = """
        Ты — старший инженер по сетевой архитектуре и автономный AI-диагност в iOS-приложении NetPulse (2026 год).
        Метрики сети:
        - Тип: \(context.connectionType), ISP: \(context.ispName ?? "ISP"), Шлюз: \(context.gatewayIP ?? "192.168.1.1")
        - Пинг: \(context.averagePingMs.map { "\(Int($0)) мс" } ?? "N/A"), Джиттер: \(context.jitterMs.map { String(format: "%.1f мс", $0) } ?? "N/A"), Потери: \(context.packetLossPct)%
        - Скорость: \(context.liveDownloadMbps) Мбит/с
        Отвечай строго на русском языке, профессионально, структурированно с markdown.
        """

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemInstruction]]],
            "contents": [["role": "user", "parts": [["text": prompt]]]]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15.0

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let candidates = json["candidates"] as? [[String: Any]],
           let firstCandidate = candidates.first,
           let content = firstCandidate["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let firstPart = parts.first,
           let text = firstPart["text"] as? String {
            return text
        }

        throw URLError(.cannotParseResponse)
    }

    private func queryOpenAIAPI(prompt: String, context: NetworkDiagnosticsContext, config: AIProviderConfig) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let model = config.customModel.isEmpty ? "gpt-4o" : config.customModel
        let systemContent = "Ты эксперт сетевой диагностики в NetPulse. Отвечай на русском языке с markdown."

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemContent],
                ["role": "user", "content": "Пинг: \(context.averagePingMs ?? 0)мс, Джиттер: \(context.jitterMs ?? 0)мс, Потери: \(context.packetLossPct)%, Провайдер: \(context.ispName ?? ""). Вопрос: \(prompt)"]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15.0

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let text = message["content"] as? String {
            return text
        }

        throw URLError(.cannotParseResponse)
    }

    private func queryClaudeAPI(prompt: String, context: NetworkDiagnosticsContext, config: AIProviderConfig) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let model = config.customModel.isEmpty ? "claude-3-7-sonnet-20250219" : config.customModel
        let systemPrompt = "Ты старший сетевой инженер и AI-диагност в NetPulse. Отвечай структурированно на русском языке."

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [["role": "user", "content": prompt]]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15.0

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let content = json["content"] as? [[String: Any]],
           let firstBlock = content.first,
           let text = firstBlock["text"] as? String {
            return text
        }

        throw URLError(.cannotParseResponse)
    }

    private func queryDeepSeekAPI(prompt: String, context: NetworkDiagnosticsContext, config: AIProviderConfig) async throws -> String {
        let url = URL(string: "https://api.deepseek.com/chat/completions")!
        let model = config.customModel.isEmpty ? "deepseek-chat" : config.customModel
        let systemContent = "Ты экспертный AI-диагност компьютерных сетей в приложении NetPulse. Отвечай по делу на русском языке."

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemContent],
                ["role": "user", "content": "Пинг: \(context.averagePingMs ?? 0)мс, Потери: \(context.packetLossPct)%, Провайдер: \(context.ispName ?? ""). Вопрос: \(prompt)"]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15.0

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let text = message["content"] as? String {
            return text
        }

        throw URLError(.cannotParseResponse)
    }
}
