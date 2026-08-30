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
        } else if bytes > 0 {
            let kb = bytes / 1_024.0
            return kb >= 0.1 ? String(format: "%.1f КБ/с", kb) : "0 КБ/с"
        } else {
            return "0 КБ/с"
        }
    }

    public var compactDownload: String {
        if downloadBytesPerSec >= 1_048_576 {
            let val = downloadBytesPerSec / 1_048_576
            return val >= 10 ? String(format: "%.0fM", val) : String(format: "%.1fM", val)
        } else if downloadBytesPerSec >= 1024 {
            return String(format: "%.0fK", downloadBytesPerSec / 1024)
        } else if downloadBytesPerSec > 0 {
            let kb = downloadBytesPerSec / 1024.0
            return kb >= 0.1 ? String(format: "%.1fK", kb) : "0K"
        } else {
            return "0K"
        }
    }

    public var compactUpload: String {
        if uploadBytesPerSec >= 1_048_576 {
            let val = uploadBytesPerSec / 1_048_576
            return val >= 10 ? String(format: "%.0fM", val) : String(format: "%.1fM", val)
        } else if uploadBytesPerSec >= 1024 {
            return String(format: "%.0fK", uploadBytesPerSec / 1024)
        } else if uploadBytesPerSec > 0 {
            let kb = uploadBytesPerSec / 1024.0
            return kb >= 0.1 ? String(format: "%.1fK", kb) : "0K"
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
    public var vpnIn: UInt64 = 0
    public var vpnOut: UInt64 = 0

    public init(
        totalIn: UInt64 = 0,
        totalOut: UInt64 = 0,
        wifiIn: UInt64 = 0,
        wifiOut: UInt64 = 0,
        cellularIn: UInt64 = 0,
        cellularOut: UInt64 = 0,
        vpnIn: UInt64 = 0,
        vpnOut: UInt64 = 0
    ) {
        self.totalIn = totalIn
        self.totalOut = totalOut
        self.wifiIn = wifiIn
        self.wifiOut = wifiOut
        self.cellularIn = cellularIn
        self.cellularOut = cellularOut
        self.vpnIn = vpnIn
        self.vpnOut = vpnOut
    }
}

/// Системный движок точного замера РЕАЛЬНОГО сетевого трафика через getifaddrs (Darwin BSD) с EMA сглаживанием
public final class BandwidthEngine: @unchecked Sendable {
    public static let shared = BandwidthEngine()

    private var prevCounters: InterfaceByteCounters
    private var prevTimestamp: Date?
    private var smoothedDownloadBps: Double = 0.0
    private var smoothedUploadBps: Double = 0.0
    private let lock = NSLock()

    public init() {
        let counters = Self.fetchDetailedInterfaceBytes()
        self.prevCounters = counters
        self.prevTimestamp = Date()
    }

    /// Принудительная синхронизация базовой точки отсчета
    public func resetBaseline(to counters: InterfaceByteCounters? = nil) {
        lock.lock()
        defer { lock.unlock() }
        self.prevCounters = counters ?? Self.fetchDetailedInterfaceBytes()
        self.prevTimestamp = Date()
        self.smoothedDownloadBps = 0.0
        self.smoothedUploadBps = 0.0
    }

    /// Получение текущего снимка реальной скорости трафика с EMA-фильтрацией и защитой от переполнения
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

        let vpnInDelta = Self.computeDelta(prev: prevCounters.vpnIn, current: currentCounters.vpnIn)
        let vpnOutDelta = Self.computeDelta(prev: prevCounters.vpnOut, current: currentCounters.vpnOut)

        // Суммарный реальный внешний сетевой трафик
        let inDelta: UInt64
        let outDelta: UInt64

        if vpnInDelta > 0 || vpnOutDelta > 0 {
            // При активном VPN трафик берем из туннельного интерфейса для точности
            inDelta = vpnInDelta
            outDelta = vpnOutDelta
        } else {
            // Без VPN берем сумму физических адаптеров
            inDelta = wifiInDelta + cellInDelta
            outDelta = wifiOutDelta + cellOutDelta
        }

        let instantDownloadBps = Double(inDelta) / timeDelta
        let instantUploadBps = Double(outDelta) / timeDelta

        // Экспоненциальное сглаживание (EMA) для устранения микро-скачков и обеспечения плавной анимации
        if instantDownloadBps > (smoothedDownloadBps * 2.0) && instantDownloadBps > 512 {
            // Резкий старт скачивания: мгновенный отклик
            smoothedDownloadBps = instantDownloadBps
        } else if instantDownloadBps == 0 && smoothedDownloadBps < 1024 {
            smoothedDownloadBps = 0.0
        } else {
            smoothedDownloadBps = (0.80 * instantDownloadBps) + (0.20 * smoothedDownloadBps)
        }

        if instantUploadBps > (smoothedUploadBps * 2.0) && instantUploadBps > 512 {
            smoothedUploadBps = instantUploadBps
        } else if instantUploadBps == 0 && smoothedUploadBps < 1024 {
            smoothedUploadBps = 0.0
        } else {
            smoothedUploadBps = (0.80 * instantUploadBps) + (0.20 * smoothedUploadBps)
        }

        let downloadBytesPerSec = smoothedDownloadBps
        let uploadBytesPerSec = smoothedUploadBps
        
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
            // Защита от аномальных всплесков (до 1.5 ГБ за такт / 12 Гбит/с)
            if delta > 1_500_000_000 {
                return 0
            }
            return delta
        } else {
            // Обработка 32-битного rollover Darwin (4,294,967,296 байт)
            let max32: UInt64 = 4_294_967_296
            if prev <= max32 && (current + max32) >= prev {
                let delta = (current + max32) - prev
                if delta < 1_500_000_000 {
                    return delta
                }
            }
            return 0
        }
    }

    /// Считывание счетчиков байт ВСЕХ физических и виртуальных интерфейсов BSD (en*, pdp_ip*, bridge*, ap*, utun*).
    public static func fetchDetailedInterfaceBytes() -> InterfaceByteCounters {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return InterfaceByteCounters()
        }
        defer { freeifaddrs(ifaddr) }

        var result = InterfaceByteCounters()
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        var seenInterfaces = Set<String>()
        var otherIn: UInt64 = 0
        var otherOut: UInt64 = 0

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

                        if ifName.hasPrefix("en") {
                            // Физические адаптеры Wi-Fi / Ethernet (en0, en1, en2...)
                            result.wifiIn += inBytes
                            result.wifiOut += outBytes
                        } else if ifName.hasPrefix("pdp_ip") || ifName.hasPrefix("bridge") || ifName.hasPrefix("ap") || ifName.hasPrefix("anpi") {
                            // Сотовая связь 5G/LTE и Режим модема (Hotspot Tethering bridge)
                            result.cellularIn += inBytes
                            result.cellularOut += outBytes
                        } else if ifName.hasPrefix("utun") || ifName.hasPrefix("ipsec") || ifName.hasPrefix("ppp") {
                            // VPN туннели
                            result.vpnIn += inBytes
                            result.vpnOut += outBytes
                        } else {
                            otherIn += inBytes
                            otherOut += outBytes
                        }
                    }
                }
            }
            cursor = ptr.pointee.ifa_next
        }

        result.totalIn = result.wifiIn + result.cellularIn + result.vpnIn + otherIn
        result.totalOut = result.wifiOut + result.cellularOut + result.vpnOut + otherOut

        return result
    }
}
