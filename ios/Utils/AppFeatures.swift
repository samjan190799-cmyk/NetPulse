//
//  AppFeatures.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Что включено в выпускаемой версии приложения.
enum AppFeatures {
    /// Платная версия NetPulse PRO (отключает рекламу и открывает игровой HUD-оверлей).
    ///
    /// Пока `false`, предложения PRO нигде не показываются, а игровой HUD доступен всем. Включать можно только после
    /// того, как покупка с идентификатором `StoreConfig.proProductID` создана в App Store Connect: иначе экран
    /// покупки сообщал бы «покупка недоступна», а App Review отклоняет приложения с нерабочей покупкой (правило 2.1).
    static let proPurchaseEnabled = false
}
