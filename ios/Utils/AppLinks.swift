//
//  AppLinks.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation

/// Страницы, на которые ведут ссылки из приложения и из карточки App Store.
///
/// Лежат в ветке `appstore-assets` репозитория: она отделена от рабочих веток и не удаляется, поэтому ссылки,
/// зашитые в уже выпущенные сборки, продолжают работать. Если страницы переедут на собственный сайт, поменять
/// нужно только эти адреса (и ссылки в App Store Connect).
enum AppLinks {
    /// Политика конфиденциальности (обязательна по правилу App Store 5.1.1: ссылка есть и в карточке, и в приложении)
    static let privacyPolicy = URL(string: "https://github.com/samjan190799-cmyk/NetPulse/blob/appstore-assets/legal/privacy-policy-ru.md")!
    /// Поддержка: как написать разработчику и ответы на частые вопросы
    static let support = URL(string: "https://github.com/samjan190799-cmyk/NetPulse/blob/appstore-assets/legal/support-ru.md")!
}
