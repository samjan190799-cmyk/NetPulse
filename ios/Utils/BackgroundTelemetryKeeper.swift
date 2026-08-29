//
//  BackgroundTelemetryKeeper.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / AVFoundation) - 2026.
//

import Foundation
import UIKit
import AVFoundation

/// Фоновый хранитель сессии телеметрии: обеспечивает бесперебойную работу Live Activity (Dynamic Island)
/// и непрерывный учет трафика 24/7 в фоне через сессию воспроизведения тишины (Zero CPU / Zero Battery).
@MainActor
public final class BackgroundTelemetryKeeper: NSObject, AVAudioPlayerDelegate {
    public static let shared = BackgroundTelemetryKeeper()

    private var audioPlayer: AVAudioPlayer?
    private var isRunning: Bool = false
    private var observers: [NSObjectProtocol] = []

    private override init() {
        super.init()
    }

    /// Запуск удержания фоновой сессии
    public func startKeepAlive() {
        guard !isRunning else { return }
        isRunning = true

        setupSilentAudioSession()
        setupAudioSessionObservers()
        playSilentSound()

        // Регистрация на фоновое обновление через BGTaskScheduler
        BackgroundTaskManager.shared.scheduleBackgroundFetch()
        print("⚡️ [BackgroundTelemetryKeeper] Фоновая сессия телеметрии 24/7 успешно запущена")
    }

    /// Остановка фонового удержания
    public func stopKeepAlive() {
        guard isRunning else { return }
        isRunning = false

        removeAudioSessionObservers()
        audioPlayer?.stop()
        audioPlayer = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ Ошибка деактивации аудиосессии: \(error.localizedDescription)")
        }
        print("🛑 [BackgroundTelemetryKeeper] Фоновая сессия остановлена")
    }

    private func setupSilentAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Режим playback + mixWithOthers гарантирует, что мы не глушим музыку пользователя (YouTube, Spotify, Apple Music)
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowAirPlay])
            try session.setActive(true)
        } catch {
            print("⚠️ Ошибка настройки аудиосессии фонового мониторинга: \(error.localizedDescription)")
        }
    }

    /// Регистрация обработчиков системных прерываний, смены маршрутов и сброса аудиоподсистемы
    private func setupAudioSessionObservers() {
        removeAudioSessionObservers()

        // 1. Прерывания (Входящие звонки, Siri, будильники)
        let interruptionObs = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                guard let userInfo = notification.userInfo,
                      let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                    return
                }

                switch type {
                case .began:
                    print("⏸️ [BackgroundTelemetryKeeper] Аудиосессия прервана системой (звонок / Siri)")
                case .ended:
                    print("▶️ [BackgroundTelemetryKeeper] Прерывание завершено — восстанавливаем фоновую сессию")
                    self.setupSilentAudioSession()
                    self.playSilentSound()
                @unknown default:
                    break
                }
            }
        }
        observers.append(interruptionObs)

        // 2. Смена аудиомаршрута (Подключение / отключение AirPods, Bluetooth, CarPlay)
        let routeChangeObs = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                guard let userInfo = notification.userInfo,
                      let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                    return
                }

                switch reason {
                case .oldDeviceUnavailable, .newDeviceAvailable, .categoryChange, .override:
                    print("🎧 [BackgroundTelemetryKeeper] Смена аудиомаршрута (\(reasonValue)) — перезапуск тишины")
                    self.setupSilentAudioSession()
                    if self.audioPlayer?.isPlaying != true {
                        self.playSilentSound()
                    }
                default:
                    break
                }
            }
        }
        observers.append(routeChangeObs)

        // 3. Сброс аудиосервисов (Media Services Reset)
        let resetObs = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            print("🔄 [BackgroundTelemetryKeeper] Сброс аудиосервисов iOS — полная переинициализация")
            self.setupSilentAudioSession()
            self.playSilentSound()
        }
        observers.append(resetObs)
    }

    private func removeAudioSessionObservers() {
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
        observers.removeAll()
    }

    private func playSilentSound() {
        guard isRunning else { return }

        let sampleRate: UInt32 = 8000
        let duration: Double = 1.0
        let numSamples = Int(Double(sampleRate) * duration)
        let numBytes = UInt32(numSamples * 2)

        var pcmData = Data()
        // RIFF header
        pcmData.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        let fileSize: UInt32 = 36 + numBytes
        withUnsafeBytes(of: fileSize.littleEndian) { pcmData.append(contentsOf: $0) }
        pcmData.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt chunk
        pcmData.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        let fmtChunkSize: UInt32 = 16
        withUnsafeBytes(of: fmtChunkSize.littleEndian) { pcmData.append(contentsOf: $0) }
        let formatType: UInt16 = 1 // PCM
        withUnsafeBytes(of: formatType.littleEndian) { pcmData.append(contentsOf: $0) }
        let channels: UInt16 = 1
        withUnsafeBytes(of: channels.littleEndian) { pcmData.append(contentsOf: $0) }
        withUnsafeBytes(of: sampleRate.littleEndian) { pcmData.append(contentsOf: $0) }
        let byteRate: UInt32 = sampleRate * 2
        withUnsafeBytes(of: byteRate.littleEndian) { pcmData.append(contentsOf: $0) }
        let blockAlign: UInt16 = 2
        withUnsafeBytes(of: blockAlign.littleEndian) { pcmData.append(contentsOf: $0) }
        let bitsPerSample: UInt16 = 16
        withUnsafeBytes(of: bitsPerSample.littleEndian) { pcmData.append(contentsOf: $0) }

        // data chunk
        pcmData.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        withUnsafeBytes(of: numBytes.littleEndian) { pcmData.append(contentsOf: $0) }
        // Silent PCM samples (all zeros)
        pcmData.append(Data(count: Int(numBytes)))

        do {
            let player = try AVAudioPlayer(data: pcmData)
            player.delegate = self
            player.numberOfLoops = -1
            player.volume = 0.0
            player.prepareToPlay()
            player.play()
            self.audioPlayer = player
        } catch {
            print("⚠️ Ошибка запуска тишины: \(error.localizedDescription)")
        }
    }
}
