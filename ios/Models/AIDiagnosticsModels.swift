//
//  AIDiagnosticsModels.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import SwiftUI
import Security

// MARK: - 1. Провайдеры и конфигурация AI

/// Провайдер искусственного интеллекта для сетевого анализа
public enum AIProviderType: String, CaseIterable, Identifiable, Codable, Sendable {
    case offlineSmart = "Встроенный AI (Offline Smart)"
    case gemini = "Google Gemini"
    case openai = "OpenAI"
    case claude = "Anthropic Claude"
    case deepseek = "DeepSeek"

    public var id: String { rawValue }

    /// Модель по умолчанию. Название можно изменить в настройках AI.
    public var defaultModelName: String {
        switch self {
        case .offlineSmart: return "Локальная эвристическая модель"
        case .gemini: return "gemini-2.0-flash"
        case .openai: return "gpt-4o"
        case .claude: return "claude-opus-5-5"
        case .deepseek: return "deepseek-chat"
        }
    }

    /// Облачный провайдер: ему отправляются вопрос пользователя и сводные метрики сети
    public var isCloud: Bool {
        self != .offlineSmart
    }

    /// Ключ записи в Keychain и в настройках
    public var storageKey: String {
        switch self {
        case .offlineSmart: return "offline"
        case .gemini: return "gemini"
        case .openai: return "openai"
        case .claude: return "claude"
        case .deepseek: return "deepseek"
        }
    }
}

/// Конфигурация подключения к AI-провайдеру
public struct AIProviderConfig: Codable, Sendable {
    public var selectedProvider: AIProviderType
    /// Ключ API выбранного провайдера. В настройках приложения (UserDefaults) не хранится — только в Keychain
    /// (см. `AIConfigStore`). Раньше ключ вообще не сохранялся, а подпись в интерфейсе утверждала обратное.
    public var apiKey: String = ""
    public var customModel: String

    private enum CodingKeys: String, CodingKey {
        case selectedProvider
        case customModel
    }

    public init(
        selectedProvider: AIProviderType = .offlineSmart,
        apiKey: String = "",
        customModel: String = ""
    ) {
        self.selectedProvider = selectedProvider
        self.apiKey = apiKey
        // Раньше значение по умолчанию было «gemini-2.0-flash» для любого провайдера
        let trimmed = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.customModel = trimmed.isEmpty ? selectedProvider.defaultModelName : trimmed
    }
}

/// Хранилище настроек AI: провайдер и модель — в UserDefaults, ключи API — в Keychain (отдельный ключ на провайдера).
public enum AIConfigStore {
    private static let providerDefaultsKey = "netpulse_ai_provider"
    private static let modelDefaultsKeyPrefix = "netpulse_ai_model_"
    private static let keychainService = "com.samvel.netpulse.ai-keys"

    /// Загрузка сохранённой конфигурации (по умолчанию — встроенный AI)
    public static func load() -> AIProviderConfig {
        let defaults = UserDefaults.standard
        let provider = defaults.string(forKey: providerDefaultsKey).flatMap(AIProviderType.init(rawValue:)) ?? .offlineSmart
        return AIProviderConfig(
            selectedProvider: provider,
            apiKey: apiKey(for: provider),
            customModel: storedModel(for: provider)
        )
    }

    public static func save(_ config: AIProviderConfig) {
        let defaults = UserDefaults.standard
        defaults.set(config.selectedProvider.rawValue, forKey: providerDefaultsKey)
        defaults.set(config.customModel, forKey: modelDefaultsKeyPrefix + config.selectedProvider.storageKey)
        setAPIKey(config.apiKey, for: config.selectedProvider)
    }

    /// Ранее сохранённое название модели провайдера (или модель по умолчанию)
    public static func storedModel(for provider: AIProviderType) -> String {
        let stored = UserDefaults.standard.string(forKey: modelDefaultsKeyPrefix + provider.storageKey) ?? ""
        return stored.isEmpty ? provider.defaultModelName : stored
    }

    // MARK: Keychain

    private static func baseQuery(for provider: AIProviderType) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: provider.storageKey
        ]
    }

    public static func apiKey(for provider: AIProviderType) -> String {
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return ""
        }
        return key
    }

    private static func setAPIKey(_ key: String, for provider: AIProviderType) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = baseQuery(for: provider)

        guard !trimmed.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }

        let data = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            // Ключ доступен только на этом устройстве и только при разблокированном экране; в резервные копии не попадает
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
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

/// Полный отчет здоровья сети от AI.
///
/// Оценка считается только по реальным измерениям. Если данных для сценария нет, значение равно `nil`
/// (интерфейс показывает «—»): раньше при отсутствии измерений подставлялись пинг 25 мс, джиттер 2 мс и потери 0 %,
/// и отчёт сообщал «Идеальное качество сети».
public struct NetworkHealthReport: Identifiable, Codable, Sendable {
    public let id: UUID
    public let overallScore: Int? // 0 - 100, nil — данных недостаточно
    public let gamingScore: Int? // 0 - 100
    public let streamingScore: Int? // 0 - 100 (нужен замер скорости)
    public let videoCallScore: Int? // 0 - 100
    public let webBrowsingScore: Int? // 0 - 100
    public let statusTitle: String
    public let summaryText: String
    public let identifiedIssues: [NetworkIssue]
    public let recommendations: [NetworkRecommendation]
    public let timestamp: Date

    public var healthScore: Int? { overallScore }

    public var hasEnoughData: Bool { overallScore != nil }

    public var statusBadgeColor: Color {
        guard let overallScore else { return .gray }
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
        overallScore: Int?,
        gamingScore: Int?,
        streamingScore: Int?,
        videoCallScore: Int?,
        webBrowsingScore: Int?,
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
    /// Измерить нельзя (нет данных или iOS не даёт приложению такой информации) — вердикт не выносится
    case skipped = "Нет данных"
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

/// Полный отчет по сетевым аномалиям (анализируются текущие измерения, истории по часам приложение не ведёт)
public struct NetworkAnomalyReport: Identifiable, Codable, Sendable {
    public let id: UUID
    public let anomalies: [NetworkAnomalyItem]
    public let overallRiskLevel: IssueSeverity
    /// 0 — анализировался только текущий снимок измерений
    public let analyzedHours: Int
    public let generatedAt: Date

    public init(
        id: UUID = UUID(),
        anomalies: [NetworkAnomalyItem],
        overallRiskLevel: IssueSeverity = .info,
        analyzedHours: Int = 0,
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

/// Шаблон обращения в техподдержку интернет-провайдера
public enum ISPDisputeTemplate: String, CaseIterable, Identifiable, Codable, Sendable {
    case packetLossAndLatency = "Потери и задержка"
    case speedMismatch = "Скорость ниже тарифа"
    case routingAndMTR = "Проблемы на маршруте"

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
    /// Есть ли свежие результаты проверок. Если нет, «0 % потерь» означает отсутствие данных, а не отличное качество
    public let hasLiveData: Bool
    /// Текущая скорость трафика на устройстве (не пропускная способность канала)
    public let liveDownloadMbps: Double
    public let liveUploadMbps: Double
    public let speedtestDownloadMbps: Double?
    /// Отдача из замера скорости; 0 или nil — не измерена
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
        hasLiveData: Bool,
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
        self.hasLiveData = hasLiveData
        self.liveDownloadMbps = liveDownloadMbps
        self.liveUploadMbps = liveUploadMbps
        self.speedtestDownloadMbps = speedtestDownloadMbps
        self.speedtestUploadMbps = speedtestUploadMbps
        self.recentAlertsCount = recentAlertsCount
        self.tracerouteHopsCount = tracerouteHopsCount
    }

    /// Результат замера отдачи (0 означает «не измерено»)
    public var measuredUploadMbps: Double? {
        guard let upload = speedtestUploadMbps, upload > 0 else { return nil }
        return upload
    }

    /// Сводка метрик для облачного AI. Без IP-адресов и названия провайдера: для диагностики они не нужны,
    /// а в сторонний сервис уходить не должны.
    public var summaryForCloudAI: String {
        var lines: [String] = ["Тип подключения: \(connectionType)"]

        if hasLiveData {
            lines.append("Средний пинг до проверяемых узлов: " + (averagePingMs.map { String(format: "%.1f мс", $0) } ?? "узлы не отвечают"))
            lines.append("Джиттер: " + (jitterMs.map { String(format: "%.1f мс", $0) } ?? "не измерен"))
            lines.append("Потери пакетов в окне последних проверок: " + String(format: "%.1f %%", packetLossPct))
        } else {
            lines.append("Живой мониторинг: свежих данных нет (мониторинг остановлен или приложение было в фоне)")
        }

        if let download = speedtestDownloadMbps, download > 0 {
            let upload = measuredUploadMbps.map { String(format: "%.1f Мбит/с", $0) } ?? "не измерена"
            lines.append(String(format: "Последний замер скорости: загрузка %.1f Мбит/с, отдача ", download) + upload)
        } else {
            lines.append("Замер скорости не выполнялся")
        }
        lines.append(String(format: "Текущая скорость трафика на устройстве: ↓ %.1f / ↑ %.1f Мбит/с (это не пропускная способность канала)", liveDownloadMbps, liveUploadMbps))
        lines.append("Оповещений за сеанс: \(recentAlertsCount)")
        return lines.joined(separator: "\n")
    }

    /// Текст обращения в техподдержку провайдера. Содержит только измеренные значения; того, чего не измеряли,
    /// в нём нет (раньше шаблон утверждал «систематические потери» при потерях 0 %, подставлял шлюз 192.168.1.1
    /// и приписывал нарушение нормативов).
    public func generateISPSupportReport(template: ISPDisputeTemplate = .packetLossAndLatency) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateStr = formatter.string(from: Date())

        let pingStr: String
        let jitterStr: String
        let lossStr: String
        if hasLiveData {
            pingStr = averagePingMs.map { String(format: "%.1f мс", $0) } ?? "проверяемые узлы не отвечают"
            jitterStr = jitterMs.map { String(format: "%.2f мс (RFC 3550)", $0) } ?? "не измерен"
            lossStr = String(format: "%.2f %%", packetLossPct)
        } else {
            pingStr = "не измерялась (мониторинг не работал)"
            jitterStr = "не измерялся"
            lossStr = "не измерялись"
        }
        let downloadStr = speedtestDownloadMbps.flatMap { $0 > 0 ? String(format: "%.1f Мбит/с", $0) : nil } ?? "не измерялась"
        let uploadStr = measuredUploadMbps.map { String(format: "%.1f Мбит/с", $0) } ?? "не измерялась"

        let reasonTitle: String
        let reference: String
        let request: String

        switch template {
        case .packetLossAndLatency:
            reasonTitle = "ОБРАЩЕНИЕ: нестабильное соединение (потери пакетов, высокая задержка)"
            reference = "Справочно: ориентиры параметров IP-сетей (задержка, джиттер, потери) — ITU-T Y.1541."
            request = "Прошу проверить качество линии и параметры доступа на моём подключении и сообщить результат проверки."
        case .speedMismatch:
            reasonTitle = "ОБРАЩЕНИЕ: скорость подключения ниже указанной в тарифе"
            reference = "Справочно: условия моего тарифного плана и договора об оказании услуг связи."
            request = "Прошу проверить соответствие фактической скорости подключения моему тарифу и сообщить результат проверки."
        case .routingAndMTR:
            reasonTitle = "ОБРАЩЕНИЕ: проблемы на маршруте до внешних узлов"
            reference = "Справочно: трассировка (раздел 3); проблемный узел маршрута может принадлежать не моему оператору."
            request = "Прошу проверить маршрут от моего подключения до внешних узлов и сообщить результат проверки."
        }

        var connectionLines: [String] = [
            "• Оператор связи (ISP): \(ispName ?? "не определён")",
            "• Тип подключения: \(connectionType)",
            "• Публичный IP-адрес: \(publicIP ?? "не определён")"
        ]
        if !dnsServers.isEmpty {
            connectionLines.append("• DNS-серверы: \(dnsServers.joined(separator: ", "))")
        }

        let tracerouteLine = tracerouteHopsCount > 0
            ? "• Трассировка выполнена: узлов в маршруте — \(tracerouteHopsCount)"
            : "• Трассировка не выполнялась"

        return """
        ================================================================
        NETPULSE — ОБРАЩЕНИЕ В ТЕХНИЧЕСКУЮ ПОДДЕРЖКУ ПРОВАЙДЕРА
        Тема: \(reasonTitle)
        Дата фиксации: \(dateStr)
        \(reference)
        ================================================================

        1. СВЕДЕНИЯ О ПОДКЛЮЧЕНИИ:
        \(connectionLines.joined(separator: "\n"))

        2. РЕЗУЛЬТАТЫ ИЗМЕРЕНИЙ:
        • Задержка (среднее время установления TCP-соединения): \(pingStr)
        • Джиттер: \(jitterStr)
        • Потери пакетов (окно последних проверок): \(lossStr)
        • Скорость загрузки (замер): \(downloadStr)
        • Скорость отдачи (замер): \(uploadStr)

        3. ДОПОЛНИТЕЛЬНЫЕ СВЕДЕНИЯ:
        • Зафиксировано оповещений за сеанс: \(recentAlertsCount)
        \(tracerouteLine)
        • Метод измерений: время установления TCP-соединения с публичными узлами (Cloudflare, Google и др.), не ICMP.
          Измерения выполнены с мобильного устройства и сами по себе не показывают, где возникает проблема
          (Wi-Fi, оборудование абонента, оператор или удалённый узел).

        4. ПРОСЬБА:
        \(request)

        Документ сформирован приложением NetPulse по результатам измерений на устройстве абонента.
        ================================================================
        """
    }
}
