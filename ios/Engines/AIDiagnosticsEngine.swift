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
                icon: "arrow.counterclockwise.circle.fill",
                title: "Перезагрузка роутера",
                detail: "Очистит переполненный буфер NAT и перераспределит радиочастотный канал.",
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

    // MARK: - 2. Обработка пользовательских запросов к AI

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
        }
    }

    // MARK: - 3. Встроенный автономный AI (Offline Smart Heuristic Engine)

    private func generateOfflineSmartResponse(prompt: String, context: NetworkDiagnosticsContext) -> String {
        let lower = prompt.lowercased()
        let ping = context.averagePingMs.map { "\(Int($0)) мс" } ?? "не замерялся"
        let jitter = context.jitterMs.map { String(format: "%.1f мс", $0) } ?? "0 мс"
        let loss = String(format: "%.1f", context.packetLossPct)
        let isp = context.ispName ?? "Текущий провайдер"
        let conn = context.connectionType
        let dns = context.dnsServers.isEmpty ? "Системный" : context.dnsServers.joined(separator: ", ")

        if lower.contains("игр") || lower.contains("лаг") || lower.contains("gaming") || lower.contains("пинг") {
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
            2. Убедитесь, что в фоновом режиме не работают торренты, облачные синхронизации (iCloud / Google Drive) или загрузки обновлений.
            3. Если пинг высокий только до определенных серверов, используйте игровой маршрутизатор с поддержкой **QoS** (Quality of Service).
            """
        } else if lower.contains("стрим") || lower.contains("видео") || lower.contains("youtube") || lower.contains("4k") {
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
            * Проверьте кэш медиаплеера и смените DNS на **1.1.1.1** (Cloudflare), который имеет самые быстрые CDN-маршруты до серверов YouTube и онлайн-кинотеатров.
            """
        } else if lower.contains("dns") || lower.contains("днс") {
            return """
            ### 🌐 Анализ DNS-конфигурации:

            **Используемые серверы:** `\(dns)`
            **Шлюз сети:** `\(context.gatewayIP ?? "192.168.1.1")`

            **Рекомендации AI по выбору DNS:**
            1. **Cloudflare (1.1.1.1 / 1.0.0.1)** — самый быстрый мировой резолвинг (средний отклик ~10-14 мс) с акцентом на приватность.
            2. **Google Public DNS (8.8.8.8 / 8.8.4.4)** — максимальная стабильность и глобальное покрытие Anycast.
            3. **AdGuard DNS (94.140.14.14)** — встроенная блокировка рекламы и фишинговых сайтов на уровне сети.
            """
        } else if lower.contains("роутер") || lower.contains("wifi") || lower.contains("вайфай") {
            return """
            ### 📡 Рекомендации по оптимизации роутера и Wi-Fi:

            * **Расположение:** Установите роутер на высоте 1.5–2 метра от пола, вдали от микроволновых печей, зеркал и толстых бетонных стен.
            * **Ширина канала:** Для 5 GHz выберите ширину **80 MHz** (или 160 MHz для Wi-Fi 6), для 2.4 GHz — **20 MHz** (снижает интерференцию).
            * **Безопасность:** Используйте протокол шифрования **WPA3-Personal** или WPA2-AES.
            * **Перезагрузка:** Регулярная перезагрузка раз в неделю освобождает оперативную память роутера и сбрасывает зависшие сессии TCP/UDP.
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
            Сеть функционирует в штатном режиме. Все ключевые сетевые интерфейсы Darwin стабильно передают телеметрию. Задайте любой уточняющий вопрос (например: *«Как настроить DNS?»*, *«Почему высокий пинг?»*, *«Оптимизация под видеозвонки»*).
            """
        }
    }

    // MARK: - 4. Интеграция с Google Gemini 2.0 API

    private func queryGeminiAPI(
        prompt: String,
        context: NetworkDiagnosticsContext,
        config: AIProviderConfig
    ) async throws -> String {
        let model = config.customModel.isEmpty ? "gemini-2.0-flash" : config.customModel
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(config.apiKey)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let systemInstruction = """
        Ты — старший инженер по сетевой архитектуре и AI-диагност в iOS-приложении NetPulse (2026 год).
        Твоя задача — анализировать сетевые метрики пользователя и давать глубокие, понятные, профессиональные и структурированные советы на русском языке.
        Текущие метрики сети пользователя:
        - Тип подключения: \(context.connectionType)
        - Локальный IP: \(context.localIP), Шлюз: \(context.gatewayIP ?? "N/A")
        - Провайдер (ISP): \(context.ispName ?? "Неизвестен")
        - DNS: \(context.dnsServers.joined(separator: ", "))
        - Средний пинг: \(context.averagePingMs.map { "\(Int($0)) мс" } ?? "N/A")
        - Джиттер: \(context.jitterMs.map { String(format: "%.1f мс", $0) } ?? "N/A")
        - Потеря пакетов: \(context.packetLossPct)%
        - Скорость загрузки: \(context.liveDownloadMbps) Мбит/с
        """

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [
                    ["text": systemInstruction]
                ]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ]
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

    // MARK: - 5. Интеграция с OpenAI API (GPT-4o)

    private func queryOpenAIAPI(
        prompt: String,
        context: NetworkDiagnosticsContext,
        config: AIProviderConfig
    ) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let model = config.customModel.isEmpty ? "gpt-4o" : config.customModel

        let systemContent = "Ты ведущий сетевой эксперт и AI-диагност в приложении NetPulse. Отвечай на русском языке с четким форматированием markdown."

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemContent],
                ["role": "user", "content": "Метрики сети: Пинг: \(context.averagePingMs ?? 0)мс, Потери: \(context.packetLossPct)%, Провайдер: \(context.ispName ?? ""). Вопрос: \(prompt)"]
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
