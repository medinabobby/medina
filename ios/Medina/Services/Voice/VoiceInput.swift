//
// VoiceInput.swift
// Medina
//
// v231: Consolidated voice input services
// - SpeechRecognitionService: Apple Speech STT
// - VoiceModeManager: Interactive STT→GPT→TTS loop
//

import Foundation
import Speech
import AVFoundation

// MARK: - SpeechRecognitionService

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

// MARK: - VoiceModeManager

/// Manages unified voice chat mode
///
/// Flow:
/// 1. User taps voice button → enters voice mode
/// 2. User speaks → Apple Speech transcribes
/// 3. Text sent to GPT via ResponsesManager
/// 4. Response spoken via OpenAI TTS
/// 5. Loop continues until user taps to exit
///
/// Latency: ~2-3 seconds (vs ~500ms with Realtime API)
/// Cost: Similar to text chat + TTS (~$0.01-0.02 per exchange)
@MainActor
class VoiceModeManager: ObservableObject {

    // MARK: - Published State

    /// Whether voice mode is active
    @Published var isActive = false

    /// Current phase of voice interaction
    @Published var phase: VoicePhase = .idle

    /// Current transcript being built (user speech)
    @Published var currentTranscript = ""

    /// Error message if something fails
    @Published var errorMessage: String?

    /// Whether we're waiting for user to speak
    @Published var isListening = false

    /// Whether AI is currently speaking
    @Published var isSpeaking = false

    // MARK: - Voice Phases

    enum VoicePhase {
        case idle           // Not in voice mode
        case listening      // Waiting for user speech
        case processing     // Transcribing/sending to GPT
        case speaking       // AI is responding via TTS
    }

    // MARK: - Callbacks

    /// Called when user transcript is finalized (to add to chat UI)
    var onUserMessage: ((String) -> Void)?

    /// Called when AI response is received (to add to chat UI)
    var onAIResponse: ((String) -> Void)?

    /// Called to send message to GPT (returns response)
    var sendToGPT: ((String) async -> String?)?

    // MARK: - Private Properties

    private let speechService: SpeechRecognitionService
    private let voiceService: VoiceService
    private var userId: String = ""
    private var isProcessing = false

    // MARK: - Initialization

    init() {
        self.speechService = SpeechRecognitionService()
        self.voiceService = VoiceService()
    }

    // MARK: - Public Methods

    /// Start voice mode
    func startVoiceMode(userId: String) {
        guard !isActive else { return }

        self.userId = userId
        isActive = true
        errorMessage = nil
        currentTranscript = ""

        Logger.log(.info, component: "VoiceModeManager", message: "Voice mode started")

        // Start listening immediately
        startListening()
    }

    /// End voice mode
    func endVoiceMode() {
        guard isActive else { return }

        // Stop any ongoing operations
        speechService.stopRecording()
        voiceService.stopSpeaking()

        isActive = false
        phase = .idle
        isListening = false
        isSpeaking = false
        currentTranscript = ""

        Logger.log(.info, component: "VoiceModeManager", message: "Voice mode ended")
    }

    /// Interrupt AI speech and start listening
    func interrupt() {
        if isSpeaking {
            voiceService.stopSpeaking()
            isSpeaking = false
        }
        startListening()
    }

    // MARK: - Private Methods

    /// Start listening for user speech
    private func startListening() {
        guard isActive else { return }

        phase = .listening
        isListening = true
        currentTranscript = ""

        // Start speech recognition
        speechService.startRecording()

        // Monitor for transcript updates
        Task {
            // Wait for speech to complete
            var lastTranscript = ""
            var silenceCount = 0
            let maxSilence = 15 // ~1.5 seconds of no change = done speaking

            while isActive && isListening {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

                let newTranscript = speechService.transcribedText

                if newTranscript != lastTranscript {
                    currentTranscript = newTranscript
                    lastTranscript = newTranscript
                    silenceCount = 0
                } else if !newTranscript.isEmpty {
                    silenceCount += 1
                    if silenceCount >= maxSilence {
                        // User stopped speaking
                        break
                    }
                }

                // Check if recording stopped
                if !speechService.isRecording && !newTranscript.isEmpty {
                    break
                }
            }

            // Finalize if we have text
            if isActive && !currentTranscript.isEmpty {
                await finalizeUserSpeech()
            } else if isActive {
                // No speech detected, keep listening
                startListening()
            }
        }
    }

    /// Process finalized user speech
    private func finalizeUserSpeech() async {
        guard isActive && !currentTranscript.isEmpty else { return }
        guard !isProcessing else { return }

        isProcessing = true
        let userText = currentTranscript

        // Stop recording
        speechService.stopRecording()
        isListening = false
        phase = .processing

        Logger.log(.info, component: "VoiceModeManager", message: "User said: \(userText.prefix(50))...")

        // Notify UI to add user message
        onUserMessage?(userText)

        // Send to GPT
        guard let response = await sendToGPT?(userText) else {
            errorMessage = "Failed to get AI response"
            isProcessing = false
            if isActive { startListening() }
            return
        }

        // Notify UI to add AI response
        onAIResponse?(response)

        // Speak response
        phase = .speaking
        isSpeaking = true

        do {
            try await speakResponse(response)
        } catch {
            Logger.log(.error, component: "VoiceModeManager", message: "TTS failed: \(error)")
        }

        isSpeaking = false
        isProcessing = false

        // Continue listening if still active
        if isActive {
            startListening()
        }
    }

    /// Speak AI response with OpenAI TTS
    private func speakResponse(_ text: String) async throws {
        // Strip any markdown or special formatting
        let cleanText = stripMarkdown(text)

        // Use VoiceService for TTS (bypassing user check since we're in voice mode)
        try await speakDirect(cleanText)
    }

    /// v215: Now uses Firebase /api/tts endpoint (API key on server)
    /// Uses shimmer voice for chat (more conversational than nova)
    private func speakDirect(_ text: String) async throws {
        // Call Firebase TTS endpoint
        let audioData = try await FirebaseAPIClient.shared.tts(
            text: text,
            voice: "shimmer",
            speed: 1.05  // Slightly faster for conversation
        )

        // Play audio
        let player = try AVAudioPlayer(data: audioData)
        player.prepareToPlay()
        player.volume = 1.0
        player.play()

        // Wait for playback
        while player.isPlaying && isActive && isSpeaking {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Strip markdown formatting for cleaner TTS
    private func stripMarkdown(_ text: String) -> String {
        var result = text

        // Remove bold/italic
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        result = result.replacingOccurrences(of: "*", with: "")
        result = result.replacingOccurrences(of: "_", with: "")

        // Remove headers
        result = result.replacingOccurrences(of: "### ", with: "")
        result = result.replacingOccurrences(of: "## ", with: "")
        result = result.replacingOccurrences(of: "# ", with: "")

        // Remove bullet points
        result = result.replacingOccurrences(of: "- ", with: "")
        result = result.replacingOccurrences(of: "• ", with: "")

        // Remove links [text](url) → text
        let linkPattern = "\\[([^\\]]+)\\]\\([^\\)]+\\)"
        if let regex = try? NSRegularExpression(pattern: linkPattern) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1"
            )
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
