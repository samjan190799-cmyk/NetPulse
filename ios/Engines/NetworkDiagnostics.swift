//
//  NetworkDiagnostics.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import Network

/// Диагностика сетевых параметров iOS (интерфейсы, IP, шлюз, провайдер).
public actor NetworkDiagnostics {
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.netpulse.pathmonitor", qos: .utility)
    private var lastKnownPath: NWPath?
    
    private var cachedPublicDetails: (ip: String?, isp: String?, country: String?, city: String?)?
    private var lastDetailsFetchDate: Date?
    private var lastConnectionType: NetworkConnectionType?

    public init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { [weak self] in
                await self?.updatePath(path)
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    private func updatePath(_ path: NWPath) {
        self.lastKnownPath = path
    }

    /// Получение активной сетевой конфигурации с гарантированным определением типа сети
    public func collectSystemInfo() async -> NetworkInterfaceInfo {
        let (connType, localIP) = detectActiveInterfaceAndIP()
        let publicDetails = await fetchPublicIPDetails(connType: connType)

        let isExpensive = lastKnownPath?.isExpensive ?? (connType == .cellular)
        let isConstrained = lastKnownPath?.isConstrained ?? false

        // Корректное отображение имени провайдера или типа подключения
        let defaultISP: String
        switch connType {
        case .wifi:
            defaultISP = publicDetails.isp ?? "Wi-Fi Подключение"
        case .cellular:
            defaultISP = publicDetails.isp ?? "Мобильная сеть (5G/LTE)"
        case .ethernet:
            defaultISP = publicDetails.isp ?? "Ethernet Сеть"
        case .loopback:
            defaultISP = "Локальный интерфейс"
        case .unavailable:
            defaultISP = "Подключение отсутствует"
        }

        return NetworkInterfaceInfo(
            localIP: localIP,
            gatewayIP: getGatewayIPAddress(for: localIP),
            connectionType: connType,
            dnsServers: ["1.1.1.1", "8.8.8.8"],
            publicIP: publicDetails.ip ?? localIP,
            ispName: defaultISP,
            country: publicDetails.country,
            city: publicDetails.city,
            isExpensive: isExpensive,
            isConstrained: isConstrained
        )
    }

    // MARK: - Гарантированное определение типа соединения и локального IP

    private func detectActiveInterfaceAndIP() -> (NetworkConnectionType, String) {
        var wifiIP: String?
        var cellIP: String?
        var otherIP: String?

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return (determineConnectionTypeFromNWPath(), "127.0.0.1")
        }
        defer { freeifaddrs(ifaddr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let ptr = cursor {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isRunning = (flags & IFF_RUNNING) == IFF_RUNNING
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            if isUp && isRunning && !isLoopback, let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
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
                        wifiIP = ipStr
                    } else if ifName.hasPrefix("pdp_ip") {
                        cellIP = ipStr
                    } else {
                        otherIP = ipStr
                    }
                }
            }
            cursor = ptr.pointee.ifa_next
        }

        // Приоритеты: NWPathMonitor -> затем физические активные интерфейсы BSD
        let nwPath = lastKnownPath ?? pathMonitor.currentPath
        if nwPath.status == .satisfied {
            if nwPath.usesInterfaceType(.wifi), let ip = wifiIP {
                return (.wifi, ip)
            } else if nwPath.usesInterfaceType(.cellular), let ip = cellIP {
                return (.cellular, ip)
            } else if nwPath.usesInterfaceType(.wiredEthernet) {
                return (.ethernet, wifiIP ?? otherIP ?? "127.0.0.1")
            }
        }

        // Если NWPath еще не обновился, смотрим на физические сокеты
        if let wIP = wifiIP {
            return (.wifi, wIP)
        } else if let cIP = cellIP {
            return (.cellular, cIP)
        } else if let oIP = otherIP {
            return (.ethernet, oIP)
        }

        return (.unavailable, "127.0.0.1")
    }

    private func determineConnectionTypeFromNWPath() -> NetworkConnectionType {
        let path = lastKnownPath ?? pathMonitor.currentPath
        if path.status != .satisfied {
            return .unavailable
        }
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        }
        return .unavailable
    }

    private func getGatewayIPAddress(for localIP: String) -> String {
        let components = localIP.split(separator: ".")
        if components.count == 4 {
            return "\(components[0]).\(components[1]).\(components[2]).1"
        }
        return "192.168.1.1"
    }

    // MARK: - Определение внешнего IP и реального провайдера через Anycast с авто-фолбеком

    private func fetchPublicIPDetails(connType: NetworkConnectionType) async -> (ip: String?, isp: String?, country: String?, city: String?) {
        guard connType != .unavailable else {
            return (nil, nil, nil, nil)
        }

        // Проверяем актуальность кэша (5 минут) при неизменном типе подключения
        if let cached = cachedPublicDetails,
           let lastDate = lastDetailsFetchDate,
           lastConnectionType == connType,
           Date().timeIntervalSince(lastDate) < 300.0 {
            return cached
        }

        let ispName = connType == .cellular ? "Мобильная сеть (LTE/5G)" : "Wi-Fi Сеть (Интернет)"

        // 1. Cloudflare Anycast endpoint
        if let url = URL(string: "https://1.1.1.1/cdn-cgi/trace") {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2.5
            if let (data, _) = try? await URLSession.shared.data(for: request),
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
                    let result = (foundIP, ispName, loc, nil as String?)
                    self.cachedPublicDetails = result
                    self.lastDetailsFetchDate = Date()
                    self.lastConnectionType = connType
                    return result
                }
            }
        }

        // 2. Fallback: ipify
        if let url = URL(string: "https://api.ipify.org?format=json") {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2.5
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ip = json["ip"] as? String {
                let result = (ip, ispName, nil as String?, nil as String?)
                self.cachedPublicDetails = result
                self.lastDetailsFetchDate = Date()
                self.lastConnectionType = connType
                return result
            }
        }

        // 3. Fallback: icanhazip
        if let url = URL(string: "https://icanhazip.com") {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2.5
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                let result = (text, ispName, nil as String?, nil as String?)
                self.cachedPublicDetails = result
                self.lastDetailsFetchDate = Date()
                self.lastConnectionType = connType
                return result
            }
        }

        let fallback = (nil as String?, ispName, nil as String?, nil as String?)
        return fallback
    }
}
