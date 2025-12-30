//
// VoiceOutput.swift
// Medina
//
// v231: Consolidated voice output services
// - VoiceService: Firebase TTS proxy
// - VoiceTemplateService: Fast template-based announcements
//

import Foundation
import AVFoundation

// MARK: - VoiceService

/// Service for text-to-speech voice guidance during workouts
///
/// Uses Firebase /api/tts endpoint which proxies to OpenAI TTS-1 API.
/// API key is stored securely on server - iOS never has access.
/// Recommended voice: nova (warm, energetic female voice for motivation)
///
/// Usage:
/// ```swift
/// let service = VoiceService()
/// try await service.speak("Starting your workout!", userId: user.id)
/// ```
@MainActor
class VoiceService: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    private let dataManager: LocalDataStore

    @Published var isSpeaking = false

    /// Available TTS voices
    enum Voice: String {
        case alloy, echo, fable, onyx, nova, shimmer
    }

    /// Initialize voice service
    /// - Parameter dataManager: Data manager for accessing user voice settings
    init(dataManager: LocalDataStore = .shared) {
        self.dataManager = dataManager

        // Configure audio session for playback on iOS devices
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
            Logger.log(.info, component: "VoiceService", message: "Audio session configured for playback")
        } catch {
            Logger.log(.error, component: "VoiceService", message: "Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    /// Legacy initializer for backwards compatibility (apiKey ignored)
    /// - Parameter apiKey: Ignored - API key now on server
    /// - Parameter dataManager: Data manager for accessing user voice settings
    @available(*, deprecated, message: "API key no longer needed - stored on server")
    convenience init(apiKey: String, dataManager: LocalDataStore = .shared) {
        self.init(dataManager: dataManager)
    }

    /// Speak text using Firebase TTS endpoint
    ///
    /// v47: Checks user's voice settings before speaking. If voice is disabled, returns silently.
    /// v215: Now uses Firebase /api/tts endpoint (API key on server)
    ///
    /// - Parameters:
    ///   - text: Text to speak (workout guidance, exercise instructions, etc.)
    ///   - userId: User ID to check voice settings for
    ///   - voice: Voice to use (default: .nova - warm, energetic)
    /// - Throws: Network errors, API errors, audio playback errors
    func speak(_ text: String, userId: String, voice: Voice = .nova) async throws {
        // v47: Check if user has voice enabled
        // If voiceSettings is nil OR isEnabled is false, skip speech
        guard let user = dataManager.users[userId],
              let voiceSettings = user.memberProfile?.voiceSettings,
              voiceSettings.isEnabled else {
            Logger.log(.debug, component: "VoiceService", message: "Voice disabled for user \(userId), skipping speech")
            return
        }

        isSpeaking = true
        defer { isSpeaking = false }

        Logger.log(.info, component: "VoiceService", message: "Speaking via Firebase: \(text.prefix(50))...")

        do {
            // v215: Call Firebase TTS endpoint instead of OpenAI directly
            let audioData = try await FirebaseAPIClient.shared.tts(
                text: text,
                voice: voice.rawValue,
                speed: 1.0
            )

            // Play audio
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = 1.0

            let success = audioPlayer?.play() ?? false
            if !success {
                Logger.log(.error, component: "VoiceService", message: "Audio playback failed to start")
                throw NSError(domain: "VoiceService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Audio playback failed"])
            }

            Logger.log(.info, component: "VoiceService", message: "Audio playback started (\(audioData.count) bytes)")

            // Wait for playback to complete
            while audioPlayer?.isPlaying == true {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            }

            Logger.log(.info, component: "VoiceService", message: "Audio playback completed")
        } catch {
            Logger.log(.error, component: "VoiceService", message: "TTS failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Stop current speech playback
    func stopSpeaking() {
        audioPlayer?.stop()
        isSpeaking = false
        Logger.log(.info, component: "VoiceService", message: "Speech stopped")
    }
}

// MARK: - VoiceTemplateService

/// Fast template-based announcements (no GPT, TTS only)
///
/// Used for instant voice feedback during workout execution.
/// v106.2: Uses simplified brief/normal toggle (maps to verbosity 1 or 3)
///
/// **Announcement Modes:**
/// - Brief (verbosity 1): Essential counts only ("Set 1. 5 at 150.")
/// - Normal (verbosity 3): Full detail ("Set 1. 5 reps at 150 pounds.")
enum VoiceTemplateService {

    // MARK: - v106.2 Convenience

    /// Convert brief toggle to verbosity level
    static func verbosity(fromBrief brief: Bool) -> Int {
        return brief ? 1 : 3
    }

    // MARK: - Set Announcements

    /// Generate set target announcement - what user needs to do
    ///
    /// Called before each set to tell user what weight to rack.
    /// - Parameters:
    ///   - setNumber: Current set (1-indexed)
    ///   - totalSets: Total sets for this exercise
    ///   - targetReps: Target rep count
    ///   - targetWeight: Target weight in user's preferred unit
    ///   - exerciseName: Optional exercise name (include for first set of exercise)
    ///   - verbosity: Detail level 1-5 (default 3)
    /// - Returns: Announcement string for TTS
    static func setTarget(
        setNumber: Int,
        totalSets: Int,
        targetReps: Int,
        targetWeight: Double,
        exerciseName: String? = nil,
        verbosity: Int = 3
    ) -> String {
        let weight = Int(targetWeight)

        switch verbosity {
        case 1:
            // Minimal: "Set 1. 5 at 150."
            return "Set \(setNumber). \(targetReps) at \(weight)."

        case 2:
            // Basic: "Set 1. 5 reps at 150."
            return "Set \(setNumber). \(targetReps) reps at \(weight)."

        case 3:
            // Moderate: "Set 1. 5 reps at 150 pounds."
            return "Set \(setNumber). \(targetReps) reps at \(weight) pounds."

        case 4:
            // Detailed: "Set 1 of 3. 5 reps at 150 pounds."
            return "Set \(setNumber) of \(totalSets). \(targetReps) reps at \(weight) pounds."

        default: // 5 (Verbose)
            // Full: "Bench Press. Set 1 of 3. 5 reps at 150 pounds."
            if let name = exerciseName {
                return "\(name). Set \(setNumber) of \(totalSets). \(targetReps) reps at \(weight) pounds."
            }
            return "Set \(setNumber) of \(totalSets). Target \(targetReps) reps at \(weight) pounds."
        }
    }

    /// Generate confirmation after logging a set
    ///
    /// Echoes back what was logged so user knows it worked, then previews next set.
    /// - Parameters:
    ///   - actualReps: Reps that were logged
    ///   - actualWeight: Weight that was logged
    ///   - restDuration: Seconds of rest (nil = no rest)
    ///   - nextSetNumber: Next set number (nil = exercise complete)
    ///   - nextTargetReps: Next set target reps
    ///   - nextTargetWeight: Next set target weight
    ///   - verbosity: Detail level 1-5 (default 3)
    /// - Returns: Confirmation string for TTS
    static func setLogged(
        actualReps: Int,
        actualWeight: Double,
        restDuration: Int?,
        nextSetNumber: Int?,
        nextTargetReps: Int?,
        nextTargetWeight: Double?,
        verbosity: Int = 3
    ) -> String {
        let weight = Int(actualWeight)

        switch verbosity {
        case 1:
            // Minimal: "Logged."
            return "Logged."

        case 2:
            // Basic: "Logged. 90 rest."
            if let rest = restDuration, rest > 0 {
                return "Logged. \(rest) rest."
            }
            return "Logged."

        case 3:
            // Moderate: "Logged 5 at 150. 90 seconds rest."
            var message = "Logged \(actualReps) at \(weight)."
            if let rest = restDuration, rest > 0 {
                message += " \(rest) seconds rest."
            }
            return message

        case 4:
            // Detailed: "Logged 5 reps at 150. 90 seconds, then Set 2."
            var message = "Logged \(actualReps) reps at \(weight)."
            if let rest = restDuration, rest > 0 {
                message += " \(rest) seconds"
                if let nextSet = nextSetNumber {
                    message += ", then Set \(nextSet)."
                } else {
                    message += " rest."
                }
            }
            return message

        default: // 5 (Verbose)
            // Full detail + next set preview
            var message = "Logged \(actualReps) reps at \(weight) pounds."

            if let rest = restDuration, rest > 0 {
                message += " \(rest) seconds rest."
            }

            if let nextSet = nextSetNumber,
               let nextReps = nextTargetReps,
               let nextWeight = nextTargetWeight {
                message += " Then Set \(nextSet), \(nextReps) reps at \(Int(nextWeight))."
            }

            return message
        }
    }

    // MARK: - Workout Announcements

    /// Generate workout intro (short version for template)
    ///
    /// Note: For personality, use GPT with hybrid approach for actual intro.
    /// This template is a fallback or for minimal verbosity users.
    static func workoutIntro(workoutName: String, exerciseCount: Int) -> String {
        return "Starting \(workoutName). \(exerciseCount) exercises."
    }

    /// Generate workout complete announcement
    ///
    /// Note: For personality/celebration, use GPT with hybrid approach.
    /// This template is a fallback or for minimal verbosity users.
    static func workoutComplete(duration: Int) -> String {
        return "Workout complete. \(duration) minutes."
    }

    // MARK: - Exercise Transitions

    /// v97: Generate exercise transition announcement
    ///
    /// Called when moving from one exercise to the next.
    /// Uses "Next up, X" for more natural speech vs robotic "Next: X"
    static func exerciseTransition(
        exerciseName: String,
        setCount: Int,
        firstSetReps: Int? = nil,
        firstSetWeight: Double? = nil,
        verbosity: Int = 3
    ) -> String {
        switch verbosity {
        case 1, 2:
            // Minimal/Basic: "Next up, Bench Press."
            return "Next up, \(exerciseName)."

        case 3:
            // Moderate: "Next up, Bench Press. 3 sets."
            return "Next up, \(exerciseName). \(setCount) sets."

        case 4, 5:
            // Detailed/Verbose: Include first set target
            if let reps = firstSetReps, let weight = firstSetWeight {
                return "Next up, \(exerciseName). \(setCount) sets, starting at \(reps) reps, \(Int(weight)) pounds."
            }
            return "Next up, \(exerciseName). \(setCount) sets."

        default:
            return "Next up, \(exerciseName). \(setCount) sets."
        }
    }

    // MARK: - Rest Announcements

    /// Generate rest start announcement
    static func restStart(duration: Int, verbosity: Int = 3) -> String {
        switch verbosity {
        case 1:
            return "\(duration) seconds."
        case 2, 3:
            return "\(duration) seconds rest."
        default:
            return "Rest for \(duration) seconds."
        }
    }

    /// Generate rest ending warning (optional 10-second countdown)
    static func restWarning(secondsRemaining: Int) -> String {
        if secondsRemaining <= 3 {
            return "\(secondsRemaining)"
        }
        return "\(secondsRemaining) seconds."
    }

    /// v98: Superset rotation announcement
    ///
    /// Called when rotating within a superset (e.g., from exercise 1a to 1b).
    /// - Parameters:
    ///   - exerciseName: Name of the next exercise
    ///   - setNumber: Set number (1-indexed)
    ///   - verbosity: Detail level 1-5 (default 3)
    /// - Returns: Announcement string for TTS
    static func supersetRotation(
        exerciseName: String,
        setNumber: Int,
        verbosity: Int = 3
    ) -> String {
        switch verbosity {
        case 1, 2:
            return "Now \(exerciseName)."
        default:
            return "Now to \(exerciseName), set \(setNumber)."
        }
    }

    // MARK: - Utility

    /// Clamp verbosity to valid range
    static func clampVerbosity(_ level: Int) -> Int {
        min(max(level, 1), 5)
    }
}
