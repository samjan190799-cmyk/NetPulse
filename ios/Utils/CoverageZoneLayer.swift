//
//  CoverageZoneLayer.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import Observation

/// Зоны покрытия для карты. Считаются не на главном потоке: при тридцати маршрутах это до ста двадцати тысяч точек,
/// и пересчёт не должен задерживать ни карту, ни панель.
@MainActor
@Observable
final class CoverageZoneLayer {
    private(set) var zones: [CoverageZone] = []
    @ObservationIgnored private var generation = 0

    /// Пересчитывает зоны. Если зоны выключены, они сразу пропадают. Результат устаревшего расчёта
    /// (за это время пришёл новый запрос) отбрасывается.
    func refresh(routes: [RouteRecord], metric: RouteMetric, enabled: Bool) {
        generation += 1
        let current = generation
        guard enabled else {
            if !zones.isEmpty { zones = [] }
            return
        }
        Task { [weak self] in
            let computed = await Task.detached(priority: .utility) {
                ZoneBuilder.zones(from: routes, metric: metric)
            }.value
            guard let self, current == self.generation, computed != self.zones else { return }
            self.zones = computed
        }
    }
}
