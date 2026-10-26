//
//  IslandSnapshot.swift
//  NetPulse
//
//  Кадр острова по кнопке «Обновить»: берёт то, что уже показано, и подставляет только что измеренное.
//  Расчёт отделён от ActivityKit-вызовов, чтобы его проверяли юнит-тесты.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit

enum IslandSnapshot {
    /// Сколько секунд после ручного обновления остров считается свежим. У обычных кадров срок 20 секунд, потому что
    /// за ними идут следующие; ручной кадр единственный, а пометка «спит» через 20 секунд после нажатия кнопки
    /// выглядела бы как поломка. Через три минуты остров честно снова скажет, что данные устарели.
    static let staleAfter: TimeInterval = 180

    /// Подпись вида связи для чипа на острове. Для неопределённого вида остаётся прежняя подпись.
    static func connectionLabel(for link: LinkKind, fallback: String) -> String {
        switch link {
        case .offline: return NetworkConnectionType.unavailable.rawValue
        case .wifi: return NetworkConnectionType.wifi.rawValue
        case .ethernet: return NetworkConnectionType.ethernet.rawValue
        case .g5, .lte, .g3, .g2, .cellular: return link.title
        case .other: return fallback
        }
    }

    /// Новое состояние острова. Что не измерялось (отдача, джиттер), показывается прочерком, а не прежним числом:
    /// старая цифра рядом со свежим пингом выглядела бы свежей.
    static func state(
        from result: ProbeResult,
        previous: NetPulseAttributes.ContentState,
        now: Date
    ) -> NetPulseAttributes.ContentState {
        var state = previous
        state.isTesting = false
        state.updatedAt = now
        state.connectionType = connectionLabel(for: result.link, fallback: previous.connectionType)
        state.jitterMs = nil
        state.uploadSpeedText = "— Мбит/с"
        state.compactUploadText = "—"

        guard result.reachable else {
            state.pingMs = nil
            state.packetLossPct = 100
            state.downloadSpeedText = "— Мбит/с"
            state.compactDownloadText = "—"
            return state
        }

        state.pingMs = result.latencyMs.map { $0.rounded() }
        state.packetLossPct = nil
        if let mbps = result.downloadMbps, mbps > 0 {
            state.downloadSpeedText = BandwidthSnapshot.formatSpeed(mbps: mbps)
            state.compactDownloadText = BandwidthSnapshot.compactSpeed(mbps: mbps)
        } else {
            state.downloadSpeedText = "— Мбит/с"
            state.compactDownloadText = "—"
        }
        return state
    }
}
#endif

/// Обработчик кнопки «Обновить»: делает замер и отправляет кадр в остров.
@MainActor
enum IslandRefresh {
    /// Один и тот же замерщик на всё время работы: ему нужно мгновенье, чтобы узнать вид связи у системы,
    /// поэтому он создаётся при запуске приложения, а не в момент нажатия кнопки.
    private static let sharedProbe = LiveNetworkProbe()

    /// Устанавливает обработчик кнопки. Вызывается при запуске приложения, в том числе фоновом.
    static func install() {
        _ = sharedProbe
        IslandRefreshBridge.install {
            await IslandRefresh.run()
        }
    }

    /// Замер (пинг и короткий замер скорости, до двух секунд) и новый кадр. Если острова нет, замер не делается.
    static func run(probe: NetworkProbing? = nil) async {
        #if canImport(ActivityKit)
        guard ActivityManager.shared.hasLiveActivity else {
            IslandDiagnostics.shared.log("Кнопка «Обновить» нажата, но острова нет — нечего обновлять", .warning)
            return
        }
        IslandDiagnostics.shared.log("Кнопка «Обновить» на острове: делаю замер", .island)
        let result = await (probe ?? sharedProbe).measure(withSpeed: true)
        await ActivityManager.shared.applyOnDemandMeasurement(result)
        #endif
    }
}
