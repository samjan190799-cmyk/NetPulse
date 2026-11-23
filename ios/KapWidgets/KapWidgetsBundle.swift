//
//  KapWidgetsBundle.swift
//  KapWidgets
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI
import WidgetKit

/// Точка входа для бандла виджетов и Dynamic Island в расширении KapWidgets.
@main
struct KapWidgetsBundle: WidgetBundle {
    var body: some Widget {
        KapHomeScreenWidget()
        KapLiveActivityWidget()
    }
}

