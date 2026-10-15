//
//  PerformanceMonitor.swift
//  NetPulse
//
//  Замер плавности и нагрузки для тестовых сборок: кадры в секунду, загрузка процессора, свободная память.
//  По просадкам кадров пишет запись в журнал «Диагностика острова» с указанием экрана, чтобы видеть, где тормозит.
//  Работает только в отладочных и тестовых сборках (флаг NETPULSE_TESTER), в сборке для App Store кода нет.
//

#if DEBUG || NETPULSE_TESTER

import SwiftUI
import UIKit
import QuartzCore
import Observation
import Darwin

/// Снимок нагрузки за последнюю секунду
struct PerformanceSample: Equatable, Sendable {
    var fps: Int = 0
    /// Самый долгий кадр за секунду, миллисекунд
    var worstFrameMs: Int = 0
    /// Загрузка процессора приложением, процентов (может быть выше 100 при нескольких ядрах)
    var cpuPercent: Int = 0
    /// Сколько памяти осталось до лимита, после которого система закроет приложение, МБ
    var freeMemoryMB: Int = 0
}

@MainActor
@Observable
final class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    private(set) var sample = PerformanceSample()
    /// Название экрана для журнала («Сеть», «Инструменты»…); ставится из ContentView
    @ObservationIgnored var screenName: String = "Сеть"

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var ticker: FrameTicker?
    @ObservationIgnored private var windowStart: CFTimeInterval = 0
    @ObservationIgnored private var lastFrameAt: CFTimeInterval = 0
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var worstFrame: CFTimeInterval = 0
    @ObservationIgnored private var lastCPUTime: Double = 0
    @ObservationIgnored private var lowSeconds = 0
    @ObservationIgnored private var lastLoggedAt: Date = .distantPast

    /// Ниже скольких кадров в секунду считать просадкой и сколько секунд подряд терпеть до записи в журнал
    private static let lowFPS = 45
    private static let lowSecondsToLog = 3

    var isRunning: Bool {
        link != nil
    }

    func start() {
        guard link == nil else { return }
        let ticker = FrameTicker { [weak self] link in
            MainActor.assumeIsolated {
                self?.frame(link.timestamp)
            }
        }
        let link = CADisplayLink(target: ticker, selector: #selector(FrameTicker.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.ticker = ticker
        self.link = link
        windowStart = 0
        lastFrameAt = 0
        frames = 0
        worstFrame = 0
        lastCPUTime = Self.processCPUTime()
    }

    func stop() {
        link?.invalidate()
        link = nil
        ticker = nil
        sample = PerformanceSample()
    }

    private func frame(_ timestamp: CFTimeInterval) {
        if windowStart == 0 {
            windowStart = timestamp
            lastFrameAt = timestamp
            return
        }
        frames += 1
        worstFrame = max(worstFrame, timestamp - lastFrameAt)
        lastFrameAt = timestamp

        let elapsed = timestamp - windowStart
        guard elapsed >= 1 else { return }

        let cpuNow = Self.processCPUTime()
        let cpu = max(0, (cpuNow - lastCPUTime) / elapsed * 100)
        lastCPUTime = cpuNow

        let next = PerformanceSample(
            fps: Int((Double(frames) / elapsed).rounded()),
            worstFrameMs: Int((worstFrame * 1_000).rounded()),
            cpuPercent: Int(cpu.rounded()),
            freeMemoryMB: IslandDiagnostics.availableMemoryMB() ?? 0
        )
        sample = next
        windowStart = timestamp
        frames = 0
        worstFrame = 0
        report(next)
    }

    /// Несколько секунд подряд низкая частота кадров: записываем в журнал, на каком экране и при какой нагрузке
    private func report(_ sample: PerformanceSample) {
        if sample.fps < Self.lowFPS {
            lowSeconds += 1
        } else {
            lowSeconds = 0
        }
        guard lowSeconds >= Self.lowSecondsToLog, Date().timeIntervalSince(lastLoggedAt) >= 10 else { return }
        lastLoggedAt = Date()
        let recording = RouteRecorder.shared.isActive ? "запись идёт" : "записи нет"
        IslandDiagnostics.shared.log(
            "Просадка кадров: \(sample.fps) к/с, худший кадр \(sample.worstFrameMs) мс, процессор \(sample.cpuPercent) %, "
                + "свободно памяти \(sample.freeMemoryMB) МБ, экран «\(screenName)», \(recording)",
            .warning
        )
    }

    /// Процессорное время приложения (пользовательское плюс системное), секунд
    private static func processCPUTime() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }
}

/// Цель для `CADisplayLink`: ему нужен объект NSObject с методом, а не замыкание
private final class FrameTicker: NSObject {
    private let onFrame: (CADisplayLink) -> Void

    init(onFrame: @escaping (CADisplayLink) -> Void) {
        self.onFrame = onFrame
    }

    @objc func tick(_ link: CADisplayLink) {
        onFrame(link)
    }
}

/// Плашка со счётчиками поверх приложения (не перехватывает нажатия)
struct PerformanceOverlay: View {
    private let monitor = PerformanceMonitor.shared

    var body: some View {
        let sample = monitor.sample
        HStack(spacing: 8) {
            Text("\(sample.fps) к/с")
                .foregroundStyle(sample.fps >= 100 ? Color.green : (sample.fps >= 55 ? Color.yellow : Color.red))
            Text("худший \(sample.worstFrameMs) мс")
            Text("ЦП \(sample.cpuPercent) %")
            Text("ОЗУ \(sample.freeMemoryMB) МБ")
        }
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.78)))
        .allowsHitTesting(false)
        .accessibilityIdentifier("performanceOverlay")
    }
}

#endif
