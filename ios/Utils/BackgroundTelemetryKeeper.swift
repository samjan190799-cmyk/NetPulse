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
public final class BackgroundTelemetryKeeper {
    public static let shared = BackgroundTelemetryKeeper()

    private var audioPlayer: AVAudioPlayer?
    private var isRunning: Bool = false
    private var isObservingNotifications: Bool = false

    private init() {}

    /// Запуск удержания фоновой сессии
    public func startKeepAlive() {
        setupObserversIfNeeded()

        guard !isRunning else { return }
        isRunning = true

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .duckOthers]
            )
            try audioSession.setActive(true)

            // Создаем минимальный беззвучный PCM буфер (0.1 сек тишины)
            if audioPlayer == nil {
                let silentData = generateSilentWavData()
                audioPlayer = try AVAudioPlayer(data: silentData)
                audioPlayer?.numberOfLoops = -1 // Бесконечный тихий цикл
                audioPlayer?.volume = 0.001 // Полная тишина
                audioPlayer?.prepareToPlay()
            }

            audioPlayer?.play()
            print("✅ Фоновый процесс телеметрии NetPulse активирован (Dynamic Island будет обновляться непрерывно)")
        } catch {
            print("⚠️ Ошибка запуска фонового аудио-удержания: \(error.localizedDescription)")
        }
    }

    /// Остановка фонового удержания
    public func stopKeepAlive() {
        guard isRunning else { return }
        isRunning = false

        audioPlayer?.stop()
        audioPlayer = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Игнорируем ошибку деактивации
        }
        print("🛑 Фоновый процесс телеметрии NetPulse остановлен")
    }

    // MARK: - Обработка системных прерываний аудиосессии

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
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard isRunning,
              let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        if type == .ended {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                if audioPlayer?.isPlaying == false {
                    audioPlayer?.play()
                }
                print("🔄 Фоновое аудио-удержание возобновлено после системного прерывания")
            } catch {
                print("⚠️ Не удалось возобновить фоновую сессию: \(error.localizedDescription)")
            }
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        if isRunning, audioPlayer?.isPlaying == false {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                audioPlayer?.play()
            } catch {
                // Игнорируем
            }
        }
    }

    /// Генерация 0.1-секундного беззвучного WAV-файла в памяти
    private func generateSilentWavData() -> Data {
        let sampleRate: Int32 = 8000
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let numSamples: Int32 = 800 // 0.1 сек при 8kHz
        let dataSize = numSamples * Int32(numChannels) * Int32(bitsPerSample / 8)
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
        var channels = numChannels
        data.append(Data(bytes: &channels, count: 2))
        var rate = sampleRate
        data.append(Data(bytes: &rate, count: 4))
        var byteRate = sampleRate * Int32(numChannels) * Int32(bitsPerSample / 8)
        data.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = Int16(numChannels * (bitsPerSample / 8))
        data.append(Data(bytes: &blockAlign, count: 2))
        var bps = bitsPerSample
        data.append(Data(bytes: &bps, count: 2))

        // data subchunk
        data.append(contentsOf: "data".utf8)
        var subchunk2Size = dataSize
        data.append(Data(bytes: &subchunk2Size, count: 4))

        // Тишина (нули)
        data.append(Data(repeating: 0, count: Int(dataSize)))

        return data
    }
}

