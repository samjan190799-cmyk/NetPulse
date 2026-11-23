//
//  NetPulseControlWidget.swift
//  NetPulseWidgets
//
//  Кнопка «Проверить связь» для Пункта управления (iOS 18+): одно касание, как у фонарика. Приложение не
//  открывается: проверка занимает пару секунд, итог приходит уведомлением и появляется в виджетах. Эту же кнопку
//  можно назначить на Action Button в настройках iPhone.
//

import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct NetPulseCheckControl: ControlWidget {
    static let kind = "com.samvel.netpulse.control.check"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ControlCheckConnectionIntent()) {
                Label("Проверить связь", systemImage: "wifi")
            }
        }
        .displayName("Проверить связь")
        .description("Проверяет интернет за пару секунд, не открывая приложение.")
    }
}
