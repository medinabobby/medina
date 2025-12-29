//
// RealtimeVoiceManager.swift
// Medina
//
// v86.0: OpenAI Realtime API integration for unified voice chat
// Uses swift-realtime-openai SDK for WebRTC voice sessions
// Created: December 5, 2025
//

import Foundation
import AVFoundation

#if canImport(SwiftRealtimeOpenAI)
import SwiftRealtimeOpenAI
#endif

/// Manages OpenAI Realtime API voice sessions for chat
///
/// **Features:**
/// - WebRTC connection for low-latency bidirectional voice
/// - Automatic microphone recording and audio playback
/// - Real-time transcription streaming
/// - Tool/function call support
///
/// **Usage:**
/// ```swift
/// let manager = RealtimeVoiceManager()
/// try await manager.startSession(instructions: systemPrompt)
/// // Manager handles audio automatically
/// // Listen to published properties for UI updates
/// manager.endSession()
/// ```
@MainActor
class RealtimeVoiceManager: ObservableObject {

    // MARK: - Constants

    private static let component = "RealtimeVoiceManager"

    // MARK: - Published State

    /// Whether a voice session is currently active
    @Published var isSessionActive = false

    /// Whether the user is currently speaking (voice activity detected)
    @Published var isUserSpeaking = false

    /// Whether the AI is currently speaking
    @Published var isAISpeaking = false

    /// Current user transcript (updated in real-time as user speaks)
    @Published var userTranscript = ""

    /// Current AI transcript (updated in real-time as AI responds)
    @Published var aiTranscript = ""

    /// Error message if something goes wrong
    @Published var errorMessage: String?

    // MARK: - Callbacks

    /// Called when a tool call is received from the AI
    /// Parameters: (toolName, arguments as JSON string, callId)
    /// Returns: Tool result string
    var onToolCall: ((String, String, String) async -> String)?

    /// Called when user transcript is finalized (for adding to chat)
    var onUserTranscriptFinalized: ((String) -> Void)?

    /// Called when AI transcript is finalized (for adding to chat)
    var onAITranscriptFinalized: ((String) -> Void)?

    // MARK: - Private Properties

    #if canImport(SwiftRealtimeOpenAI)
    private var conversation: Conversation?
    #endif

    private var sessionInstructions: String = ""
    private var eventTask: Task<Void, Never>?

    // MARK: - Session Management

    /// Start a new voice session with the given system prompt
    /// - Parameter instructions: System prompt/instructions for the AI
    func startSession(instructions: String) async throws {
        guard !isSessionActive else {
            Logger.log(.warning, component: Self.component, message: "Session already active")
            return
        }

        Logger.log(.info, component: Self.component, message: "Starting voice session...")

        sessionInstructions = instructions
        errorMessage = nil
        userTranscript = ""
        aiTranscript = ""

        #if canImport(SwiftRealtimeOpenAI)
        do {
            // Get API key for connection
            let apiKey = Config.openAIKey

            // Create and connect conversation
            conversation = Conversation(authToken: apiKey)

            try await conversation?.connect()

            // Configure session with instructions and enable transcription
            try await conversation?.configureSession { session in
                session.instructions = instructions
                session.voice = .alloy
                session.inputAudioTranscription = .init(model: "whisper-1")
            }

            isSessionActive = true
            Logger.log(.info, component: Self.component, message: "Voice session started")

            // Start processing events
            eventTask = Task { await processEvents() }

        } catch {
            Logger.log(.error, component: Self.component, message: "Failed to start session: \(error)")
            errorMessage = error.localizedDescription
            throw error
        }
        #else
        // Package not installed - show helpful message
        isSessionActive = true
        errorMessage = "Voice package not installed. Add swift-realtime-openai via SPM."
        Logger.log(.warning, component: Self.component, message: "SwiftRealtimeOpenAI package not available")
        #endif
    }

    /// End the current voice session
    func endSession() {
        guard isSessionActive else { return }

        Logger.log(.info, component: Self.component, message: "Ending voice session...")

        // Cancel event processing
        eventTask?.cancel()
        eventTask = nil

        #if canImport(SwiftRealtimeOpenAI)
        conversation?.disconnect()
        conversation = nil
        #endif

        // Finalize any pending transcripts
        if !userTranscript.isEmpty {
            onUserTranscriptFinalized?(userTranscript)
        }
        if !aiTranscript.isEmpty {
            onAITranscriptFinalized?(aiTranscript)
        }

        isSessionActive = false
        isUserSpeaking = false
        isAISpeaking = false
        userTranscript = ""
        aiTranscript = ""
        errorMessage = nil

        Logger.log(.info, component: Self.component, message: "Voice session ended")
    }

    // MARK: - Event Processing

    /// Process events from the Realtime API
    private func processEvents() async {
        #if canImport(SwiftRealtimeOpenAI)
        guard let conversation = conversation else { return }

        do {
            for try await event in conversation.events {
                // Check for cancellation
                if Task.isCancelled { break }

                await handleEvent(event)
            }
        } catch {
            if !Task.isCancelled {
                Logger.log(.error, component: Self.component, message: "Event stream error: \(error)")
                errorMessage = error.localizedDescription
            }
        }
        #endif
    }

    #if canImport(SwiftRealtimeOpenAI)
    /// Handle a single event from the Realtime API
    private func handleEvent(_ event: ServerEvent) async {
        switch event {
        case .inputAudioBufferSpeechStarted:
            isUserSpeaking = true
            Logger.log(.debug, component: Self.component, message: "User started speaking")

        case .inputAudioBufferSpeechStopped:
            isUserSpeaking = false
            Logger.log(.debug, component: Self.component, message: "User stopped speaking")

        case .conversationItemInputAudioTranscriptionCompleted(let item):
            if let transcript = item.transcript {
                userTranscript = transcript
                onUserTranscriptFinalized?(transcript)
                Logger.log(.debug, component: Self.component, message: "User transcript: \(transcript.prefix(50))...")
            }

        case .responseAudioTranscriptDelta(let delta):
            aiTranscript += delta.delta
            isAISpeaking = true

        case .responseAudioTranscriptDone(let done):
            aiTranscript = done.transcript
            onAITranscriptFinalized?(done.transcript)
            Logger.log(.debug, component: Self.component, message: "AI transcript: \(done.transcript.prefix(50))...")

        case .responseAudioDone:
            isAISpeaking = false

        case .responseFunctionCallArgumentsDone(let functionCall):
            await handleToolCall(
                callId: functionCall.callId,
                name: functionCall.name,
                arguments: functionCall.arguments
            )

        case .error(let error):
            errorMessage = error.message
            Logger.log(.error, component: Self.component, message: "API error: \(error.message)")

        default:
            break
        }
    }
    #endif

    /// Handle a tool call from the AI
    private func handleToolCall(callId: String, name: String, arguments: String) async {
        Logger.log(.info, component: Self.component, message: "Tool call: \(name)")

        guard let onToolCall = onToolCall else {
            Logger.log(.warning, component: Self.component, message: "No tool handler registered")
            return
        }

        // Execute tool and get result
        let result = await onToolCall(name, arguments, callId)

        #if canImport(SwiftRealtimeOpenAI)
        // Send result back to API
        do {
            try await conversation?.sendToolResponse(callId: callId, result: result)
            Logger.log(.info, component: Self.component, message: "Tool result sent: \(result.prefix(50))...")
        } catch {
            Logger.log(.error, component: Self.component, message: "Failed to send tool result: \(error)")
        }
        #endif
    }
}
