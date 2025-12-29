//
// VoiceSequencer.swift
// Medina
//
// v95.0: Coordinates voice playback with visual transitions
// Ensures announcements complete before screen changes
//

import Foundation

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
/// v95.0: Coordinates voice playback with visual transitions
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
        self.voiceService = voiceService ?? VoiceService(apiKey: Config.openAIKey)
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
        guard let user = TestDataManager.shared.users[userId],
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
        guard let user = TestDataManager.shared.users[userId],
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

