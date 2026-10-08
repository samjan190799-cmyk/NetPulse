//
//  HomeComponents.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

// MARK: - Цвета и значки качества сети

extension RouteQuality {
    /// Цвет качества: одинаков на карте, в легенде и в полосках сводки и не зависит от темы оформления.
    /// Опираться на один цвет нельзя, поэтому у каждого качества есть слово и значок (`title`, `systemIcon`),
    /// а участок «нет сети» на карте ещё и пунктирный.
    var displayColor: Color {
        switch self {
        case .good: return Color(red: 0.239, green: 0.863, blue: 0.592)
        case .fair: return Color(red: 1.0, green: 0.835, blue: 0.290)
        case .poor: return Color(red: 1.0, green: 0.624, blue: 0.263)
        case .dead: return Color(red: 0.937, green: 0.325, blue: 0.314)
        }
    }

    /// Значок качества: по нему качество понятно и без цвета
    var systemIcon: String {
        switch self {
        case .good: return "checkmark.circle.fill"
        case .fair: return "minus.circle.fill"
        case .poor: return "exclamationmark.triangle.fill"
        case .dead: return "xmark.circle.fill"
        }
    }
}

/// Цвета, которых нет в темах оформления: они подобраны так, чтобы белый текст на них читался (контраст не ниже 4,5:1)
enum HomePalette {
    /// Красная кнопка «Остановить и сохранить»
    static let stopRed = Color(red: 0.851, green: 0.227, blue: 0.212)
    /// Светлый красный для значков и подписей на тёмном фоне
    static let softRed = Color(red: 1.0, green: 0.541, blue: 0.502)
}

@MainActor
extension NetworkMonitorViewModel {
    /// Оценка связи сейчас: одна и та же в плашке над картой и в цветной зоне вокруг точки «вы здесь»
    var homeLinkQuality: RouteQuality? {
        HomeLinkStatus.quality(isOnline: systemInfo.connectionType != .unavailable, pingMs: currentAveragePing)
    }
}

// MARK: - Стекло поверх карты

/// Полупрозрачная тёмная подложка с размытием и тонкой обводкой: плашки и кнопки поверх карты
@MainActor
struct HomeGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background(shape.fill(NPTheme.cardBackground.opacity(0.88)))
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

@MainActor
extension View {
    func homeGlass<S: InsettableShape>(_ shape: S) -> some View {
        modifier(HomeGlassModifier(shape: shape))
    }
}

/// Фон нижней панели: скруглённые верхние углы, обводка и тень вверх
@MainActor
struct HomePanelBackground: View {
    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 28,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 28,
            style: .continuous
        )
        shape
            .fill(NPTheme.cardBackground.opacity(0.96))
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.4), radius: 14, x: 0, y: -4)
    }
}

// MARK: - Кнопки и плашки

/// Круглая стеклянная кнопка поверх карты (настройки, схема/спутник, покрытие, к моему положению)
@MainActor
struct GlassCircleButton: View {
    let systemImage: String
    let label: String
    /// Состояние переключателя для VoiceOver («Показано» / «Скрыто»); у обычных кнопок его нет
    var value: String?
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NPTheme.textPrimary)
                .frame(width: 44, height: 44)
                .homeGlass(Circle())
        }
        .buttonStyle(NPPressableButtonStyle(scale: 0.94))
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
        .accessibilityIdentifier(identifier)
    }
}

/// Небольшая подпись на карте («Последний маршрут · 12.4 км»)
@MainActor
struct HomeChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(NPTheme.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .homeGlass(Capsule())
            .accessibilityIdentifier("homeLastRouteChip")
    }
}

/// Плитка с одним показателем: «Отдача 42.1 Мбит/с»
@MainActor
struct HomeStatTile: View {
    let title: String
    let icon: String?
    let value: String
    let unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 12))
            }
            .foregroundStyle(NPTheme.textSecondary)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(NPTheme.textPrimary)
                    .contentTransition(.numericText())
                    .npAnimation(value: value)
                if let unit {
                    Text(unit)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NPTheme.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NPTheme.cardBackgroundTertiary)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Полоска качества маршрута

/// Диагональная штриховка: участок «нет сети» отличается от остальных не только цветом
struct HatchShape: Shape {
    var spacing: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.height))
            path.addLine(to: CGPoint(x: x + rect.height, y: 0))
            x += spacing
        }
        return path
    }
}

/// Полоска из долей качества сети: чем длиннее цвет, тем больше точек маршрута с таким качеством
@MainActor
struct QualityBar: View {
    let shares: [RouteQuality: Double]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(RouteQuality.allCases, id: \.self) { quality in
                    let share = shares[quality] ?? 0
                    if share > 0 {
                        segment(for: quality)
                            .frame(width: max(2, (proxy.size.width - 6) * share))
                    }
                }
            }
        }
        .frame(height: height)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func segment(for quality: RouteQuality) -> some View {
        if quality == .dead {
            Rectangle()
                .fill(quality.displayColor)
                .overlay(HatchShape().stroke(Color.black.opacity(0.4), lineWidth: 2))
                .clipped()
        } else {
            Rectangle()
                .fill(quality.displayColor)
        }
    }
}

/// Цветной квадратик легенды; у «нет сети» он штрихованный
@MainActor
struct QualitySwatch: View {
    let quality: RouteQuality

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(quality.displayColor)
            .overlay(
                Group {
                    if quality == .dead {
                        HatchShape(spacing: 4).stroke(Color.black.opacity(0.4), lineWidth: 1.5)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .frame(width: 12, height: 12)
    }
}

// MARK: - Точка «вы здесь» и легенда

/// Точка «вы здесь»: белая окантовка и синяя середина, как в системных картах. Цвет качества сети у неё нет:
/// он есть только у линий маршрутов, то есть у мест, где сеть действительно измерялась.
@MainActor
struct HomeUserMarker: View {
    @Environment(\.npContinuousMotion) private var continuous

    var body: some View {
        ZStack {
            if continuous {
                ripple
            }
            Circle()
                .fill(Color.white)
                .frame(width: 22, height: 22)
                .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
            Circle()
                .fill(Color(red: 0.04, green: 0.52, blue: 1.0))
                .frame(width: 15, height: 15)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Мягкая волна от точки: показывает, что положение живое. Бежит, только пока бесконечное движение разрешено.
    private var ripple: some View {
        Circle()
            .stroke(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.55), lineWidth: 2)
            .frame(width: 22, height: 22)
            .phaseAnimator([0.0, 1.0]) { view, progress in
                view
                    .scaleEffect(1 + 1.6 * progress)
                    .opacity(0.7 * (1 - progress))
            } animation: { progress in
                progress == 1.0 ? .easeOut(duration: 1.8) : nil
            }
    }
}

/// Что значат цвета линий маршрутов на карте: те же цвета и слова, что в итоге маршрута
@MainActor
struct HomeCoverageLegend: View {
    var body: some View {
        HStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                singleRow
                twoRows
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .homeGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Цвета линий маршрутов: хорошо, средне, плохо, нет сети")
        .accessibilityIdentifier("homeCoverageLegend")
    }

    private func item(_ quality: RouteQuality) -> some View {
        HStack(spacing: 5) {
            QualitySwatch(quality: quality)
            Text(quality.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NPTheme.textPrimary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var singleRow: some View {
        HStack(spacing: 12) {
            ForEach(RouteQuality.allCases, id: \.self) { quality in
                item(quality)
            }
        }
    }

    /// Запасной вид для узких экранов
    private var twoRows: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                item(.good)
                item(.fair)
            }
            GridRow {
                item(.poor)
                item(.dead)
            }
        }
    }
}
