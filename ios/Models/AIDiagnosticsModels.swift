//
//  AIDiagnosticsModels.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import SwiftUI

// MARK: - 1. Провайдеры и конфигурация AI

/// Провайдер искусственного интеллекта для сетевого анализа
public enum AIProviderType: String, CaseIterable, Identifiable, Codable, Sendable {
    case offlineSmart = "Встроенный AI (Offline Smart)"
    case gemini = "Google Gemini 2.0 Flash"
    case openai = "OpenAI GPT-4o"
    case claude = "Anthropic Claude 3.7 Sonnet"
    case deepseek = "DeepSeek V3 / R1"

    public var id: String { rawValue }

    public var defaultModelName: String {
        switch self {
        case .offlineSmart: return "Локальная эвристическая модель"
        case .gemini: return "gemini-2.0-flash"
        case .openai: return "gpt-4o"
        case .claude: return "claude-3-7-sonnet-20250219"
        case .deepseek: return "deepseek-chat"
        }
    }
}

/// Конфигурация подключения к AI-провайдеру
public struct AIProviderConfig: Codable, Sendable {
    public var selectedProvider: AIProviderType
    public var apiKey: String
    public var customModel: String

    public init(
        selectedProvider: AIProviderType = .offlineSmart,
        apiKey: String = "",
        customModel: String = "gemini-2.0-flash"
    ) {
        self.selectedProvider = selectedProvider
        self.apiKey = apiKey
        self.customModel = customModel.isEmpty ? selectedProvider.defaultModelName : customModel
    }
}

// MARK: - 2. Модели вызова функций (Tool / Function Calling)

/// Типы инструментов, которые сетевой AI-агент может вызывать в реальном времени
public enum AIToolType: String, Codable, Sendable, CaseIterable {
    case pingHost = "tool_ping"
    case tracerouteHost = "tool_traceroute"
    case dnsBenchmark = "tool_dns_benchmark"
    case checkBufferbloat = "tool_bufferbloat"
    case scanAnomalies = "tool_scan_anomalies"

    public var displayName: String {
        switch self {
        case .pingHost: return "Пинг узла"
        case .tracerouteHost: return "Трассировка MTR"
        case .dnsBenchmark: return "DNS Бенчмарк"
        case .checkBufferbloat: return "Тест Bufferbloat"
        case .scanAnomalies: return "Анализ аномалий"
        }
    }

    public var icon: String {
        switch self {
        case .pingHost: return "network"
        case .tracerouteHost: return "point.topleft.down.to.point.bottomright.curvepath"
        case .dnsBenchmark: return "globe.europe.africa.fill"
        case .checkBufferbloat: return "gauge.with.dots.needle.67percent"
        case .scanAnomalies: return "waveform.path.ecg"
        }
    }
}

/// Вызов инструмента со стороны нейросети
public struct AIToolCall: Identifiable, Codable, Sendable {
    public let id: String
    public let toolType: AIToolType
    public let target: String
    public let argumentsDescription: String

    public init(id: String = UUID().uuidString, toolType: AIToolType, target: String, argumentsDescription: String) {
        self.id = id
        self.toolType = toolType
        self.target = target
        self.argumentsDescription = argumentsDescription
    }
}

/// Результат исполнения вызова инструмента приложением
public struct AIToolResult: Identifiable, Codable, Sendable {
    public let id: String
    public let toolCallId: String
    public let toolType: AIToolType
    public let outputText: String
    public let isSuccess: Bool
    public let executionTimeMs: Double

    public init(
        id: String = UUID().uuidString,
        toolCallId: String,
        toolType: AIToolType,
        outputText: String,
        isSuccess: Bool = true,
        executionTimeMs: Double = 0.0
    ) {
        self.id = id
        self.toolCallId = toolCallId
        self.toolType = toolType
        self.outputText = outputText
        self.isSuccess = isSuccess
        self.executionTimeMs = executionTimeMs
    }
}

// MARK: - 3. Проблемы, рекомендации и здоровье сети

/// Уровень критичности обнаруженной сетевой проблемы
public enum IssueSeverity: String, Codable, Sendable {
    case info = "Информация"
    case warning = "Предупреждение"
    case critical = "Критическая"

    public var colorName: String {
        switch self {
        case .info: return "blue"
        case .warning: return "yellow"
        case .critical: return "red"
        }
    }
}

/// Обнаруженная сетевая проблема
public struct NetworkIssue: Identifiable, Codable, Sendable {
    public let id: UUID
    public let severity: IssueSeverity
    public let title: String
    public let description: String
    public let component: String // "Роутер / Wi-Fi", "Провайдер / DNS", "Маршрутизация"

    public init(
        id: UUID = UUID(),
        severity: IssueSeverity,
        title: String,
        description: String,
        component: String
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.description = description
        self.component = component
    }
}

/// Тип рекомендуемого действия
public enum RecommendationAction: String, Codable, Sendable {
    case changeDNS = "Сменить DNS"
    case switchBand = "Переключить диапазон"
    case restartRouter = "Перезагрузить роутер"
    case checkISP = "Обратиться к провайдеру"
    case general = "Оптимизация"
}

/// Конкретная пошаговая рекомендация от AI
public struct NetworkRecommendation: Identifiable, Codable, Sendable {
    public let id: UUID
    public let icon: String
    public let title: String
    public let detail: String
    public let actionType: RecommendationAction

    public init(
        id: UUID = UUID(),
        icon: String,
        title: String,
        detail: String,
        actionType: RecommendationAction = .general
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.detail = detail
        self.actionType = actionType
    }
}

/// Полный отчет здоровья сети от AI
public struct NetworkHealthReport: Identifiable, Codable, Sendable {
    public let id: UUID
    public let overallScore: Int // 0 - 100
    public let gamingScore: Int // 0 - 100
    public let streamingScore: Int // 0 - 100
    public let videoCallScore: Int // 0 - 100
    public let webBrowsingScore: Int // 0 - 100
    public let statusTitle: String
    public let summaryText: String
    public let identifiedIssues: [NetworkIssue]
    public let recommendations: [NetworkRecommendation]
    public let timestamp: Date

    public var healthScore: Int { overallScore }

    public var statusBadgeColor: Color {
        if overallScore >= 85 {
            return .green
        } else if overallScore >= 65 {
            return .blue
        } else if overallScore >= 45 {
            return .yellow
        } else {
            return .red
        }
    }

    public init(
        id: UUID = UUID(),
        overallScore: Int,
        gamingScore: Int,
        streamingScore: Int,
        videoCallScore: Int,
        webBrowsingScore: Int,
        statusTitle: String,
        summaryText: String,
        identifiedIssues: [NetworkIssue],
        recommendations: [NetworkRecommendation],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.overallScore = overallScore
        self.gamingScore = gamingScore
        self.streamingScore = streamingScore
        self.videoCallScore = videoCallScore
        self.webBrowsingScore = webBrowsingScore
        self.statusTitle = statusTitle
        self.summaryText = summaryText
        self.identifiedIssues = identifiedIssues
        self.recommendations = recommendations
        self.timestamp = timestamp
    }
}

// MARK: - 4. Сообщения диалога с поддержкой Tool Execution

/// Роль автора сообщения в чате с AI
public enum AIMessageRole: String, Codable, Sendable {
    case user = "user"
    case assistant = "assistant"
    case tool = "tool"
}

/// Сообщение диалога с AI-диагностом
public struct AIMessage: Identifiable, Codable, Sendable {
    public let id: UUID
    public let role: AIMessageRole
    public let content: String
    public let timestamp: Date
    public let toolCall: AIToolCall?
    public let toolResult: AIToolResult?

    public init(
        id: UUID = UUID(),
        role: AIMessageRole,
        content: String,
        timestamp: Date = Date(),
        toolCall: AIToolCall? = nil,
        toolResult: AIToolResult? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCall = toolCall
        self.toolResult = toolResult
    }
}

// MARK: - 5. Интерактивный Мастер Траблшутинга (Guided Troubleshooting)

/// Категории сценариев для пошагового мастера диагностики
public enum TroubleshootingScenarioType: String, CaseIterable, Identifiable, Codable, Sendable {
    case gaming = "Киберспорт и Онлайн-игры"
    case videoCalls = "Видеозвонки (Zoom/FaceTime)"
    case streaming4K = "4K/8K HDR Стриминг"
    case wifiInterference = "Wi-Fi Помехи и Диапазоны"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .gaming: return "gamecontroller.fill"
        case .videoCalls: return "video.fill"
        case .streaming4K: return "tv.fill"
        case .wifiInterference: return "wifi.exclamationmark"
        }
    }

    public var description: String {
        switch self {
        case .gaming: return "Диагностика RTT, джиттера, Bufferbloat и игровых серверов (CS2, Dota, Valorant)."
        case .videoCalls: return "Проверка симметрии отдачи, потерь UDP-пакетов и стабильности микрофона."
        case .streaming4K: return "Анализ пропускной способности, CDN-задержки и стабильности буфера."
        case .wifiInterference: return "Замер задержки шлюза, радиопомех и сравнение 2.4 vs 5/6 GHz."
        }
    }
}

/// Статус отдельного шага интерактивной диагностики
public enum TroubleshootingStepStatus: String, Codable, Sendable {
    case pending = "Ожидание"
    case running = "Проверка..."
    case success = "В норме"
    case warning = "Замечание"
    case critical = "Критично"
}

/// Шаг в мастере устранения сетевых неполадок
public struct TroubleshootingStep: Identifiable, Codable, Sendable {
    public let id: UUID
    public let order: Int
    public let title: String
    public let subtitle: String
    public var status: TroubleshootingStepStatus
    public var resultDetail: String?
    public var icon: String

    public init(
        id: UUID = UUID(),
        order: Int,
        title: String,
        subtitle: String,
        status: TroubleshootingStepStatus = .pending,
        resultDetail: String? = nil,
        icon: String
    ) {
        self.id = id
        self.order = order
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.resultDetail = resultDetail
        self.icon = icon
    }
}

/// Результат работы интерактивного мастера
public struct TroubleshootingReport: Identifiable, Codable, Sendable {
    public let id: UUID
    public let scenario: TroubleshootingScenarioType
    public let steps: [TroubleshootingStep]
    public let conclusion: String
    public let actionPlan: [String]
    public let isIssueFound: Bool
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        scenario: TroubleshootingScenarioType = .gaming,
        steps: [TroubleshootingStep],
        conclusion: String,
        actionPlan: [String],
        isIssueFound: Bool,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.scenario = scenario
        self.steps = steps
        self.conclusion = conclusion
        self.actionPlan = actionPlan
        self.isIssueFound = isIssueFound
        self.timestamp = timestamp
    }
}

// MARK: - 6. Предиктивная аналитика сетевых аномалий

/// Тип обнаруженной сетевой аномалии
public enum NetworkAnomalyType: String, Codable, Sendable {
    case eveningCongestion = "Вечерний оверселлинг провайдера"
    case wifiInterference = "Деградация радиоэфира Wi-Fi"
    case budgetExhaustion = "Риск исчерпания лимита трафика"
    case dnsDegradation = "Нестабильность DNS-резолвинга"
    case packetLossSpike = "Всплеск потерь пакетов на узле"

    public var icon: String {
        switch self {
        case .eveningCongestion: return "moon.stars.fill"
        case .wifiInterference: return "antenna.radiowaves.left.and.right"
        case .budgetExhaustion: return "chart.line.uptrend.xyaxis"
        case .dnsDegradation: return "globe.badge.chevron.backward"
        case .packetLossSpike: return "exclamationmark.triangle.fill"
        }
    }
}

/// Элемент обнаруженной сетевой аномалии
public struct NetworkAnomalyItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public let type: NetworkAnomalyType
    public let title: String
    public let description: String
    public let severity: IssueSeverity
    public let detectedAt: Date
    public let metricValue: String
    public let suggestedFix: String

    public init(
        id: UUID = UUID(),
        type: NetworkAnomalyType,
        title: String,
        description: String,
        severity: IssueSeverity,
        detectedAt: Date = Date(),
        metricValue: String,
        suggestedFix: String
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.description = description
        self.severity = severity
        self.detectedAt = detectedAt
        self.metricValue = metricValue
        self.suggestedFix = suggestedFix
    }
}

/// Полный отчет по сетевым аномалиям
public struct NetworkAnomalyReport: Identifiable, Codable, Sendable {
    public let id: UUID
    public let anomalies: [NetworkAnomalyItem]
    public let overallRiskLevel: IssueSeverity
    public let analyzedHours: Int
    public let generatedAt: Date

    public init(
        id: UUID = UUID(),
        anomalies: [NetworkAnomalyItem],
        overallRiskLevel: IssueSeverity = .info,
        analyzedHours: Int = 24,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.anomalies = anomalies
        self.overallRiskLevel = overallRiskLevel
        self.analyzedHours = analyzedHours
        self.generatedAt = generatedAt
    }
}

// MARK: - 7. Шаблоны официальных претензий провайдеру (ISP Dispute Letter)

/// Шаблон официальной претензии в техподдержку интернет-провайдера
public enum ISPDisputeTemplate: String, CaseIterable, Identifiable, Codable, Sendable {
    case packetLossAndLatency = "Потеря пакетов и высокая задержка RTT"
    case speedMismatch = "Несоответствие заявленной тарифной скорости"
    case routingAndMTR = "Сбои магистральной маршрутизации (MTR)"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .packetLossAndLatency: return "waveform.path.badge.minus"
        case .speedMismatch: return "speedometer"
        case .routingAndMTR: return "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
}

// MARK: - 8. Контекст диагностики сети

/// Контекст текущего состояния сети для передачи в AI
public struct NetworkDiagnosticsContext: Sendable {
    public let connectionType: String
    public let localIP: String
    public let gatewayIP: String?
    public let publicIP: String?
    public let ispName: String?
    public let dnsServers: [String]
    public let averagePingMs: Double?
    public let jitterMs: Double?
    public let packetLossPct: Double
    public let liveDownloadMbps: Double
    public let liveUploadMbps: Double
    public let speedtestDownloadMbps: Double?
    public let speedtestUploadMbps: Double?
    public let recentAlertsCount: Int
    public let tracerouteHopsCount: Int

    public init(
        connectionType: String,
        localIP: String,
        gatewayIP: String?,
        publicIP: String?,
        ispName: String?,
        dnsServers: [String],
        averagePingMs: Double?,
        jitterMs: Double?,
        packetLossPct: Double,
        liveDownloadMbps: Double,
        liveUploadMbps: Double,
        speedtestDownloadMbps: Double?,
        speedtestUploadMbps: Double?,
        recentAlertsCount: Int,
        tracerouteHopsCount: Int
    ) {
        self.connectionType = connectionType
        self.localIP = localIP
        self.gatewayIP = gatewayIP
        self.publicIP = publicIP
        self.ispName = ispName
        self.dnsServers = dnsServers
        self.averagePingMs = averagePingMs
        self.jitterMs = jitterMs
        self.packetLossPct = packetLossPct
        self.liveDownloadMbps = liveDownloadMbps
        self.liveUploadMbps = liveUploadMbps
        self.speedtestDownloadMbps = speedtestDownloadMbps
        self.speedtestUploadMbps = speedtestUploadMbps
        self.recentAlertsCount = recentAlertsCount
        self.tracerouteHopsCount = tracerouteHopsCount
    }

    /// Формирование структурированного текстового отчета для отправки в техподдержку интернет-провайдера
    public func generateISPSupportReport(template: ISPDisputeTemplate = .packetLossAndLatency) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateStr = formatter.string(from: Date())

        let pingStr = averagePingMs.map { String(format: "%.1f мс", $0) } ?? "N/A"
        let jitterStr = jitterMs.map { String(format: "%.2f мс (RFC 3550)", $0) } ?? "N/A"
        let speedStr = speedtestDownloadMbps.map { String(format: "%.1f Мбит/с", $0) } ?? String(format: "%.1f Мбит/с (live)", liveDownloadMbps)
        let uploadStr = speedtestUploadMbps.map { String(format: "%.1f Мбит/с", $0) } ?? String(format: "%.1f Мбит/с (live)", liveUploadMbps)

        let reasonTitle: String
        let legalReference: String

        switch template {
        case .packetLossAndLatency:
            reasonTitle = "ПРЕТЕНЗИЯ: Систематическая потеря сетевых пакетов и недопустимый джиттер"
            legalReference = "Нарушение требований качества передачи данных по протоколам TCP/UDP (ITU-T Rec. Y.1541, класс QoS 1)."
        case .speedMismatch:
            reasonTitle = "ПРЕТЕНЗИЯ: Несоответствие фактической скорости тарифному плану"
            legalReference = "Несоблюдение гарантированной полосы пропускания интернет-канала по договору оказания услуг связи."
        case .routingAndMTR:
            reasonTitle = "ПРЕТЕНЗИЯ: Деградация магистральной маршрутизации и потери на узлах оператора"
            legalReference = "Сбой транзитных пиринговых стыков и переполнение очередей на промежуточных L3-маршрутизаторах."
        }

        return """
        ================================================================
        NETPULSE AI — ОФИЦИАЛЬНАЯ ПРЕТЕНЗИЯ В ТЕХНИЧЕСКУЮ СЛУЖБУ ISP
        Тема: \(reasonTitle)
        Дата фиксации: \(dateStr)
        Нормативная база: \(legalReference)
        ================================================================

        1. СВЕДЕНИЯ ОБ АБОНЕНТЕ И ПОДКЛЮЧЕНИИ:
        • Оператор связи (ISP): \(ispName ?? "Не определен")
        • Тип сетевого интерфейса: \(connectionType)
        • Публичный IP-адрес: \(publicIP ?? "N/A")
        • Локальный IP абонента: \(localIP)
        • Основной шлюз доступа (Default Gateway): \(gatewayIP ?? "192.168.1.1")
        • Активные DNS-серверы: \(dnsServers.isEmpty ? "Системный (DHCP)" : dnsServers.joined(separator: ", "))

        2. РЕЗУЛЬТАТЫ ИЗМЕРЕНИЙ И ДИАГНОСТИКИ:
        • Задержка приема-передачи (RTT / Ping): \(pingStr)
        • Межпакетный джиттер (Jitter RFC 3550): \(jitterStr)
        • Коэффициент потери пакетов (Packet Loss): \(String(format: "%.2f", packetLossPct))%
        • Скорость входящего трафика (Download): \(speedStr)
        • Скорость исходящего трафика (Upload): \(uploadStr)

        3. ТЕХНИЧЕСКИЕ ДЕТАЛИ И СТАБИЛЬНОСТЬ:
        • Зафиксировано сетевых аномалий / алертов: \(recentAlertsCount)
        • Число пройденных узлов маршрутизации (MTR): \(tracerouteHopsCount)
        • Аппаратный источник телеметрии: Darwin Kernel BSD Socket Subsystem

        4. ТРЕБОВАНИЕ АБОНЕНТА:
        Прошу провести проверку кабельной линии связи, порта коммутатора доступа и магистральных стыков.
        Принять меры по стабилизации параметров RTT, устранению потерь пакетов и восстановлению заявленной скорости.

        Документ сформирован автоматически диагностическим модулем NetPulse AI (iOS 2026).
        ================================================================
        """
    }
}
