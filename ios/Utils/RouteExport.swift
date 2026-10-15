//
//  RouteExport.swift
//  NetPulse
//
//  Экспорт маршрута: файл GPX (открывается в картах и фитнес-приложениях) и картинка карты с цветной линией.
//

import SwiftUI
import MapKit
import UIKit

/// Окно «Поделиться» системы для файлов и картинок
struct NPShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Что показывает окно «Поделиться»
struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

enum RouteExport {
    // MARK: - GPX

    /// Текст GPX 1.1: дорожка из точек маршрута с временем и пометкой качества связи
    static func gpx(for route: RouteRecord, appVersion: String) -> String {
        let time = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<gpx version=\"1.1\" creator=\"NetPulse \(escape(appVersion))\" xmlns=\"http://www.topografix.com/GPX/1/1\">")
        lines.append("  <metadata>")
        lines.append("    <name>\(escape(RouteTitle.dateRange(of: route)))</name>")
        lines.append("    <time>\(time.string(from: route.startedAt))</time>")
        lines.append("  </metadata>")
        lines.append("  <trk>")
        lines.append("    <name>NetPulse \(escape(RouteTitle.dateRange(of: route)))</name>")
        lines.append("    <trkseg>")
        for point in route.points {
            lines.append(String(format: "      <trkpt lat=\"%.7f\" lon=\"%.7f\">", point.latitude, point.longitude))
            lines.append("        <time>\(time.string(from: point.time))</time>")
            lines.append("        <desc>\(escape(description(of: point)))</desc>")
            lines.append("      </trkpt>")
        }
        lines.append("    </trkseg>")
        lines.append("  </trk>")
        lines.append("</gpx>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Подпись точки: «Связь: хорошо · задержка 42 мс · скорость 12.5 Мбит/с»
    static func description(of point: RoutePoint) -> String {
        var parts = ["Связь: \(point.quality.title.lowercased())"]
        if let latency = point.latencyMs {
            parts.append("задержка \(Int(latency.rounded())) мс")
        } else if !point.reachable {
            parts.append("нет ответа сети")
        }
        if let speed = point.downloadMbps, speed > 0 {
            parts.append(String(format: "скорость %.1f Мбит/с", speed))
        }
        return parts.joined(separator: " · ")
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Записывает GPX во временный файл для «Поделиться»
    static func writeGPX(for route: RouteRecord) -> URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let name = "NetPulse-маршрут-\(formatter.string(from: route.startedAt)).gpx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try gpx(for: route, appVersion: version).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Картинка карты

    /// Картинка карты 1080×1350 с цветным маршрутом, датой, длиной и легендой. `nil`, если карта не загрузилась.
    @MainActor
    static func mapImage(for route: RouteRecord) async -> UIImage? {
        guard route.points.count >= 2 else { return nil }
        let size = CGSize(width: 1080, height: 1350)

        var rect = MKMapRect.null
        for point in route.points {
            let mapPoint = MKMapPoint(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            rect = rect.union(MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 1, height: 1))
        }
        // Отступ вокруг маршрута и минимальный размер, чтобы короткий маршрут не «прилипал» к краям
        let padX = max(rect.width * 0.25, 300)
        let padY = max(rect.height * 0.25, 300)
        let area = rect.insetBy(dx: -padX, dy: -padY)

        let options = MKMapSnapshotter.Options()
        options.mapRect = area
        options.size = size
        options.scale = 1
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.pointOfInterestFilter = .excludingAll

        let snapshot: MKMapSnapshotter.Snapshot
        do {
            snapshot = try await MKMapSnapshotter(options: options).start()
        } catch {
            return nil
        }

        let stats = RouteAnalyzer.stats(of: route)
        let segments = RouteAnalyzer.segments(for: route.points, metric: .latency)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)

            for segment in segments {
                let path = UIBezierPath()
                for (index, coordinate) in segment.path.enumerated() {
                    let point = snapshot.point(for: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                UIColor.black.withAlphaComponent(0.6).setStroke()
                path.lineWidth = 14
                path.stroke()
                UIColor(segment.quality.displayColor).setStroke()
                path.lineWidth = 8
                if segment.quality == .dead {
                    path.setLineDash([2, 14], count: 2, phase: 0)
                }
                path.stroke()
            }

            drawLabel(
                "NetPulse · \(RouteTitle.dateRange(of: route))",
                subtitle: "\(RouteFormat.distance(stats.distanceMeters)) · \(RouteFormat.duration(stats.duration))",
                at: CGPoint(x: 40, y: 40)
            )
            drawLegend(at: CGPoint(x: 40, y: size.height - 90))
        }
    }

    private static func drawLabel(_ title: String, subtitle: String, at origin: CGPoint) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 34, weight: .heavy),
            .foregroundColor: UIColor.white
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
            .foregroundColor: UIColor(white: 0.85, alpha: 1)
        ]
        let titleSize = (title as NSString).size(withAttributes: titleAttributes)
        let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttributes)
        let box = CGRect(
            x: origin.x,
            y: origin.y,
            width: max(titleSize.width, subtitleSize.width) + 40,
            height: titleSize.height + subtitleSize.height + 32
        )
        UIColor.black.withAlphaComponent(0.65).setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 22).fill()
        (title as NSString).draw(at: CGPoint(x: box.minX + 20, y: box.minY + 14), withAttributes: titleAttributes)
        (subtitle as NSString).draw(at: CGPoint(x: box.minX + 20, y: box.minY + 18 + titleSize.height), withAttributes: subtitleAttributes)
    }

    private static func drawLegend(at origin: CGPoint) {
        let items: [(RouteQuality, String)] = [(.good, "Хорошо"), (.fair, "Средне"), (.poor, "Плохо"), (.dead, "Нет сети")]
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        let box = CGRect(x: origin.x, y: origin.y, width: 720, height: 56)
        UIColor.black.withAlphaComponent(0.65).setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 28).fill()
        var x = box.minX + 24
        for (quality, title) in items {
            UIColor(quality.displayColor).setFill()
            UIBezierPath(roundedRect: CGRect(x: x, y: box.minY + 17, width: 22, height: 22), cornerRadius: 6).fill()
            x += 32
            (title as NSString).draw(at: CGPoint(x: x, y: box.minY + 10), withAttributes: attributes)
            x += (title as NSString).size(withAttributes: attributes).width + 28
        }
    }
}
