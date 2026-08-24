//
//  NetPulseWidgetsBundle.swift
//  NetPulseWidgets
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import WidgetKit

/// Точка входа для бандла виджетов и Dynamic Island в расширении NetPulseWidgets.
@main
struct NetPulseWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NetPulseLiveActivityWidget()
        NetPulseHomeScreenWidget()
    }
}

