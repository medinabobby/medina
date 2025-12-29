//
// VoiceAnnouncementService.swift
// Medina
//
// v86.0: AI-generated workout voice announcements
// Uses GPT-4o-mini to create personality-driven, contextual coaching
//

import Foundation

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

    // MARK: - Private Properties

    private let apiKey: String

    // MARK: - Initialization

    init(apiKey: String = Config.openAIKey) {
        self.apiKey = apiKey
    }

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

    /// Call GPT-4o-mini API
    private func callGPT(systemPrompt: String, userPrompt: String) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw NSError(domain: "VoiceAnnouncementService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_tokens": 100,  // Keep announcements brief
            "temperature": 0.7  // Some creativity for natural variation
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "VoiceAnnouncementService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.log(.error, component: "VoiceAnnouncementService", message: "GPT API error: \(httpResponse.statusCode) - \(errorBody)")
            throw NSError(domain: "VoiceAnnouncementService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorBody])
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "VoiceAnnouncementService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.log(.info, component: "VoiceAnnouncementService", message: "Generated: \(trimmed.prefix(50))...")

        return trimmed
    }
}
