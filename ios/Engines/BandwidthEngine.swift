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

    /// Скорость в Мбит/с — единая единица для мониторинга, замера скорости, острова и HUD.
    /// Раньше живой мониторинг показывал МБ/с (байты), а замер скорости — Мбит/с: числа различались в 8 раз,
    /// а суффикс «M» в компактном виде мог означать и то и другое.
    public var formattedDownloadSpeed: String {
        Self.formatSpeed(mbps: downloadMbps)
    }

    public var formattedUploadSpeed: String {
        Self.formatSpeed(mbps: uploadMbps)
    }

    /// Компактный вид для Dynamic Island: только число в Мбит/с (единица указана в развёрнутом виде)
    public var compactDownload: String {
        Self.compactSpeed(mbps: downloadMbps)
    }

    public var compactUpload: String {
        Self.compactSpeed(mbps: uploadMbps)
    }

    public static func formatSpeed(mbps: Double) -> String {
        if mbps >= 100 {
            return String(format: "%.0f Мбит/с", mbps)
        } else if mbps >= 10 {
            return String(format: "%.1f Мбит/с", mbps)
        } else if mbps >= 1 {
            return String(format: "%.2f Мбит/с", mbps)
        } else if mbps >= 0.001 {
            return String(format: "%.0f Кбит/с", mbps * 1000.0)
        }
        return "0 Мбит/с"
    }

    public static func compactSpeed(mbps: Double) -> String {
        if mbps >= 10 {
            return String(format: "%.0f", mbps)
        } else if mbps >= 0.05 {
            return String(format: "%.1f", mbps)
        }
        return "0"
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

    // MARK: - Трафик за время, пока приложение спало

    private var backgroundMark: [String: (inBytes: UInt64, outBytes: UInt64)]?
    private var backgroundMarkedAt: Date?

    /// Запоминает счётчики интерфейсов в момент ухода приложения в фон
    public func markBackground() {
        lock.lock()
        defer { lock.unlock() }
        backgroundMark = Self.fetchDetailedInterfaceMap()
        backgroundMarkedAt = Date()
    }

    /// Сколько байт прошло по счётчикам интерфейсов с момента `markBackground()`; метка при этом сбрасывается.
    /// Считается от собственной метки, а не от базовой точки живого цикла: живой цикл при возвращении успевает
    /// «съесть» эту разницу раньше, чем её прочитает экран. `nil` — метки не было.
    /// Ограничение: счётчики Darwin 32-битные, поэтому разницу свыше 4 ГБ за один сон точно не отличить от переполнения,
    /// такой интервал отбрасывается.
    public func trafficSinceBackgroundMark() -> SleepTrafficSummary? {
        lock.lock()
        defer { lock.unlock() }
        guard let mark = backgroundMark, let markedAt = backgroundMarkedAt else { return nil }
        backgroundMark = nil
        backgroundMarkedAt = nil

        let current = Self.fetchDetailedInterfaceMap()
        let elapsed = max(Date().timeIntervalSince(markedAt), 1.0)
        let plausible = UInt64(min(elapsed * 200_000_000.0, 4_000_000_000.0))

        var physicalIn: UInt64 = 0
        var physicalOut: UInt64 = 0
        var vpnIn: UInt64 = 0
        var vpnOut: UInt64 = 0
        for (name, now) in current {
            guard let before = mark[name] else { continue }
            let inDelta = Self.computeSingleInterfaceDelta(prev: before.inBytes, current: now.inBytes, maxPlausibleDelta: plausible)
            let outDelta = Self.computeSingleInterfaceDelta(prev: before.outBytes, current: now.outBytes, maxPlausibleDelta: plausible)
            switch Self.interfaceKind(for: name) {
            case .wifi, .cellular:
                physicalIn += inDelta
                physicalOut += outDelta
            case .vpn:
                vpnIn += inDelta
                vpnOut += outDelta
            case .ignored:
                break
            }
        }
        // Как и в живом цикле: туннель дублирует физический трафик, поэтому берётся большее из двух
        return SleepTrafficSummary(downloadBytes: max(physicalIn, vpnIn), uploadBytes: max(physicalOut, vpnOut))
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

        // Предел правдоподобной дельты за интервал (≈ 1,6 Гбит/с): если счётчик «уменьшился» и после поправки на
        // 32-битное переполнение получилось больше, это сброс счётчика (интерфейс перезапущен), а не трафик.
        let maxPlausible = UInt64(max(timeDelta, 1.0) * 200_000_000.0)

        // Вычисляем дельты ПО КАЖДОМУ ИНТЕРФЕЙСУ ОТДЕЛЬНО для защиты от 32-битного переполнения
        for (ifName, current) in currentMap {
            let prevIn = prevInterfaceMap[ifName]?.inBytes ?? current.inBytes
            let prevOut = prevInterfaceMap[ifName]?.outBytes ?? current.outBytes

            let singleInDelta = Self.computeSingleInterfaceDelta(prev: prevIn, current: current.inBytes, maxPlausibleDelta: maxPlausible)
            let singleOutDelta = Self.computeSingleInterfaceDelta(prev: prevOut, current: current.outBytes, maxPlausibleDelta: maxPlausible)

            switch Self.interfaceKind(for: ifName) {
            case .wifi:
                wifiInDelta += singleInDelta
                wifiOutDelta += singleOutDelta
            case .cellular:
                cellInDelta += singleInDelta
                cellOutDelta += singleOutDelta
            case .vpn:
                vpnInDelta += singleInDelta
                vpnOutDelta += singleOutDelta
            case .ignored:
                break
            }
        }

        self.prevInterfaceMap = currentMap
        self.prevCounters = currentCounters
        self.prevTimestamp = now

        // Суммарный физический трафик сетевых чипов
        let physicalInDelta = wifiInDelta + cellInDelta
        let physicalOutDelta = wifiOutDelta + cellOutDelta

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

    /// Вычисление дельты одного физического/виртуального интерфейса с поддержкой 32-битного rollover Darwin.
    ///
    /// `maxPlausibleDelta` — наибольшая правдоподобная дельта за интервал между замерами. Если счётчик уменьшился
    /// (`current < prev`), это либо настоящее 32-битное переполнение, либо СБРОС счётчика (перезапуск интерфейса,
    /// перезагрузка). Результат с поправкой на переполнение принимается, только если он правдоподобен; иначе дельта 0.
    /// Раньше порог был 2 ГБ при любом интервале, и сброс счётчика с накопленными > 2,3 ГБ превращался в фантомные
    /// сотни мегабайт трафика.
    public static func computeSingleInterfaceDelta(
        prev: UInt64,
        current: UInt64,
        maxPlausibleDelta: UInt64 = 2_000_000_000
    ) -> UInt64 {
        guard prev > 0 else {
            return 0
        }
        if current >= prev {
            let delta = current - prev
            // Защита от аномальных всплесков ядра
            return delta < maxPlausibleDelta ? delta : 0
        } else {
            // 32-битный rollover Darwin (4,294,967,296 байт)
            let max32: UInt64 = 4_294_967_296
            let delta = (current + max32) - prev
            return delta < maxPlausibleDelta ? delta : 0
        }
    }

    /// Обратная совместимость для внешних вызовов (TrafficStorage)
    public static func computeDelta(
        prev: UInt64,
        current: UInt64,
        maxPlausibleDelta: UInt64 = 2_000_000_000
    ) -> UInt64 {
        computeSingleInterfaceDelta(prev: prev, current: current, maxPlausibleDelta: maxPlausibleDelta)
    }

    /// Тип сетевого интерфейса для учёта трафика
    public enum InterfaceKind: Sendable {
        case wifi        // Wi-Fi / Ethernet (en0, en1, …)
        case cellular    // сотовая связь (pdp_ip*)
        case vpn         // VPN-туннели
        case ignored     // не относится к расходу интернета или дублирует другой интерфейс
    }

    /// Классификация интерфейса по имени.
    /// `bridge*`, `ap*` (раздача интернета) и `anpi*` не считаются: трафик раздачи уже учтён на физическом
    /// интерфейсе (pdp_ip для сотовой сети), и раньше он считался дважды. `awdl*` / `llw*` (AirDrop, прямые
    /// каналы между устройствами) к интернет-трафику не относятся.
    public static func interfaceKind(for name: String) -> InterfaceKind {
        if name.hasPrefix("en") {
            return .wifi
        }
        if name.hasPrefix("pdp_ip") {
            return .cellular
        }
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") || name.hasPrefix("tun") {
            return .vpn
        }
        return .ignored
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

        for (ifName, counters) in map {
            switch interfaceKind(for: ifName) {
            case .wifi:
                result.wifiIn += counters.inBytes
                result.wifiOut += counters.outBytes
            case .cellular:
                result.cellularIn += counters.inBytes
                result.cellularOut += counters.outBytes
            case .vpn:
                result.vpnIn += counters.inBytes
                result.vpnOut += counters.outBytes
            case .ignored:
                break
            }
        }

        result.totalIn = result.wifiIn + result.cellularIn + result.vpnIn
        result.totalOut = result.wifiOut + result.cellularOut + result.vpnOut
        return result
    }

    /// Считывание счетчиков физических и виртуальных интерфейсов BSD
    public static func fetchDetailedInterfaceBytes() -> InterfaceByteCounters {
        let map = fetchDetailedInterfaceMap()
        return aggregateInterfaceCounters(from: map)
    }
}
