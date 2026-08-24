//
//  SpeechRecognizerManager.swift
//  NetPulse
//
//  Created for iOS (Swift 6.0+ / SwiftUI / Speech) - 2026.
//

import Foundation
import SwiftUI
import Speech
import AVFoundation
import Observation

/// Менеджер распознавания речи Apple Speech-to-Text для голосового ввода запросов в NetPulse AI.
@Observable
@MainActor
public final class SpeechRecognizerManager {
    public static let shared = SpeechRecognizerManager()

    public var isRecording: Bool = false
    public var transcribedText: String = ""
    public var errorMessage: String? = nil
    public var isAuthorized: Bool = false
    public var audioLevel: Float = 0.0

    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private init() {
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
    }

    /// Запрос разрешений на доступ к микрофону и распознаванию речи
    public func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task { @MainActor in
                switch authStatus {
                case .authorized:
                    self?.isAuthorized = true
                    self?.errorMessage = nil
                case .denied:
                    self?.isAuthorized = false
                    self?.errorMessage = "Доступ к распознаванию речи отклонен в Настройках iOS."
                case .restricted:
                    self?.isAuthorized = false
                    self?.errorMessage = "Распознавание речи ограничено на этом устройстве."
                case .notDetermined:
                    self?.isAuthorized = false
                @unknown default:
                    self?.isAuthorized = false
                }
            }
        }
    }

    /// Запуск сессии записи и живой транскрипции
    public func startRecording(onResult: @escaping (String) -> Void) {
        guard !isRecording else { return }

        // Сброс предыдущей задачи
        stopRecording()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.errorMessage = "Не удалось настроить аудиосессию микрофона."
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            self.errorMessage = "Ошибка инициализации буфера распознавания."
            return
        }

        recognitionRequest.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            recognitionRequest.addsPunctuation = true
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            // Расчет уровня громкости для анимации звуковой волны
            let channelData = buffer.floatChannelData?[0]
            let channelDataValue = channelData?[0] ?? 0.0
            let level = max(0.0, min(1.0, abs(channelDataValue) * 8.0))

            Task { @MainActor in
                self?.audioLevel = level
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            self.errorMessage = "Не удалось запустить аудиодвижок: \(error.localizedDescription)"
            return
        }

        self.transcribedText = ""
        self.isRecording = true
        HapticManager.shared.impactLight()

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.transcribedText = text
                    onResult(text)
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in
                    self.stopRecording()
                }
            }
        }
    }

    /// Остановка записи
    public func stopRecording() {
        guard isRecording else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        audioLevel = 0.0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        HapticManager.shared.impactLight()
    }
}
