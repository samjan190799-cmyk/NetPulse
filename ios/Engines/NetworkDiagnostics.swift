//
//  NetworkDiagnostics.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import Network

/// Диагностика сетевых параметров iOS (интерфейсы, IP, шлюз, провайдер).
///
/// Принцип: если значение определить нельзя, возвращается `nil` / пустой список / «—», а не правдоподобная
/// выдумка. Раньше при неудаче подставлялись шлюз «x.x.x.1», DNS 1.1.1.1 / 8.8.8.8, локальный IP 100.64.0.1,
/// «публичный IP», равный локальному, а отсутствие сети определялось как «сотовая сеть».
public actor NetworkDiagnostics {
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.netpulse.pathmonitor", qos: .utility)
    private var lastKnownPath: NWPath?

    private typealias PublicDetails = (ip: String?, isp: String?, country: String?, city: String?)

    private var cachedPublicDetails: PublicDetails?
    private var cachedDetailsKey: String?
    private var lastDetailsFetchDate: Date?
    private var lastFailedFetchDate: Date?
    private var lastFailedFetchKey: String?

    public init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { [weak self] in
                await self?.updatePath(path)
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    deinit {
        // Каждый экземпляр запускает свой NWPathMonitor — без отмены он жил бы до конца процесса
        pathMonitor.cancel()
    }

    private func updatePath(_ path: NWPath) {
        self.lastKnownPath = path
    }

    /// Быстрый снимок локальной конфигурации (без обращений в интернет).
    /// Публичный IP и провайдер подставляются только из кэша.
    public func collectLocalInfo() async -> NetworkInterfaceInfo {
        await waitForFirstPathUpdate()
        let path = lastKnownPath ?? pathMonitor.currentPath
        let (connType, localIP) = detectActiveInterfaceAndIP(path: path)
        let gatewayIP = detectGatewayIP(path: path, connType: connType)
        let key = cacheKey(connType: connType, localIP: localIP, gatewayIP: gatewayIP)
        let cached: PublicDetails? = (cachedDetailsKey == key) ? cachedPublicDetails : nil
        return makeInfo(
            path: path,
            connType: connType,
            localIP: localIP,
            gatewayIP: gatewayIP,
            details: cached ?? noPublicDetails()
        )
    }

    private func noPublicDetails() -> PublicDetails {
        return (nil, nil, nil, nil)
    }

    /// Получение активной сетевой конфигурации (включая публичный IP и провайдера)
    public func collectSystemInfo() async -> NetworkInterfaceInfo {
        await waitForFirstPathUpdate()
        let path = lastKnownPath ?? pathMonitor.currentPath
        let (connType, localIP) = detectActiveInterfaceAndIP(path: path)
        let gatewayIP = detectGatewayIP(path: path, connType: connType)
        let details = await fetchPublicIPDetails(connType: connType, localIP: localIP, gatewayIP: gatewayIP)
        return makeInfo(path: path, connType: connType, localIP: localIP, gatewayIP: gatewayIP, details: details)
    }

    private func makeInfo(
        path: NWPath,
        connType: NetworkConnectionType,
        localIP: String?,
        gatewayIP: String?,
        details: PublicDetails
    ) -> NetworkInterfaceInfo {
        NetworkInterfaceInfo(
            localIP: localIP ?? "—",
            gatewayIP: gatewayIP,
            connectionType: connType,
            // Системные DNS-серверы публичного API iOS не отдаёт — пустой список означает «не определены»
            dnsServers: [],
            publicIP: details.ip,
            ispName: details.isp,
            country: details.country,
            city: details.city,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }

    /// Сразу после запуска монитор ещё не прислал первый путь — коротко ждём, чтобы не принять это за «нет сети».
    private func waitForFirstPathUpdate() async {
        guard lastKnownPath == nil else { return }
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if lastKnownPath != nil { return }
        }
    }

    // MARK: - Определение типа соединения и локального IP

    private func detectActiveInterfaceAndIP(path: NWPath) -> (NetworkConnectionType, String?) {
        var wifiIP: String?
        var cellIP: String?
        var otherIP: String?

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr {
            defer { freeifaddrs(ifaddr) }

            var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
            while let ptr = cursor {
                let flags = Int32(ptr.pointee.ifa_flags)
                let isUp = (flags & IFF_UP) == IFF_UP
                let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

                if isUp && !isLoopback, let addr = ptr.pointee.ifa_addr {
                    let family = addr.pointee.sa_family
                    if family == UInt8(AF_INET) || family == UInt8(AF_INET6) {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(
                            ptr.pointee.ifa_addr,
                            socklen_t(addr.pointee.sa_len),
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            0,
                            NI_NUMERICHOST
                        ) == 0 {
                            let ipStr = String(cString: hostname)
                            let ifName = String(cString: ptr.pointee.ifa_name)

                            if ifName.hasPrefix("en") {
                                if wifiIP == nil || family == UInt8(AF_INET) {
                                    wifiIP = ipStr
                                }
                            } else if ifName.hasPrefix("pdp_ip") {
                                if cellIP == nil || family == UInt8(AF_INET) {
                                    cellIP = ipStr
                                }
                            } else if ifName.hasPrefix("utun") || ifName.hasPrefix("ipsec") {
                                otherIP = ipStr
                            }
                        }
                    }
                }
                cursor = ptr.pointee.ifa_next
            }
        }

        // Нет маршрута в интернет (авиарежим, Wi-Fi без сети и т.п.) — так и сообщаем
        guard path.status == .satisfied else {
            return (.unavailable, nil)
        }

        if path.usesInterfaceType(.wifi) {
            return (.wifi, wifiIP)
        } else if path.usesInterfaceType(.cellular) {
            return (.cellular, cellIP)
        } else if path.usesInterfaceType(.wiredEthernet) {
            return (.ethernet, wifiIP ?? otherIP)
        }

        // Любой другой активный маршрут (VPN / Relay): определяем по найденным интерфейсам
        if let wIP = wifiIP {
            return (.wifi, wIP)
        } else if let cIP = cellIP {
            return (.cellular, cIP)
        } else if let oIP = otherIP {
            return (.cellular, oIP)
        }
        return (.unavailable, nil)
    }

    /// Реальный шлюз по умолчанию из системного маршрута (NWPath.gateways).
    /// Раньше он вычислялся как «первые три октета локального IP + .1», что неверно для многих сетей.
    private func detectGatewayIP(path: NWPath, connType: NetworkConnectionType) -> String? {
        // В мобильной сети «шлюз» — это не домашний роутер, пинговать его бессмысленно
        guard connType == .wifi || connType == .ethernet else { return nil }
        for gateway in path.gateways {
            if case .hostPort(let host, _) = gateway, case .ipv4(let address) = host {
                let octets = address.rawValue
                if octets.count == 4 {
                    return octets.map { String($0) }.joined(separator: ".")
                }
            }
        }
        return nil
    }

    // MARK: - Определение внешнего IP и провайдера с авто-фолбеком

    private func cacheKey(connType: NetworkConnectionType, localIP: String?, gatewayIP: String?) -> String {
        "\(connType.rawValue)|\(localIP ?? "")|\(gatewayIP ?? "")"
    }

    private func fetchData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.5
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return nil
        }
        return data
    }

    private func fetchPublicIPDetails(
        connType: NetworkConnectionType,
        localIP: String?,
        gatewayIP: String?
    ) async -> PublicDetails {
        guard connType != .unavailable else {
            return (nil, nil, nil, nil)
        }

        // Кэш (5 минут) действует, только пока не сменилась сеть: тип подключения, локальный IP и шлюз
        let key = cacheKey(connType: connType, localIP: localIP, gatewayIP: gatewayIP)
        if let cached = cachedPublicDetails,
           let lastDate = lastDetailsFetchDate,
           cachedDetailsKey == key,
           Date().timeIntervalSince(lastDate) < 300.0 {
            return cached
        }

        // Неудачный опрос не повторяем чаще раза в минуту (иначе до 4 × 2,5 с ожидания каждые 20 секунд)
        if let failedDate = lastFailedFetchDate,
           lastFailedFetchKey == key,
           Date().timeIntervalSince(failedDate) < 60.0 {
            return (nil, nil, nil, nil)
        }

        var found: PublicDetails?

        // 1. ipapi.co: IP, провайдер, страна и город одним запросом
        if let url = URL(string: "https://ipapi.co/json/"),
           let data = await fetchData(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["error"] == nil,
           let ip = json["ip"] as? String, !ip.isEmpty {
            found = (ip, json["org"] as? String, json["country_name"] as? String, json["city"] as? String)
        }

        // 2. Cloudflare Anycast endpoint: IP и код страны
        if found == nil, let url = URL(string: "https://1.1.1.1/cdn-cgi/trace"),
           let data = await fetchData(from: url),
           let text = String(data: data, encoding: .utf8) {
            var ip: String?
            var loc: String?

            for line in text.split(separator: "\n") {
                if line.starts(with: "ip=") {
                    ip = String(line.dropFirst(3))
                } else if line.starts(with: "loc=") {
                    loc = String(line.dropFirst(4))
                }
            }

            if let foundIP = ip {
                found = (foundIP, nil, loc, nil)
            }
        }

        // 3. Fallback: ipify
        if found == nil, let url = URL(string: "https://api.ipify.org?format=json"),
           let data = await fetchData(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ip = json["ip"] as? String {
            found = (ip, nil, nil, nil)
        }

        // 4. Fallback: icanhazip
        if found == nil, let url = URL(string: "https://icanhazip.com"),
           let data = await fetchData(from: url),
           let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            found = (text, nil, nil, nil)
        }

        if let result = found {
            cachedPublicDetails = result
            cachedDetailsKey = key
            lastDetailsFetchDate = Date()
            lastFailedFetchDate = nil
            lastFailedFetchKey = nil
            return result
        }

        lastFailedFetchDate = Date()
        lastFailedFetchKey = key
        return (nil, nil, nil, nil)
    }
}

/// Потокобезопасный бокс однократного возобновления CheckedContinuation
public final class SafeContinuationBox<T: Sendable>: @unchecked Sendable {
    private var isResumed = false
    private let lock = NSLock()
    nonisolated(unsafe) private var continuation: CheckedContinuation<T, Never>?

    public init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    public func resumeOnce(_ value: T) {
        lock.lock()
        defer { lock.unlock() }
        if !isResumed {
            isResumed = true
            continuation?.resume(returning: value)
            continuation = nil
        }
    }
}
