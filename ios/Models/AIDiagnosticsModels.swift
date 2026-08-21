//
//  AIDiagnosticsModels.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import SwiftUI

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
        identifiedIssues: [NetworkIssue] = [],
        recommendations: [NetworkRecommendation] = [],
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

/// Роль отправителя сообщения в чате
public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

/// Сообщение в интеллектуальном диалоге с AI
public struct AIMessage: Identifiable, Codable, Sendable {
    public let id: UUID
    public let role: MessageRole
    public let content: String
    public let timestamp: Date
    public let suggestedPrompts: [String]

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        suggestedPrompts: [String] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.suggestedPrompts = suggestedPrompts
    }
}

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
    public func generateISPSupportReport() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateStr = formatter.string(from: Date())

        let pingStr = averagePingMs.map { String(format: "%.1f мс", $0) } ?? "N/A"
        let jitterStr = jitterMs.map { String(format: "%.2f мс (RFC 3550)", $0) } ?? "N/A"
        let speedStr = speedtestDownloadMbps.map { String(format: "%.1f Мбит/с", $0) } ?? String(format: "%.1f Мбит/с (live)", liveDownloadMbps)
        let uploadStr = speedtestUploadMbps.map { String(format: "%.1f Мбит/с", $0) } ?? String(format: "%.1f Мбит/с (live)", liveUploadMbps)

        return """
        ========================================
        NETPULSE AI — ТЕХНИЧЕСКИЙ ОТЧЕТ ДЛЯ ISP
        Дата и время: \(dateStr)
        ========================================

        1. СВЕДЕНИЯ О ПОДКЛЮЧЕНИИ:
        • Тип сети: \(connectionType)
        • Провайдер: \(ispName ?? "Не определен")
        • Публичный IP: \(publicIP ?? "N/A")
        • Локальный IP: \(localIP)
        • Основной шлюз: \(gatewayIP ?? "192.168.1.1")
        • DNS-серверы: \(dnsServers.isEmpty ? "Системный (DHCP)" : dnsServers.joined(separator: ", "))

        2. СЕТЕВЫЕ МЕТРИКИ И СТАБИЛЬНОСТЬ:
        • Задержка RTT (Ping): \(pingStr)
        • Джиттер: \(jitterStr)
        • Потери пакетов (Packet Loss): \(String(format: "%.2f", packetLossPct))%
        • Скорость скачивания: \(speedStr)
        • Скорость отдачи: \(uploadStr)

        3. ДИАГНОСТИЧЕСКИЕ ДАННЫЕ:
        • Активных сетевых алертов: \(recentAlertsCount)
        • Пройдено узлов трассировки (MTR): \(tracerouteHopsCount)
        • Движок телеметрии: Darwin Kernel BSD Socket Subsystem

        Сгенерировано автоматически диагностическим модулем NetPulse AI (iOS).
        ========================================
        """
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
    public let steps: [TroubleshootingStep]
    public let conclusion: String
    public let actionPlan: [String]
    public let isIssueFound: Bool
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        steps: [TroubleshootingStep],
        conclusion: String,
        actionPlan: [String],
        isIssueFound: Bool,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.steps = steps
        self.conclusion = conclusion
        self.actionPlan = actionPlan
        self.isIssueFound = isIssueFound
        self.timestamp = timestamp
    }
}

