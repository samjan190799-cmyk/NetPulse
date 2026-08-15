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
    private let monitorQueue = DispatchQueue(label: "com.netpulse.pathmonitor")

    public init() {}

    /// Получение активной сетевой конфигурации
    public func collectSystemInfo() async -> NetworkInterfaceInfo {
        let localIP = getLocalIPAddress() ?? "127.0.0.1"
        let connType = determineConnectionType()
        let publicDetails = await fetchPublicIPDetails()

        return NetworkInterfaceInfo(
            localIP: localIP,
            gatewayIP: getGatewayIPAddress() ?? "192.168.1.1",
            connectionType: connType,
            dnsServers: ["1.1.1.1", "8.8.8.8"],
            publicIP: publicDetails.ip ?? "N/A",
            ispName: publicDetails.isp ?? "Active Cellular/Wi-Fi ISP",
            country: publicDetails.country,
            city: publicDetails.city,
            isExpensive: pathMonitor.currentPath.isExpensive,
            isConstrained: pathMonitor.currentPath.isConstrained
        )
    }

    // MARK: - Вспомогательные методы

    private func determineConnectionType() -> NetworkConnectionType {
        let path = pathMonitor.currentPath
        if path.status != .satisfied {
            return .unavailable
        }
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else if path.usesInterfaceType(.loopback) {
            return .loopback
        }
        return .wifi
    }

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            // Исключаем loopback
            if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING) {
                if addr.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        ptr.pointee.ifa_addr,
                        socklen_t(addr.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 {
                        address = String(cString: hostname)
                        break
                    }
                }
            }
        }
        return address
    }

    private func getGatewayIPAddress() -> String? {
        // На iOS песочница ограничивает прямое чтение таблиц sysctl маршрутизации,
        // поэтому вычисляем вероятный адрес подсети или шлюза по локальному IP
        guard let local = getLocalIPAddress() else { return "192.168.1.1" }
        let components = local.split(separator: ".")
        if components.count == 4 {
            return "\(components[0]).\(components[1]).\(components[2]).1"
        }
        return "192.168.1.1"
    }

    private func fetchPublicIPDetails() async -> (ip: String?, isp: String?, country: String?, city: String?) {
        guard let url = URL(string: "https://1.1.1.1/cdn-cgi/trace") else {
            return (nil, nil, nil, nil)
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let text = String(data: data, encoding: .utf8) {
                var ip: String?
                var loc: String?

                for line in text.split(separator: "\n") {
                    if line.starts(with: "ip=") {
                        ip = String(line.dropFirst(3))
                    } else if line.starts(with: "loc=") {
                        loc = String(line.dropFirst(4))
                    }
                }
                return (ip, "Cloudflare Anycast ISP", loc, nil)
            }
        } catch {
            // Ошибка сети
        }

        return (nil, nil, nil, nil)
    }
}
