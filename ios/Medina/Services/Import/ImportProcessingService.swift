//
// ImportProcessingService.swift
// Medina
//
// v74.6: Common import processing logic
// Shared by CSV, PDF, Photo, and Chat imports
// v74.7: Updated to use OneRMCalculationService (Epley + quality scoring)
// v75.0: Added ImportIntelligenceService integration for experience/style inference
// v79.5: Added historical workout creation from imports
// Created: December 2, 2025
//

import Foundation

// MARK: - Import Result

/// Result of processing imported workout data
struct ImportProcessingResult {
    let importData: ImportedWorkoutData
    let targets: [ExerciseTarget]
    let matchedExerciseIds: [String]
    let unmatchedExercises: [String]
    let intelligence: ImportIntelligence?  // v75.0: Inferred experience, style, muscles
    let historicalWorkouts: [Workout]       // v79.5: Created historical workout records

    /// Summary for chat display
    var summary: ImportSummary {
        // Deduplicate matched exercise IDs (multiple CSV names may map to same exercise)
        let uniqueMatchedIds = Set(matchedExerciseIds)

        return ImportSummary(
            sessionCount: importData.sessionCount,
            exerciseCount: importData.exercises.count,
            totalSets: importData.totalSets,
            matchedCount: uniqueMatchedIds.count,  // Use deduplicated count
            unmatchedCount: unmatchedExercises.count,
            dateRange: importData.dateRange,
            topExercises: getTopExercises(),
            intelligence: intelligence  // v75.0
        )
    }

    private func getTopExercises() -> [(name: String, max: Double)] {
        // Group by matched exercise ID to deduplicate (e.g., "Squats" and "Squat" → same exercise)
        var bestByExerciseId: [String: (name: String, max: Double)] = [:]

        for ex in importData.exercises {
            guard let max = ex.effectiveMax else { continue }
            let key = ex.matchedExerciseId ?? ex.exerciseName  // Use ID if matched, else name

            if let existing = bestByExerciseId[key] {
                if max > existing.max {
                    bestByExerciseId[key] = (ex.exerciseName, max)
                }
            } else {
                bestByExerciseId[key] = (ex.exerciseName, max)
            }
        }

        return bestByExerciseId.values
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { ($0.0, $0.1) }
    }
}

/// Summary data for chat display
struct ImportSummary {
    let sessionCount: Int
    let exerciseCount: Int
    let totalSets: Int
    let matchedCount: Int
    let unmatchedCount: Int
    let dateRange: (start: Date, end: Date)?
    let topExercises: [(name: String, max: Double)]
    let intelligence: ImportIntelligence?  // v75.0

    /// Format as chat message
    func formatForChat() -> String {
        var lines: [String] = []

        lines.append("I've imported your workout history! Here's what I found:")
        lines.append("")

        // Stats
        if sessionCount > 0 {
            if let range = dateRange {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                lines.append("**\(sessionCount) workouts** from \(formatter.string(from: range.start)) - \(formatter.string(from: range.end))")
            } else {
                lines.append("**\(sessionCount) workouts** imported")
            }
        }
        lines.append("**\(matchedCount) exercises** matched to library")
        lines.append("**\(totalSets) sets** recorded")
        lines.append("")

        // v75.0: Training profile insights from intelligence
        if let intel = intelligence {
            lines.append("**Training Profile:**")
            if let level = intel.inferredExperience {
                lines.append("• Experience: **\(level.displayName)**")
            }
            if let style = intel.trainingStyle {
                lines.append("• Style: **\(style.displayName)**")
            }
            if !intel.topMuscleGroups.isEmpty {
                let muscles = intel.topMuscleGroups.prefix(3).map { $0.displayName }.joined(separator: ", ")
                lines.append("• Top focus: **\(muscles)**")
            }
            lines.append("")
        }

        // Top exercises with 1RMs
        if !topExercises.isEmpty {
            lines.append("**Your estimated maxes:**")
            for (name, max) in topExercises {
                lines.append("• \(name): \(Int(max)) lbs")
            }
            lines.append("")
        }

        // Unmatched warning
        if unmatchedCount > 0 {
            lines.append("⚠️ **\(unmatchedCount) exercises** couldn't be matched to the library.")
        }

        lines.append("")
        lines.append("Your profile has been updated! I'll use this to personalize your training.")

        return lines.joined(separator: "\n")
    }
}

// MARK: - Import Processing Service

struct ImportProcessingService {

    // MARK: - Main Processing

    /// Process imported workout data - creates targets, adds to library, stores history
    /// - Parameters:
    ///   - importData: The imported workout data to process
    ///   - userId: User ID to associate with import
    ///   - createHistoricalWorkouts: If true, creates actual Workout records in addition to targets
    @MainActor
    static func process(
        _ importData: ImportedWorkoutData,
        userId: String,
        createHistoricalWorkouts: Bool = true  // v79.5: Default to creating historical workouts
    ) throws -> ImportProcessingResult {
        // 1. Create exercise targets from aggregated data
        let targets = createExerciseTargets(from: importData, userId: userId)

        // 2. Identify matched vs unmatched exercises
        let matchedExerciseIds = targets.map { $0.exerciseId }
        let unmatchedExercises = importData.exercises
            .filter { $0.matchedExerciseId == nil }
            .map { $0.exerciseName }

        // 3. Save targets to storage
        for target in targets {
            TestDataManager.shared.targets[target.id] = target
        }

        // 4. Add exercises to user's library
        if !matchedExerciseIds.isEmpty {
            try LibraryPersistenceService.addExercises(matchedExerciseIds, userId: userId)
        }

        // 5. Store the import data for history
        storeImportData(importData, userId: userId)

        // 6. v75.0: Extract intelligence from import data
        let userWeight = TestDataManager.shared.users[userId]?.memberProfile?.currentWeight
        let intelligence = ImportIntelligenceService.analyze(
            importData: importData,
            userWeight: userWeight
        )

        // 7. v75.0: Update user profile with inferred data
        updateProfileFromIntelligence(intelligence, userId: userId)

        // 8. v79.5: Create historical workout records if requested
        var historicalWorkouts: [Workout] = []
        if createHistoricalWorkouts && !importData.sessions.isEmpty {
            historicalWorkouts = HistoricalWorkoutService.createHistoricalWorkouts(
                from: importData.sessions,
                memberId: userId,
                source: importData.source
            )
            Logger.log(.info, component: "ImportProcessingService",
                       message: "Created \(historicalWorkouts.count) historical workout records")
        }

        Logger.log(.info, component: "ImportProcessingService",
                   message: "Processed import: \(targets.count) targets, \(importData.sessionCount) sessions")

        return ImportProcessingResult(
            importData: importData,
            targets: targets,
            matchedExerciseIds: matchedExerciseIds,
            unmatchedExercises: unmatchedExercises,
            intelligence: intelligence,
            historicalWorkouts: historicalWorkouts
        )
    }

    // MARK: - Exercise Matching

    /// Match exercise name to library (fuzzy matching)
    static func matchExerciseToLibrary(_ name: String) -> String? {
        let normalizedName = name.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)

        // Check exact matches first
        for (id, exercise) in TestDataManager.shared.exercises {
            let exerciseName = exercise.name.lowercased()
            if exerciseName == normalizedName {
                return id
            }
        }

        // Check partial matches
        for (id, exercise) in TestDataManager.shared.exercises {
            let exerciseName = exercise.name.lowercased()

            // "Squats" → "squat", "Deadlifts" → "deadlift"
            let singularName = normalizedName.hasSuffix("s")
                ? String(normalizedName.dropLast())
                : normalizedName

            if exerciseName.contains(singularName) || singularName.contains(exerciseName) {
                return id
            }
        }

        return nil
    }

    /// Batch match multiple exercise names
    static func matchExercises(_ names: [String]) -> [String: String?] {
        var results: [String: String?] = [:]
        for name in names {
            results[name] = matchExerciseToLibrary(name)
        }
        return results
    }

    // MARK: - 1RM Calculation

    /// Calculate 1RM using Epley formula (via OneRMCalculationService)
    /// Epley is more accurate for 3-10 reps than Brzycki
    static func calculate1RM(weight: Double, reps: Int) -> Double? {
        return OneRMCalculationService.calculate(weight: weight, reps: reps)
    }

    /// Calculate best 1RM from a set of ImportedSets using quality-weighted selection
    /// Quality factors: rep accuracy (3-5 best) + freshness (earlier sets better)
    static func calculateBest1RM(from sets: [ImportedSet]) -> Double? {
        return OneRMCalculationService.calculateFromImportedSets(sets)
    }

    // MARK: - Target Creation

    /// Create ExerciseTarget records from import data
    static func createExerciseTargets(from importData: ImportedWorkoutData, userId: String) -> [ExerciseTarget] {
        var targets: [ExerciseTarget] = []

        // Create target for each matched exercise with a valid 1RM
        for exercise in importData.exercises {
            guard let exerciseId = exercise.matchedExerciseId,
                  let rm = exercise.effectiveMax else { continue }

            let target = ExerciseTarget(
                id: "\(userId)-\(exerciseId)",
                exerciseId: exerciseId,
                memberId: userId,
                targetType: .max,
                currentTarget: rm,
                lastCalibrated: Date(),
                targetHistory: [
                    ExerciseTarget.TargetEntry(
                        date: Date(),
                        target: rm,
                        calibrationSource: importData.source.displayName
                    )
                ]
            )
            targets.append(target)
        }

        return targets
    }

    // MARK: - Storage

    /// Store import data for historical lookup
    @MainActor
    private static func storeImportData(_ importData: ImportedWorkoutData, userId: String) {
        // Add to TestDataManager's import storage
        if TestDataManager.shared.importedData[userId] == nil {
            TestDataManager.shared.importedData[userId] = []
        }
        TestDataManager.shared.importedData[userId]?.append(importData)

        Logger.log(.info, component: "ImportProcessingService",
                   message: "Stored import data: \(importData.id) for user \(userId)")
    }

    // MARK: - Session Helpers

    /// Get all sessions for a specific exercise across all imports
    @MainActor
    static func getSessionsForExercise(_ exerciseId: String, userId: String) -> [ImportedSessionExercise] {
        guard let imports = TestDataManager.shared.importedData[userId] else { return [] }

        var results: [ImportedSessionExercise] = []

        for importData in imports {
            for session in importData.sessions {
                let matching = session.exercises.filter { $0.matchedExerciseId == exerciseId }
                results.append(contentsOf: matching)
            }
        }

        return results.sorted { ($0.estimated1RM ?? 0) > ($1.estimated1RM ?? 0) }
    }

    // MARK: - v75.0 Profile Intelligence Update

    /// Update user profile from inferred intelligence
    /// Only updates if confidence is high enough and field is at default/nil
    @MainActor
    private static func updateProfileFromIntelligence(_ intelligence: ImportIntelligence, userId: String) {
        guard var user = TestDataManager.shared.users[userId] else {
            Logger.log(.warning, component: "ImportProcessingService",
                       message: "Cannot update profile: user not found")
            return
        }
        guard var profile = user.memberProfile else {
            Logger.log(.warning, component: "ImportProcessingService",
                       message: "Cannot update profile: no member profile")
            return
        }

        var updated = false

        // Update experience level if:
        // - Currently at beginner (default), OR
        // - High confidence (>0.7)
        if let inferredLevel = intelligence.inferredExperience {
            if profile.experienceLevel == .beginner || intelligence.confidenceScore > 0.7 {
                profile.experienceLevel = inferredLevel
                updated = true
                Logger.log(.info, component: "ImportProcessingService",
                           message: "Updated experience level to \(inferredLevel.displayName)")
            }
        }

        // Update emphasized muscles (merge with existing, don't overwrite)
        if !intelligence.topMuscleGroups.isEmpty {
            if let existing = profile.emphasizedMuscleGroups {
                // Merge: keep user preferences + add import insights
                profile.emphasizedMuscleGroups = existing.union(intelligence.topMuscleGroups)
            } else {
                profile.emphasizedMuscleGroups = intelligence.topMuscleGroups
            }
            updated = true
        }

        // Update split type preference (only if not set)
        if profile.preferredSplitType == nil, let inferredSplit = intelligence.inferredSplit {
            profile.preferredSplitType = inferredSplit
            updated = true
            Logger.log(.info, component: "ImportProcessingService",
                       message: "Updated preferred split to \(inferredSplit.displayName)")
        }

        // Update session duration (only if still at default 60 min)
        if profile.preferredSessionDuration == 60 && intelligence.estimatedSessionDuration != 60 {
            profile.preferredSessionDuration = intelligence.estimatedSessionDuration
            updated = true
            Logger.log(.info, component: "ImportProcessingService",
                       message: "Updated session duration to \(intelligence.estimatedSessionDuration) min")
        }

        // Save if anything changed
        if updated {
            user.memberProfile = profile
            TestDataManager.shared.users[userId] = user

            // v206: Sync to Firestore (fire-and-forget)
            Task {
                do {
                    try await FirestoreUserRepository.shared.saveUser(user)
                    Logger.log(.info, component: "ImportProcessingService",
                               message: "☁️ Profile updated from import intelligence")
                } catch {
                    Logger.log(.warning, component: "ImportProcessingService",
                               message: "⚠️ Firestore sync failed: \(error)")
                }
            }
        }
    }
}
