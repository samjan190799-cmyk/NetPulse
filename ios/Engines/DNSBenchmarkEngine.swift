//
//  DNSBenchmarkEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / Network.framework) - 2026.
//

import Foundation
import Network

/// Асинхронный движок параллельного тестирования DNS-серверов.
///
/// Каждому серверу отправляются настоящие DNS-запросы (запись A, UDP/53), ответ разбирается и проверяется.
/// Раньше «замер» был обычным TCP-подключением к порту 53, а число «проверенных доменов» бралось из длины списка,
/// хотя ни один домен не разрешался.
public actor DNSBenchmarkEngine {
    public static let shared = DNSBenchmarkEngine()

    /// Домены проверочных запросов. Это популярные домены: у крупных резолверов они почти всегда в кэше,
    /// поэтому замер отражает прежде всего скорость ответа сервера, а не рекурсивного разрешения.
    static let testDomains = ["google.com", "apple.com", "cloudflare.com", "microsoft.com", "github.com"]
    /// Таймаут одного запроса
    static let queryTimeoutSeconds: Double = 2.0

    public init() {}

    /// Параллельный замер DNS-серверов с передачей прогресса
    public func runBenchmark(
        providers: [DNSProviderInfo] = DNSProviderInfo.defaultCatalog,
        onProgress: (@Sendable (DNSBenchmarkResult) -> Void)? = nil
    ) async -> [DNSBenchmarkResult] {
        var results: [DNSBenchmarkResult] = []

        await withTaskGroup(of: DNSBenchmarkResult.self) { group in
            for provider in providers {
                group.addTask {
                    await self.benchmarkSingleProvider(provider)
                }
            }

            for await result in group {
                results.append(result)
                onProgress?(result)
            }
        }

        // Порядок: надёжные серверы по возрастанию задержки, затем нестабильные, затем не ответившие
        func tier(_ result: DNSBenchmarkResult) -> Int {
            if !result.isReachable { return 2 }
            return result.isUnstable ? 1 : 0
        }
        let sorted = results.sorted { a, b in
            let tierA = tier(a)
            let tierB = tier(b)
            if tierA != tierB { return tierA < tierB }
            return (a.latencyMs ?? .infinity) < (b.latencyMs ?? .infinity)
        }

        // Места получают только надёжные серверы: быстрый, но теряющий запросы сервер не должен быть «победителем»
        var nextRank = 1
        return sorted.map { item in
            var updated = item
            if item.isReachable && !item.isUnstable {
                updated.rank = nextRank
                nextRank += 1
            }
            return updated
        }
    }

    /// Замер конкретного DNS-сервера по реальным запросам
    public func benchmarkSingleProvider(_ provider: DNSProviderInfo) async -> DNSBenchmarkResult {
        let domains = Self.testDomains

        // Прогревочный запрос не учитывается: первый пакет после простоя включает разрешение ARP
        // и «пробуждение» радиомодуля, что искажает замер
        _ = await DNSQueryProbe.query(
            server: provider.primaryIPv4,
            domain: domains[0],
            timeoutSeconds: Self.queryTimeoutSeconds
        )

        var latencies: [Double] = []
        for domain in domains {
            if Task.isCancelled { break }
            if let latency = await DNSQueryProbe.query(
                server: provider.primaryIPv4,
                domain: domain,
                timeoutSeconds: Self.queryTimeoutSeconds
            ) {
                latencies.append(latency)
            }
        }

        let total = domains.count
        guard !latencies.isEmpty else {
            return DNSBenchmarkResult(
                provider: provider,
                latencyMs: nil,
                isReachable: false,
                isTested: true,
                successRatePct: 0.0,
                queriesSucceeded: 0,
                queriesTotal: total
            )
        }

        let sortedLatencies = latencies.sorted()
        let middle = sortedLatencies.count / 2
        let median = sortedLatencies.count % 2 == 0
            ? (sortedLatencies[middle - 1] + sortedLatencies[middle]) / 2.0
            : sortedLatencies[middle]

        // Джиттер — средняя абсолютная разница соседних ответов (как в RFC 3550), а не |первый − последний|
        var jitter: Double?
        if latencies.count > 1 {
            var differences = 0.0
            for index in 1..<latencies.count {
                differences += abs(latencies[index] - latencies[index - 1])
            }
            jitter = differences / Double(latencies.count - 1)
        }

        return DNSBenchmarkResult(
            provider: provider,
            latencyMs: (median * 10).rounded() / 10,
            isReachable: true,
            isTested: true,
            successRatePct: Double(latencies.count) / Double(total) * 100.0,
            queriesSucceeded: latencies.count,
            queriesTotal: total,
            jitterMs: jitter.map { ($0 * 10).rounded() / 10 }
        )
    }

    /// Генерация конфигурационного профиля Apple (.mobileconfig) для DNS-over-HTTPS.
    /// Для серверов без DoH-адреса профиль не создаётся (раньше подставлялся адрес Cloudflare, то есть профиль
    /// «Яндекс» устанавливал бы DNS другой компании).
    public func generateMobileConfig(for provider: DNSProviderInfo) -> String? {
        guard let dohURL = provider.dohURL else { return nil }

        let identifierPrefix = Bundle.main.bundleIdentifier ?? "com.samvel.netpulse"
        let uuidPayload = UUID().uuidString
        let uuidProfile = UUID().uuidString
        let addressesXML = [provider.primaryIPv4, provider.secondaryIPv4]
            .filter { !$0.isEmpty }
            .map { "                            <string>\(Self.xmlEscaped($0))</string>" }
            .joined(separator: "\n")
        let name = Self.xmlEscaped(provider.name)
        let identifierSuffix = Self.xmlEscaped(provider.id)

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>PayloadContent</key>
            <array>
                <dict>
                    <key>DNSSettings</key>
                    <dict>
                        <key>DNSProtocol</key>
                        <string>HTTPS</string>
                        <key>ServerURL</key>
                        <string>\(Self.xmlEscaped(dohURL))</string>
                        <key>ServerAddresses</key>
                        <array>
        \(addressesXML)
                        </array>
                    </dict>
                    <key>PayloadDescription</key>
                    <string>Настройка шифрованного DNS (DoH) для \(name)</string>
                    <key>PayloadDisplayName</key>
                    <string>\(name) DNS over HTTPS</string>
                    <key>PayloadIdentifier</key>
                    <string>\(identifierPrefix).dns.\(identifierSuffix)</string>
                    <key>PayloadType</key>
                    <string>com.apple.dnsSettings.managed</string>
                    <key>PayloadUUID</key>
                    <string>\(uuidPayload)</string>
                    <key>PayloadVersion</key>
                    <integer>1</integer>
                </dict>
            </array>
            <key>PayloadDescription</key>
            <string>Профиль сгенерирован в NetPulse. Направляет DNS-запросы устройства на сервер \(name) по зашифрованному каналу.</string>
            <key>PayloadDisplayName</key>
            <string>NetPulse: \(name)</string>
            <key>PayloadIdentifier</key>
            <string>\(identifierPrefix).profile.\(identifierSuffix)</string>
            <key>PayloadOrganization</key>
            <string>NetPulse</string>
            <key>PayloadRemovalDisallowed</key>
            <false/>
            <key>PayloadType</key>
            <string>Configuration</string>
            <key>PayloadUUID</key>
            <string>\(uuidProfile)</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
        </plist>
        """
    }

    private static func xmlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Один DNS-запрос по UDP

/// Отправка одного DNS-запроса (запись A) и замер времени до корректного ответа.
private enum DNSQueryProbe {
    /// Время ответа в мс. `nil` — ответа нет, он пришёл с ошибкой или не соответствует запросу.
    static func query(server: String, domain: String, timeoutSeconds: Double) async -> Double? {
        let queryID = UInt16.random(in: 0...UInt16.max)
        guard let packet = makeQuery(id: queryID, domain: domain) else { return nil }

        return await withCheckedContinuation { continuation in
            let box = SafeContinuationBox<Double?>(continuation)
            let connection = NWConnection(host: NWEndpoint.Host(server), port: 53, using: .udp)
            let queue = DispatchQueue(label: "com.samvel.netpulse.dns.\(server)", qos: .userInitiated)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let sentAt = ContinuousClock().now
                    connection.send(content: packet, completion: .contentProcessed { error in
                        if error != nil {
                            connection.cancel()
                            box.resumeOnce(nil)
                        }
                    })
                    connection.receiveMessage { data, _, _, error in
                        defer { connection.cancel() }
                        guard error == nil, let data, isValidAnswer(data, expectedID: queryID) else {
                            box.resumeOnce(nil)
                            return
                        }
                        let elapsed = ContinuousClock().now - sentAt
                        let milliseconds = Double(elapsed.components.seconds) * 1000.0
                            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0
                        box.resumeOnce(milliseconds)
                    }
                case .failed, .cancelled:
                    box.resumeOnce(nil)
                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                connection.cancel()
                box.resumeOnce(nil)
            }
        }
    }

    /// DNS-запрос по RFC 1035: заголовок (ID, RD=1, один вопрос), имя по меткам, тип A, класс IN.
    static func makeQuery(id: UInt16, domain: String) -> Data? {
        var packet = Data()
        packet.append(UInt8(id >> 8))
        packet.append(UInt8(id & 0xFF))
        packet.append(contentsOf: [0x01, 0x00])                         // флаги: стандартный запрос, рекурсия желательна
        packet.append(contentsOf: [0x00, 0x01])                         // QDCOUNT = 1
        packet.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) // ANCOUNT, NSCOUNT, ARCOUNT = 0

        for label in domain.split(separator: ".") {
            let bytes = Array(label.utf8)
            guard !bytes.isEmpty, bytes.count <= 63 else { return nil }
            packet.append(UInt8(bytes.count))
            packet.append(contentsOf: bytes)
        }
        packet.append(0x00)                                             // конец имени
        packet.append(contentsOf: [0x00, 0x01])                         // QTYPE = A
        packet.append(contentsOf: [0x00, 0x01])                         // QCLASS = IN
        return packet
    }

    /// Корректный ответ: тот же ID, флаг ответа, RCODE = 0 (без ошибки) и хотя бы одна запись в ответе.
    static func isValidAnswer(_ data: Data, expectedID: UInt16) -> Bool {
        guard data.count >= 12 else { return false }
        let bytes = [UInt8](data.prefix(12))
        let responseID = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        guard responseID == expectedID else { return false }

        let flags = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        let isResponse = flags & 0x8000 != 0
        let responseCode = flags & 0x000F
        let answerCount = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        return isResponse && responseCode == 0 && answerCount > 0
    }
}
