//
//  BandwidthEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import SystemConfiguration

/// Структура детального снимка сетевого трафика
public struct BandwidthSnapshot: Sendable {
    public let downloadBytesPerSec: Double
    public let uploadBytesPerSec: Double
    public let downloadMbps: Double
    public let uploadMbps: Double
    
    // По типам интерфейсов (Wi-Fi vs Cellular)
    public let wifiDownloadBps: Double
    public let wifiUploadBps: Double
    public let cellularDownloadBps: Double
    public let cellularUploadBps: Double
    
    // Накопленные счетчики
    public let totalReceivedBytes: UInt64
    public let totalSentBytes: UInt64
    public let wifiReceivedBytes: UInt64
    public let wifiSentBytes: UInt64
    public let cellularReceivedBytes: UInt64
    public let cellularSentBytes: UInt64
    
    // Дельты за последний интервал
    public let deltaDownloadBytes: UInt64
    public let deltaUploadBytes: UInt64
    public let deltaWifiBytes: UInt64
    public let deltaCellularBytes: UInt64
    
    public let timestamp: Date

    public var formattedDownloadSpeed: String {
        formatBytesPerSec(downloadBytesPerSec)
    }

    public var formattedUploadSpeed: String {
        formatBytesPerSec(uploadBytesPerSec)
    }

    private func formatBytesPerSec(_ bytes: Double) -> String {
        if bytes >= 1_048_576 {
            return String(format: "%.1f МБ/с", bytes / 1_048_576)
        } else if bytes >= 1_024 {
            return String(format: "%.0f КБ/с", bytes / 1_024)
        } else {
            return String(format: "%.0f Б/с", bytes)
        }
    }

    public var compactDownload: String {
        if downloadBytesPerSec >= 1_048_576 {
            return String(format: "%.1fM", downloadBytesPerSec / 1_048_576)
        } else if downloadBytesPerSec >= 1024 {
            return String(format: "%.0fK", downloadBytesPerSec / 1024)
        } else {
            return "0K"
        }
    }

    public var compactUpload: String {
        if uploadBytesPerSec >= 1_048_576 {
            return String(format: "%.1fM", uploadBytesPerSec / 1_048_576)
        } else if uploadBytesPerSec >= 1024 {
            return String(format: "%.0fK", uploadBytesPerSec / 1024)
        } else {
            return "0K"
        }
    }
}

/// Счетчики физических интерфейсов Darwin BSD
public struct InterfaceByteCounters: Sendable, Codable, Equatable {
    public var totalIn: UInt64 = 0
    public var totalOut: UInt64 = 0
    public var wifiIn: UInt64 = 0
    public var wifiOut: UInt64 = 0
    public var cellularIn: UInt64 = 0
    public var cellularOut: UInt64 = 0

    public init(
        totalIn: UInt64 = 0,
        totalOut: UInt64 = 0,
        wifiIn: UInt64 = 0,
        wifiOut: UInt64 = 0,
        cellularIn: UInt64 = 0,
        cellularOut: UInt64 = 0
    ) {
        self.totalIn = totalIn
        self.totalOut = totalOut
        self.wifiIn = wifiIn
        self.wifiOut = wifiOut
        self.cellularIn = cellularIn
        self.cellularOut = cellularOut
    }
}

/// Системный движок точного замера РЕАЛЬНОГО сетевого трафика через getifaddrs (Darwin BSD)
public final class BandwidthEngine: @unchecked Sendable {
    public static let shared = BandwidthEngine()

    private var prevCounters: InterfaceByteCounters
    private var prevTimestamp: Date?
    private let lock = NSLock()

    public init() {
        let counters = Self.fetchDetailedInterfaceBytes()
        self.prevCounters = counters
        self.prevTimestamp = Date()
    }

    /// Принудительная синхронизация базовой точки отсчета (вызывается после фоновой сверки)
    public func resetBaseline(to counters: InterfaceByteCounters? = nil) {
        lock.lock()
        defer { lock.unlock() }
        self.prevCounters = counters ?? Self.fetchDetailedInterfaceBytes()
        self.prevTimestamp = Date()
    }

    /// Получение текущего снимка реальной скорости трафика с защитой от двойного подсчета в режиме модема (Personal Hotspot)
    public func sampleBandwidth(activeConnectionType: NetworkConnectionType? = nil) -> BandwidthSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let currentCounters = Self.fetchDetailedInterfaceBytes()
        let now = Date()
        let timeDelta = prevTimestamp != nil ? max(now.timeIntervalSince(prevTimestamp!), 0.2) : 1.0

        // Дельты по физическим сетевым интерфейсам
        let wifiInDelta = Self.computeDelta(prev: prevCounters.wifiIn, current: currentCounters.wifiIn)
        let wifiOutDelta = Self.computeDelta(prev: prevCounters.wifiOut, current: currentCounters.wifiOut)
        
        let cellInDelta = Self.computeDelta(prev: prevCounters.cellularIn, current: currentCounters.cellularIn)
        let cellOutDelta = Self.computeDelta(prev: prevCounters.cellularOut, current: currentCounters.cellularOut)

        // ЗАЩИТА ОТ ДВОЙНОГО УЧЕТА В РЕЖИМЕ МОДЕМА (HOTSPOT):
        // Если телефон раздает интернет на ноутбук через Hotspot:
        // - Входящий трафик идет через сотовую сеть (pdp_ip0).
        // - Исходящий трафик ретранслируется на ноутбук через Wi-Fi точку доступа (en0).
        // Если их просто сложить, каждый байт посчитается дважды!
        // Поэтому внешний WAN-трафик определяется строго активным интернет-интерфейсом.
        let inDelta: UInt64
        let outDelta: UInt64

        if let conn = activeConnectionType {
            switch conn {
            case .cellular:
                // В режиме сотовой связи берем сотовую дельту (с защитой от смены контекста eSIM)
                inDelta = cellInDelta > 0 ? cellInDelta : max(wifiInDelta, cellInDelta)
                outDelta = cellOutDelta > 0 ? cellOutDelta : max(wifiOutDelta, cellOutDelta)
            case .wifi, .ethernet:
                // В режиме Wi-Fi берем Wi-Fi дельту
                inDelta = wifiInDelta > 0 ? wifiInDelta : max(wifiInDelta, cellInDelta)
                outDelta = wifiOutDelta > 0 ? wifiOutDelta : max(wifiOutDelta, cellOutDelta)
            default:
                inDelta = max(wifiInDelta, cellInDelta)
                outDelta = max(wifiOutDelta, cellOutDelta)
            }
        } else {
            inDelta = max(wifiInDelta, cellInDelta)
            outDelta = max(wifiOutDelta, cellOutDelta)
        }

        let downloadBytesPerSec = Double(inDelta) / timeDelta
        let uploadBytesPerSec = Double(outDelta) / timeDelta
        
        let wifiDownloadBps = Double(wifiInDelta) / timeDelta
        let wifiUploadBps = Double(wifiOutDelta) / timeDelta
        
        let cellDownloadBps = Double(cellInDelta) / timeDelta
        let cellUploadBps = Double(cellOutDelta) / timeDelta

        let downloadMbps = (downloadBytesPerSec * 8.0) / 1_000_000.0
        let uploadMbps = (uploadBytesPerSec * 8.0) / 1_000_000.0

        self.prevCounters = currentCounters
        self.prevTimestamp = now

        return BandwidthSnapshot(
            downloadBytesPerSec: downloadBytesPerSec,
            uploadBytesPerSec: uploadBytesPerSec,
            downloadMbps: downloadMbps,
            uploadMbps: uploadMbps,
            wifiDownloadBps: wifiDownloadBps,
            wifiUploadBps: wifiUploadBps,
            cellularDownloadBps: cellDownloadBps,
            cellularUploadBps: cellUploadBps,
            totalReceivedBytes: currentCounters.totalIn,
            totalSentBytes: currentCounters.totalOut,
            wifiReceivedBytes: currentCounters.wifiIn,
            wifiSentBytes: currentCounters.wifiOut,
            cellularReceivedBytes: currentCounters.cellularIn,
            cellularSentBytes: currentCounters.cellularOut,
            deltaDownloadBytes: inDelta,
            deltaUploadBytes: outDelta,
            deltaWifiBytes: wifiInDelta + wifiOutDelta,
            deltaCellularBytes: cellInDelta + cellOutDelta,
            timestamp: now
        )
    }

    public static func computeDelta(prev: UInt64, current: UInt64) -> UInt64 {
        guard prev > 0 else {
            return 0
        }
        if current >= prev {
            let delta = current - prev
            // Защита от переполнения: до 150 МБ за интервал (1.2 Гбит/с)
            if delta > 150_000_000 {
                return 0
            }
            return delta
        } else {
            return 0
        }
    }

    /// Считывание счетчиков байт ВСЕХ физических и виртуальных интерфейсов BSD (en*, pdp_ip*, utun*).
    public static func fetchDetailedInterfaceBytes() -> InterfaceByteCounters {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return InterfaceByteCounters()
        }
        defer { freeifaddrs(ifaddr) }

        var result = InterfaceByteCounters()
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        var seenInterfaces = Set<String>()

        while let ptr = cursor {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            if isUp && !isLoopback, let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) {
                if let data = ptr.pointee.ifa_data, let ifaNamePtr = ptr.pointee.ifa_name {
                    let ifName = String(cString: ifaNamePtr)

                    if !seenInterfaces.contains(ifName) {
                        seenInterfaces.insert(ifName)
                        let networkData = data.assumingMemoryBound(to: if_data.self)
                        let inBytes = UInt64(networkData.pointee.ifi_ibytes)
                        let outBytes = UInt64(networkData.pointee.ifi_obytes)

                        // Учет физических сетевых интерфейсов iOS (Wi-Fi 6/7, Ethernet, 5G/LTE Dual SIM)
                        if ifName.hasPrefix("en") {
                            // Физические адаптеры Wi-Fi / Ethernet (en0, en1, en2...)
                            result.wifiIn += inBytes
                            result.wifiOut += outBytes
                        } else if ifName.hasPrefix("pdp_ip") {
                            // Физические сотовые каналы 5G/LTE (pdp_ip0, pdp_ip1...)
                            result.cellularIn += inBytes
                            result.cellularOut += outBytes
                        }
                    }
                }
            }
            cursor = ptr.pointee.ifa_next
        }

        result.totalIn = result.wifiIn + result.cellularIn
        result.totalOut = result.wifiOut + result.cellularOut

        return result
    }
}
