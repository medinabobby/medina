//
// VoiceModeManager.swift
// Medina
//
// v106.3: Unified voice chat mode (STT → GPT → TTS loop)
// v215: Migrated TTS to Firebase /api/tts endpoint (API key on server)
// Simpler alternative to Realtime API for beta
// Created: December 10, 2025
//

import Foundation
import AVFoundation

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
