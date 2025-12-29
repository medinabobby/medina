//
// TrainingDataContextBuilder.swift
// Medina
//
// v96.0 - Flywheel data for AI prompts
// Created: December 8, 2025
//
// Purpose: Pass user strength data and exercise preferences to AI
// Enables: Weight prescription based on actual 1RMs, exercise selection
//          weighted by completion rates
//
// Token cost: ~150 tokens (80 for strength + 70 for affinity)
// Quality impact: Personalized weights, exercises user actually completes
//

import Foundation

/// Builds flywheel data context for AI prompts
///
/// **Flywheel Concept:**
/// More user data → better workouts → better results → more data
///
/// **Data Sources:**
/// - `TestDataManager.targets`: 1RM values for main lifts
/// - `UserExercisePreferences`: Completion rates, favorites, exclusions
///
/// **Token Budget:**
/// - Strength baselines: ~80 tokens
/// - Exercise affinity: ~70 tokens
/// - Total: ~150 tokens per request
///
/// **Note (v190):** targets.json removed, targets dictionary starts empty.
/// User targets will be populated via UI or Firestore in future.
enum TrainingDataContextBuilder {

    // MARK: - Strength Baselines

    /// Build strength baselines section for AI weight prescription
    ///
    /// Provides 1RM data for main compound lifts so AI can prescribe
    /// accurate percentages: "75% of your 225lb bench = 170lbs"
    ///
    /// - Parameter userId: The user's ID
    /// - Returns: Formatted strength data (~80 tokens), or empty string if no data
    static func buildStrengthBaselines(for userId: String) -> String {
        let mainLiftIds = ["barbell_back_squat", "conventional_deadlift", "barbell_bench_press", "overhead_press"]

        // Get all targets for this user from TestDataManager
        let allTargets = TestDataManager.shared.targets.values.filter { $0.memberId == userId }

        // Filter to main lifts first
        let mainLifts = allTargets.filter { mainLiftIds.contains($0.exerciseId) }

        // Get additional targets (non-main lifts)
        let additionalTargets = allTargets.filter { target in
            !mainLiftIds.contains(target.exerciseId)
        }.prefix(4)  // Limit to 4 additional to control tokens

        let allRelevantTargets = Array(mainLifts) + Array(additionalTargets)
        guard !allRelevantTargets.isEmpty else { return "" }

        var rows: [String] = []
        for target in allRelevantTargets {
            guard let weight = target.currentTarget else { continue }

            // Get exercise name
            let exerciseName = ExerciseDataStore.exercise(byId: target.exerciseId)?.name ?? target.exerciseId

            // Format last calibrated date
            let dateStr: String
            if let date = target.lastCalibrated {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                dateStr = formatter.string(from: date)
            } else {
                dateStr = "Unknown"
            }

            rows.append("| \(exerciseName) | \(Int(weight)) lbs | \(dateStr) |")
        }

        guard !rows.isEmpty else { return "" }

        return """
        ## STRENGTH BASELINES (Use for weight prescription)
        | Lift | 1RM | Last Tested |
        |------|-----|-------------|
        \(rows.joined(separator: "\n"))

        When prescribing weights, use percentages: "75% of your 225lb bench = 170lbs"
        """
    }

    // MARK: - Exercise Affinity

    /// Build exercise affinity section based on completion rates
    ///
    /// Guides AI to favor exercises the user actually completes,
    /// and avoid exercises they frequently skip.
    ///
    /// - Parameter userId: The user's ID
    /// - Returns: Formatted affinity data (~70 tokens), or empty string if no data
    static func buildExerciseAffinity(for userId: String) -> String {
        let prefs = TestDataManager.shared.userExercisePreferences(for: userId)

        // Get recent exercises (last 30 days)
        let recent = prefs.recentExercises(withinDays: 30)
        guard !recent.isEmpty else { return "" }

        // High affinity: completion rate > 80%
        let highAffinity = recent
            .filter { $0.completionRate > 0.8 }
            .sorted { $0.completionRate > $1.completionRate }
            .prefix(8)
            .compactMap { ExerciseDataStore.exercise(byId: $0.exerciseId)?.name }

        // Low affinity: completion rate < 50%
        let lowAffinity = recent
            .filter { $0.completionRate < 0.5 }
            .prefix(4)
            .compactMap { ExerciseDataStore.exercise(byId: $0.exerciseId)?.name }

        // Favorites (always include)
        let favorites = prefs.favorites
            .prefix(6)
            .compactMap { ExerciseDataStore.exercise(byId: $0)?.name }

        // Build output
        var sections: [String] = []

        if !favorites.isEmpty {
            sections.append("**Favorites** (always prioritize): \(favorites.joined(separator: ", "))")
        }

        if !highAffinity.isEmpty {
            sections.append("**High completion** (favor these): \(highAffinity.joined(separator: ", "))")
        }

        if !lowAffinity.isEmpty {
            sections.append("**Often skipped** (consider alternatives): \(lowAffinity.joined(separator: ", "))")
        }

        guard !sections.isEmpty else { return "" }

        return """
        ## EXERCISE AFFINITY (Completion-Weighted)
        \(sections.joined(separator: "\n"))
        """
    }

    // MARK: - Excluded Exercises

    /// Build excluded exercises list
    ///
    /// Hard blocks - never suggest these exercises to this user.
    ///
    /// - Parameter userId: The user's ID
    /// - Returns: Formatted exclusions, or empty string if none
    static func buildExclusions(for userId: String) -> String {
        let prefs = TestDataManager.shared.userExercisePreferences(for: userId)
        guard !prefs.excluded.isEmpty else { return "" }

        let excludedNames = prefs.excluded
            .prefix(10)
            .compactMap { ExerciseDataStore.exercise(byId: $0)?.name }

        guard !excludedNames.isEmpty else { return "" }

        return """
        ## EXCLUDED EXERCISES (Never suggest)
        \(excludedNames.joined(separator: ", "))
        """
    }

    // MARK: - Combined Builder

    /// Build all flywheel data for a user
    ///
    /// Combines strength baselines, exercise affinity, and exclusions
    /// into a single context block for the AI prompt.
    ///
    /// - Parameter userId: The user's ID
    /// - Returns: Combined flywheel context (~150 tokens total)
    static func buildAllFlyweelData(for userId: String) -> String {
        let strength = buildStrengthBaselines(for: userId)
        let affinity = buildExerciseAffinity(for: userId)
        let exclusions = buildExclusions(for: userId)

        let sections = [strength, affinity, exclusions].filter { !$0.isEmpty }

        guard !sections.isEmpty else { return "" }

        return """
        # PERSONALIZED TRAINING DATA
        \(sections.joined(separator: "\n\n"))
        """
    }
}
