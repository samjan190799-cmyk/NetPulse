//
//  NetworkProbe.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import Network
import CoreTelephony

/// Результат одной проверки сети в точке маршрута
public struct ProbeResult: Sendable, Equatable {
    /// Ответил ли контрольный узел
    public var reachable: Bool
    /// Задержка TCP-соединения, мс (`nil` — узел не ответил)
    public var latencyMs: Double?
    /// Скорость скачивания, Мбит/с (`nil` — не измерялась)
    public var downloadMbps: Double?
    public var link: LinkKind

    public init(reachable: Bool, latencyMs: Double? = nil, downloadMbps: Double? = nil, link: LinkKind = .other) {
        self.reachable = reachable
        self.latencyMs = latencyMs
        self.downloadMbps = downloadMbps
        self.link = link
    }
}

/// Проверка сети в текущем месте. В приложении — настоящая (`LiveNetworkProbe`), в тестах — подставная.
public protocol NetworkProbing: Sendable {
    func measure(withSpeed: Bool) async -> ProbeResult
}

/// Состояние сетевого пути, нужное для определения вида связи
private struct PathSnapshot: Sendable {
    var isSatisfied: Bool
    var usesWifi: Bool
    var usesCellular: Bool
    var usesWired: Bool
}

/// Настоящая проверка: время TCP-соединения с контрольным узлом, вид связи и (по желанию) короткий замер скорости.
///
/// Скорость измеряется одним потоком не дольше двух секунд и не больше полутора мегабайт, поэтому замер
/// на маршруте расходует немного трафика; включается он только по желанию пользователя.
public final class LiveNetworkProbe: NetworkProbing, @unchecked Sendable {
    private let pingEngine = PingEngine(timeout: 3.0)
    private let target = HostTarget(name: "Cloudflare", address: "1.1.1.1", tcpPort: 443)
    private let speedURL = URL(string: "https://speed.cloudflare.com/__down?bytes=1500000")!
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.samvel.netpulse.routeprobe.path")
    private let telephony = CTTelephonyNetworkInfo()
    private let lock = NSLock()
    private var snapshot: PathSnapshot?

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let value = PathSnapshot(
                isSatisfied: path.status == .satisfied,
                usesWifi: path.usesInterfaceType(.wifi),
                usesCellular: path.usesInterfaceType(.cellular),
                usesWired: path.usesInterfaceType(.wiredEthernet)
            )
            self?.store(value)
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }

    public func measure(withSpeed: Bool) async -> ProbeResult {
        let path = currentSnapshot()

        // Система сама сообщает, что сети нет: ждать таймаута проверки незачем
        if let path, !path.isSatisfied {
            return ProbeResult(reachable: false, latencyMs: nil, downloadMbps: nil, link: .offline)
        }

        let record = await pingEngine.pingTarget(target)

        var download: Double?
        if withSpeed && record.isSuccess {
            let mbps = await SpeedtestEngine.shared.measureMultiStreamDownload(
                endpoints: [speedURL],
                streamCount: 1,
                durationSeconds: 2.0
            )
            if mbps > 0 {
                download = (mbps * 10).rounded() / 10
            }
        }

        let link = LinkKind.detect(
            isSatisfied: true,
            usesWifi: path?.usesWifi ?? false,
            usesCellular: path?.usesCellular ?? false,
            usesWired: path?.usesWired ?? false,
            radioTechnology: radioTechnology()
        )
        return ProbeResult(
            reachable: record.isSuccess,
            latencyMs: record.isSuccess ? record.latencyMs : nil,
            downloadMbps: download,
            link: link
        )
    }

    // MARK: - Внутреннее

    private func store(_ value: PathSnapshot) {
        lock.lock()
        snapshot = value
        lock.unlock()
    }

    private func currentSnapshot() -> PathSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    /// Технология сотовой связи (LTE, NR и т. д.); при нескольких SIM берётся первая по ключу, чтобы значение не «прыгало»
    private func radioTechnology() -> String? {
        guard let services = telephony.serviceCurrentRadioAccessTechnology, !services.isEmpty else { return nil }
        return services.sorted { $0.key < $1.key }.first?.value
    }
}
