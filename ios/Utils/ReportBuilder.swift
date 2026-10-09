//
//  ReportBuilder.swift
//  NetPulse
//
//  Отчёт для провайдера в PDF: скорость, задержка, потери, обрывы, проблемные места на маршрутах и готовое обращение.
//

import UIKit

// MARK: - Данные отчёта

struct ReportHostLine: Sendable {
    let name: String
    let address: String
    let averageLatencyMs: Double?
    let jitterMs: Double?
    let lossPct: Double?
    let status: String
}

struct ReportRouteLine: Sendable {
    let title: String
    let summary: String
    let problems: String
    let quality: String
}

struct ProReportData: Sendable {
    var generatedAt: Date
    var appVersion: String
    var connection: String
    var provider: String?
    var publicIP: String?
    var periodText: String
    var speedSummary: SpeedHistorySummary?
    /// Скорость скачивания по замерам, от старых к новым (для графика)
    var speedSeries: [Double]
    var hosts: [ReportHostLine]
    var problems: [String]
    var routes: [ReportRouteLine]
    var complaint: String
}

// MARK: - PDF

enum ReportBuilder {
    static let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    private static let margin: CGFloat = 40
    private static let accent = UIColor(red: 0.0, green: 0.55, blue: 0.5, alpha: 1)

    /// Собирает PDF. Чистая функция без обращения к приложению: легко проверяется тестом.
    static func makePDF(_ data: ProReportData) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Отчёт о качестве интернета",
            kCGPDFContextCreator as String: "NetPulse"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        return renderer.pdfData { context in
            let page = PageWriter(context: context, rect: pageRect, margin: margin)

            page.text("Отчёт о качестве интернета", font: .systemFont(ofSize: 24, weight: .heavy), after: 2)
            page.text(
                "Создан \(data.generatedAt.formatted(date: .long, time: .shortened)) в приложении NetPulse \(data.appVersion)",
                font: .systemFont(ofSize: 11),
                color: .darkGray,
                after: 10
            )

            page.heading("Подключение")
            page.text("Тип подключения: \(data.connection)", font: .systemFont(ofSize: 12), after: 2)
            if let provider = data.provider, !provider.isEmpty {
                page.text("Провайдер: \(provider)", font: .systemFont(ofSize: 12), after: 2)
            }
            if let ip = data.publicIP, !ip.isEmpty {
                page.text("Внешний IP-адрес: \(ip)", font: .systemFont(ofSize: 12), after: 2)
            }
            page.text(data.periodText, font: .systemFont(ofSize: 11), color: .darkGray, after: 6)

            page.heading("Скорость")
            if let summary = data.speedSummary {
                page.text(
                    "Замеров: \(summary.count). Скачивание: в среднем \(mbps(summary.averageDownloadMbps)), лучший результат \(mbps(summary.bestDownloadMbps)), худший \(mbps(summary.worstDownloadMbps)). Отдача в среднем \(mbps(summary.averageUploadMbps))."
                        + (summary.averagePingMs.map { " Пинг в среднем \(Int($0.rounded())) мс." } ?? ""),
                    font: .systemFont(ofSize: 12),
                    after: 8
                )
                page.chart(values: data.speedSeries, caption: "Скачивание по замерам, Мбит/с (слева старые, справа новые)")
            } else {
                page.text("Замеров скорости нет: сделайте замер на вкладке «Сеть», и он появится в отчёте.", font: .systemFont(ofSize: 12), color: .darkGray)
            }

            page.heading("Задержка и потери по узлам")
            if data.hosts.isEmpty {
                page.text("Данных мониторинга нет: приложение не опрашивало узлы.", font: .systemFont(ofSize: 12), color: .darkGray)
            } else {
                page.tableRow(["Узел", "Задержка", "Джиттер", "Потери", "Состояние"], bold: true)
                for host in data.hosts {
                    page.tableRow([
                        "\(host.name) (\(host.address))",
                        host.averageLatencyMs.map { "\(Int($0.rounded())) мс" } ?? "—",
                        host.jitterMs.map { String(format: "%.1f мс", $0) } ?? "—",
                        host.lossPct.map { String(format: "%.1f %%", $0) } ?? "—",
                        host.status
                    ], bold: false)
                }
            }

            page.heading("Обрывы и серьёзные проблемы")
            if data.problems.isEmpty {
                page.text("Серьёзных проблем за сеанс не зафиксировано.", font: .systemFont(ofSize: 12), color: .darkGray)
            } else {
                for line in data.problems {
                    page.text("• \(line)", font: .systemFont(ofSize: 11.5), after: 3)
                }
            }

            if !data.routes.isEmpty {
                page.heading("Проблемные места на маршрутах")
                for route in data.routes {
                    page.text(route.title, font: .systemFont(ofSize: 12, weight: .bold), after: 1)
                    page.text(route.summary, font: .systemFont(ofSize: 11.5), after: 1)
                    page.text(route.quality, font: .systemFont(ofSize: 11.5), after: 1)
                    page.text(route.problems, font: .systemFont(ofSize: 11.5), color: .darkGray, after: 8)
                }
            }

            page.heading("Обращение провайдеру")
            page.text(data.complaint, font: .systemFont(ofSize: 11.5), after: 8)

            page.text(
                "Отчёт собран на телефоне по измерениям приложения. Приложение измеряет качество с вашего телефона и не знает причин: они могут быть на стороне провайдера, внутри дома или в сети сервисов.",
                font: .italicSystemFont(ofSize: 10),
                color: .darkGray
            )
        }
    }

    private static func mbps(_ value: Double) -> String {
        String(format: "%.1f Мбит/с", value)
    }

    // MARK: - Рисование страниц

    private final class PageWriter {
        let context: UIGraphicsPDFRendererContext
        let rect: CGRect
        let margin: CGFloat
        var y: CGFloat = 0
        var pageNumber = 0

        init(context: UIGraphicsPDFRendererContext, rect: CGRect, margin: CGFloat) {
            self.context = context
            self.rect = rect
            self.margin = margin
            startPage()
        }

        private var contentWidth: CGFloat { rect.width - margin * 2 }
        private var bottomLimit: CGFloat { rect.height - margin - 18 }

        func startPage() {
            context.beginPage()
            pageNumber += 1
            y = margin
            let footer = "NetPulse · страница \(pageNumber)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.gray
            ]
            (footer as NSString).draw(
                in: CGRect(x: margin, y: rect.height - margin + 4, width: contentWidth, height: 12),
                withAttributes: attributes
            )
        }

        func ensure(_ height: CGFloat) {
            if y + height > bottomLimit {
                startPage()
            }
        }

        @discardableResult
        func text(_ string: String, font: UIFont, color: UIColor = .black, after: CGFloat = 6) -> CGFloat {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: style
            ]
            let bounds = (string as NSString).boundingRect(
                with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
            let height = ceil(bounds.height)
            ensure(height)
            (string as NSString).draw(
                in: CGRect(x: margin, y: y, width: contentWidth, height: height),
                withAttributes: attributes
            )
            y += height + after
            return height
        }

        func heading(_ string: String) {
            ensure(40)
            y += 8
            text(string, font: .systemFont(ofSize: 15, weight: .bold), color: ReportBuilder.accent, after: 3)
            let line = UIBezierPath()
            line.move(to: CGPoint(x: margin, y: y))
            line.addLine(to: CGPoint(x: margin + contentWidth, y: y))
            UIColor(white: 0.8, alpha: 1).setStroke()
            line.lineWidth = 0.7
            line.stroke()
            y += 6
        }

        /// Строка таблицы: ширины колонок заданы долями (узел шире остальных)
        func tableRow(_ cells: [String], bold: Bool) {
            let fractions: [CGFloat] = [0.40, 0.14, 0.14, 0.14, 0.18]
            let font = bold ? UIFont.systemFont(ofSize: 10.5, weight: .bold) : UIFont.systemFont(ofSize: 10.5)
            var heights: [CGFloat] = []
            for (index, cell) in cells.enumerated() {
                let width = contentWidth * fractions[min(index, fractions.count - 1)] - 4
                let bounds = (cell as NSString).boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: font],
                    context: nil
                )
                heights.append(ceil(bounds.height))
            }
            let rowHeight = (heights.max() ?? 14) + 4
            ensure(rowHeight)
            var x = margin
            for (index, cell) in cells.enumerated() {
                let width = contentWidth * fractions[min(index, fractions.count - 1)]
                (cell as NSString).draw(
                    in: CGRect(x: x, y: y, width: width - 4, height: rowHeight),
                    withAttributes: [.font: font, .foregroundColor: UIColor.black]
                )
                x += width
            }
            y += rowHeight
        }

        /// Линейный график скорости: подпись, сетка, линия и точки
        func chart(values: [Double], caption: String) {
            let height: CGFloat = 130
            ensure(height + 26)
            let box = CGRect(x: margin, y: y, width: contentWidth, height: height)
            UIColor(white: 0.96, alpha: 1).setFill()
            UIBezierPath(roundedRect: box, cornerRadius: 6).fill()

            guard values.count >= 2, let maxValue = values.max(), maxValue > 0 else {
                text("Для графика нужно хотя бы два замера.", font: .systemFont(ofSize: 11), color: .darkGray)
                return
            }

            let inner = box.insetBy(dx: 12, dy: 16)
            UIColor(white: 0.85, alpha: 1).setStroke()
            for step in 0...2 {
                let level = inner.maxY - inner.height * CGFloat(step) / 2
                let grid = UIBezierPath()
                grid.move(to: CGPoint(x: inner.minX, y: level))
                grid.addLine(to: CGPoint(x: inner.maxX, y: level))
                grid.lineWidth = 0.5
                grid.stroke()
            }

            let path = UIBezierPath()
            var points: [CGPoint] = []
            for (index, value) in values.enumerated() {
                let px = inner.minX + inner.width * CGFloat(index) / CGFloat(values.count - 1)
                let py = inner.maxY - inner.height * CGFloat(value / maxValue)
                let point = CGPoint(x: px, y: py)
                points.append(point)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            ReportBuilder.accent.setStroke()
            path.lineWidth = 1.8
            path.stroke()
            ReportBuilder.accent.setFill()
            for point in points {
                UIBezierPath(ovalIn: CGRect(x: point.x - 2.2, y: point.y - 2.2, width: 4.4, height: 4.4)).fill()
            }

            let label = String(format: "%.0f", maxValue) as NSString
            label.draw(
                at: CGPoint(x: box.minX + 4, y: box.minY + 2),
                withAttributes: [.font: UIFont.systemFont(ofSize: 8.5), .foregroundColor: UIColor.darkGray]
            )
            y += height + 4
            text(caption, font: .systemFont(ofSize: 9.5), color: .darkGray, after: 8)
        }
    }
}

// MARK: - Сбор данных из приложения

@MainActor
extension ProReportData {
    /// Собирает отчёт по текущему состоянию приложения: узлы, оповещения, замеры, маршруты, обращение
    static func gather(viewModel: NetworkMonitorViewModel) -> ProReportData {
        let info = viewModel.systemInfo
        let entries = SpeedHistoryStore.shared.entries
        let speedEntries = Array(entries.prefix(40).reversed())

        let period: String
        if let first = entries.last, let last = entries.first {
            period = "Замеры скорости с \(first.date.formatted(date: .abbreviated, time: .omitted)) по \(last.date.formatted(date: .abbreviated, time: .omitted)); задержка, потери и оповещения за текущий сеанс работы приложения."
        } else {
            period = "Задержка, потери и оповещения за текущий сеанс работы приложения."
        }

        let hosts = viewModel.hostMetrics.values
            .sorted { $0.name < $1.name }
            .map { host in
                ReportHostLine(
                    name: host.name,
                    address: host.address,
                    averageLatencyMs: host.avgLatencyMs,
                    jitterMs: host.sentCount > 1 ? host.jitterMs : nil,
                    lossPct: host.sentCount > 0 ? host.lossRatePct : nil,
                    status: statusText(host.status)
                )
            }

        let problems = viewModel.recentAlerts
            .filter { $0.severity == .critical }
            .prefix(12)
            .map { "\($0.timestamp.formatted(date: .abbreviated, time: .shortened)) · \($0.targetName): \($0.message)" }

        let routes = RouteRecorder.shared.history.prefix(3).map { route -> ReportRouteLine in
            let stats = RouteAnalyzer.stats(of: route)
            let zones = RouteAnalyzer.deadZones(in: route.points)
            let quality = [RouteQuality.good, .fair, .poor, .dead]
                .map { "\($0.title) \(RouteFormat.percent(stats.share(of: $0)))" }
                .joined(separator: " · ")
            var summary = "\(RouteFormat.distance(stats.distanceMeters)) · \(RouteFormat.duration(stats.duration))"
            if let average = stats.averageLatencyMs {
                summary += " · задержка в среднем \(RouteFormat.latency(average))"
            }
            if let speed = stats.averageDownloadMbps {
                summary += " · скорость в среднем \(RouteFormat.speed(speed))"
            }
            let total = zones.reduce(0) { $0 + $1.duration }
            let problemsText = zones.isEmpty
                ? "Мест без связи не найдено."
                : "Мест без связи: \(zones.count), всего \(RouteFormat.spokenDuration(total)), самая длинная зона — \(RouteFormat.distance(stats.longestDeadStretchMeters))."
            return ReportRouteLine(
                title: RouteTitle.dateRange(of: route),
                summary: summary,
                problems: problemsText,
                quality: "Качество связи: \(quality)"
            )
        }

        let complaint = viewModel.buildDiagnosticsContext().generateISPSupportReport(template: .packetLossAndLatency)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"

        return ProReportData(
            generatedAt: Date(),
            appVersion: version,
            connection: info.connectionType.rawValue,
            provider: info.ispName,
            publicIP: info.publicIP,
            periodText: period,
            speedSummary: SpeedHistorySummary.make(from: entries),
            speedSeries: speedEntries.map(\.downloadMbps),
            hosts: hosts,
            problems: Array(problems),
            routes: routes,
            complaint: complaint
        )
    }

    private static func statusText(_ status: HostStatus) -> String {
        switch status {
        case .ok: return "норма"
        case .warning: return "предупреждение"
        case .critical: return "критично"
        case .down: return "недоступен"
        case .unknown: return "—"
        }
    }

    /// Сохраняет PDF во временный файл для окна «Поделиться»
    nonisolated static func writePDF(_ data: ProReportData) -> URL? {
        let pdf = ReportBuilder.makePDF(data)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let stamp = formatter.string(from: data.generatedAt)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NetPulse-отчёт-\(stamp).pdf")
        do {
            try pdf.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }
}
