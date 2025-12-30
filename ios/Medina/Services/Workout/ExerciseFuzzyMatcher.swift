//
//  ExerciseFuzzyMatcher.swift
//  Medina
//
//  v102.4 - Fuzzy matching for AI-provided exercise IDs
//  v102.5 - Added modifier-aware matching (incline, decline, seated, etc.)
//  v130 - Added generic plural stripping (push_ups → push_up) and singularize per word
//  Created: December 2025
//
//  Problem: AI hallucinates exercise IDs with wrong word order, pluralization,
//  or prefix variants. This causes silent rejections and short workouts.
//
//  Examples:
//  - overhead_dumbbell_press → dumbbell_overhead_press (word order)
//  - cable_triceps_pushdown → cable_tricep_pushdown (pluralization)
//  - bodyweight_dips → dip (prefix + name simplification)
//  - incline_bench_press → incline_dumbbell_bench_press (equipment inference)
//

import Foundation

/// Fuzzy matching for AI-provided exercise IDs
/// Handles common AI mistakes: word order, pluralization, underscore variants
enum ExerciseFuzzyMatcher {

    // MARK: - Main Entry Point

    /// Try to match an AI-provided ID to an actual exercise
    /// Returns the Exercise if found, nil otherwise
    static func match(_ aiId: String) -> Exercise? {
        let exercises = LocalDataStore.shared.exercises

        // 1. Exact match (most common case - fast path)
        if let exercise = exercises[aiId] {
            return exercise
        }

        // 2. Normalize and try again (fix common pluralization issues)
        let normalized = normalize(aiId)
        if normalized != aiId, let exercise = exercises[normalized] {
            Logger.log(.info, component: "ExerciseFuzzyMatcher",
                message: "✓ Normalized '\(aiId)' → '\(normalized)'")
            return exercise
        }

        // 3. Try word reordering (overhead_dumbbell_press → dumbbell_overhead_press)
        if let exercise = findByWordReorder(normalized, in: exercises) {
            Logger.log(.info, component: "ExerciseFuzzyMatcher",
                message: "✓ Reordered '\(aiId)' → '\(exercise.id)'")
            return exercise
        }

        // 4. Try adding equipment prefix (incline_bench_press → incline_dumbbell_bench_press)
        if let exercise = findByAddingEquipment(normalized, in: exercises) {
            Logger.log(.info, component: "ExerciseFuzzyMatcher",
                message: "✓ Equipment added '\(aiId)' → '\(exercise.id)'")
            return exercise
        }

        // 5. Try name-based fuzzy match
        if let exercise = findByName(aiId, in: exercises) {
            Logger.log(.info, component: "ExerciseFuzzyMatcher",
                message: "✓ Name matched '\(aiId)' → '\(exercise.id)'")
            return exercise
        }

        // 6. Try partial word match (superset of words)
        if let exercise = findByPartialWordMatch(normalized, in: exercises) {
            Logger.log(.info, component: "ExerciseFuzzyMatcher",
                message: "✓ Partial matched '\(aiId)' → '\(exercise.id)'")
            return exercise
        }

        // No match found
        return nil
    }

    // MARK: - Normalization

    /// Normalize common AI mistakes in exercise IDs
    private static func normalize(_ id: String) -> String {
        var result = id.lowercased()

        // Fix specific plural forms (AI often uses plural)
        result = result.replacingOccurrences(of: "triceps", with: "tricep")
        result = result.replacingOccurrences(of: "biceps", with: "bicep")
        result = result.replacingOccurrences(of: "glutes", with: "glute")
        result = result.replacingOccurrences(of: "calves", with: "calf")
        result = result.replacingOccurrences(of: "delts", with: "delt")

        // v130: Generic plural stripping - singularize each word in the ID
        // Example: push_ups → push_up, lunges → lunge, squats → squat
        let words = result.split(separator: "_").map(String.init)
        let singularizedWords = words.map { word -> String in
            // Don't singularize short words or words that don't end in 's'
            guard word.count > 2, word.hasSuffix("s"), !word.hasSuffix("ss") else {
                return word
            }
            // Special cases where we shouldn't strip 's'
            let keepAsIs = ["press", "cross", "abs", "pass", "boss", "class"]
            if keepAsIs.contains(word) {
                return word
            }
            // Strip trailing 's' for plurals
            return String(word.dropLast())
        }
        result = singularizedWords.joined(separator: "_")

        // Strip common prefixes AI adds unnecessarily
        if result.hasPrefix("bodyweight_") {
            let stripped = String(result.dropFirst("bodyweight_".count))
            // Only strip if the stripped version exists
            if LocalDataStore.shared.exercises[stripped] != nil {
                result = stripped
            }
        }

        return result
    }

    // MARK: - Word Reordering

    /// Find exercise by reordering words in the ID
    /// Example: overhead_dumbbell_press → dumbbell_overhead_press
    private static func findByWordReorder(_ normalizedId: String, in exercises: [String: Exercise]) -> Exercise? {
        let words = Set(normalizedId.split(separator: "_").map(String.init))

        // Need at least 2 words to reorder
        guard words.count >= 2 else { return nil }

        for (id, exercise) in exercises {
            let exerciseWords = Set(id.split(separator: "_").map(String.init))
            // If same words, just different order → match
            if words == exerciseWords {
                return exercise
            }
        }

        return nil
    }

    // MARK: - Name-Based Matching

    /// Find exercise by human-readable name (fuzzy)
    /// Converts underscores to spaces and does contains matching
    private static func findByName(_ query: String, in exercises: [String: Exercise]) -> Exercise? {
        let humanized = query.replacingOccurrences(of: "_", with: " ").lowercased()

        // Try exact name match first
        if let match = exercises.values.first(where: {
            $0.name.lowercased() == humanized
        }) {
            return match
        }

        // Try contains match (either direction)
        if let match = exercises.values.first(where: {
            $0.name.lowercased().contains(humanized) || humanized.contains($0.name.lowercased())
        }) {
            return match
        }

        // Try matching against baseExercise field
        if let match = exercises.values.first(where: {
            $0.baseExercise.lowercased() == humanized.replacingOccurrences(of: " ", with: "_")
        }) {
            return match
        }

        return nil
    }

    // MARK: - Equipment Insertion

    /// Common equipment types to try inserting
    private static let equipmentTypes = ["dumbbell", "barbell", "cable", "machine", "bodyweight"]

    /// Modifiers that precede equipment in exercise IDs
    private static let modifiers = ["incline", "decline", "seated", "standing", "overhead", "reverse"]

    /// Try adding equipment type to find a match
    /// Example: incline_bench_press → incline_dumbbell_bench_press
    private static func findByAddingEquipment(_ id: String, in exercises: [String: Exercise]) -> Exercise? {
        let parts = id.split(separator: "_").map(String.init)
        guard parts.count >= 2 else { return nil }

        // Check if first word is a modifier (incline, decline, etc.)
        if let modifier = parts.first, modifiers.contains(modifier) {
            // Try inserting equipment after modifier
            // e.g., "incline" + "dumbbell" + "bench_press"
            let rest = parts.dropFirst().joined(separator: "_")
            for equipment in equipmentTypes {
                let candidate = "\(modifier)_\(equipment)_\(rest)"
                if let exercise = exercises[candidate] {
                    return exercise
                }
            }
        }

        // Try prepending equipment
        for equipment in equipmentTypes {
            let candidate = "\(equipment)_\(id)"
            if let exercise = exercises[candidate] {
                return exercise
            }
        }

        return nil
    }

    // MARK: - Partial Word Matching

    /// Find exercise where AI's words are a subset of the actual ID words
    /// Example: "bench_press" matches "incline_dumbbell_bench_press"
    /// v130: Also handles single words with singularized matching
    private static func findByPartialWordMatch(_ id: String, in exercises: [String: Exercise]) -> Exercise? {
        let aiWords = Set(id.split(separator: "_").map(String.init))

        // v130: Handle single-word queries (e.g., "squats" normalized to "squat")
        // Try to find exercises that START with this word
        if aiWords.count == 1, let singleWord = aiWords.first {
            // Find exercises where the ID starts with or equals this word
            // Prioritize exact single-word matches, then prefix matches
            if let exactMatch = exercises[singleWord] {
                return exactMatch
            }
            // Try finding exercises that start with this word
            // e.g., "squat" matches "squat", "jump_squat" matches "jump" prefix
            for (exerciseId, exercise) in exercises {
                let exerciseWords = exerciseId.split(separator: "_").map(String.init)
                if exerciseWords.first == singleWord || exerciseWords.last == singleWord {
                    return exercise
                }
            }
        }

        guard aiWords.count >= 2 else { return nil }

        // Find exercises where AI's words are all present
        var bestMatch: (Exercise, Int)?

        for (exerciseId, exercise) in exercises {
            let exerciseWords = Set(exerciseId.split(separator: "_").map(String.init))

            // AI words must be subset of exercise words
            if aiWords.isSubset(of: exerciseWords) {
                let extraWords = exerciseWords.subtracting(aiWords).count

                // Prefer matches with fewer extra words (more specific)
                if bestMatch == nil || extraWords < bestMatch!.1 {
                    bestMatch = (exercise, extraWords)
                }
            }
        }

        return bestMatch?.0
    }
}
