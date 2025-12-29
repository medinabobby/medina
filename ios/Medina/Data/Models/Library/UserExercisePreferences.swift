//
// UserExercisePreferences.swift
// Medina
//
// v81.0 - Exercise Selection System Redesign
// Created: December 4, 2025
//
// Purpose: User exercise preferences for AI-first selection
// Tracks favorites, exclusions, recent usage, and learned rules
// Replaces UserLibrary.exercises with richer preference data
//

import Foundation

// MARK: - Main Preferences Model

struct UserExercisePreferences: Codable, Identifiable {
    var id: String  // userId

    /// Starred exercises (binary: starred or not)
    /// These are always prioritized in AI context
    var favorites: Set<String>

    /// Explicitly excluded exercises (never suggest)
    /// User has hard-blocked these
    var excluded: Set<String>

    /// Recent exercise usage (last 30 days)
    /// Sorted by lastUsed descending
    var recentExercises: [RecentExercise]

    /// Learned rules from user modifications
    /// When user adds/removes exercises from AI workouts
    var learnedRules: [LearnedRule]

    /// Last time preferences were modified
    var lastModified: Date

    // MARK: - Initialization

    init(userId: String) {
        self.id = userId
        self.favorites = []
        self.excluded = []
        self.recentExercises = []
        self.learnedRules = []
        self.lastModified = Date()
    }

    /// Migration from UserLibrary
    /// Old exercises set becomes favorites (user already curated them)
    init(migratingFrom library: UserLibrary) {
        self.id = library.id
        self.favorites = library.exercises  // Treat old library as favorites
        self.excluded = []
        self.recentExercises = []
        self.learnedRules = []
        self.lastModified = Date()
    }

    // MARK: - Convenience Methods

    /// Check if exercise is favorited
    func isFavorite(_ exerciseId: String) -> Bool {
        favorites.contains(exerciseId)
    }

    /// Check if exercise is excluded
    func isExcluded(_ exerciseId: String) -> Bool {
        excluded.contains(exerciseId)
    }

    /// Get recent exercises within last N days
    func recentExercises(withinDays days: Int) -> [RecentExercise] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return recentExercises.filter { $0.lastUsed >= cutoff }
    }

    /// Get learned preference for an exercise in a split
    func learnedPreference(for exerciseId: String, split: SplitDay?) -> RuleAction? {
        // Look for split-specific rule first
        if let split = split {
            if let rule = learnedRules.first(where: {
                $0.exerciseId == exerciseId && $0.splitDay == split
            }) {
                return rule.action
            }
        }

        // Fall back to global rule
        return learnedRules.first(where: {
            $0.exerciseId == exerciseId && $0.splitDay == nil
        })?.action
    }

    // MARK: - Mutation Methods

    /// Toggle favorite status
    mutating func toggleFavorite(_ exerciseId: String) {
        if favorites.contains(exerciseId) {
            favorites.remove(exerciseId)
        } else {
            favorites.insert(exerciseId)
            // If it was excluded, remove from excluded
            excluded.remove(exerciseId)
        }
        lastModified = Date()
    }

    /// Add to favorites
    mutating func addFavorite(_ exerciseId: String) {
        favorites.insert(exerciseId)
        excluded.remove(exerciseId)
        lastModified = Date()
    }

    /// Remove from favorites
    mutating func removeFavorite(_ exerciseId: String) {
        favorites.remove(exerciseId)
        lastModified = Date()
    }

    /// Exclude an exercise (never suggest)
    mutating func exclude(_ exerciseId: String) {
        excluded.insert(exerciseId)
        favorites.remove(exerciseId)
        lastModified = Date()
    }

    /// Remove exclusion
    mutating func removeExclusion(_ exerciseId: String) {
        excluded.remove(exerciseId)
        lastModified = Date()
    }

    /// Record exercise usage
    mutating func recordUsage(
        exerciseId: String,
        completedSets: Int,
        totalSets: Int
    ) {
        let completionRate = totalSets > 0 ? Double(completedSets) / Double(totalSets) : 1.0

        // Update or add recent exercise
        if let index = recentExercises.firstIndex(where: { $0.exerciseId == exerciseId }) {
            recentExercises[index].lastUsed = Date()
            // Rolling average of completion rate
            let oldRate = recentExercises[index].completionRate
            recentExercises[index].completionRate = (oldRate + completionRate) / 2.0
        } else {
            recentExercises.append(RecentExercise(
                exerciseId: exerciseId,
                lastUsed: Date(),
                completionRate: completionRate
            ))
        }

        // Keep only last 50 recent exercises
        if recentExercises.count > 50 {
            recentExercises.sort { $0.lastUsed > $1.lastUsed }
            recentExercises = Array(recentExercises.prefix(50))
        }

        lastModified = Date()
    }

    /// Record a learned rule from user modification
    mutating func recordLearnedRule(
        exerciseId: String,
        splitDay: SplitDay?,
        action: RuleAction,
        source: String
    ) {
        // Remove existing rule for same exercise/split
        learnedRules.removeAll {
            $0.exerciseId == exerciseId && $0.splitDay == splitDay
        }

        // Add new rule
        learnedRules.append(LearnedRule(
            exerciseId: exerciseId,
            splitDay: splitDay,
            action: action,
            source: source,
            createdAt: Date()
        ))

        // Keep only last 100 rules
        if learnedRules.count > 100 {
            learnedRules.sort { $0.createdAt > $1.createdAt }
            learnedRules = Array(learnedRules.prefix(100))
        }

        lastModified = Date()
    }

    /// Clean up old data (call periodically)
    mutating func pruneOldData() {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()

        // Remove recent exercises older than 30 days
        recentExercises.removeAll { $0.lastUsed < thirtyDaysAgo }

        // Remove learned rules older than 90 days
        learnedRules.removeAll { $0.createdAt < ninetyDaysAgo }

        lastModified = Date()
    }
}

// MARK: - Recent Exercise

struct RecentExercise: Codable, Identifiable {
    var id: String { exerciseId }

    let exerciseId: String
    var lastUsed: Date
    var completionRate: Double  // 0.0-1.0 (skipped vs completed sets)

    init(exerciseId: String, lastUsed: Date, completionRate: Double) {
        self.exerciseId = exerciseId
        self.lastUsed = lastUsed
        self.completionRate = min(1.0, max(0.0, completionRate))
    }
}

// MARK: - Learned Rule

struct LearnedRule: Codable, Identifiable {
    var id: String { "\(exerciseId)_\(splitDay?.rawValue ?? "all")_\(createdAt.timeIntervalSince1970)" }

    let exerciseId: String
    let splitDay: SplitDay?  // nil = applies to all splits
    let action: RuleAction
    let source: String  // "user_added_workout", "user_removed_workout", etc.
    let createdAt: Date
}

// MARK: - Rule Action

enum RuleAction: String, Codable {
    case prefer         // Boost in selection ranking
    case deprioritize   // Lower in selection ranking
    case alwaysInclude  // Always include when muscle group matches
    case neverInclude   // Never include (softer than excluded)
}
