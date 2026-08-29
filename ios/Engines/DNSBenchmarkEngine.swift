//
//  DNSBenchmarkEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / Network.framework) - 2026.
//

import Foundation
import Network

/// Асинхронный многопоточный движок параллельного тестирования DNS-серверов
public actor DNSBenchmarkEngine {
    public static let shared = DNSBenchmarkEngine()

    private let testDomains = [
        "google.com",
        "apple.com",
        "cloudflare.com",
        "microsoft.com",
        "github.com"
    ]

    public init() {}

    /// Параллельный замер всех доступных DNS-провайдеров с передачей прогресса
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

        // Ранжирование: сначала доступные с минимальной задержкой
        let sorted = results.sorted { (a, b) -> Bool in
            if a.isReachable && !b.isReachable { return true }
            if !a.isReachable && b.isReachable { return false }
            return (a.latencyMs ?? 9999.0) < (b.latencyMs ?? 9999.0)
        }

        // Присвоение рангов (1, 2, 3...)
        return sorted.enumerated().map { idx, item in
            var updated = item
            if item.isReachable {
                updated.rank = idx + 1
            }
            return updated
        }
    }

    /// Замер конкретного DNS-сервера
    public func benchmarkSingleProvider(_ provider: DNSProviderInfo) async -> DNSBenchmarkResult {
        var latencies: [Double] = []

        for _ in 0..<3 {
            if let lat = await measureConnectLatency(to: provider.primaryIPv4, port: 53) {
                latencies.append(lat)
            }
        }

        if latencies.isEmpty {
            return DNSBenchmarkResult(
                provider: provider,
                latencyMs: nil,
                isReachable: false,
                successRatePct: 0.0,
                testedDomainsCount: 0
            )
        }

        let avg = latencies.reduce(0.0, +) / Double(latencies.count)
        let successRate = (Double(latencies.count) / 3.0) * 100.0
        let jitter = latencies.count > 1 ? abs(latencies.first! - latencies.last!) : 0.0

        return DNSBenchmarkResult(
            provider: provider,
            latencyMs: (avg * 10).rounded() / 10,
            isReachable: true,
            successRatePct: successRate,
            testedDomainsCount: testDomains.count,
            jitterMs: (jitter * 10).rounded() / 10
        )
    }

    /// Быстрый замер задержки TCP/UDP сокета до DNS сервера
    private func measureConnectLatency(to host: String, port: UInt16) async -> Double? {
        await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 53)
            )

            let params = NWParameters.tcp
            params.prohibitExpensivePaths = false
            params.expiredDNSBehavior = .allow

            let connection = NWConnection(to: endpoint, using: params)
            let queue = DispatchQueue(label: "com.samjan.netpulse.dns.\(host)", qos: .userInitiated)
            let startTime = Date()

            let box = SafeContinuationBox<Double?>(continuation)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = Date().timeIntervalSince(startTime) * 1000.0
                    connection.cancel()
                    box.resumeOnce(elapsed)
                case .failed, .cancelled:
                    box.resumeOnce(nil)
                case .waiting:
                    break
                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + 1.5) {
                connection.cancel()
                box.resumeOnce(nil)
            }
        }
    }

    /// Генерация официального конфигурационного профиля Apple (.mobileconfig) для DoH / DoT
    public func generateMobileConfig(for provider: DNSProviderInfo) -> String {
        let dohURL = provider.dohURL ?? "https://cloudflare-dns.com/dns-query"
        let uuidPayload = UUID().uuidString
        let uuidProfile = UUID().uuidString

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
                        <string>\(dohURL)</string>
                        <key>ServerAddresses</key>
                        <array>
                            <string>\(provider.primaryIPv4)</string>
                            <string>\(provider.secondaryIPv4)</string>
                        </array>
                    </dict>
                    <key>PayloadDescription</key>
                    <string>Настройка шифрованного DNS (DoH) для \(provider.name)</string>
                    <key>PayloadDisplayName</key>
                    <string>\(provider.name) DNS over HTTPS</string>
                    <key>PayloadIdentifier</key>
                    <string>com.samjan.netpulse.dns.\(provider.id)</string>
                    <key>PayloadType</key>
                    <string>com.apple.dnsSettings.managed</string>
                    <key>PayloadUUID</key>
                    <string>\(uuidPayload)</string>
                    <key>PayloadVersion</key>
                    <integer>1</integer>
                </dict>
            </array>
            <key>PayloadDescription</key>
            <string>Профиль сгенерирован в NetPulse (2026). Шифрует все DNS-запросы вашего устройства.</string>
            <key>PayloadDisplayName</key>
            <string>NetPulse: \(provider.name)</string>
            <key>PayloadIdentifier</key>
            <string>com.samjan.netpulse.profile.\(provider.id)</string>
            <key>PayloadOrganization</key>
            <string>NetPulse Security</string>
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
}
