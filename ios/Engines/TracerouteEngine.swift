//
//  TracerouteEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Итог трассировки: найденные хопы и, если трассировку выполнить не удалось, причина.
private struct TraceOutcome: Sendable {
    let hops: [TracerouteHop]
    let errorMessage: String?
}

/// Реальный ответ на одну пробу
private enum ICMPReplyKind {
    case echoReply        // ответил сам целевой узел
    case timeExceeded     // ответил промежуточный маршрутизатор (TTL исчерпан)
    case unreachable      // сеть/узел недоступны (ответ маршрутизатора)
}

/// Асинхронный движок трассировки сетевого пути (MTR/Traceroute) для iOS.
///
/// Работает через ICMP-датаграммный сокет (`SOCK_DGRAM` + `IPPROTO_ICMP`), который iOS разрешает без root,
/// с постепенным увеличением TTL. Каждый хоп — реальный ответ маршрутизатора либо «*», если ответа нет.
/// Никаких выдуманных узлов и задержек: раньше «маршрут» целиком генерировался формулой.
/// Ограничения: только IPv4; часть маршрутизаторов не отвечает на ICMP — такие хопы остаются «*».
public actor TracerouteEngine {
    private let maxHops: Int
    private let timeoutInterval: TimeInterval

    /// Причина, по которой последняя трассировка не удалась (nil — трассировка выполнена)
    public private(set) var lastError: String?

    public init(maxHops: Int = 15, timeout: TimeInterval = 1.0) {
        self.maxHops = max(1, maxHops)
        self.timeoutInterval = max(0.2, timeout)
    }

    /// Трассировка маршрута до целевого узла
    public func traceRoute(
        to host: String,
        onHopDiscovered: (@Sendable (TracerouteHop) -> Void)? = nil
    ) async -> [TracerouteHop] {
        lastError = nil
        let hopLimit = maxHops
        let timeout = timeoutInterval

        let outcome: TraceOutcome = await withCheckedContinuation { (continuation: CheckedContinuation<TraceOutcome, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = TracerouteEngine.runTrace(
                    host: host,
                    maxHops: hopLimit,
                    timeout: timeout,
                    onHop: onHopDiscovered
                )
                continuation.resume(returning: result)
            }
        }

        lastError = outcome.errorMessage
        return outcome.hops
    }

    // MARK: - Блокирующая реализация (выполняется в фоновой очереди)

    private static func runTrace(
        host: String,
        maxHops: Int,
        timeout: TimeInterval,
        onHop: (@Sendable (TracerouteHop) -> Void)?
    ) -> TraceOutcome {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else {
            return TraceOutcome(hops: [], errorMessage: "Узел не указан")
        }

        // 1. Разрешение имени в IPv4-адрес
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var infoPtr: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(cleanHost, nil, &hints, &infoPtr) == 0, let info = infoPtr, let sa = info.pointee.ai_addr else {
            return TraceOutcome(hops: [], errorMessage: "Не удалось определить IPv4-адрес узла «\(cleanHost)»")
        }
        defer { freeaddrinfo(infoPtr) }

        var destination = sockaddr_in()
        memcpy(&destination, sa, MemoryLayout<sockaddr_in>.size)

        // 2. ICMP-сокет без привилегий
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else {
            return TraceOutcome(hops: [], errorMessage: "Система не разрешила открыть ICMP-сокет (код \(errno))")
        }
        defer { close(fd) }

        var tv = timeval()
        tv.tv_sec = Int(timeout)
        tv.tv_usec = Int32((timeout - Double(Int(timeout))) * 1_000_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let identifier = UInt16(truncatingIfNeeded: getpid())
        var hops: [TracerouteHop] = []
        var silentStreak = 0

        for ttl in 1...maxHops {
            var ttlValue = Int32(ttl)
            if setsockopt(fd, IPPROTO_IP, IP_TTL, &ttlValue, socklen_t(MemoryLayout<Int32>.size)) != 0 {
                return TraceOutcome(hops: hops, errorMessage: "Не удалось задать TTL (код \(errno))")
            }

            let sequence = UInt16(ttl)
            let packet = makeEchoRequest(identifier: identifier, sequence: sequence)
            let sentAt = DispatchTime.now().uptimeNanoseconds

            let sent: Int = packet.withUnsafeBytes { raw -> Int in
                withUnsafePointer(to: destination) { destPtr -> Int in
                    destPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr -> Int in
                        sendto(fd, raw.baseAddress, raw.count, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            guard sent > 0 else {
                return TraceOutcome(hops: hops, errorMessage: "Не удалось отправить ICMP-пакет (код \(errno))")
            }

            // Ждём ответ именно на эту пробу (чужой ICMP-трафик пропускаем, дедлайн не продлевается)
            var reply: ICMPReplyKind?
            var replyIP = ""
            var rttMs = 0.0
            let deadline = sentAt + UInt64(timeout * 1_000_000_000)
            var buffer = [UInt8](repeating: 0, count: 1500)
            let capacity = buffer.count

            while DispatchTime.now().uptimeNanoseconds < deadline {
                var from = sockaddr_in()
                var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)
                let received: Int = withUnsafeMutablePointer(to: &from) { fromPtr -> Int in
                    fromPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr -> Int in
                        recvfrom(fd, &buffer, capacity, 0, saPtr, &fromLength)
                    }
                }
                if received < 0 {
                    if errno == EINTR { continue }
                    break   // таймаут (EAGAIN) или ошибка сокета
                }
                if received == 0 { break }

                if let kind = parseReply(Array(buffer[0..<received]), sequence: sequence) {
                    reply = kind
                    replyIP = ipString(from)
                    rttMs = Double(DispatchTime.now().uptimeNanoseconds - sentAt) / 1_000_000.0
                    break
                }
            }

            let hop: TracerouteHop
            if reply != nil {
                silentStreak = 0
                hop = TracerouteHop(
                    hopNumber: ttl,
                    ipAddress: replyIP,
                    hostname: nil,
                    latencyMs: (rttMs * 10).rounded() / 10,
                    lossPercent: 0.0
                )
            } else {
                silentStreak += 1
                hop = TracerouteHop(hopNumber: ttl, ipAddress: nil, hostname: nil, latencyMs: nil, lossPercent: 100.0)
            }
            hops.append(hop)
            onHop?(hop)

            // Дошли до цели (или маршрутизатор сообщил о недоступности) — дальше идти некуда
            if let kind = reply, kind == .echoReply || kind == .unreachable {
                break
            }
            // Пять молчащих хопов подряд — дальше фильтрует межсетевой экран; ждать остальные таймауты бессмысленно
            if silentStreak >= 5 {
                break
            }
        }

        if hops.isEmpty {
            return TraceOutcome(hops: [], errorMessage: "Ответов нет: ICMP, вероятно, заблокирован в этой сети")
        }
        return TraceOutcome(hops: hops, errorMessage: nil)
    }

    // MARK: - ICMP

    /// ICMP Echo Request: type 8, code 0, контрольная сумма, identifier, sequence и небольшая полезная нагрузка
    private static func makeEchoRequest(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        var packet: [UInt8] = [
            8, 0, 0, 0,
            UInt8(identifier >> 8), UInt8(identifier & 0xFF),
            UInt8(sequence >> 8), UInt8(sequence & 0xFF)
        ]
        packet.append(contentsOf: Array("NetPulseTrace".utf8))

        let checksum = internetChecksum(packet)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(checksum & 0xFF)
        return packet
    }

    /// Контрольная сумма Internet (RFC 1071)
    private static func internetChecksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum += (UInt32(bytes[index]) << 8) | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count {
            sum += UInt32(bytes[index]) << 8
        }
        while (sum >> 16) != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(sum & 0xFFFF)
    }

    /// Разбор полученного пакета. Ядро может отдать его с IP-заголовком или без — определяем по версии в первом байте.
    /// Ответ принимается, только если относится к нашей пробе (совпадает sequence).
    private static func parseReply(_ data: [UInt8], sequence: UInt16) -> ICMPReplyKind? {
        var offset = 0
        if data.count >= 20 && (data[0] >> 4) == 4 {
            offset = Int(data[0] & 0x0F) * 4
        }
        guard data.count >= offset + 8 else { return nil }

        let type = data[offset]
        switch type {
        case 0:
            let replySequence = (UInt16(data[offset + 6]) << 8) | UInt16(data[offset + 7])
            return replySequence == sequence ? .echoReply : nil

        case 11, 3:
            // Внутри ICMP-ошибки — IP-заголовок и первые 8 байт нашего исходного пакета
            let innerStart = offset + 8
            guard data.count >= innerStart + 20 else { return nil }
            let innerHeaderLength = Int(data[innerStart] & 0x0F) * 4
            let innerICMP = innerStart + innerHeaderLength
            guard data.count >= innerICMP + 8, data[innerICMP] == 8 else { return nil }
            let innerSequence = (UInt16(data[innerICMP + 6]) << 8) | UInt16(data[innerICMP + 7])
            guard innerSequence == sequence else { return nil }
            return type == 11 ? .timeExceeded : .unreachable

        default:
            return nil
        }
    }

    private static func ipString(_ address: sockaddr_in) -> String {
        var inAddress = address.sin_addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &inAddress, &buffer, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buffer)
    }
}
