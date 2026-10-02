// Распознаёт текст на скриншотах симулятора (Vision), чтобы содержимое Dynamic Island можно было прочитать
// прямо в журнале CI. Дополнительно сохраняет верхнюю полосу экрана (там находится остров) отдельным файлом.
//
// Запуск: swift ios/ci/ocr_screenshots.swift файл1.png файл2.png ...

import AppKit
import Foundation
import Vision

func recognizeText(in image: CGImage) -> [String] {
    let handler = VNImageRequestHandler(cgImage: image, options: [:])

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["ru-RU", "en-US"]
    do {
        try handler.perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    } catch {
        // Русский язык может быть недоступен в этой версии системы — повторяем без явного списка языков
        let fallback = VNRecognizeTextRequest()
        fallback.recognitionLevel = .accurate
        fallback.usesLanguageCorrection = false
        do {
            try handler.perform([fallback])
            return (fallback.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        } catch {
            return ["(ошибка распознавания: \(error.localizedDescription))"]
        }
    }
}

func savePNG(_ image: CGImage, to path: String) {
    let representation = NSBitmapImageRep(cgImage: image)
    if let data = representation.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

for path in CommandLine.arguments.dropFirst() {
    let name = (path as NSString).lastPathComponent
    guard let nsImage = NSImage(contentsOfFile: path),
          let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("=== \(name): не удалось открыть изображение")
        continue
    }

    print("=== \(name) (\(cgImage.width)x\(cgImage.height))")
    print("весь экран: " + recognizeText(in: cgImage).joined(separator: " | "))

    // Остров находится в верхней части экрана: берём полосу 14 % высоты
    let bandHeight = Int(Double(cgImage.height) * 0.14)
    if bandHeight > 0, let band = cgImage.cropping(to: CGRect(x: 0, y: 0, width: cgImage.width, height: bandHeight)) {
        print("верхняя полоса: " + recognizeText(in: band).joined(separator: " | "))
        let bandPath = (path as NSString).deletingPathExtension + "-top-band.png"
        savePNG(band, to: bandPath)
    }
}
