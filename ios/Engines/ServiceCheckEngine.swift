//
//  ServiceCheckEngine.swift
//  NetPulse
//
//  Проверка доступности популярных сервисов: отвечает ли сайт сервиса и как быстро.
//

import Foundation

/// Сервис, доступность которого проверяется
public struct ServiceTarget: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    /// Значок SF Symbols
    public let icon: String
    public let url: URL

    public init(id: String, name: String, icon: String, url: URL) {
        self.id = id
        self.name = name
        self.icon = icon
        self.url = url
    }
}

/// Итог проверки одного сервиса
public enum ServiceState: String, Codable, Sendable {
    /// Ответил быстро
    case ok
    /// Ответил, но медленно
    case slow
    /// Не ответил
    case down

    public var title: String {
        switch self {
        case .ok: return "Работает"
        case .slow: return "Медленно"
        case .down: return "Не отвечает"
        }
    }
}

public struct ServiceCheckResult: Identifiable, Sendable, Equatable {
    public var id: String { targetID }
    public let targetID: String
    public let state: ServiceState
    /// Время до ответа сервера, миллисекунд (`nil`, если ответа не было)
    public let latencyMs: Double?
    /// Что произошло, человеческим языком: «Ответ за 240 мс» или причина сбоя
    public let detail: String
    public let checkedAt: Date

    public init(targetID: String, state: ServiceState, latencyMs: Double?, detail: String, checkedAt: Date = Date()) {
        self.targetID = targetID
        self.state = state
        self.latencyMs = latencyMs
        self.detail = detail
        self.checkedAt = checkedAt
    }
}

/// Проверка сервисов обычным защищённым запросом: любой ответ сервера (даже «доступ запрещён» или «не найдено»)
/// означает, что сервис досягаем. «Не отвечает» ставится только когда ответа нет вовсе: тайм-аут, обрыв, сбой DNS.
/// Мы видим только то, отвечает ли сервис с вашей сети, и не можем сказать, почему он не отвечает.
public enum ServiceCheckEngine {
    /// С какой задержки ответ считается медленным
    public static let slowThresholdMs: Double = 1_500
    /// Сколько ждать ответа, секунд
    public static let timeoutSeconds: TimeInterval = 8

    private static func site(_ string: String) -> URL {
        URL(string: string) ?? URL(fileURLWithPath: "/")
    }

    public static let targets: [ServiceTarget] = [
        ServiceTarget(id: "telegram", name: "Telegram", icon: "paperplane.fill", url: site("https://telegram.org/")),
        ServiceTarget(id: "whatsapp", name: "WhatsApp", icon: "message.fill", url: site("https://www.whatsapp.com/")),
        ServiceTarget(id: "youtube", name: "YouTube", icon: "play.rectangle.fill", url: site("https://www.youtube.com/generate_204")),
        ServiceTarget(id: "discord", name: "Discord", icon: "bubble.left.and.bubble.right.fill", url: site("https://discord.com/api/v9/gateway")),
        ServiceTarget(id: "instagram", name: "Instagram", icon: "camera.fill", url: site("https://www.instagram.com/")),
        ServiceTarget(id: "steam", name: "Steam", icon: "gamecontroller.fill", url: site("https://store.steampowered.com/")),
        ServiceTarget(id: "google", name: "Google", icon: "magnifyingglass", url: site("https://www.google.com/generate_204")),
        ServiceTarget(id: "yandex", name: "Яндекс", icon: "y.circle.fill", url: site("https://yandex.ru/")),
        ServiceTarget(id: "vk", name: "ВКонтакте", icon: "person.2.fill", url: site("https://vk.com/")),
        ServiceTarget(id: "cloudflare", name: "Cloudflare", icon: "cloud.fill", url: site("https://www.cloudflare.com/cdn-cgi/trace"))
    ]

    // MARK: - Правила

    /// Состояние по времени до ответа: нет ответа — «не отвечает», долго — «медленно»
    public static func classify(latencyMs: Double?) -> ServiceState {
        guard let latencyMs else { return .down }
        return latencyMs >= slowThresholdMs ? .slow : .ok
    }

    /// Причина сбоя понятными словами
    public static func describe(_ code: URLError.Code) -> String {
        switch code {
        case .timedOut:
            return "Нет ответа за \(Int(timeoutSeconds)) с"
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return "Нет подключения к интернету"
        case .cannotFindHost, .dnsLookupFailed:
            return "Адрес сервиса не находится (DNS)"
        case .cannotConnectToHost:
            return "Сервер не принимает соединение"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected:
            return "Не удалось установить защищённое соединение"
        case .cancelled:
            return "Проверка прервана"
        default:
            return "Сбой соединения"
        }
    }

    /// Вывод по всему списку: что не отвечает и как это понимать
    public static func verdict(_ results: [ServiceCheckResult]) -> String {
        guard !results.isEmpty else { return "Проверка ещё не выполнялась." }
        let down = results.filter { $0.state == .down }
        let slow = results.filter { $0.state == .slow }
        if down.count == results.count {
            return "Ни один сервис не ответил: похоже, нет подключения к интернету. Проверьте Wi-Fi или мобильную сеть."
        }
        var parts: [String] = []
        if !down.isEmpty {
            parts.append("Не отвечают: \(names(of: down)). Если остальное работает, дело в самом сервисе или в маршруте до него.")
        }
        if !slow.isEmpty {
            parts.append("Медленно отвечают: \(names(of: slow)).")
        }
        if parts.isEmpty {
            return "Все проверенные сервисы отвечают."
        }
        return parts.joined(separator: " ")
    }

    private static func names(of results: [ServiceCheckResult]) -> String {
        results
            .compactMap { result in targets.first(where: { $0.id == result.targetID })?.name }
            .joined(separator: ", ")
    }

    // MARK: - Проверка

    /// Проверяет один сервис: время до начала ответа сервера
    public static func check(_ target: ServiceTarget) async -> ServiceCheckResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutSeconds
        configuration.timeoutIntervalForResource = timeoutSeconds
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: target.url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        let started = Date()
        do {
            // Нужны только заголовки ответа: тело не читается, сессия закрывается сразу после замера
            let (_, response) = try await session.bytes(for: request)
            let elapsedMs = Date().timeIntervalSince(started) * 1_000
            _ = response
            let state = classify(latencyMs: elapsedMs)
            let detail = state == .slow
                ? "Ответ за \(formatLatency(elapsedMs)): медленно"
                : "Ответ за \(formatLatency(elapsedMs))"
            return ServiceCheckResult(targetID: target.id, state: state, latencyMs: elapsedMs, detail: detail)
        } catch let error as URLError {
            return ServiceCheckResult(targetID: target.id, state: .down, latencyMs: nil, detail: describe(error.code))
        } catch {
            return ServiceCheckResult(targetID: target.id, state: .down, latencyMs: nil, detail: "Сбой соединения")
        }
    }

    /// Проверяет все сервисы одновременно; результаты идут в порядке списка
    public static func checkAll(_ list: [ServiceTarget] = ServiceCheckEngine.targets) async -> [ServiceCheckResult] {
        await withTaskGroup(of: ServiceCheckResult.self, returning: [ServiceCheckResult].self) { group in
            for target in list {
                group.addTask { await ServiceCheckEngine.check(target) }
            }
            var byID: [String: ServiceCheckResult] = [:]
            for await result in group {
                byID[result.targetID] = result
            }
            return list.compactMap { byID[$0.id] }
        }
    }

    /// «240 мс» или «1.8 с»
    public static func formatLatency(_ ms: Double) -> String {
        ms >= 1_000 ? String(format: "%.1f с", ms / 1_000) : "\(Int(ms.rounded())) мс"
    }
}

// MARK: - История проверок

/// Запись одной проверки всех сервисов
public struct ServiceRun: Codable, Sendable, Equatable {
    public let date: Date
    public let states: [String: ServiceState]
}

/// Последние проверки сервисов хранятся на устройстве: по ним в строке видно, как сервис вёл себя раньше
@MainActor
public final class ServiceHistoryStore {
    public static let shared = ServiceHistoryStore()

    private static let key = "netpulse_service_history_v1"
    private static let maxRuns = 30

    private let defaults: UserDefaults
    public private(set) var runs: [ServiceRun]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let decoded = try? JSONDecoder().decode([ServiceRun].self, from: data) {
            self.runs = decoded
        } else {
            self.runs = []
        }
    }

    public func record(_ results: [ServiceCheckResult], at date: Date = Date()) {
        guard !results.isEmpty else { return }
        var states: [String: ServiceState] = [:]
        for result in results {
            states[result.targetID] = result.state
        }
        runs.append(ServiceRun(date: date, states: states))
        if runs.count > Self.maxRuns {
            runs.removeFirst(runs.count - Self.maxRuns)
        }
        if let data = try? JSONEncoder().encode(runs) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// Последние состояния сервиса, от старых к новым (для полоски точек)
    public func recentStates(for id: String, limit: Int = 12) -> [ServiceState] {
        runs.compactMap { $0.states[id] }.suffix(limit).map { $0 }
    }

    public func clear() {
        runs = []
        defaults.removeObject(forKey: Self.key)
    }
}
