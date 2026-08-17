//
//  BackgroundTelemetryKeeper.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import Foundation
import AVFoundation
import UIKit

/// Системный хранитель фонового процесса телеметрии для непрерывного обновления Dynamic Island 24/7.
@MainActor
public final class BackgroundTelemetryKeeper: NSObject, AVAudioPlayerDelegate {
    public static let shared = BackgroundTelemetryKeeper()

    private var audioPlayer: AVAudioPlayer?
    private var isRunning: Bool = false
    private var isObservingNotifications: Bool = false
    private var watchdogTimer: Timer?

    private override init() {
        super.init()
    }

    /// Запуск удержания фоновой сессии
    public func startKeepAlive() {
        setupObserversIfNeeded()

        guard !isRunning else {
            // Если уже работает, проверяем активность плеера
            ensurePlayerIsActive()
            return
        }
        isRunning = true

        activateAudioEngine()
        startWatchdog()
    }

    /// Остановка фонового удержания
    public func stopKeepAlive() {
        guard isRunning else { return }
        isRunning = false
        stopWatchdog()

        audioPlayer?.stop()
        audioPlayer = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Игнорируем ошибку деактивации
        }
        print("🛑 Фоновый процесс телеметрии NetPulse остановлен")
    }

    // MARK: - Активация аудио-рантайма с поддержкой микширования (.mixWithOthers)

    private func activateAudioEngine() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Используем .mixWithOthers + .duckOthers, чтобы фоновый процесс телеметрии НИКОГДА не прерывался
            // при воспроизведении музыки (Apple Music / Spotify), видео, играх или системных звуках.
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .duckOthers]
            )
            try audioSession.setActive(true)

            if audioPlayer == nil {
                let silentData = generateInaudibleWavData()
                audioPlayer = try AVAudioPlayer(data: silentData)
                audioPlayer?.delegate = self
                audioPlayer?.numberOfLoops = -1 // Бесконечный непрерывный цикл
                audioPlayer?.volume = 0.05
                audioPlayer?.prepareToPlay()
            }

            audioPlayer?.play()
            print("✅ Фоновый процесс телеметрии NetPulse активирован (Dynamic Island работает непрерывно с поддержкой фоновой музыки)")
        } catch {
            print("⚠️ Ошибка активации аудио-сессии: \(error.localizedDescription)")
        }
    }

    private func ensurePlayerIsActive() {
        guard isRunning else { return }
        if audioPlayer == nil || audioPlayer?.isPlaying == false {
            activateAudioEngine()
        }
    }

    // MARK: - Сторожевой таймер (Watchdog) для предотвращения засыпания

    private func startWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isRunning else { return }
                self.ensurePlayerIsActive()
            }
        }
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    // MARK: - AVAudioPlayerDelegate

    public nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor in
            if self.isRunning {
                self.audioPlayer = nil
                self.activateAudioEngine()
            }
        }
    }

    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.isRunning {
                self.ensurePlayerIsActive()
            }
        }
    }

    // MARK: - Обработка системных событий аудиосессии

    private func setupObserversIfNeeded() {
        guard !isObservingNotifications else { return }
        isObservingNotifications = true

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioInterruption(notification)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleRouteChange(notification)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.audioPlayer = nil
                if self?.isRunning == true {
                    self?.activateAudioEngine()
                }
            }
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard isRunning,
              let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        if type == .ended {
            // Проверяем флаг shouldResume
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    activateAudioEngine()
                    return
                }
            }
            activateAudioEngine()
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        if isRunning {
            // При смене Bluetooth/AirPods/динамика возобновляем плеер
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.ensurePlayerIsActive()
            }
        }
    }

    /// Генерация 5.0-секундного инфразвукового WAV-файла (18 Гц, 8kHz, 16-bit Mono PCM).
    private func generateInaudibleWavData() -> Data {
        let sampleRate: Double = 8000.0
        let durationSeconds: Double = 5.0
        let numSamples = Int(sampleRate * durationSeconds)
        let frequency: Double = 18.0 // 18 Гц — инфразвук ниже порога слышимости
        let amplitude: Double = 80.0 // 0.2% от 32767
        let bytesPerSample = 2
        let dataSize = Int32(numSamples * bytesPerSample)
        let totalSize = 36 + dataSize

        var data = Data()

        // RIFF Header
        data.append(contentsOf: "RIFF".utf8)
        var chunkSize = totalSize
        data.append(Data(bytes: &chunkSize, count: 4))
        data.append(contentsOf: "WAVE".utf8)

        // fmt subchunk
        data.append(contentsOf: "fmt ".utf8)
        var subchunk1Size: Int32 = 16
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: Int16 = 1 // PCM
        data.append(Data(bytes: &audioFormat, count: 2))
        var channels: Int16 = 1 // Mono
        data.append(Data(bytes: &channels, count: 2))
        var rate = Int32(sampleRate)
        data.append(Data(bytes: &rate, count: 4))
        var byteRate = Int32(sampleRate) * Int32(channels) * Int32(bytesPerSample)
        data.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = Int16(channels * Int16(bytesPerSample))
        data.append(Data(bytes: &blockAlign, count: 2))
        var bps: Int16 = 16
        data.append(Data(bytes: &bps, count: 2))

        // data subchunk
        data.append(contentsOf: "data".utf8)
        var subchunk2Size = dataSize
        data.append(Data(bytes: &subchunk2Size, count: 4))

        // Генерация синусоиды 18 Гц
        for i in 0..<numSamples {
            let angle = 2.0 * Double.pi * frequency * Double(i) / sampleRate
            let sampleVal = Int16(amplitude * sin(angle))
            var leVal = sampleVal.littleEndian
            withUnsafeBytes(of: &leVal) { data.append(contentsOf: $0) }
        }

        return data
    }
}
