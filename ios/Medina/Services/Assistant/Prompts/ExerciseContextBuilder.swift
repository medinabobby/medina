//
// ExerciseContextBuilder.swift
// Medina
//
// v81.0 - AI-First Exercise Selection Context
// v96.0 - Added compact mode for standard tier (token optimization)
// Created: December 4, 2025
//
// Purpose: Build preference-aware exercise context for AI
// Replaces UserContextBuilder.buildExerciseLibrary()
// Formats favorites, recent, excluded, and available exercises
//

import Foundation

/// Builds preference-aware exercise context for AI workout creation
/// The AI receives a filtered, prioritized view of exercises
struct ExerciseContextBuilder {

    // MARK: - Main Entry Point

    /// Build exercise context for AI system prompt
    /// Includes favorites, recent, available, and excluded exercises
    /// All filtered by user's equipment availability
    ///
    /// - Parameters:
    ///   - user: The user to build context for
    ///   - trainingLocation: Training location (gym/home/outdoor)
    ///   - availableEquipment: Override equipment set
    ///   - compact: If true, use compact format (~500 tokens vs ~1500 tokens)
    static func buildExerciseContext(
        for user: UnifiedUser,
        trainingLocation: TrainingLocation? = nil,
        availableEquipment: Set<Equipment>? = nil,
        compact: Bool = false
    ) -> String {
        // v96.0: Compact mode for standard tier
        if compact {
            return buildCompactExerciseContext(
                for: user,
                trainingLocation: trainingLocation,
                availableEquipment: availableEquipment
            )
        }
        let prefs = TestDataManager.shared.userExercisePreferences(for: user.id)
        let allExercises = TestDataManager.shared.exercises

        // Determine equipment filter
        let equipment = resolveEquipment(
            user: user,
            trainingLocation: trainingLocation,
            availableEquipment: availableEquipment
        )

        // Build each section
        let favorites = buildFavoritesSection(prefs: prefs, exercises: allExercises, equipment: equipment)
        let recent = buildRecentSection(prefs: prefs, exercises: allExercises, equipment: equipment)
        let available = buildAvailableSection(prefs: prefs, exercises: allExercises, equipment: equipment)
        let excluded = buildExcludedSection(prefs: prefs, exercises: allExercises)
        let rules = buildSelectionRules()

        return """
        ## YOUR EXERCISE OPTIONS
        Equipment filter: \(formatEquipment(equipment))

        \(favorites)

        \(recent)

        \(available)

        \(excluded)

        \(rules)
        """
    }

    // MARK: - Equipment Resolution

    /// Resolve equipment from multiple sources (priority order)
    /// 1. Explicit availableEquipment parameter (from AI tool call)
    /// 2. TrainingLocation-based equipment
    /// 3. User profile defaults
    private static func resolveEquipment(
        user: UnifiedUser,
        trainingLocation: TrainingLocation?,
        availableEquipment: Set<Equipment>?
    ) -> Set<Equipment> {
        // 1. Explicit equipment parameter takes priority
        if let explicit = availableEquipment, !explicit.isEmpty {
            return explicit.union([.bodyweight])  // Always include bodyweight
        }

        // 2. Training location determines equipment set
        if let location = trainingLocation {
            switch location {
            case .gym:
                // Gym has full equipment
                return Set(Equipment.allCases)
            case .home:
                // Home uses user's configured equipment
                if let homeEquipment = user.memberProfile?.availableEquipment, !homeEquipment.isEmpty {
                    return homeEquipment.union([.bodyweight])
                }
                // Fallback: bodyweight only
                return [.bodyweight]
            case .outdoor:
                return [.bodyweight]
            case .hybrid:
                // Hybrid: gym equipment plus home equipment
                if let homeEquipment = user.memberProfile?.availableEquipment, !homeEquipment.isEmpty {
                    return Set(Equipment.allCases)  // Has gym access too
                }
                return Set(Equipment.allCases)  // Gym access available
            }
        }

        // 3. Use profile's training location default
        if let defaultLocation = user.memberProfile?.trainingLocation {
            return resolveEquipment(user: user, trainingLocation: defaultLocation, availableEquipment: nil)
        }

        // 4. Ultimate fallback: gym (full equipment)
        return Set(Equipment.allCases)
    }

    // MARK: - Section Builders

    /// Build favorites section (★ always consider first)
    private static func buildFavoritesSection(
        prefs: UserExercisePreferences,
        exercises: [String: Exercise],
        equipment: Set<Equipment>
    ) -> String {
        guard !prefs.favorites.isEmpty else {
            return "### ★ FAVORITES\nNo favorites set. User can star exercises to prioritize them."
        }

        let favoriteExercises = prefs.favorites.compactMap { id -> Exercise? in
            guard let exercise = exercises[id] else { return nil }
            // Include favorites even if equipment doesn't match (user explicitly wants them)
            return exercise
        }.sorted { $0.name < $1.name }

        if favoriteExercises.isEmpty {
            return "### ★ FAVORITES\nNo favorites set."
        }

        var lines = ["### ★ FAVORITES (always consider first)"]
        lines.append("| ID | Name | Type | Equipment | Muscles |")
        lines.append("|:---|:-----|:-----|:----------|:--------|")

        for exercise in favoriteExercises {
            let muscleNames = exercise.muscleGroups.prefix(2).map { $0.displayName }.joined(separator: ", ")
            let equipmentMatch = equipment.contains(exercise.equipment) ? "" : " ⚠️"
            lines.append("| \(exercise.id) | \(exercise.name) | \(exercise.type.rawValue) | \(exercise.equipment.displayName)\(equipmentMatch) | \(muscleNames) |")
        }

        if favoriteExercises.contains(where: { !equipment.contains($0.equipment) }) {
            lines.append("\n⚠️ = Requires equipment user may not have. Ask before including.")
        }

        return lines.joined(separator: "\n")
    }

    /// Build recent exercises section (used in last 30 days)
    private static func buildRecentSection(
        prefs: UserExercisePreferences,
        exercises: [String: Exercise],
        equipment: Set<Equipment>
    ) -> String {
        let recentExercises = prefs.recentExercises(withinDays: 30)
            .filter { !prefs.favorites.contains($0.exerciseId) }  // Don't duplicate favorites
            .filter { recent in
                guard let exercise = exercises[recent.exerciseId] else { return false }
                return equipment.contains(exercise.equipment)
            }
            .sorted { $0.lastUsed > $1.lastUsed }
            .prefix(10)

        guard !recentExercises.isEmpty else {
            return "### RECENT (last 30 days)\nNo recent exercise history."
        }

        var lines = ["### RECENT (last 30 days, high completion)"]
        lines.append("| ID | Name | Last Used | Completion |")
        lines.append("|:---|:-----|:----------|:-----------|")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"

        for recent in recentExercises {
            guard let exercise = exercises[recent.exerciseId] else { continue }
            let dateStr = dateFormatter.string(from: recent.lastUsed)
            let completionStr = "\(Int(recent.completionRate * 100))%"
            lines.append("| \(recent.exerciseId) | \(exercise.name) | \(dateStr) | \(completionStr) |")
        }

        return lines.joined(separator: "\n")
    }

    /// Build available exercises section (filtered by equipment)
    /// v83.1: Shows ALL exercises in compact format to prevent AI ID guessing
    private static func buildAvailableSection(
        prefs: UserExercisePreferences,
        exercises: [String: Exercise],
        equipment: Set<Equipment>
    ) -> String {
        // Get exercises that pass equipment filter and aren't favorites/excluded
        let available = exercises.values.filter { exercise in
            !prefs.favorites.contains(exercise.id) &&
            !prefs.excluded.contains(exercise.id) &&
            equipment.contains(exercise.equipment)
        }.sorted { $0.name < $1.name }

        guard !available.isEmpty else {
            return "### AVAILABLE\nNo exercises available with current equipment filter."
        }

        // Group by type for AI context
        let compounds = available.filter { $0.type == .compound }
        let isolations = available.filter { $0.type == .isolation }

        var lines = ["### AVAILABLE (\(available.count) exercises for current equipment)"]

        // v83.1: FULL EXERCISE VOCABULARY - compact format for all exercises
        // This ensures AI can find any exercise the user asks for
        lines.append("\n**FULL EXERCISE VOCABULARY** (use these exact IDs):")

        // Compounds - compact format: "id: Name, id: Name, ..."
        if !compounds.isEmpty {
            lines.append("\n*Compounds:*")
            let compoundList = compounds.map { "\($0.id): \($0.name)" }.joined(separator: ", ")
            lines.append(compoundList)
        }

        // Isolations - compact format
        if !isolations.isEmpty {
            lines.append("\n*Isolations:*")
            let isolationList = isolations.map { "\($0.id): \($0.name)" }.joined(separator: ", ")
            lines.append(isolationList)
        }

        // Detailed table for top 10 compounds (for quick reference with muscle info)
        if !compounds.isEmpty {
            lines.append("\n**Top Compound Details** (muscle groups for reference):")
            lines.append("| ID | Name | Equipment | Muscles |")
            lines.append("|:---|:-----|:----------|:--------|")

            for exercise in compounds.prefix(10) {
                let muscleNames = exercise.muscleGroups.prefix(2).map { $0.displayName }.joined(separator: ", ")
                lines.append("| \(exercise.id) | \(exercise.name) | \(exercise.equipment.displayName) | \(muscleNames) |")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Build excluded exercises section (never suggest)
    private static func buildExcludedSection(
        prefs: UserExercisePreferences,
        exercises: [String: Exercise]
    ) -> String {
        guard !prefs.excluded.isEmpty else {
            return "### ❌ EXCLUDED\nNo excluded exercises."
        }

        let excludedExercises = prefs.excluded.compactMap { id -> Exercise? in
            exercises[id]
        }

        var lines = ["### ❌ EXCLUDED (never suggest)"]
        for exercise in excludedExercises.prefix(10) {
            lines.append("- \(exercise.id) (\(exercise.name))")
        }
        if excludedExercises.count > 10 {
            lines.append("- ... +\(excludedExercises.count - 10) more excluded")
        }

        return lines.joined(separator: "\n")
    }

    /// Build selection rules for AI
    /// v82.2: Added diversity and movement pattern guidance
    private static func buildSelectionRules() -> String {
        return """
        ### SELECTION RULES
        1. **ALWAYS include favorites** when their muscle group matches the workout
        2. **Prefer recent exercises** with high completion rate (user clearly likes them)
        3. **VARY MOVEMENT PATTERNS**: For upper body, include BOTH pushing AND pulling movements
        4. **VARIETY OVER REPETITION**: Avoid picking 3+ variations of the same base exercise (e.g., max 2 push-up variants)
        5. **BALANCED MUSCLE COVERAGE**: Include exercises for different muscle groups within the split
        6. **Duration guide**: 30min→3, 45min→4-5, 60min→5-6, 75min→7, 90min→8 exercises
        7. **Never use excluded exercises** - user has explicitly blocked them
        8. **Only use exercise IDs from the tables above** - validation will fail otherwise
        9. **User can modify your selection** - that's expected and encouraged
        """
    }

    // MARK: - Helpers

    private static func formatEquipment(_ equipment: Set<Equipment>) -> String {
        if equipment.count == Equipment.allCases.count {
            return "Full gym equipment"
        }

        let sorted = equipment.sorted { $0.rawValue < $1.rawValue }
        return sorted.map { $0.displayName }.joined(separator: ", ")
    }

    // MARK: - Compact Mode (v96.0)

    /// Build compact exercise context (~500 tokens vs ~1500)
    /// Used for standard tier prompts where full vocabulary isn't needed
    private static func buildCompactExerciseContext(
        for user: UnifiedUser,
        trainingLocation: TrainingLocation?,
        availableEquipment: Set<Equipment>?
    ) -> String {
        let prefs = TestDataManager.shared.userExercisePreferences(for: user.id)
        let allExercises = TestDataManager.shared.exercises

        let equipment = resolveEquipment(
            user: user,
            trainingLocation: trainingLocation,
            availableEquipment: availableEquipment
        )

        // Favorites - always include
        let favoriteExercises = prefs.favorites.compactMap { id -> String? in
            guard let exercise = allExercises[id] else { return nil }
            return "\(exercise.id): \(exercise.name)"
        }.prefix(10)

        // Top exercises by muscle group (compact)
        let available = allExercises.values.filter { exercise in
            !prefs.excluded.contains(exercise.id) &&
            equipment.contains(exercise.equipment)
        }

        // Group by primary muscle for diversity
        var byMuscle: [MuscleGroup: [Exercise]] = [:]
        for exercise in available {
            guard let primary = exercise.muscleGroups.first else { continue }
            byMuscle[primary, default: []].append(exercise)
        }

        // Take top 3 per muscle group
        var topExercises: [String] = []
        for (_, exercises) in byMuscle.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let top3 = exercises.sorted { $0.name < $1.name }.prefix(3)
            topExercises.append(contentsOf: top3.map { "\($0.id): \($0.name)" })
        }

        // Excluded - just IDs
        let excludedIds = prefs.excluded.prefix(5).joined(separator: ", ")

        return """
        ## EXERCISE CONTEXT (Compact)
        Equipment: \(formatEquipment(equipment))

        **Favorites:** \(favoriteExercises.isEmpty ? "None" : favoriteExercises.joined(separator: ", "))

        **Excluded:** \(excludedIds.isEmpty ? "None" : excludedIds)

        **Top exercises by muscle:**
        \(topExercises.prefix(50).joined(separator: ", "))

        Use exact IDs above. For full vocabulary, ask user to specify exercise.
        """
    }
}

// MARK: - Learned Rules Integration

extension ExerciseContextBuilder {

    /// Build learned preferences section for AI context
    /// Shows exercises AI should prefer or deprioritize based on user behavior
    static func buildLearnedPreferencesSection(
        prefs: UserExercisePreferences,
        exercises: [String: Exercise],
        splitDay: SplitDay?
    ) -> String {
        guard !prefs.learnedRules.isEmpty else { return "" }

        // Filter rules relevant to this split (or global)
        let relevantRules = prefs.learnedRules.filter { rule in
            rule.splitDay == splitDay || rule.splitDay == nil
        }

        guard !relevantRules.isEmpty else { return "" }

        let preferred = relevantRules.filter { $0.action == .prefer || $0.action == .alwaysInclude }
        let deprioritized = relevantRules.filter { $0.action == .deprioritize || $0.action == .neverInclude }

        var lines = ["\n### LEARNED PREFERENCES"]

        if !preferred.isEmpty {
            lines.append("**User tends to prefer:**")
            for rule in preferred.prefix(5) {
                if let exercise = exercises[rule.exerciseId] {
                    lines.append("- \(exercise.name) (added to workouts)")
                }
            }
        }

        if !deprioritized.isEmpty {
            lines.append("**User tends to skip:**")
            for rule in deprioritized.prefix(5) {
                if let exercise = exercises[rule.exerciseId] {
                    lines.append("- \(exercise.name) (removed from workouts)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}
