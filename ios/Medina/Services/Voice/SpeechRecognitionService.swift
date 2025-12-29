//
// SpeechRecognitionService.swift
// Medina
//
// v74.8: Speech-to-text service using Apple's Speech framework
// Provides voice dictation for chat input
// Created: December 2, 2025
//

import Foundation
import Speech
import AVFoundation

/// Service for converting speech to text
@MainActor
class SpeechRecognitionService: ObservableObject {

    // MARK: - Published State

    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var errorMessage: String?
    @Published var isAuthorized = false
    @Published var canRequestAuthorization = true  // v89: True until explicitly denied

    // MARK: - Private Properties

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: - Initialization

    init() {
        // v82.5: Don't request authorization on init - defer until microphone tapped
        // Check current status without prompting
        updateAuthorizationStatus()
    }

    // MARK: - Authorization

    /// Update authorization status without prompting (non-blocking check)
    /// v89: Also updates canRequestAuthorization for proper button state
    private func updateAuthorizationStatus() {
        let status = SFSpeechRecognizer.authorizationStatus()
        isAuthorized = (status == .authorized)
        // Can request if authorized OR not yet determined (will prompt on tap)
        canRequestAuthorization = (status == .authorized || status == .notDetermined)
    }

    /// Request speech recognition authorization (only when needed)
    /// Returns true if authorized, false otherwise
    private func requestAuthorizationIfNeeded() async -> Bool {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()

        switch currentStatus {
        case .authorized:
            isAuthorized = true
            return true

        case .notDetermined:
            // Request authorization - this will show the prompt
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { [weak self] status in
                    Task { @MainActor in
                        let authorized = (status == .authorized)
                        self?.isAuthorized = authorized
                        if authorized {
                            Logger.log(.info, component: "SpeechRecognitionService", message: "✅ Speech recognition authorized")
                        } else {
                            self?.errorMessage = "Speech recognition access denied. Enable in Settings."
                            Logger.log(.warning, component: "SpeechRecognitionService", message: "⚠️ Speech recognition denied")
                        }
                        continuation.resume(returning: authorized)
                    }
                }
            }

        case .denied:
            isAuthorized = false
            canRequestAuthorization = false  // v89: Disable button when denied
            errorMessage = "Speech recognition access denied. Enable in Settings."
            Logger.log(.warning, component: "SpeechRecognitionService", message: "⚠️ Speech recognition denied")
            return false

        case .restricted:
            isAuthorized = false
            canRequestAuthorization = false  // v89: Disable button when restricted
            errorMessage = "Speech recognition is restricted on this device."
            Logger.log(.warning, component: "SpeechRecognitionService", message: "⚠️ Speech recognition restricted")
            return false

        @unknown default:
            isAuthorized = false
            canRequestAuthorization = false
            return false
        }
    }

    // MARK: - Recording Control

    /// Start recording and transcribing speech
    /// v82.5: Now requests authorization on first use instead of on init
    func startRecording() {
        Task {
            await startRecordingAsync()
        }
    }

    /// Async implementation of startRecording
    private func startRecordingAsync() async {
        // v82.5: Request authorization on first microphone tap
        let authorized = await requestAuthorizationIfNeeded()
        guard authorized else {
            return // Error message already set by requestAuthorizationIfNeeded
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition not available"
            return
        }

        // Cancel any ongoing task
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Failed to configure audio session"
            Logger.log(.error, component: "SpeechRecognitionService", message: "❌ Audio session error: \(error)")
            return
        }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "Failed to create recognition request"
            return
        }

        recognitionRequest.shouldReportPartialResults = true

        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                if let result = result {
                    self?.transcribedText = result.bestTranscription.formattedString
                }

                if error != nil || (result?.isFinal ?? false) {
                    self?.stopRecordingInternal()
                }
            }
        }

        // Start audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            transcribedText = ""
            errorMessage = nil
            Logger.log(.info, component: "SpeechRecognitionService", message: "🎤 Recording started")
        } catch {
            errorMessage = "Failed to start audio engine"
            Logger.log(.error, component: "SpeechRecognitionService", message: "❌ Audio engine error: \(error)")
            stopRecordingInternal()
        }
    }

    /// Stop recording and finalize transcription
    func stopRecording() {
        guard isRecording else { return }

        // End the audio request to get final transcription
        recognitionRequest?.endAudio()

        // Small delay to allow final transcription to complete
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            await MainActor.run {
                stopRecordingInternal()
            }
        }
    }

    /// Internal cleanup when stopping
    private func stopRecordingInternal() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        isRecording = false
        Logger.log(.info, component: "SpeechRecognitionService", message: "🎤 Recording stopped, text: \(transcribedText.prefix(50))...")
    }

    /// Toggle recording state
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    /// Clear transcribed text
    func clearTranscription() {
        transcribedText = ""
    }
}
