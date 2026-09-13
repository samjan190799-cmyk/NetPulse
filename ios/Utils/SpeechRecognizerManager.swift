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

    /// Потокобезопасный запрос прав у TCC без привязки closure к @MainActor
    private nonisolated static func requestSpeechAuth() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                continuation.resume(returning: authStatus)
            }
        }
    }

    /// Запрос разрешений на доступ к микрофону и распознаванию речи
    public func requestAuthorization() {
        Task { @MainActor in
            let authStatus = await Self.requestSpeechAuth()
            switch authStatus {
            case .authorized:
                self.isAuthorized = true
                self.errorMessage = nil
            case .denied:
                self.isAuthorized = false
                self.errorMessage = "Доступ к распознаванию речи отклонен в Настройках iOS."
            case .restricted:
                self.isAuthorized = false
                self.errorMessage = "Распознавание речи ограничено на этом устройстве."
            case .notDetermined:
                self.isAuthorized = false
            @unknown default:
                self.isAuthorized = false
            }
        }
    }

    /// Запуск сессии записи и живой транскрипции
    public func startRecording(onResult: @escaping @Sendable (String) -> Void) {
        guard !isRecording else { return }

        if !isAuthorized {
            Task { @MainActor in
                let authStatus = await Self.requestSpeechAuth()
                if authStatus == .authorized {
                    self.isAuthorized = true
                    self.errorMessage = nil
                    self.beginRecordingSession(onResult: onResult)
                } else {
                    self.isAuthorized = false
                    self.errorMessage = "Требуется разрешение на распознавание речи в Настройках iOS."
                }
            }
            return
        }

        beginRecordingSession(onResult: onResult)
    }

    private func beginRecordingSession(onResult: @escaping @Sendable (String) -> Void) {
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

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        self.recognitionRequest = newRequest

        newRequest.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            newRequest.addsPunctuation = true
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Предотвращаем NSException 'required condition is false: [self canInstallTapOnBus:bus]'
        inputNode.removeTap(onBus: 0)

        let safeReq = newRequest
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            safeReq.append(buffer)

            // Расчет уровня громкости для анимации звуковой волны (с защитой от разыменования пустых буферов)
            if buffer.frameLength > 0, let channelData = buffer.floatChannelData {
                let channelDataValue = channelData.pointee[0]
                let level = max(0.0, min(1.0, abs(channelDataValue) * 8.0))

                Task { @MainActor [weak self] in
                    self?.audioLevel = level
                }
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

        recognitionTask = speechRecognizer?.recognitionTask(with: newRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.transcribedText = text
                    onResult(text)
                }

                if error != nil || (result?.isFinal ?? false) {
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
        BackgroundTelemetryKeeper.shared.startKeepAlive()
        HapticManager.shared.impactLight()
    }
}
