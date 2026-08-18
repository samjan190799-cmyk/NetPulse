//
//  NetPulseTheme.swift
//  NetPulse
//
//  Дизайн-система «Obsidian Mono» — монохромная палитра,
//  точно соответствующая стилю логотипа NetPulse.
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Централизованные дизайн-токены палитры «Obsidian Mono».
/// Все UI-компоненты ссылаются на эти значения для единообразия.
public enum NPTheme {

    // MARK: - Фон

    /// Самый глубокий фон (как в лого): #07090E
    public static let backgroundDeep = Color(red: 0.027, green: 0.035, blue: 0.055)

    /// Верхний край градиентного фона: #121620
    public static let backgroundTop = Color(red: 0.071, green: 0.086, blue: 0.125)

    /// Фон карточек: #0F1218
    public static let cardBackground = Color(red: 0.059, green: 0.071, blue: 0.094)

    /// Фон вложенных элементов (третичный): #181C26
    public static let cardBackgroundTertiary = Color(red: 0.094, green: 0.110, blue: 0.149)

    // MARK: - Акценты

    /// Основной акцент — чистый белый (как глиф в лого)
    public static let accentPrimary = Color.white

    /// Мягкий белый акцент: #E2E8F0
    public static let accentSoft = Color(red: 0.886, green: 0.910, blue: 0.941)

    /// Серебристый (для upload, вторичных метрик): #94A3B8
    public static let accentSilver = Color(red: 0.580, green: 0.639, blue: 0.722)

    // MARK: - Текст

    /// Основной текст — белый
    public static let textPrimary = Color.white

    /// Вторичный текст: Slate-400 #64748B
    public static let textSecondary = Color(red: 0.392, green: 0.455, blue: 0.545)

    /// Третичный текст: Slate-500 #475569
    public static let textTertiary = Color(red: 0.278, green: 0.333, blue: 0.412)

    // MARK: - Границы и свечение

    /// Тонкая серебристая обводка карточек
    public static let border = Color.white.opacity(0.06)

    /// Мягкое свечение (glow) — как в лого
    public static let glow = Color.white.opacity(0.08)

    /// Усиленное свечение для активных элементов
    public static let glowActive = Color.white.opacity(0.15)

    // MARK: - Семантические цвета (минимальные цветные исключения)

    /// Предупреждение — единственный допустимый тёплый цвет
    public static let semanticWarn = Color(red: 1.0, green: 0.655, blue: 0.149) // #FFA726

    /// Критическое состояние — красный
    public static let semanticCritical = Color(red: 0.937, green: 0.325, blue: 0.314) // #EF5350

    /// OK-статус — белый (не зелёный!)
    public static let semanticOK = Color.white

    // MARK: - Метрики Download / Upload

    /// Download — белый (вместо синего)
    public static let download = Color.white

    /// Upload — серебристый (вместо циана)
    public static let upload = accentSilver

    // MARK: - Градиенты

    /// Основной фоновый градиент (как в лого)
    public static let backgroundGradient = LinearGradient(
        colors: [backgroundTop, backgroundDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Градиент акцента для дуг и кнопок (белый → мягкий белый)
    public static let accentGradient = LinearGradient(
        colors: [accentPrimary, accentSoft],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Градиент для кнопки запуска (белый)
    public static let buttonGradient = LinearGradient(
        colors: [Color.white, accentSoft],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Градиент для неактивной кнопки
    public static let buttonDisabledGradient = LinearGradient(
        colors: [Color.white.opacity(0.3), Color.white.opacity(0.15)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Модификаторы карточек

extension View {
    /// Применяет стиль карточки «Obsidian Mono»: тёмный фон + серебристая обводка
    public func npCardStyle(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(NPTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(NPTheme.border, lineWidth: 1)
            )
    }

    /// Применяет полноэкранный фон «Obsidian Mono»
    public func npScreenBackground() -> some View {
        self.background(NPTheme.backgroundGradient.ignoresSafeArea())
    }
}
