//
//  BandwidthEngine.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import SystemConfiguration

/// Структура замера пропускной способности сети
public struct BandwidthSnapshot: Sendable {
    public let downloadBytesPerSec: Double
    public let uploadBytesPerSec: Double
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let totalReceivedBytes: UInt64
    public let totalSentBytes: UInt64
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

/// Системный движок замера РЕАЛЬНОГО сетевого трафика всего iPhone через getifaddrs
public final class BandwidthEngine: @unchecked Sendable {
    private var prevInBytes: UInt64 = 0
    private var prevOutBytes: UInt64 = 0
    private var prevTimestamp: Date?

    public init() {
        let (inB, outB) = fetchInterfaceBytes()
        self.prevInBytes = inB
        self.prevOutBytes = outB
        self.prevTimestamp = Date()
    }

    /// Получение текущего снимка реальной скорости трафика всего устройства
    public func sampleBandwidth() -> BandwidthSnapshot {
        let (currentIn, currentOut) = fetchInterfaceBytes()
        let now = Date()
        let timeDelta = prevTimestamp != nil ? max(now.timeIntervalSince(prevTimestamp!), 0.2) : 1.0

        var inDelta: UInt64 = 0
        if currentIn >= prevInBytes {
            inDelta = currentIn - prevInBytes
        } else if prevInBytes > 0 && currentIn < prevInBytes {
            // Защита от переполнения 32-битного счетчика
            inDelta = (UInt64(UInt32.max) - prevInBytes) + currentIn
        }

        var outDelta: UInt64 = 0
        if currentOut >= prevOutBytes {
            outDelta = currentOut - prevOutBytes
        } else if prevOutBytes > 0 && currentOut < prevOutBytes {
            // Защита от переполнения 32-битного счетчика
            outDelta = (UInt64(UInt32.max) - prevOutBytes) + currentOut
        }

        let downloadBytesPerSec = Double(inDelta) / timeDelta
        let uploadBytesPerSec = Double(outDelta) / timeDelta

        let downloadMbps = (downloadBytesPerSec * 8.0) / 1_000_000.0
        let uploadMbps = (uploadBytesPerSec * 8.0) / 1_000_000.0

        self.prevInBytes = currentIn
        self.prevOutBytes = currentOut
        self.prevTimestamp = now

        return BandwidthSnapshot(
            downloadBytesPerSec: downloadBytesPerSec,
            uploadBytesPerSec: uploadBytesPerSec,
            downloadMbps: downloadMbps,
            uploadMbps: uploadMbps,
            totalReceivedBytes: currentIn,
            totalSentBytes: currentOut,
            timestamp: now
        )
    }

    /// Считывание счетчиков байт сетевых интерфейсов BSD (Wi-Fi, 5G/LTE, Ethernet)
    private func fetchInterfaceBytes() -> (UInt64, UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return (0, 0)
        }
        defer { freeifaddrs(ifaddr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let ptr = cursor {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            // ВАЖНО: В ядре Darwin (iOS/macOS) только записи с sa_family == AF_LINK содержат struct if_data
            if isUp && !isLoopback, let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) {
                if let data = ptr.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self)
                    totalIn += UInt64(networkData.pointee.ifi_ibytes)
                    totalOut += UInt64(networkData.pointee.ifi_obytes)
                }
            }
            cursor = ptr.pointee.ifa_next
        }

        return (totalIn, totalOut)
    }
}
