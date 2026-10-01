//
//  LANScannerEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / Network.framework) - 2026.
//

import Foundation
import Network
import Darwin

/// Результат проверки одного TCP-порта
private enum PortProbeResult: Sendable {
    /// Соединение установлено — порт открыт
    case open(latencyMs: Double)
    /// Пришёл RST: порт закрыт, но устройство отвечает (то есть оно в сети)
    case refused(latencyMs: Double)
    /// Ответа нет (устройства нет или оно молча отбрасывает пакеты)
    case noResponse
    /// iOS запретила доступ к локальной сети
    case permissionDenied
}

/// ECONNREFUSED / ECONNRESET: хост ответил RST. Network.framework при этом обычно остаётся в `.waiting`.
private func isRefusedByHost(_ error: NWError) -> Bool {
    if case .posix(let code) = error {
        return code == .ECONNREFUSED || code == .ECONNRESET
    }
    return false
}

/// kDNSServiceErr_PolicyDenied (-65570): так Network.framework сообщает об отказе в доступе к локальной сети
private func isLocalNetworkDenied(_ error: NWError) -> Bool {
    if case .dns(let code) = error {
        return code == -65570
    }
    return false
}

private func milliseconds(since start: ContinuousClock.Instant) -> Double {
    let elapsed = ContinuousClock().now - start
    return Double(elapsed.components.seconds) * 1000.0
        + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0
}

/// Асинхронный движок поиска устройств локальной сети.
///
/// Метод — проверка TCP-портов, а не ARP (iOS не даёт приложениям доступа к ARP-таблице). Устройство считается
/// найденным, если оно открыло порт или ответило RST; устройства, которые молча отбрасывают соединения
/// (например, многие смартфоны и умные колонки), этим способом не видны.
public actor LANScannerEngine {
    public static let shared = LANScannerEngine()

    /// Проверяемые порты и названия служб
    private static let probePorts: [UInt16] = [80, 443, 22, 53, 445, 8080, 554, 62078, 7000]
    /// Порты, открытые службы на которых стоит проверить владельцу сети (удалённый доступ, файлы, видеопоток)
    private static let sensitivePorts: Set<UInt16> = [22, 445, 554]
    /// Таймаут проверки порта в локальной сети
    private static let probeTimeoutSeconds: Double = 0.5
    /// Сколько адресов проверяется одновременно (9 портов × 12 адресов ≈ 108 сокетов; лимит дескрипторов iOS — 256)
    private static let concurrentHosts = 12

    public init() {}

    /// Сканирование локальной сети.
    ///
    /// Запускается только в Wi-Fi/Ethernet и только в частном диапазоне адресов (RFC 1918): в мобильной сети
    /// «локальный» адрес принадлежит оператору, и перебор его подсети — это сканирование чужой сети.
    public func scanSubnet(
        localIP: String?,
        gatewayIP: String?,
        connectionType: NetworkConnectionType,
        onProgress: (@Sendable (Int, Int, LANDevice?) -> Void)? = nil
    ) async -> Result<LANScanReport, LANScanError> {
        guard connectionType == .wifi || connectionType == .ethernet,
              let localString = localIP,
              let localAddress = LANSubnet.address(from: localString),
              LANSubnet.isPrivate(localAddress),
              let subnet = Self.makeSubnet(localAddress: localAddress) else {
            return .failure(.notOnLocalNetwork)
        }

        let gatewayAddress = gatewayIP.flatMap { LANSubnet.address(from: $0) }
        let gatewayString = gatewayAddress.map { LANSubnet.string(from: $0) }

        // Проверка разрешения «Локальная сеть» на шлюзе. Пока пользователь отвечает на системный запрос,
        // проба ждёт; отказ определяется по коду ошибки. Без этого первые адреса проверялись бы до ответа
        // пользователя и ложно считались пустыми.
        if let gatewayString, gatewayAddress != localAddress {
            let access = await Self.probePort(ip: gatewayString, port: 80, timeoutSeconds: 6.0)
            if case .permissionDenied = access {
                return .failure(.localNetworkAccessDenied)
            }
        }

        let hosts = subnet.hostAddresses.map { LANSubnet.string(from: $0) }
        var discovered: [LANDevice] = []
        var scanned = 0

        var index = 0
        while index < hosts.count {
            if Task.isCancelled { return .failure(.cancelled) }
            let chunk = Array(hosts[index..<min(index + Self.concurrentHosts, hosts.count)])
            index += Self.concurrentHosts

            await withTaskGroup(of: LANDevice?.self) { group in
                for ip in chunk {
                    group.addTask {
                        await self.probeHost(ip: ip, isGateway: ip == gatewayString)
                    }
                }
                for await device in group {
                    scanned += 1
                    if let device {
                        discovered.append(device)
                    }
                    onProgress?(scanned, hosts.count, device)
                }
            }
        }
        if Task.isCancelled { return .failure(.cancelled) }

        // Шлюз и само устройство известны системе — показываются всегда, но без выдуманных задержек и портов
        if let gatewayString, !discovered.contains(where: { $0.ipAddress == gatewayString }) {
            discovered.append(
                LANDevice(
                    ipAddress: gatewayString,
                    serviceHint: "Основной шлюз сети; на проверяемые порты не отвечает",
                    deviceType: .router,
                    isGateway: true
                )
            )
        }
        discovered.append(
            LANDevice(
                ipAddress: localString,
                deviceType: .smartphone,
                isCurrentDevice: true
            )
        )

        discovered.sort { lhs, rhs in
            (LANSubnet.address(from: lhs.ipAddress) ?? 0) < (LANSubnet.address(from: rhs.ipAddress) ?? 0)
        }

        return .success(
            LANScanReport(devices: discovered, subnet: subnet, scannedHostCount: hosts.count)
        )
    }

    // MARK: - Проверка одного адреса

    /// Параллельная проверка всех портов адреса. `nil` — на адресе никого нет (ни открытых портов, ни RST).
    private func probeHost(ip: String, isGateway: Bool) async -> LANDevice? {
        let results = await withTaskGroup(
            of: (UInt16, PortProbeResult).self,
            returning: [(UInt16, PortProbeResult)].self
        ) { group in
            for port in Self.probePorts {
                group.addTask {
                    (port, await Self.probePort(ip: ip, port: port, timeoutSeconds: Self.probeTimeoutSeconds))
                }
            }
            var collected: [(UInt16, PortProbeResult)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }

        var openPorts: [LANOpenPort] = []
        var fastestResponse: Double?

        for (port, result) in results.sorted(by: { $0.0 < $1.0 }) {
            switch result {
            case .open(let latency):
                fastestResponse = min(fastestResponse ?? latency, latency)
                openPorts.append(
                    LANOpenPort(
                        portNumber: port,
                        serviceName: Self.serviceName(for: port),
                        isCriticalSecurityRisk: Self.sensitivePorts.contains(port)
                    )
                )
            case .refused(let latency):
                fastestResponse = min(fastestResponse ?? latency, latency)
            case .noResponse, .permissionDenied:
                break
            }
        }

        guard let latency = fastestResponse else { return nil }

        let guess = Self.classify(openPorts: openPorts, isGateway: isGateway)
        return LANDevice(
            ipAddress: ip,
            vendorName: guess.vendor,
            serviceHint: guess.hint,
            deviceType: guess.type,
            latencyMs: max(0.1, (latency * 10).rounded() / 10),
            openPorts: openPorts,
            isGateway: isGateway
        )
    }

    private static func probePort(ip: String, port: UInt16, timeoutSeconds: Double) async -> PortProbeResult {
        await withCheckedContinuation { continuation in
            let box = SafeContinuationBox<PortProbeResult>(continuation)
            let connection = NWConnection(
                host: NWEndpoint.Host(ip),
                port: NWEndpoint.Port(rawValue: port) ?? 80,
                using: .tcp
            )
            let queue = DispatchQueue(label: "com.samvel.netpulse.lan.\(ip).\(port)", qos: .utility)
            let start = ContinuousClock().now

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let latency = milliseconds(since: start)
                    connection.cancel()
                    box.resumeOnce(.open(latencyMs: latency))

                case .waiting(let error):
                    // Остальные причины ожидания (нет маршрута и т.п.) не завершают проверку — их обработает таймаут
                    if isLocalNetworkDenied(error) {
                        connection.cancel()
                        box.resumeOnce(.permissionDenied)
                    } else if isRefusedByHost(error) {
                        let latency = milliseconds(since: start)
                        connection.cancel()
                        box.resumeOnce(.refused(latencyMs: latency))
                    }

                case .failed(let error):
                    let latency = milliseconds(since: start)
                    connection.cancel()
                    if isLocalNetworkDenied(error) {
                        box.resumeOnce(.permissionDenied)
                    } else if isRefusedByHost(error) {
                        box.resumeOnce(.refused(latencyMs: latency))
                    } else {
                        box.resumeOnce(.noResponse)
                    }

                case .cancelled:
                    box.resumeOnce(.noResponse)

                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                connection.cancel()
                box.resumeOnce(.noResponse)
            }
        }
    }

    // MARK: - Подсеть

    /// Диапазон проверяемых адресов по маске интерфейса. Если сеть шире /24, проверяется только блок /24 устройства;
    /// если уже (например, точка доступа iPhone — /28), только реальные адреса сети.
    static func makeSubnet(localAddress: UInt32) -> LANSubnet? {
        let reportedPrefix = prefixLength(forLocalAddress: localAddress) ?? 24
        // /30 и уже: в сети нет адресов для проверки
        guard reportedPrefix <= 29 else { return nil }

        let effectivePrefix = max(reportedPrefix, 24)
        let mask: UInt32 = (~UInt32(0)) << UInt32(32 - effectivePrefix)
        let network = localAddress & mask
        let broadcast = network | ~mask
        guard broadcast > network + 1 else { return nil }

        let hosts = ((network + 1)...(broadcast - 1)).filter { $0 != localAddress }
        return LANSubnet(
            networkAddress: network,
            prefixLength: effectivePrefix,
            hostAddresses: Array(hosts),
            isTruncated: reportedPrefix < 24
        )
    }

    /// Длина префикса сети интерфейса, которому принадлежит адрес. `nil` — интерфейс не найден или маска нестандартная.
    private static func prefixLength(forLocalAddress local: UInt32) -> Int? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }

            guard let addressPointer = current.pointee.ifa_addr,
                  let maskPointer = current.pointee.ifa_netmask,
                  addressPointer.pointee.sa_family == sa_family_t(AF_INET) else {
                continue
            }

            let address = addressPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            guard address == local else { continue }

            let mask = maskPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            // Маска должна быть непрерывной: единицы, затем нули
            let inverted = ~mask
            guard inverted & (inverted &+ 1) == 0 else { return nil }
            return mask.nonzeroBitCount
        }
        return nil
    }

    // MARK: - Описание служб и предположения о типе устройства

    private static func serviceName(for port: UInt16) -> String {
        switch port {
        case 80: return "HTTP (веб-интерфейс)"
        case 443: return "HTTPS (веб-интерфейс)"
        case 22: return "SSH (удалённый доступ)"
        case 53: return "DNS"
        case 445: return "SMB (общие папки)"
        case 8080: return "HTTP (альтернативный порт)"
        case 554: return "RTSP (видеопоток)"
        case 62078: return "Служба синхронизации Apple (lockdown)"
        case 7000: return "AirPlay"
        default: return "TCP-служба"
        }
    }

    /// Предположение о типе устройства по открытым портам. Это эвристика, а не факт: производитель указывается
    /// только при однозначном признаке (порт 62078 — служба синхронизации iPhone/iPad).
    private static func classify(
        openPorts: [LANOpenPort],
        isGateway: Bool
    ) -> (type: LANDeviceType, vendor: String?, hint: String?) {
        let ports = Set(openPorts.map { $0.portNumber })

        if isGateway {
            return (.router, nil, "Основной шлюз сети")
        }
        if ports.contains(62078) {
            return (.smartphone, "Apple", "Служба синхронизации iOS (порт 62078)")
        }
        if ports.contains(554) {
            return (.iot, nil, "RTSP: вероятно, IP-камера или видеорегистратор")
        }
        if ports.contains(7000) {
            return (.unknown, nil, "AirPlay: вероятно, Apple TV, HomePod или Mac")
        }
        if ports.contains(445) {
            return (.computer, nil, "SMB: вероятно, компьютер или сетевое хранилище")
        }
        if ports.contains(22) {
            return (.unknown, nil, "SSH: вероятно, компьютер, сервер или NAS")
        }
        if ports.contains(53) && (ports.contains(80) || ports.contains(443)) {
            return (.unknown, nil, "DNS и веб-интерфейс: вероятно, роутер или точка доступа")
        }
        if ports.contains(80) || ports.contains(443) || ports.contains(8080) {
            return (.unknown, nil, "Веб-интерфейс на открытом порту")
        }
        return (.unknown, nil, nil)
    }
}
