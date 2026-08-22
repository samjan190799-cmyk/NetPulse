//
//  NetPulseTheme.swift
//  NetPulse
//
//  Дизайн-система нового поколения (iOS 17+ / Swift 6.0+) — 2026.
//  Поддержка динамических тем оформления, стеклянного морфизма (Glassmorphism),
//  верхних световых бликов (Specular Highlights) и живых градиентов.
//

import SwiftUI
import Observation

/// Доступные темы визуального оформления NetPulse
public enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case obsidianMono = "Obsidian Mono"
    case cyberNeon = "Cyberpunk Neon"
    case titaniumFrost = "Titanium Frost"
    case oledBlack = "OLED Pitch Black"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .obsidianMono:
            return "Монохромная стелс-палитра с мягким лунным свечением"
        case .cyberNeon:
            return "Электрический циан, неоновый пурпур и киберпанк-контраст"
        case .titaniumFrost:
            return "Шлифованный титан с ледяным акцентом и матовым стеклом"
        case .oledBlack:
            return "100% глубокий черный фон для экономии батареи на OLED"
        }
    }
}

/// Менеджер тем оформления с реактивным обновлением интерфейса
@Observable
@MainActor
public final class ThemeManager {
    public static let shared = ThemeManager()

    private let themeKey = "netpulse_selected_theme_v2"

    public var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: themeKey)
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: themeKey),
           let theme = AppTheme(rawValue: saved) {
            self.currentTheme = theme
        } else {
            self.currentTheme = .obsidianMono
        }
    }
}

/// Централизованные дизайн-токены NetPulse.
/// Автоматически адаптируются под выбранную тему оформления.
public enum NPTheme {

    // MARK: - Фон

    /// Самый глубокий фон приложения
    public static var backgroundDeep: Color {
        switch ThemeManager.shared.currentTheme {
        case .obsidianMono:
            return Color(red: 0.027, green: 0.035, blue: 0.055) // #07090E
        case .cyberNeon:
            return Color(red: 0.031, green: 0.027, blue: 0.063) // #080710
        case .titaniumFrost:
            return Color(red: 0.043, green: 0.051, blue: 0.067) // #0B0D11
        case .oledBlack:
            return Color.black
        }
    }

    /// Верхний край градиентного фона
    public static var backgroundTop: Color {
        switch ThemeManager.shared.currentTheme {
        case .obsidianMono:
            return Color(red: 0.071, green: 0.086, blue: 0.125) // #121620
        case .cyberNeon:
            return Color(red: 0.078, green: 0.055, blue: 0.141) // #140E24
        case .titaniumFrost:
            return Color(red: 0.090, green: 0.110, blue: 0.137) // #171C23
        case .oledBlack:
            return Color.black
        }
    }

    /// Фон карточек и панелей
    public static var cardBackground: Color {
        switch ThemeManager.shared.currentTheme {
        case .obsidianMono:
            return Color(red: 0.059, green: 0.071, blue: 0.094) // #0F1218
        case .cyberNeon:
            return Color(red: 0.075, green: 0.063, blue: 0.125) // #131020
        case .titaniumFrost:
            return Color(red: 0.078, green: 0.094, blue: 0.118) // #14181E
        case .oledBlack:
            return Color(red: 0.04, green: 0.04, blue: 0.04)
        }
    }

    /// Фон вложенных элементов (третичный)
    public static var cardBackgroundTertiary: Color {
        switch ThemeManager.shared.currentTheme {
        case .obsidianMono:
            return Color(red: 0.094, green: 0.110, blue: 0.149) // #181C26
        case .cyberNeon:
            return Color(red: 0.118, green: 0.094, blue: 0.196) // #1E1832
        case .titaniumFrost:
            return Color(red: 0.118, green: 0.141, blue: 0.176) // #1E242D
        case .oledBlack:
            return Color(red: 0.08, green: 0.08, blue: 0.08)
        }
    }

    // MARK: - Акценты

    /// Основной акцентный цвет
    public static var accentPrimary: Color {
        switch ThemeManager.shared.currentTheme {
        case .obsidianMono:
            return Color.white
        case .cyberNeon:
            return Color(red: 0.0, green: 0.95, blue: 0.85) // Electric Cyan
        case .titaniumFrost:
            return Color(red: 0.40, green: 0.75, blue: 1.0) // Ice Blue
        case .oledBlack:
            return Color.white
        }
    }

    /// Мягкий акцентный цвет
    public static var accentSoft: Color {
        switch ThemeManager.shared.currentTheme {
        case .obsidianMono:
            return Color(red: 0.886, green: 0.910, blue: 0.941) // #E2E8F0
        case .cyberNeon:
            return Color(red: 0.65, green: 0.45, blue: 1.0) // Neon Purple
        case .titaniumFrost:
            return Color(red: 0.70, green: 0.85, blue: 0.95) // Frost Tint
        case .oledBlack:
            return Color(white: 0.9)
        }
    }

    /// Вторичный акцент (для upload, вторичных метрик)
    public static var accentSilver: Color {
        switch ThemeManager.shared.currentTheme {
        case .obsidianMono:
            return Color(red: 0.580, green: 0.639, blue: 0.722) // #94A3B8
        case .cyberNeon:
            return Color(red: 0.98, green: 0.35, blue: 0.75) // Cyber Pink
        case .titaniumFrost:
            return Color(red: 0.55, green: 0.65, blue: 0.75) // Titanium Slate
        case .oledBlack:
            return Color(white: 0.65)
        }
    }

    // MARK: - Текст

    /// Основной текст
    public static let textPrimary = Color.white

    /// Вторичный текст: Slate-400
    public static let textSecondary = Color(red: 0.392, green: 0.455, blue: 0.545)

    /// Третичный текст: Slate-500
    public static let textTertiary = Color(red: 0.278, green: 0.333, blue: 0.412)

    // MARK: - Границы и свечение

    /// Тонкая обводка карточек
    public static var border: Color {
        switch ThemeManager.shared.currentTheme {
        case .obsidianMono:
            return Color.white.opacity(0.08)
        case .cyberNeon:
            return accentPrimary.opacity(0.18)
        case .titaniumFrost:
            return Color.white.opacity(0.12)
        case .oledBlack:
            return Color.white.opacity(0.12)
        }
    }

    /// Мягкое свечение (glow)
    public static var glow: Color {
        accentPrimary.opacity(0.12)
    }

    /// Усиленное свечение для активных элементов
    public static var glowActive: Color {
        accentPrimary.opacity(0.25)
    }

    // MARK: - Семантические цвета

    /// Предупреждение
    public static let semanticWarn = Color(red: 1.0, green: 0.655, blue: 0.149) // #FFA726

    /// Критическое состояние
    public static let semanticCritical = Color(red: 0.937, green: 0.325, blue: 0.314) // #EF5350

    /// OK-статус
    public static var semanticOK: Color {
        switch ThemeManager.shared.currentTheme {
        case .obsidianMono:
            return Color.white
        case .cyberNeon:
            return Color(red: 0.0, green: 0.95, blue: 0.6)
        case .titaniumFrost:
            return Color(red: 0.3, green: 0.85, blue: 0.6)
        case .oledBlack:
            return Color.white
        }
    }

    // MARK: - Метрики Download / Upload

    /// Download скорость
    public static var download: Color {
        accentPrimary
    }

    /// Upload скорость
    public static var upload: Color {
        accentSilver
    }

    // MARK: - Градиенты

    /// Основной фоновый градиент
    public static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Градиент акцента для дуг и кнопок
    public static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentPrimary, accentSoft],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Градиент для кнопки запуска
    public static var buttonGradient: LinearGradient {
        LinearGradient(
            colors: [accentPrimary, accentSoft],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Градиент для неактивной кнопки
    public static var buttonDisabledGradient: LinearGradient {
        LinearGradient(
            colors: [accentPrimary.opacity(0.3), accentPrimary.opacity(0.15)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Премиальные модификаторы карточек и поверхностей (2026 Glassmorphism)

extension View {
    /// Применяет премиальный стеклянный стиль 2026:
    /// полупрозрачная база + верхний зеркальный блик (Specular Highlight) + мягкая тень
    public func npGlassCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(NPTheme.cardBackground.opacity(0.85))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            )
            .overlay(
                // Верхний световой блик (Specular Highlight)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.20), location: 0.0),
                                .init(color: Color.white.opacity(0.05), location: 0.35),
                                .init(color: NPTheme.border, location: 0.7),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
    }

    /// Совместимый модификатор обычной карточки
    public func npCardStyle(cornerRadius: CGFloat = 16) -> some View {
        self.npGlassCard(cornerRadius: cornerRadius)
    }

    /// Применяет полноэкранный динамический фон
    public func npScreenBackground() -> some View {
        self.background(NPTheme.backgroundGradient.ignoresSafeArea())
    }

    /// Мягкое атмосферное свечение вокруг элемента
    public func npAmbientGlow(color: Color = NPTheme.accentPrimary, radius: CGFloat = 12, opacity: Double = 0.15) -> some View {
        self.shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 0)
    }
}
