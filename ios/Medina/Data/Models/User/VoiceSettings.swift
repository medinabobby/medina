//
// VoiceSettings.swift
// Medina
//
// Created: November 2025
// v47: Voice coaching preferences for workout sessions
// v86.0: Added Realtime API voice chat and workout voice commands
// v95.0: Added voice gender selection for TTS variety
//

import Foundation

// MARK: - Voice Gender

/// Voice gender preference for TTS
///
/// Maps to different OpenAI TTS voices:
/// - Female: nova, shimmer
/// - Male: onyx, echo
enum VoiceGender: String, Codable, CaseIterable, Identifiable {
    case female = "female"
    case male = "male"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        }
    }

    /// Icon for UI display
    var icon: String {
        switch self {
        case .female: return "person.circle"
        case .male: return "person.circle.fill"
        }
    }
}

/// Voice coaching configuration for workout sessions
///
/// **v47 Voice Architecture:**
/// - Top-level toggle: Enable/disable all voice coaching
/// - Verbosity dial: Control announcement detail level (1-5)
/// - Granular toggles: What to announce (sets, reps, rest, RPE, tempo, weights)
///
/// **v86.0 Voice Chat:**
/// - Chat voice: Enable Realtime API voice conversations
/// - Workout commands: Enable voice commands during exercise ("log", "skip", "pause")
///
/// **Default Configuration:**
/// - Voice enabled by default
/// - Verbosity level 3 (moderate)
/// - All announcements enabled
/// - Chat voice: disabled by default (opt-in)
/// - Workout commands: disabled by default (opt-in)
///
/// **Persistence:**
/// - Stored in `MemberProfile.voiceSettings`
/// - Persisted via `UserPersistenceStore`
/// - Migration: Nil voiceSettings → VoiceSettings.default
struct VoiceSettings: Codable, Equatable {

    // MARK: - Properties

    /// Master toggle for voice coaching
    var isEnabled: Bool

    /// Verbosity level: 1 (minimal) to 5 (verbose)
    ///
    /// - 1: Essential only (set/rep counts)
    /// - 2: Basic (+ rest time)
    /// - 3: Moderate (+ RPE guidance)
    /// - 4: Detailed (+ tempo cues)
    /// - 5: Verbose (+ weight recommendations, form tips)
    var verbosityLevel: Int

    // MARK: - Announcement Toggles

    /// Announce set number ("Set 1 of 3")
    var announceSets: Bool

    /// Announce rep count ("8 reps")
    var announceReps: Bool

    /// Announce rest time ("90 seconds rest")
    var announceRestTime: Bool

    /// Announce RPE targets ("Target RPE: 8")
    var announceRPE: Bool

    /// Announce tempo ("3-0-1 tempo")
    var announceTempo: Bool

    /// Announce weight recommendations ("Try 135 pounds")
    var announceWeights: Bool

    // MARK: - v86.0: Chat Voice Settings

    /// Enable Realtime API voice conversations in chat
    /// When enabled, shows voice button next to microphone
    var chatVoiceEnabled: Bool

    /// Preferred voice for Realtime API responses
    /// Options: alloy, echo, shimmer, ash, ballad, coral, sage, verse
    var realtimeVoice: String

    // MARK: - v86.0: Workout Voice Commands

    /// Enable voice commands during workout execution
    /// Commands: "log", "done", "skip", "skip rest", "pause", "resume"
    var workoutVoiceCommands: Bool

    // MARK: - v95.0: Voice Gender

    /// Preferred voice gender for TTS announcements
    /// v182: Maps to OpenAI voices (male=onyx, female=nova)
    var voiceGender: VoiceGender

    // MARK: - Default Configuration

    /// Default voice settings for new users and migration
    static var `default`: VoiceSettings {
        VoiceSettings(
            isEnabled: true,
            verbosityLevel: 3, // Moderate
            announceSets: true,
            announceReps: true,
            announceRestTime: true,
            announceRPE: true,
            announceTempo: false, // Off by default (advanced users only)
            announceWeights: true,
            chatVoiceEnabled: true, // v86.0: Enabled by default for testing
            realtimeVoice: "alloy", // v86.0: Default voice
            workoutVoiceCommands: false, // v86.0: Opt-in for workout commands
            voiceGender: .female // v95.0: Default to female voice
        )
    }

    // MARK: - Initialization

    init(
        isEnabled: Bool,
        verbosityLevel: Int,
        announceSets: Bool,
        announceReps: Bool,
        announceRestTime: Bool,
        announceRPE: Bool,
        announceTempo: Bool,
        announceWeights: Bool,
        chatVoiceEnabled: Bool = false,
        realtimeVoice: String = "alloy",
        workoutVoiceCommands: Bool = false,
        voiceGender: VoiceGender = .female
    ) {
        self.isEnabled = isEnabled
        self.verbosityLevel = min(max(verbosityLevel, 1), 5) // Clamp to 1-5
        self.announceSets = announceSets
        self.announceReps = announceReps
        self.announceRestTime = announceRestTime
        self.announceRPE = announceRPE
        self.announceTempo = announceTempo
        self.announceWeights = announceWeights
        self.chatVoiceEnabled = chatVoiceEnabled
        self.realtimeVoice = realtimeVoice
        self.workoutVoiceCommands = workoutVoiceCommands
        self.voiceGender = voiceGender
    }

    // MARK: - Computed Properties

    /// Human-readable verbosity label
    var verbosityLabel: String {
        switch verbosityLevel {
        case 1: return "Minimal"
        case 2: return "Basic"
        case 3: return "Moderate"
        case 4: return "Detailed"
        case 5: return "Verbose"
        default: return "Moderate"
        }
    }

    /// v106.2: Simplified toggle - brief vs normal announcements
    /// Maps to verbosityLevel 1 (brief) or 3 (normal)
    var briefAnnouncements: Bool {
        get { verbosityLevel <= 2 }
        set { verbosityLevel = newValue ? 1 : 3 }
    }

    /// Check if any announcements are enabled
    var hasAnyAnnouncementsEnabled: Bool {
        announceSets || announceReps || announceRestTime ||
        announceRPE || announceTempo || announceWeights
    }

    // MARK: - Codable Migration

    /// Custom decoder to handle migration from older JSON without new fields
    /// v95.0: Adds default values for chatVoiceEnabled, realtimeVoice, workoutVoiceCommands, voiceGender
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Required fields (always present in valid JSON)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        verbosityLevel = try container.decode(Int.self, forKey: .verbosityLevel)
        announceSets = try container.decode(Bool.self, forKey: .announceSets)
        announceReps = try container.decode(Bool.self, forKey: .announceReps)
        announceRestTime = try container.decode(Bool.self, forKey: .announceRestTime)
        announceRPE = try container.decode(Bool.self, forKey: .announceRPE)
        announceTempo = try container.decode(Bool.self, forKey: .announceTempo)
        announceWeights = try container.decode(Bool.self, forKey: .announceWeights)

        // v86.0 fields - may be missing in old persisted data
        chatVoiceEnabled = try container.decodeIfPresent(Bool.self, forKey: .chatVoiceEnabled) ?? true
        realtimeVoice = try container.decodeIfPresent(String.self, forKey: .realtimeVoice) ?? "alloy"
        workoutVoiceCommands = try container.decodeIfPresent(Bool.self, forKey: .workoutVoiceCommands) ?? false

        // v95.0 field - may be missing in old persisted data
        voiceGender = try container.decodeIfPresent(VoiceGender.self, forKey: .voiceGender) ?? .female
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, verbosityLevel
        case announceSets, announceReps, announceRestTime, announceRPE, announceTempo, announceWeights
        case chatVoiceEnabled, realtimeVoice, workoutVoiceCommands
        case voiceGender
    }
}
