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

/// Контейнер для передачи запроса распознавания в обработчик аудиобуферов, который вызывается с аудиопотока
private final class RecognitionRequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }
}

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
    private var isStarting: Bool = false

    private init() {
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
    }

    // MARK: - Разрешения

    /// Потокобезопасный запрос прав у TCC без привязки closure к @MainActor
    private nonisolated static func requestSpeechAuth() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                continuation.resume(returning: authStatus)
            }
        }
    }

    /// Запрос доступа к микрофону. Раньше он не запрашивался явно: без доступа формат входа получался невалидным,
    /// и установка обработчика буферов аварийно завершала приложение.
    private nonisolated static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Проверка обоих разрешений: распознавание речи и микрофон
    private func ensurePermissions() async -> Bool {
        let speechStatus = await Self.requestSpeechAuth()
        switch speechStatus {
        case .authorized:
            isAuthorized = true
        case .denied:
            isAuthorized = false
            errorMessage = "Доступ к распознаванию речи отклонён в Настройках iOS."
            return false
        case .restricted:
            isAuthorized = false
            errorMessage = "Распознавание речи ограничено на этом устройстве."
            return false
        case .notDetermined:
            isAuthorized = false
            errorMessage = "Требуется разрешение на распознавание речи."
            return false
        @unknown default:
            isAuthorized = false
            return false
        }

        guard await Self.requestMicrophoneAccess() else {
            errorMessage = "Доступ к микрофону отклонён. Разрешите его в Настройках iOS: Конфиденциальность → Микрофон."
            return false
        }

        errorMessage = nil
        return true
    }

    /// Запрос разрешений на доступ к микрофону и распознаванию речи
    public func requestAuthorization() {
        Task { @MainActor in
            _ = await self.ensurePermissions()
        }
    }

    // MARK: - Запись

    /// Запуск сессии записи и живой транскрипции
    public func startRecording(onResult: @escaping @Sendable (String) -> Void) {
        guard !isRecording, !isStarting else { return }
        isStarting = true

        Task { @MainActor in
            defer { self.isStarting = false }
            guard await self.ensurePermissions() else { return }
            self.beginRecordingSession(onResult: onResult)
        }
    }

    private func beginRecordingSession(onResult: @escaping @Sendable (String) -> Void) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            errorMessage = "Распознавание речи сейчас недоступно: проверьте подключение к интернету."
            return
        }

        // Остатки предыдущей сессии (в том числе неудачного запуска) сбрасываются независимо от флага isRecording
        teardownSession()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Не удалось настроить аудиосессию микрофона."
            return
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Если микрофон недоступен, частота дискретизации или число каналов равны 0. installTap с таким форматом
        // вызывает исключение Objective-C, которое нельзя перехватить через do/catch, — приложение упало бы.
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            errorMessage = "Микрофон недоступен: проверьте разрешение в Настройках iOS и что его не занимает другое приложение."
            deactivateAudioSession()
            return
        }

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        newRequest.addsPunctuation = true
        recognitionRequest = newRequest

        // Обработчики создаются в nonisolated-функциях: их вызывают потоки аудио и Speech, а замыкание, созданное
        // в методе класса @MainActor, при вызове не из главного потока завершило бы приложение в Swift 6
        inputNode.removeTap(onBus: 0)
        let tapHandler = Self.makeTapHandler(box: RecognitionRequestBox(newRequest)) { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
            }
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat, block: tapHandler)

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Не удалось запустить аудиодвижок: \(error.localizedDescription)"
            teardownSession()
            return
        }

        transcribedText = ""
        errorMessage = nil
        isRecording = true
        HapticManager.shared.impactLight()

        let resultHandler = Self.makeResultHandler { [weak self] text, isFinal, hasError in
            Task { @MainActor in
                guard let self else { return }
                if let text {
                    self.transcribedText = text
                    onResult(text)
                }
                if hasError || isFinal {
                    self.stopRecording()
                }
            }
        }
        recognitionTask = recognizer.recognitionTask(with: newRequest, resultHandler: resultHandler)
    }

    /// Остановка записи
    public func stopRecording() {
        guard isRecording else { return }
        teardownSession()
        isRecording = false
        audioLevel = 0.0
        HapticManager.shared.impactLight()
    }

    // MARK: - Вспомогательные методы

    private func teardownSession() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        deactivateAudioSession()
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Обработчик аудиобуферов: передаёт буфер распознавателю и вычисляет уровень громкости для анимации
    private nonisolated static func makeTapHandler(
        box: RecognitionRequestBox,
        onLevel: @escaping @Sendable (Float) -> Void
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        return { buffer, _ in
            box.request.append(buffer)
            onLevel(SpeechRecognizerManager.audioLevel(of: buffer))
        }
    }

    /// Обработчик результатов распознавания: текст (если есть), признак финального результата и признак ошибки
    private nonisolated static func makeResultHandler(
        onUpdate: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        return { result, error in
            onUpdate(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    /// Уровень громкости 0...1 по среднеквадратичному значению буфера (раньше бралась только первая выборка)
    private nonisolated static func audioLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard buffer.frameLength > 0, let channelData = buffer.floatChannelData else { return 0 }
        let samples = UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength))
        var sumOfSquares: Float = 0
        for sample in samples {
            sumOfSquares += sample * sample
        }
        let rms = (sumOfSquares / Float(samples.count)).squareRoot()
        return max(0, min(1, rms * 8))
    }
}
