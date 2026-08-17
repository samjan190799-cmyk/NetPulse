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
public struct InterfaceByteCounters: Sendable, Codable {
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

/// Системный движок замера РЕАЛЬНОГО сетевого трафика всего iPhone через getifaddrs
public final class BandwidthEngine: @unchecked Sendable {
    private var prevCounters: InterfaceByteCounters
    private var prevTimestamp: Date?

    public init() {
        let counters = Self.fetchDetailedInterfaceBytes()
        self.prevCounters = counters
        self.prevTimestamp = Date()
    }

    /// Получение текущего снимка реальной скорости трафика всего устройства с разделением по интерфейсам
    public func sampleBandwidth() -> BandwidthSnapshot {
        let currentCounters = Self.fetchDetailedInterfaceBytes()
        let now = Date()
        let timeDelta = prevTimestamp != nil ? max(now.timeIntervalSince(prevTimestamp!), 0.2) : 1.0

        // Дельты
        let inDelta = Self.computeDelta(prev: prevCounters.totalIn, current: currentCounters.totalIn)
        let outDelta = Self.computeDelta(prev: prevCounters.totalOut, current: currentCounters.totalOut)
        
        let wifiInDelta = Self.computeDelta(prev: prevCounters.wifiIn, current: currentCounters.wifiIn)
        let wifiOutDelta = Self.computeDelta(prev: prevCounters.wifiOut, current: currentCounters.wifiOut)
        
        let cellInDelta = Self.computeDelta(prev: prevCounters.cellularIn, current: currentCounters.cellularIn)
        let cellOutDelta = Self.computeDelta(prev: prevCounters.cellularOut, current: currentCounters.cellularOut)

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
        if current >= prev {
            return current - prev
        } else if prev > 0 {
            // Обработка возможного переполнения 32-битного счетчика BSD ядра (UInt32.max)
            // или сброса счетчиков при перезапуске сетевого интерфейса/переподключении
            if prev <= UInt64(UInt32.max) && current <= UInt64(UInt32.max) {
                return (UInt64(UInt32.max) - prev) &+ current
            } else {
                // Если счетчик был сброшен ядром iOS (например, переподключение LTE или смена сети)
                return current
            }
        }
        return 0
    }

    /// Считывание счетчиков байт сетевых интерфейсов BSD (Wi-Fi: en0/en1, Cellular: pdp_ip0..3)
    public static func fetchDetailedInterfaceBytes() -> InterfaceByteCounters {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return InterfaceByteCounters()
        }
        defer { freeifaddrs(ifaddr) }

        var result = InterfaceByteCounters()
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr

        while let ptr = cursor {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            // В ядре Darwin только записи с sa_family == AF_LINK содержат struct if_data
            if isUp && !isLoopback, let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) {
                if let data = ptr.pointee.ifa_data, let ifaNamePtr = ptr.pointee.ifa_name {
                    let networkData = data.assumingMemoryBound(to: if_data.self)
                    let inBytes = UInt64(networkData.pointee.ifi_ibytes)
                    let outBytes = UInt64(networkData.pointee.ifi_obytes)
                    let ifName = String(cString: ifaNamePtr)

                    result.totalIn += inBytes
                    result.totalOut += outBytes

                    if ifName.hasPrefix("en") {
                        // Wi-Fi / Ethernet
                        result.wifiIn += inBytes
                        result.wifiOut += outBytes
                    } else if ifName.hasPrefix("pdp_ip") {
                        // Cellular (5G / LTE)
                        result.cellularIn += inBytes
                        result.cellularOut += outBytes
                    }
                }
            }
            cursor = ptr.pointee.ifa_next
        }

        return result
    }
}
