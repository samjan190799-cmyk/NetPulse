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
    private var prevInterfaceMap: [String: (inBytes: UInt64, outBytes: UInt64)] = [:]
    private var prevTimestamp: Date?
    private var smoothedDownloadBps: Double = 0.0
    private var smoothedUploadBps: Double = 0.0
    private let lock = NSLock()

    public init() {
        let map = Self.fetchDetailedInterfaceMap()
        self.prevInterfaceMap = map
        self.prevCounters = Self.aggregateInterfaceCounters(from: map)
        self.prevTimestamp = Date()
    }

    /// Принудительная синхронизация базовой точки отсчета
    public func resetBaseline(to counters: InterfaceByteCounters? = nil) {
        lock.lock()
        defer { lock.unlock() }
        let map = Self.fetchDetailedInterfaceMap()
        self.prevInterfaceMap = map
        self.prevCounters = counters ?? Self.aggregateInterfaceCounters(from: map)
        self.prevTimestamp = Date()
        self.smoothedDownloadBps = 0.0
        self.smoothedUploadBps = 0.0
    }

    /// Получение текущего снимка реальной скорости трафика с EMA-фильтрацией и защитой от переполнения
    public func sampleBandwidth(activeConnectionType: NetworkConnectionType? = nil) -> BandwidthSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let currentMap = Self.fetchDetailedInterfaceMap()
        let currentCounters = Self.aggregateInterfaceCounters(from: currentMap)
        let now = Date()
        let timeDelta = prevTimestamp.map { max(now.timeIntervalSince($0), 0.2) } ?? 1.0

        var wifiInDelta: UInt64 = 0
        var wifiOutDelta: UInt64 = 0
        var cellInDelta: UInt64 = 0
        var cellOutDelta: UInt64 = 0
        var vpnInDelta: UInt64 = 0
        var vpnOutDelta: UInt64 = 0
        var otherInDelta: UInt64 = 0
        var otherOutDelta: UInt64 = 0

        // Вычисляем дельты ПО КАЖДОМУ ИНТЕРФЕЙСУ ОТДЕЛЬНО для защиты от 32-битного переполнения
        for (ifName, current) in currentMap {
            let prevIn = prevInterfaceMap[ifName]?.inBytes ?? current.inBytes
            let prevOut = prevInterfaceMap[ifName]?.outBytes ?? current.outBytes

            let singleInDelta = Self.computeSingleInterfaceDelta(prev: prevIn, current: current.inBytes)
            let singleOutDelta = Self.computeSingleInterfaceDelta(prev: prevOut, current: current.outBytes)

            if ifName.hasPrefix("en") {
                // Физические адаптеры Wi-Fi / Ethernet (en0, en1, en2...)
                wifiInDelta += singleInDelta
                wifiOutDelta += singleOutDelta
            } else if ifName.hasPrefix("pdp_ip") || ifName.hasPrefix("bridge") || ifName.hasPrefix("ap") || ifName.hasPrefix("anpi") {
                // Сотовая связь 5G/LTE и Режим модема (Hotspot Tethering bridge)
                cellInDelta += singleInDelta
                cellOutDelta += singleOutDelta
            } else if ifName.hasPrefix("utun") || ifName.hasPrefix("ipsec") || ifName.hasPrefix("ppp") || ifName.hasPrefix("tun") {
                // VPN туннели и прокси
                vpnInDelta += singleInDelta
                vpnOutDelta += singleOutDelta
            } else {
                otherInDelta += singleInDelta
                otherOutDelta += singleOutDelta
            }
        }

        self.prevInterfaceMap = currentMap
        self.prevCounters = currentCounters
        self.prevTimestamp = now

        // Суммарный физический трафик сетевых чипов
        let physicalInDelta = wifiInDelta + cellInDelta + otherInDelta
        let physicalOutDelta = wifiOutDelta + cellOutDelta + otherOutDelta

        // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: берем максимум между физическим оборудованием и туннелем!
        // В iOS туннели utun (iCloud Private Relay / APNs / VPN) шлют keepalive-пакеты по 2-3 КБ каждые пару секунд.
        // Используя max(), входящий поток видео стриминга (3-10 МБ на Wi-Fi/Cellular) НИКОГДА больше не затирается 3 КБ!
        let inDelta = max(physicalInDelta, vpnInDelta)
        let outDelta = max(physicalOutDelta, vpnOutDelta)

        let instantDownloadBps = Double(inDelta) / timeDelta
        let instantUploadBps = Double(outDelta) / timeDelta

        // Fast Attack & Natural Decay:
        // Резкий старт (загрузка Reels, видео, веб-страниц) моментально выводит скорость на остров.
        // Между чанками HLS / MP4 применяется адаптивное удержание, устраняющее мигание в "0K".
        if instantDownloadBps >= smoothedDownloadBps {
            smoothedDownloadBps = instantDownloadBps
        } else if instantDownloadBps > 0 {
            smoothedDownloadBps = (0.40 * instantDownloadBps) + (0.60 * smoothedDownloadBps)
        } else {
            // Мягкое затухание (0.80 вместо 0.65): между 3-5 секундными чанками видеопотока
            // спидометр не падает мгновенно в ноль, а плавно показывает темп скачивания
            smoothedDownloadBps = smoothedDownloadBps * 0.80
            if smoothedDownloadBps < 1024 {
                smoothedDownloadBps = 0.0
            }
        }

        if instantUploadBps >= smoothedUploadBps {
            smoothedUploadBps = instantUploadBps
        } else if instantUploadBps > 0 {
            smoothedUploadBps = (0.40 * instantUploadBps) + (0.60 * smoothedUploadBps)
        } else {
            smoothedUploadBps = smoothedUploadBps * 0.80
            if smoothedUploadBps < 1024 {
                smoothedUploadBps = 0.0
            }
        }

        let downloadBytesPerSec = smoothedDownloadBps
        let uploadBytesPerSec = smoothedUploadBps

        let wifiDownloadBps = Double(wifiInDelta) / timeDelta
        let wifiUploadBps = Double(wifiOutDelta) / timeDelta

        let cellDownloadBps = Double(cellInDelta) / timeDelta
        let cellUploadBps = Double(cellOutDelta) / timeDelta

        let downloadMbps = (downloadBytesPerSec * 8.0) / 1_000_000.0
        let uploadMbps = (uploadBytesPerSec * 8.0) / 1_000_000.0

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

    /// Вычисление дельты одного физического/виртуального интерфейса с поддержкой 32-битного rollover Darwin
    public static func computeSingleInterfaceDelta(prev: UInt64, current: UInt64) -> UInt64 {
        guard prev > 0 else {
            return 0
        }
        if current >= prev {
            let delta = current - prev
            // Защита от аномальных всплесков ядра (до 2 ГБ за секунду / 16 Гбит/с)
            return delta < 2_000_000_000 ? delta : 0
        } else {
            // 32-битный rollover Darwin (4,294,967,296 байт)
            let max32: UInt64 = 4_294_967_296
            let delta = (current + max32) - prev
            return delta < 2_000_000_000 ? delta : 0
        }
    }

    /// Обратная совместимость для внешних вызовов (TrafficStorage)
    public static func computeDelta(prev: UInt64, current: UInt64) -> UInt64 {
        computeSingleInterfaceDelta(prev: prev, current: current)
    }

    /// Считывание карты счетчиков байт ВСЕХ физических и виртуальных интерфейсов BSD через getifaddrs
    public static func fetchDetailedInterfaceMap() -> [String: (inBytes: UInt64, outBytes: UInt64)] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return [:]
        }
        defer { freeifaddrs(ifaddr) }

        var result: [String: (inBytes: UInt64, outBytes: UInt64)] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr

        while let ptr = cursor {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            if isUp && !isLoopback, let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) {
                if let data = ptr.pointee.ifa_data, let ifaNamePtr = ptr.pointee.ifa_name {
                    let ifName = String(cString: ifaNamePtr)
                    if result[ifName] == nil {
                        let networkData = data.assumingMemoryBound(to: if_data.self)
                        let inBytes = UInt64(networkData.pointee.ifi_ibytes)
                        let outBytes = UInt64(networkData.pointee.ifi_obytes)
                        result[ifName] = (inBytes: inBytes, outBytes: outBytes)
                    }
                }
            }
            cursor = ptr.pointee.ifa_next
        }
        return result
    }

    /// Агрегация счетчиков байт по типам адаптеров
    public static func aggregateInterfaceCounters(from map: [String: (inBytes: UInt64, outBytes: UInt64)]) -> InterfaceByteCounters {
        var result = InterfaceByteCounters()
        var otherIn: UInt64 = 0
        var otherOut: UInt64 = 0

        for (ifName, counters) in map {
            if ifName.hasPrefix("en") {
                result.wifiIn += counters.inBytes
                result.wifiOut += counters.outBytes
            } else if ifName.hasPrefix("pdp_ip") || ifName.hasPrefix("bridge") || ifName.hasPrefix("ap") || ifName.hasPrefix("anpi") {
                result.cellularIn += counters.inBytes
                result.cellularOut += counters.outBytes
            } else if ifName.hasPrefix("utun") || ifName.hasPrefix("ipsec") || ifName.hasPrefix("ppp") || ifName.hasPrefix("tun") {
                result.vpnIn += counters.inBytes
                result.vpnOut += counters.outBytes
            } else {
                otherIn += counters.inBytes
                otherOut += counters.outBytes
            }
        }

        result.totalIn = result.wifiIn + result.cellularIn + result.vpnIn + otherIn
        result.totalOut = result.wifiOut + result.cellularOut + result.vpnOut + otherOut
        return result
    }

    /// Считывание счетчиков физических и виртуальных интерфейсов BSD
    public static func fetchDetailedInterfaceBytes() -> InterfaceByteCounters {
        let map = fetchDetailedInterfaceMap()
        return aggregateInterfaceCounters(from: map)
    }
}
