//
// TierDetector.swift
// Medina
//
// v96.0 - Prompt tiering for token optimization
// Created: December 8, 2025
//
// Purpose: Match prompt complexity to request complexity
// "Hello" shouldn't get 8,000 tokens of instructions
//
// Token targets:
// - Lightweight: ~1,500 tokens (simple queries)
// - Standard: ~4,000 tokens (workout creation)
// - Full: ~8,000 tokens (plan creation, trainer mode)
//

import Foundation

/// Prompt complexity tier for token optimization
///
/// **Tier Strategy:**
/// - Lightweight: Identity + profile + off-topic + basic tools
/// - Standard: + Exercise context (compact) + workout rules + 6 tools
/// - Full: Everything including plan rules, trainer context, full library
enum PromptTier: String, CaseIterable {
    case lightweight  // ~1,500 tokens
    case standard     // ~4,000 tokens
    case full         // ~8,000 tokens

    var approximateTokens: Int {
        switch self {
        case .lightweight: return 1500
        case .standard: return 4000
        case .full: return 8000
        }
    }

    var description: String {
        switch self {
        case .lightweight: return "Simple query (hello, what's a superset?)"
        case .standard: return "Workout creation/modification"
        case .full: return "Plan creation or trainer mode"
        }
    }
}

/// Detects appropriate prompt tier based on message and user context
///
/// **Detection Strategy:**
/// 1. Trainer mode always gets full context
/// 2. Plan-related keywords trigger full tier
/// 3. Workout-related keywords trigger standard tier
/// 4. Everything else is lightweight
enum TierDetector {

    // MARK: - Main Detection

    /// Detect the appropriate prompt tier for a message
    ///
    /// - Parameters:
    ///   - message: The user's message text
    ///   - user: The user sending the message
    /// - Returns: The appropriate prompt tier
    static func detect(message: String, user: UnifiedUser) -> PromptTier {
        let text = message.lowercased()

        // Tier 3 (Full): Trainer mode with client context
        if user.hasRole(.trainer) && containsAny(text, trainerKeywords) {
            return .full
        }

        // Tier 3 (Full): Plan creation
        if containsAny(text, planKeywords) {
            return .full
        }

        // Tier 2 (Standard): Workout creation/modification
        if containsAny(text, workoutKeywords) {
            return .standard
        }

        // v111.2: Tier 2 (Standard): Class booking/listing
        if containsAny(text, classBookingKeywords) {
            return .standard
        }

        // Tier 2 (Standard): Exercise-related queries
        if containsAny(text, exerciseKeywords) {
            return .standard
        }

        // Tier 1 (Lightweight): Everything else
        return .lightweight
    }

    // MARK: - Keyword Sets

    /// Keywords that trigger full prompt (plan creation)
    private static let planKeywords = [
        "plan", "program", "weeks", "month", "periodization",
        "training plan", "workout plan", "create a plan",
        "12 week", "8 week", "4 week", "multi-week"
    ]

    /// Keywords that trigger full prompt (trainer mode)
    private static let trainerKeywords = [
        "member", "client", "for ", "their",
        "assign", "prescribe"
    ]

    /// Keywords that trigger standard prompt (workout creation/execution)
    /// v120: Added "start", "begin", "continue", "analyze", "progress" for workout execution/analysis
    private static let workoutKeywords = [
        "workout", "create", "make", "modify", "change",
        "tomorrow", "today", "schedule", "session",
        "upper body", "lower body", "chest", "back", "legs",
        "push", "pull", "arms", "shoulders",
        "superset", "circuit", "gbc", "protocol",
        "start", "begin", "continue", "analyze", "progress"
    ]

    /// v111.2: Keywords that trigger standard prompt (class booking)
    private static let classBookingKeywords = [
        "class", "classes", "book", "booking",
        "available", "yoga", "pilates", "spin", "hiit",
        "bootcamp", "boxing", "cycling", "cardio class"
    ]

    /// Keywords that trigger standard prompt (exercise queries)
    private static let exerciseKeywords = [
        "exercise", "substitute", "alternative", "instead of",
        "how do i do", "form", "technique", "sets", "reps",
        "weight", "1rm", "max"
    ]

    // MARK: - Utility

    /// Check if text contains any of the keywords
    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}

// MARK: - PromptTierConfiguration

/// Configuration for what to include at each tier
///
/// Used by SystemPrompts to assemble the right sections
struct PromptTierConfiguration {

    let tier: PromptTier

    /// Include exercise library context
    var includeExerciseContext: Bool {
        tier != .lightweight
    }

    /// Include workout creation rules
    var includeWorkoutRules: Bool {
        tier != .lightweight
    }

    /// Include plan creation rules
    var includePlanRules: Bool {
        tier == .full
    }

    /// Include trainer context
    var includeTrainerContext: Bool {
        tier == .full
    }

    /// Include full tool instructions
    var includeFullToolInstructions: Bool {
        tier != .lightweight
    }

    /// Include flywheel training data
    var includeTrainingData: Bool {
        tier != .lightweight
    }

    /// Use compact exercise format
    var useCompactExerciseFormat: Bool {
        tier == .standard
    }

    /// Tools to include
    var toolsToInclude: [String] {
        switch tier {
        case .lightweight:
            return ["show_schedule", "update_profile"]
        case .standard:
            // v102.4: Added create_custom_workout for image-based workout creation
            // v120: Added start_workout (was missing!), analyze_training_data
            // v186: Removed class tools (class booking deferred for beta)
            return [
                "show_schedule", "create_workout", "create_custom_workout", "modify_workout",
                "get_substitution_options", "update_profile", "change_protocol",
                "start_workout", "analyze_training_data"
            ]
        case .full:
            // v120: Added start_workout (was missing!), analyze_training_data
            // v186: Removed class tools (class booking deferred for beta)
            return [
                "show_schedule", "create_workout", "create_custom_workout",
                "modify_workout", "get_substitution_options", "get_summary",
                "create_plan", "reschedule_plan", "update_profile",
                "change_protocol", "update_exercise_target", "activate_plan",
                "start_workout", "analyze_training_data"
            ]
        }
    }
}
