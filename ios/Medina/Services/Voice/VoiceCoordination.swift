//
// VoiceCoordination.swift
// Medina
//
// v231: Consolidated voice coordination services
// - VoiceSequencer: Awaitable playback with UI sync
// - VoiceAnnouncementService: AI-generated workout announcements
// - RealtimeVoiceManager: WebRTC voice sessions
//

import Foundation
import AVFoundation

#if canImport(SwiftRealtimeOpenAI)
import SwiftRealtimeOpenAI
#endif

// MARK: - VoiceSequencer

/// Coordinates voice playback with visual transitions during workouts
///
/// **Problem Solved:**
/// Previously, voice announcements fired asynchronously (fire-and-forget),
/// causing audio to overlap with wrong screens (e.g., workout intro playing
/// over exercise screen, rest announcements after leaving rest screen).
///
/// **Solution:**
/// VoiceSequencer provides await-able voice playback that integrates with
/// screen transitions, ensuring audio/visual sync.
///
/// **Usage:**
/// ```swift
/// // Before transition
/// await VoiceSequencer.shared.announceAndWait(
///     trigger: .exerciseStart,
///     context: context,
///     userId: userId
/// )
/// // Now safe to transition screen
/// coordinator.advanceToExercise(nextExercise)
/// ```
@MainActor
final class VoiceSequencer: ObservableObject {

    static let shared = VoiceSequencer()

    // MARK: - Dependencies

    private let voiceService: VoiceService
    private let announcementService: VoiceAnnouncementService

    // MARK: - State

    /// Track if an announcement is currently in progress
    @Published private(set) var isAnnouncing = false

    // MARK: - Initialization

    init(
        voiceService: VoiceService? = nil,
        announcementService: VoiceAnnouncementService? = nil
    ) {
        self.voiceService = voiceService ?? VoiceService()
        self.announcementService = announcementService ?? VoiceAnnouncementService()
    }

    // MARK: - Public API

    /// Generate and speak an announcement, waiting for completion
    ///
    /// This is the primary method for sequenced voice playback.
    /// The caller should await this method before transitioning screens.
    ///
    /// - Parameters:
    ///   - trigger: The workout event triggering the announcement
    ///   - context: Current workout/exercise context
    ///   - userId: User ID for voice settings check
    ///   - voiceGender: Preferred voice gender
    /// - Returns: True if announcement was played, false if voice is disabled
    // v182: Removed trainingStyle parameter - using default Medina voice per gender
    func announceAndWait(
        trigger: VoiceAnnouncementService.VoiceTrigger,
        context: VoiceAnnouncementService.WorkoutVoiceContext,
        userId: String,
        voiceGender: VoiceGender = .female
    ) async -> Bool {
        // Check if voice is enabled
        guard let user = LocalDataStore.shared.users[userId],
              let voiceSettings = user.memberProfile?.voiceSettings,
              voiceSettings.isEnabled else {
            Logger.log(.debug, component: "VoiceSequencer", message: "Voice disabled, skipping \(trigger.rawValue)")
            return false
        }

        do {
            // Generate announcement text
            let text = try await announcementService.generateAnnouncement(
                trigger: trigger,
                context: context
            )

            // v182: Simplified voice selection - just use gender
            let voice = voiceId(for: voiceGender)

            // Speak and wait for completion
            try await voiceService.speak(text, userId: userId, voice: voice)

            Logger.log(.info, component: "VoiceSequencer",
                      message: "Completed \(trigger.rawValue) announcement")
            return true

        } catch {
            Logger.log(.error, component: "VoiceSequencer",
                      message: "Failed \(trigger.rawValue): \(error.localizedDescription)")
            return false
        }
    }

    /// Speak pre-generated text without GPT call (for canned messages)
    ///
    /// Use this for latency-sensitive announcements where the text is known
    /// in advance (e.g., countdown, simple confirmations).
    ///
    /// - Parameters:
    ///   - text: Text to speak
    ///   - userId: User ID for voice settings check
    ///   - voiceGender: Preferred voice gender
    // v182: Removed trainingStyle parameter
    func speakCanned(
        _ text: String,
        userId: String,
        voiceGender: VoiceGender = .female
    ) async -> Bool {
        guard let user = LocalDataStore.shared.users[userId],
              let voiceSettings = user.memberProfile?.voiceSettings,
              voiceSettings.isEnabled else {
            return false
        }

        do {
            let voice = voiceId(for: voiceGender)
            try await voiceService.speak(text, userId: userId, voice: voice)
            return true
        } catch {
            Logger.log(.error, component: "VoiceSequencer",
                      message: "Canned speech failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Fire-and-forget announcement (for non-blocking cases)
    ///
    /// Use sparingly - only when screen timing is not critical.
    /// Prefer `announceAndWait` for proper sequencing.
    // v182: Removed trainingStyle parameter
    func announceAsync(
        trigger: VoiceAnnouncementService.VoiceTrigger,
        context: VoiceAnnouncementService.WorkoutVoiceContext,
        userId: String,
        voiceGender: VoiceGender = .female
    ) {
        Task {
            await announceAndWait(
                trigger: trigger,
                context: context,
                userId: userId,
                voiceGender: voiceGender
            )
        }
    }

    // MARK: - Voice Selection

    /// v182: Simplified voice selection - just use gender for default Medina voice
    /// - **onyx**: Deep, confident (male)
    /// - **nova**: Natural, versatile (female)
    func voiceId(for gender: VoiceGender) -> VoiceService.Voice {
        switch gender {
        case .male: return .onyx
        case .female: return .nova
        }
    }
}

// MARK: - VoiceAnnouncementService

/// Service for generating AI-powered workout voice announcements
///
/// **Architecture:**
/// - GPT-4o-mini generates natural, personality-driven announcements
/// - v182: Default Medina personality (balanced, encouraging coach)
/// - Voice Settings control what information to include (RPE, rest, tempo, etc.)
/// - Performance data provides context (target vs actual, volume progress)
///
/// **Usage:**
/// ```swift
/// let service = VoiceAnnouncementService()
/// let text = try await service.generateAnnouncement(
///     trigger: .exerciseStart,
///     context: WorkoutVoiceContext(...)
/// )
/// voiceService.speak(text, userId: userId)
/// ```
@MainActor
class VoiceAnnouncementService {

    // MARK: - Types

    /// Voice trigger points during workout
    enum VoiceTrigger: String {
        case workoutStart = "workout_start"
        case exerciseStart = "exercise_start"
        case setComplete = "set_complete"
        case restStart = "rest_start"
        case exerciseComplete = "exercise_complete"
        case workoutComplete = "workout_complete"

        /// v97: Enhanced prompt descriptions for human-like voice
        var promptDescription: String {
            switch self {
            case .workoutStart:
                // v97: Improved for warm, natural intro
                // v182: Single Medina personality (balanced, encouraging)
                return """
                Generate a warm, motivating workout intro. Include:
                - Friendly greeting
                - Workout name in natural speech (say "December tenth" not "Dec 10")
                - Exercise count
                - Brief encouragement

                Keep under 15 words. Sound like a real coach, not a robot.

                Example: "Hey! Ready for legs day? 2 exercises, let's do this!"
                """
            case .exerciseStart:
                return "The user is about to start a new exercise. Announce it and give guidance."
            case .setComplete:
                return "The user just finished a set. Acknowledge it and preview the next set or rest."
            case .restStart:
                return "The user is taking a rest period. Tell them the duration and what's next."
            case .exerciseComplete:
                return "The user completed all sets of an exercise. Acknowledge and transition to next."
            case .workoutComplete:
                // v97: Improved for celebratory, personalized outro
                // v182: Single Medina personality
                return """
                Generate a brief, celebratory workout completion message. Include:
                - Acknowledgment of completion
                - Duration in natural speech
                - Brief encouragement

                Keep under 12 words. Sound genuine, not robotic.

                Example: "Amazing work! 45 minutes done. You crushed it!"
                """
            }
        }
    }

    /// Context for generating announcements
    struct WorkoutVoiceContext {
        // User preferences
        // v182: trainingStyle removed - using default Medina coaching personality
        let voiceSettings: VoiceSettings

        // Current state
        let workoutName: String
        let splitDay: SplitDay?
        let totalExercises: Int
        let currentExerciseNumber: Int?
        let exerciseName: String?
        let setNumber: Int?
        let totalSets: Int?

        // Performance data
        let targetWeight: Double?
        let actualWeight: Double?
        let targetReps: Int?
        let actualReps: Int?
        let targetRPE: Double?
        let actualRPE: Double?
        let oneRMPercentage: Double?  // e.g., 0.75 for 75%
        let volumeProgress: Double?   // 0.0 to 1.0

        // v95.0: Tempo (e.g., "3-1-1")
        let tempo: String?

        // Timing
        let restDuration: Int?
        let workoutDuration: TimeInterval?
    }

    // MARK: - Initialization

    /// v215: No longer needs API key (uses Firebase endpoint)
    init() {}

    // MARK: - Public API

    /// Generate an announcement using GPT-4o-mini
    /// - Parameters:
    ///   - trigger: The workout event triggering the announcement
    ///   - context: Current workout/exercise context
    /// - Returns: Generated announcement text for TTS
    // v182: Default Medina coaching personality (balanced, professional)
    private static let defaultVoicePersonality = """
        You are Medina, a balanced fitness coach. Speak naturally and conversationally.
        Mix motivation with practical guidance. Be encouraging but not over-the-top.
        Keep announcements brief (1-2 sentences max). Sound like a knowledgeable friend.
        """

    func generateAnnouncement(
        trigger: VoiceTrigger,
        context: WorkoutVoiceContext
    ) async throws -> String {
        let prompt = buildPrompt(trigger: trigger, context: context)
        let response = try await callGPT(systemPrompt: Self.defaultVoicePersonality, userPrompt: prompt)
        return response
    }

    // MARK: - Private Helpers

    private func buildPrompt(trigger: VoiceTrigger, context: WorkoutVoiceContext) -> String {
        var lines: [String] = []

        lines.append("Generate a brief spoken announcement (1-2 sentences max) for: \(trigger.promptDescription)")
        lines.append("")

        // Workout context
        lines.append("Workout: \(context.workoutName)")
        if let splitDay = context.splitDay {
            lines.append("Type: \(splitDay.displayName)")
        }

        // Exercise context (based on voice settings)
        if let exercise = context.exerciseName {
            lines.append("Exercise: \(exercise)")
        }

        if context.voiceSettings.announceSets, let set = context.setNumber, let total = context.totalSets {
            lines.append("Set: \(set) of \(total)")
        }

        if context.voiceSettings.announceReps, let reps = context.targetReps {
            lines.append("Target reps: \(reps)")
        }

        if context.voiceSettings.announceWeights, let weight = context.targetWeight {
            lines.append("Weight: \(Int(weight)) lbs")
        }

        if context.voiceSettings.announceRPE, let rpe = context.targetRPE {
            lines.append("Target RPE: \(Int(rpe))")
        }

        // v95.0: Tempo announcement (only if enabled in settings)
        if context.voiceSettings.announceTempo, let tempo = context.tempo, tempo != "X" && tempo != "0" {
            lines.append("Tempo: \(tempo)")
        }

        // 1RM percentage (always useful context)
        if let pct = context.oneRMPercentage {
            lines.append("1RM %: \(Int(pct * 100))%")
        }

        // Performance data (for post-set announcements)
        if let actual = context.actualReps, let target = context.targetReps {
            if actual >= target {
                lines.append("Result: Hit target (\(actual) reps)")
            } else {
                lines.append("Result: \(actual) of \(target) reps")
            }
        }

        if let progress = context.volumeProgress {
            lines.append("Session progress: \(Int(progress * 100))%")
        }

        // Rest duration
        if context.voiceSettings.announceRestTime, let rest = context.restDuration {
            lines.append("Rest: \(rest) seconds")
        }

        // Workout duration (for completion)
        if let duration = context.workoutDuration {
            let minutes = Int(duration / 60)
            lines.append("Workout duration: \(minutes) minutes")
        }

        lines.append("")
        lines.append("IMPORTANT: Keep it natural and conversational. Avoid robotic phrasing like 'Set 2 at 135 pounds for 8 reps'. Say it like a coach would actually speak.")

        return lines.joined(separator: "\n")
    }

    /// v215: Now uses Firebase /api/chatSimple endpoint (API key on server)
    private func callGPT(systemPrompt: String, userPrompt: String) async throws -> String {
        // Build messages for chat completion
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]

        // Call Firebase chatSimple endpoint
        let response = try await FirebaseAPIClient.shared.chatSimple(
            messages: messages,
            model: "gpt-4o-mini",
            temperature: 0.7  // Some creativity for natural variation
        )

        let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.log(.info, component: "VoiceAnnouncementService", message: "Generated: \(trimmed.prefix(50))...")

        return trimmed
    }
}

// MARK: - RealtimeVoiceManager

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
