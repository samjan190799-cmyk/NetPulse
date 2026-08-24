//
//  NetworkGlossarySheetView.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import SwiftUI

/// Интерактивный сетевой глоссарий и руководство «Где что значит» по стандартам Apple HIG 2026.
public struct NetworkGlossarySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: GlossaryCategory = .all
    @State private var searchText: String = ""

    public init() {}

    public enum GlossaryCategory: String, CaseIterable, Identifiable {
        case all = "Все"
        case metrics = "Метрики"
        case network = "Сеть и IP"
        case tools = "Утилиты"
        case ai = "AI Аудит"

        public var id: String { rawValue }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                NPTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Категории
                        Picker("Категория", selection: $selectedCategory) {
                            ForEach(GlossaryCategory.allCases) { cat in
                                Text(cat.rawValue).tag(cat)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        // Список карточек с терминами
                        LazyVStack(spacing: 12) {
                            ForEach(filteredItems) { item in
                                GlossaryItemCard(item: item)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 30)
                    }
                    .padding(.top, 10)
                }
            }
            .navigationTitle("Справочник сети")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Поиск термина (RTT, Bufferbloat, Шлюз...)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NPTheme.accentPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var filteredItems: [GlossaryItem] {
        GlossaryCatalog.items.filter { item in
            let matchesCategory = (selectedCategory == .all || item.category == selectedCategory)
            if searchText.isEmpty {
                return matchesCategory
            }
            return matchesCategory && (
                item.title.localizedCaseInsensitiveContains(searchText) ||
                item.shortDescription.localizedCaseInsensitiveContains(searchText) ||
                item.fullExplanation.localizedCaseInsensitiveContains(searchText)
            )
        }
    }
}

/// Модель элемента глоссария
public struct GlossaryItem: Identifiable {
    public let id = UUID()
    public let title: String
    public let subtitle: String
    public let icon: String
    public let iconColor: Color
    public let category: NetworkGlossarySheetView.GlossaryCategory
    public let shortDescription: String
    public let fullExplanation: String
    public let practicalTip: String?
}

/// Визуальная интерактивная карточка термина
private struct GlossaryItemCard: View {
    let item: GlossaryItem
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                    HapticManager.shared.selectionChanged()
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(item.iconColor.opacity(0.15))
                            .frame(width: 38, height: 38)

                        Image(systemName: item.icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(item.iconColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(NPTheme.textPrimary)

                        Text(item.subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(NPTheme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(isExpanded ? NPTheme.accentPrimary : NPTheme.textTertiary)
                }
            }
            .buttonStyle(.plain)

            // Краткое описание
            Text(item.shortDescription)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(NPTheme.textSecondary)
                .lineSpacing(2)

            // Раскрытая подробная информация
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                        .background(NPTheme.border)

                    Text(item.fullExplanation)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(NPTheme.textPrimary)
                        .lineSpacing(3)

                    if let tip = item.practicalTip {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.yellow)
                                .padding(.top, 2)

                            Text(tip)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(NPTheme.textSecondary)
                                .lineSpacing(2)
                        }
                        .padding(10)
                        .background(Color.yellow.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .npGlassCard(cornerRadius: 16)
    }
}

/// Каталог понятных объяснений терминов
public struct GlossaryCatalog {
    public static let items: [GlossaryItem] = [
        // 1. Метрики
        GlossaryItem(
            title: "RTT (Задержка / Пинг)",
            subtitle: "Round-Trip Time в миллисекундах",
            icon: "timer",
            iconColor: NPTheme.accentPrimary,
            category: .metrics,
            shortDescription: "Время, за которое сетевой пакет долетает от iPhone до сервера и возвращается обратно.",
            fullExplanation: "Чем ниже RTT, тем быстрее реагирует интернет. До 25 мс — идеальный показатель для соревновательного гейминга. 25–60 мс — комфортный для веб-серфинга и 4K стриминга. Более 100 мс — заметные задержки в голосовых вызовах и играх.",
            practicalTip: "На сотовой сети LTE задержка 40–80 мс является нормальной из-за беспроводной модуляции сигнала."
        ),
        GlossaryItem(
            title: "Джиттер (Jitter)",
            subtitle: "Колебания времени задержки (мс)",
            icon: "waveform.path.ecg",
            iconColor: Color.orange,
            category: .metrics,
            shortDescription: "Разброс между последовательными пакетами. Показывает, насколько стабилен пинг во времени.",
            fullExplanation: "Если один пакет идет 20 мс, а следующий 80 мс — джиттер составит 60 мс. Высокий джиттер вызывает «заикание» голоса в Telegram/Zoom и телепортации персонажей в онлайн-играх даже при быстром среднем интернете.",
            practicalTip: "Нормальный джиттер — до 3–5 мс. Если он выше 15 мс на Wi-Fi, смените канал роутера на свободный 5 GHz."
        ),
        GlossaryItem(
            title: "Потеря пакетов (Packet Loss)",
            subtitle: "Процент недошедших данных (%)",
            icon: "exclamationmark.triangle.fill",
            iconColor: NPTheme.semanticCrit,
            category: .metrics,
            shortDescription: "Доля сетевых запросов, которые потерялись в пути и не были получены адресатом.",
            fullExplanation: "При потере пакетов протокол TCP заново пересылает потерянную часть, что приводит к резким зависаниям сайтов. В UDP (звонки, видеоконференции, игры) потеря пакетов проявляется как выпадение слов из разговора или фризы картинки.",
            practicalTip: "В здоровой сети потеря пакетов должна быть строго 0.0%."
        ),

        // 2. Сеть и IP
        GlossaryItem(
            title: "Локальный IP",
            subtitle: "Адрес устройства в домашней сети",
            icon: "network",
            iconColor: Color.blue,
            category: .network,
            shortDescription: "Уникальный адрес вашего iPhone внутри Wi-Fi сети (например: 192.168.1.15 или 11.x.x.x в LTE).",
            fullExplanation: "Используется для обмена данными между вашими домашними устройствами (iPhone, Mac, телевизор, умные розетки, принтер). Этот адрес невидим из глобального интернета.",
            practicalTip: "Обычно выдается роутером автоматически по протоколу DHCP."
        ),
        GlossaryItem(
            title: "Шлюз (Gateway)",
            subtitle: "Дверь в глобальный интернет",
            icon: "arrow.triangle.branch",
            iconColor: Color.purple,
            category: .network,
            shortDescription: "Адрес вашего Wi-Fi роутера или первой сотовой базовой станции провайдера.",
            fullExplanation: "Через шлюз проходят абсолютно все данные, направляющиеся в интернет. Если пинг до шлюза высокий — проблема находится внутри вашей домашней Wi-Fi сети или радиоканала, а не у провайдера.",
            practicalTip: "В мобильных сетях (LTE/5G) сотовый шлюз оператора защищен и блокирует прямой пинг — это штатная безопасность мобильных сетей (CGNAT)."
        ),
        GlossaryItem(
            title: "Публичный IP",
            subtitle: "Внешний паспорт в интернете",
            icon: "globe",
            iconColor: Color.teal,
            category: .network,
            shortDescription: "Внешний адрес, под которым сайты, серверы и сервисы видят ваш телефон в мировой сети.",
            fullExplanation: "По публичному IP веб-сайты определяют вашу страну, город и интернет-провайдера. Если несколько устройств подключены к одному роутеру, у всех них будет общий публичный IP-адрес.",
            practicalTip: "Смена VPN или включение/выключение Авиарежима меняет ваш публичный IP-адрес."
        ),

        // 3. Утилиты
        GlossaryItem(
            title: "DNS Гонка (Benchmark)",
            subtitle: "Тест скорости серверов имен",
            icon: "bolt.shield.fill",
            iconColor: NPTheme.accentPrimary,
            category: .tools,
            shortDescription: "Сравнивает время ответа 12+ мировых DNS-резолверов (Cloudflare, Google, Quad9, AdGuard).",
            fullExplanation: "DNS преобразует понятные имена (например, apple.com) в числовые IP-адреса. Быстрый DNS сервер позволяет сайтам открываться мгновенно без пауз на поиск адреса.",
            practicalTip: "Cloudflare (1.1.1.1) обеспечивает максимальную скорость, а Quad9 (9.9.9.9) и AdGuard фильтруют вирусы и рекламу."
        ),
        GlossaryItem(
            title: "Gaming Радар",
            subtitle: "Пинг до игровых серверов",
            icon: "gamecontroller.fill",
            iconColor: Color.mint,
            category: .tools,
            shortDescription: "Показывает реальный сетевой пинг до официальных дата-центров CS2, Dota 2, Valorant, Apex и др.",
            fullExplanation: "Позволяет до запуска матча узнать, к какому региону (Франкфурт, Стокгольм, Варшава, Дубай) у вас наименьшая задержка, и избежать подбора серверов с высоким лагом.",
            practicalTip: "Для победы в шутерах идеален пинг до 35 мс с джиттером менее 2 мс."
        ),
        GlossaryItem(
            title: "Bufferbloat (RFC 8290)",
            subtitle: "Тест очередей под нагрузкой",
            icon: "gauge.with.dots.needle.67percent",
            iconColor: Color.yellow,
            category: .tools,
            shortDescription: "Проверяет, насколько подскакивает пинг, когда кто-то в доме скачивает торрент или смотрит 4K фильм.",
            fullExplanation: "Устаревшие роутеры накапливают пакеты в огромные буферы. При скачивании файлов пинг может взлетать с 20 мс до 600 мс. Оценка A+ означает, что роутер мгновенно пропускает важные пакеты без очередей.",
            practicalTip: "Устраняется включением алгоритма SQM (Cake / FQ_CoDel) в настройках современного роутера."
        ),
        GlossaryItem(
            title: "LAN Сканер",
            subtitle: "Поиск устройств и аудит портов",
            icon: "wifi.router.fill",
            iconColor: Color.cyan,
            category: .tools,
            shortDescription: "Сканирует диапазон IP-адресов подсети и находит всех скрытых соседей в Wi-Fi сети.",
            fullExplanation: "Определяет подключенные смартфоны, ноутбуки, Smart TV, IP-камеры и принтеры, а также проверяет открытые сетевые порты (HTTP, SSH, RTSP) на предмет безопасности.",
            practicalTip: "Помогает выявить, не подключился ли посторонний к вашему домашнему Wi-Fi."
        ),

        // 4. AI
        GlossaryItem(
            title: "AI Диагностика",
            subtitle: "Нейросетевой аудит сети",
            icon: "sparkles",
            iconColor: Color.indigo,
            category: .ai,
            shortDescription: "Анализирует все метрики в комплексе и выдает пошаговые рекомендации на русском языке.",
            fullExplanation: "ИИ определяет причины сбоев: радиопомехи в диапазоне 2.4 GHz, вечерний оверселлинг провайдера, сбои DNS или перерасход мобильного трафика, предлагая точные действия для исправления.",
            practicalTip: "Нажмите на значок звездочек ✨ в правом верхнем углу для мгновенного анализа."
        )
    ]
}
