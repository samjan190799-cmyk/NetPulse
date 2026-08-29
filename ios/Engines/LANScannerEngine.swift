//
//  LANScannerEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / Network.framework) - 2026.
//

import Foundation
import Network

/// Асинхронный движок сканирования устройств локальной сети (ARP & Socket Probe)
public actor LANScannerEngine {
    public static let shared = LANScannerEngine()

    private let commonPorts: [(UInt16, String, Bool)] = [
        (80, "HTTP Web", false),
        (443, "HTTPS Web", false),
        (22, "SSH Remote", true),
        (53, "DNS Service", false),
        (445, "SMB Windows Share", true),
        (8080, "Web Proxy / Alt", false),
        (554, "RTSP IP-Камера", true),
        (62078, "Apple iOS Sync", false),
        (7000, "Apple AirPlay", false)
    ]

    public init() {}

    /// Сканирование локальной подсети /24
    public func scanSubnet(
        localIP: String?,
        gatewayIP: String?,
        onProgress: (@Sendable (Int, Int, LANDevice?) -> Void)? = nil
    ) async -> [LANDevice] {
        let baseSubnet = extractSubnetPrefix(from: localIP ?? gatewayIP ?? "192.168.1.100")
        var discoveredDevices: [LANDevice] = []
        var scannedCount = 0
        let totalHosts = 254

        // Всегда добавляем шлюз и локальное устройство, если известны
        if let gw = gatewayIP, !gw.isEmpty {
            let gwDev = LANDevice(
                ipAddress: gw,
                hostname: "Домашний роутер (Шлюз)",
                vendorName: "Маршрутизатор",
                deviceType: .router,
                latencyMs: 1.2,
                openPorts: [LANOpenPort(portNumber: 80, serviceName: "Web UI"), LANOpenPort(portNumber: 53, serviceName: "DNS")],
                isGateway: true
            )
            discoveredDevices.append(gwDev)
            onProgress?(1, totalHosts, gwDev)
        }

        if let myIP = localIP, !myIP.isEmpty && myIP != gatewayIP {
            let myDev = LANDevice(
                ipAddress: myIP,
                hostname: "Этот iPhone",
                vendorName: "Apple Inc.",
                deviceType: .smartphone,
                latencyMs: 0.2,
                isCurrentDevice: true
            )
            discoveredDevices.append(myDev)
            onProgress?(2, totalHosts, myDev)
        }

        // Параллельное сканирование портов диапазона 1...254 пакетами по 20 хостов
        let batchSize = 25
        for start in stride(from: 1, to: totalHosts, by: batchSize) {
            let end = min(start + batchSize - 1, totalHosts)

            await withTaskGroup(of: LANDevice?.self) { group in
                for hostNum in start...end {
                    let targetIP = "\(baseSubnet)\(hostNum)"
                    if targetIP == localIP || targetIP == gatewayIP {
                        continue
                    }

                    group.addTask {
                        await self.probeHost(ip: targetIP)
                    }
                }

                for await dev in group {
                    scannedCount += 1
                    if let dev = dev {
                        discoveredDevices.append(dev)
                    }
                    onProgress?(scannedCount, totalHosts, dev)
                }
            }
        }

        return discoveredDevices.sorted { (a, b) -> Bool in
            let aLast = Int(a.ipAddress.split(separator: ".").last ?? "0") ?? 0
            let bLast = Int(b.ipAddress.split(separator: ".").last ?? "0") ?? 0
            return aLast < bLast
        }
    }

    /// Проверка отклика и открытых портов на конкретном IP
    private func probeHost(ip: String) async -> LANDevice? {
        var openPorts: [LANOpenPort] = []
        var fastestLatency: Double? = nil

        // Проверяем ключевые порты
        let probePorts: [UInt16] = [80, 443, 22, 445, 8080, 554, 62078]

        for port in probePorts {
            if let lat = await checkPort(ip: ip, port: port) {
                if let current = fastestLatency {
                    if lat < current {
                        fastestLatency = lat
                    }
                } else {
                    fastestLatency = lat
                }
                let service = commonPorts.first(where: { $0.0 == port })?.1 ?? "TCP Service"
                let isCritical = commonPorts.first(where: { $0.0 == port })?.2 ?? false
                openPorts.append(LANOpenPort(portNumber: port, serviceName: service, isCriticalSecurityRisk: isCritical))
            }
        }

        guard let lat = fastestLatency else { return nil }

        let deviceType = classifyDevice(openPorts: openPorts, ip: ip)
        let vendor = inferVendor(deviceType: deviceType, openPorts: openPorts)

        return LANDevice(
            ipAddress: ip,
            hostname: nil,
            vendorName: vendor,
            deviceType: deviceType,
            latencyMs: (lat * 10).rounded() / 10,
            openPorts: openPorts
        )
    }

    private func checkPort(ip: String, port: UInt16) async -> Double? {
        await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(ip),
                port: NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 80)
            )

            let params = NWParameters.tcp
            params.prohibitExpensivePaths = false

            let connection = NWConnection(to: endpoint, using: params)
            let queue = DispatchQueue(label: "com.samjan.netpulse.lan.\(ip).\(port)", qos: .utility)
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

            queue.asyncAfter(deadline: .now() + 0.35) {
                connection.cancel()
                box.resumeOnce(nil)
            }
        }
    }

    private func extractSubnetPrefix(from ip: String) -> String {
        let parts = ip.split(separator: ".")
        if parts.count >= 3 {
            return "\(parts[0]).\(parts[1]).\(parts[2])."
        }
        return "192.168.1."
    }

    private func classifyDevice(openPorts: [LANOpenPort], ip: String) -> LANDeviceType {
        let portNums = openPorts.map { $0.portNumber }
        if portNums.contains(62078) || portNums.contains(7000) {
            return .smartphone
        }
        if portNums.contains(554) {
            return .iot
        }
        if portNums.contains(445) || portNums.contains(22) {
            return .computer
        }
        if portNums.contains(80) && portNums.contains(53) {
            return .router
        }
        if portNums.contains(8080) {
            return .smartTV
        }
        return .unknown
    }

    private func inferVendor(deviceType: LANDeviceType, openPorts: [LANOpenPort]) -> String {
        let portNums = openPorts.map { $0.portNumber }
        if portNums.contains(62078) {
            return "Apple Inc."
        }
        if portNums.contains(554) {
            return "IP-Камера видеонаблюдения"
        }
        if portNums.contains(445) {
            return "Windows PC / Samba NAS"
        }
        if portNums.contains(22) {
            return "Linux / macOS / Сервер"
        }
        return "Сетевое устройство"
    }
}

/// Потокобезопасный бокс однократного возобновления Continuation
private final class SafeContinuationBox<T>: @unchecked Sendable {
    private var isResumed = false
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resumeOnce(_ value: T) {
        lock.lock()
        defer { lock.unlock() }
        if !isResumed {
            isResumed = true
            continuation?.resume(returning: value)
            continuation = nil
        }
    }
}
