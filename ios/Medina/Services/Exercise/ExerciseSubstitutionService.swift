//
// ExerciseSubstitutionService.swift
// Medina
//
// v61.0 - Exercise Substitution Service
// v61.1 - Added performSubstitution for UI-triggered substitution
// Finds alternative exercises based on coach-first scoring algorithm
//

import Foundation

/// Errors that can occur during exercise substitution
enum SubstitutionError: Error, LocalizedError {
    case instanceNotFound
    case workoutNotFound
    case exerciseNotInWorkout
    case exerciseNotFound
    case protocolNotFound

    var errorDescription: String? {
        switch self {
        case .instanceNotFound:
            return "Exercise instance not found"
        case .workoutNotFound:
            return "Workout not found"
        case .exerciseNotInWorkout:
            return "Exercise not found in workout"
        case .exerciseNotFound:
            return "Exercise not found"
        case .protocolNotFound:
            return "Protocol configuration not found"
        }
    }
}

/// Service for finding alternative exercises for substitution
/// Uses a coach-first scoring algorithm that prioritizes:
/// 1. Movement pattern match (same biomechanics)
/// 2. Primary muscle overlap (same training stimulus)
/// 3. baseExercise match (direct variants)
/// 4. Experience level compatibility (safety)
/// 5. Exercise type match (compound for compound)
enum ExerciseSubstitutionService {

    // MARK: - Scoring Weights (Coach-First Design)

    private static let movementPatternWeight: Double = 0.35
    private static let muscleOverlapWeight: Double = 0.30
    private static let baseExerciseWeight: Double = 0.20
    private static let experienceLevelWeight: Double = 0.10
    private static let exerciseTypeWeight: Double = 0.05

    // MARK: - Public API

    /// Find alternative exercises for a given exercise
    /// - Parameters:
    ///   - exerciseId: ID of the exercise to find alternatives for
    ///   - availableEquipment: Equipment the user has access to
    ///   - userLibrary: User's exercise library (prioritized in results)
    ///   - userExperienceLevel: User's experience level for safety filtering
    ///   - limit: Maximum number of alternatives to return
    /// - Returns: Array of substitution candidates sorted by score (highest first)
    static func findAlternatives(
        for exerciseId: String,
        availableEquipment: Set<Equipment>,
        userLibrary: UserLibrary?,
        userExperienceLevel: ExperienceLevel,
        limit: Int = 5
    ) -> [SubstitutionCandidate] {

        // Get the original exercise
        guard let originalExercise = LocalDataStore.shared.exercises[exerciseId] else {
            Logger.log(.warning, component: "ExerciseSubstitutionService",
                      message: "Exercise not found: \(exerciseId)")
            return []
        }

        Logger.log(.info, component: "ExerciseSubstitutionService",
                  message: "Finding alternatives for '\(originalExercise.name)' (equipment: \(availableEquipment.count) types)")

        // Get all exercises and filter by equipment
        let allExercises = LocalDataStore.shared.exercises.values

        // Filter: Must have equipment user has access to, and not be the original exercise
        let equipmentFiltered = allExercises.filter { exercise in
            exercise.id != exerciseId &&
            availableEquipment.contains(exercise.equipment)
        }

        Logger.log(.debug, component: "ExerciseSubstitutionService",
                  message: "Equipment filter: \(equipmentFiltered.count) exercises available")

        // Score each candidate
        var candidates: [SubstitutionCandidate] = equipmentFiltered.compactMap { candidate in
            let score = calculateScore(
                original: originalExercise,
                candidate: candidate,
                userLevel: userExperienceLevel
            )

            // Filter out very low scores (< 20%)
            guard score >= 0.20 else { return nil }

            let reasons = generateReasons(
                original: originalExercise,
                candidate: candidate,
                score: score
            )

            return SubstitutionCandidate(
                id: candidate.id,
                exercise: candidate,
                score: score,
                reasons: reasons
            )
        }

        // Boost library exercises (1.1x multiplier, capped at 1.0)
        if let library = userLibrary {
            candidates = candidates.map { candidate in
                if library.exercises.contains(candidate.id) {
                    let boostedScore = min(candidate.score * 1.1, 1.0)
                    return SubstitutionCandidate(
                        id: candidate.id,
                        exercise: candidate.exercise,
                        score: boostedScore,
                        reasons: candidate.reasons + ["In your exercise library"]
                    )
                }
                return candidate
            }
        }

        // Sort by score (highest first) and limit
        let sorted = candidates.sorted { $0.score > $1.score }
        let limited = Array(sorted.prefix(limit))

        Logger.log(.info, component: "ExerciseSubstitutionService",
                  message: "Found \(limited.count) alternatives for '\(originalExercise.name)'")

        return limited
    }

    // MARK: - Private Helpers

    /// Calculate overall similarity score between two exercises
    private static func calculateScore(
        original: Exercise,
        candidate: Exercise,
        userLevel: ExperienceLevel
    ) -> Double {
        let movementScore = movementPatternScore(original.movementPattern, candidate.movementPattern)
        let muscleScore = muscleOverlapScore(original.muscleGroups, candidate.muscleGroups)
        let baseScore = baseExerciseScore(original.baseExercise, candidate.baseExercise)
        let experienceScore = experienceLevelScore(
            originalLevel: original.experienceLevel,
            candidateLevel: candidate.experienceLevel,
            userLevel: userLevel
        )
        let typeScore = exerciseTypeScore(original.type, candidate.type)

        let totalScore = (movementScore * movementPatternWeight)
                       + (muscleScore * muscleOverlapWeight)
                       + (baseScore * baseExerciseWeight)
                       + (experienceScore * experienceLevelWeight)
                       + (typeScore * exerciseTypeWeight)

        return totalScore
    }

    /// Score based on movement pattern similarity
    /// - Returns: 1.0 for exact match, 0.5 for related patterns, 0.0 otherwise
    private static func movementPatternScore(
        _ original: MovementPattern?,
        _ candidate: MovementPattern?
    ) -> Double {
        guard let orig = original, let cand = candidate else {
            // If either is nil, no score but not a complete mismatch
            return 0.25
        }

        // Exact match
        if orig == cand {
            return 1.0
        }

        // Related patterns (fitness coach equivalents)
        let relatedPatterns: [Set<MovementPattern>] = [
            // Horizontal pressing movements
            [.horizontalPress, .push],
            // Vertical pressing movements
            [.verticalPress, .push],
            // Horizontal pulling movements
            [.horizontalPull, .pull],
            // Vertical pulling movements
            [.verticalPull, .pull],
            // Lower body dominant patterns
            [.squat, .lunge],
            // Hip dominant patterns
            [.hinge, .squat]
        ]

        for group in relatedPatterns {
            if group.contains(orig) && group.contains(cand) {
                return 0.5
            }
        }

        return 0.0
    }

    /// Score based on muscle group overlap using Jaccard similarity
    /// - Returns: Value between 0.0 and 1.0
    private static func muscleOverlapScore(
        _ original: [MuscleGroup],
        _ candidate: [MuscleGroup]
    ) -> Double {
        guard !original.isEmpty || !candidate.isEmpty else {
            return 0.0
        }

        let origSet = Set(original)
        let candSet = Set(candidate)

        // Jaccard similarity: intersection / union
        let intersection = origSet.intersection(candSet)
        let union = origSet.union(candSet)

        guard !union.isEmpty else { return 0.0 }

        // Weight primary muscle match more heavily
        var score = Double(intersection.count) / Double(union.count)

        // Bonus if primary muscles match
        if let origPrimary = original.first,
           let candPrimary = candidate.first,
           origPrimary == candPrimary {
            score = min(score + 0.2, 1.0)
        }

        return score
    }

    /// Score based on whether exercises share the same base exercise
    /// - Returns: 1.0 if same baseExercise, 0.0 otherwise
    private static func baseExerciseScore(
        _ original: String,
        _ candidate: String
    ) -> Double {
        return original == candidate ? 1.0 : 0.0
    }

    /// Score based on experience level compatibility
    /// - Returns: 1.0 if same or easier, 0.5 if one level harder, 0.0 if much harder
    private static func experienceLevelScore(
        originalLevel: ExperienceLevel,
        candidateLevel: ExperienceLevel,
        userLevel: ExperienceLevel
    ) -> Double {
        let levels: [ExperienceLevel] = [.beginner, .intermediate, .advanced, .expert]

        guard let _ = levels.firstIndex(of: originalLevel),
              let candIndex = levels.firstIndex(of: candidateLevel),
              let userIndex = levels.firstIndex(of: userLevel) else {
            return 0.5
        }

        // If candidate is at or below user's level, full score
        if candIndex <= userIndex {
            return 1.0
        }

        // If candidate is one level above user, partial score
        if candIndex == userIndex + 1 {
            return 0.5
        }

        // If candidate is much harder than user's level, low score
        return 0.0
    }

    /// Score based on exercise type match
    /// - Returns: 1.0 if same type, 0.0 otherwise
    private static func exerciseTypeScore(
        _ original: ExerciseType,
        _ candidate: ExerciseType
    ) -> Double {
        return original == candidate ? 1.0 : 0.0
    }

    /// Generate human-readable reasons for why this is a good substitute
    private static func generateReasons(
        original: Exercise,
        candidate: Exercise,
        score: Double
    ) -> [String] {
        var reasons: [String] = []

        // Movement pattern reason
        if let origPattern = original.movementPattern,
           let candPattern = candidate.movementPattern,
           origPattern == candPattern {
            reasons.append("Same movement pattern (\(origPattern.displayName.lowercased()))")
        } else if let candPattern = candidate.movementPattern {
            reasons.append("Similar \(candPattern.displayName.lowercased()) movement")
        }

        // Muscle groups reason
        let origSet = Set(original.muscleGroups)
        let candSet = Set(candidate.muscleGroups)
        let intersection = origSet.intersection(candSet)

        if !intersection.isEmpty {
            let muscleNames = intersection.prefix(3).map { $0.displayName.lowercased() }
            if intersection.count == origSet.count && intersection.count == candSet.count {
                reasons.append("Targets same muscles (\(muscleNames.joined(separator: ", ")))")
            } else {
                reasons.append("Targets \(muscleNames.joined(separator: ", "))")
            }
        }

        // Base exercise reason (direct variant)
        if original.baseExercise == candidate.baseExercise {
            reasons.append("Direct variant of the same exercise")
        }

        // Equipment reason
        if candidate.equipment == .bodyweight {
            reasons.append("No equipment needed")
        } else if candidate.equipment != original.equipment {
            reasons.append("Uses \(candidate.equipment.displayName.lowercased())")
        }

        // Experience level reason
        if candidate.experienceLevel.rawValue < original.experienceLevel.rawValue {
            reasons.append("Easier to perform")
        }

        return reasons
    }

    // MARK: - v61.1: Perform Substitution

    /// Perform exercise substitution in a workout
    /// Replaces the exercise instance with a new one using the same protocol
    /// - Parameters:
    ///   - instanceId: ID of the exercise instance to replace
    ///   - newExerciseId: ID of the new exercise to substitute
    ///   - workoutId: ID of the workout containing the instance
    ///   - userId: User ID for persistence
    /// - Throws: SubstitutionError if substitution cannot be performed
    static func performSubstitution(
        instanceId: String,
        newExerciseId: String,
        workoutId: String,
        userId: String
    ) throws {
        let manager = LocalDataStore.shared

        // 1. Get old instance
        guard let oldInstance = manager.exerciseInstances[instanceId] else {
            throw SubstitutionError.instanceNotFound
        }

        // 2. Get workout
        guard var workout = manager.workouts[workoutId] else {
            throw SubstitutionError.workoutNotFound
        }

        // 3. Find exercise position in workout
        let oldExerciseId = oldInstance.exerciseId
        guard let position = workout.exerciseIds.firstIndex(of: oldExerciseId) else {
            throw SubstitutionError.exerciseNotInWorkout
        }

        // 4. Verify new exercise exists
        guard manager.exercises[newExerciseId] != nil else {
            throw SubstitutionError.exerciseNotFound
        }

        // 5. Get the protocol config for the old instance
        guard let protocolConfig = manager.protocolConfigs[oldInstance.protocolVariantId] else {
            throw SubstitutionError.protocolNotFound
        }

        Logger.log(.info, component: "ExerciseSubstitutionService",
                  message: "Substituting exercise at position \(position): \(oldExerciseId) → \(newExerciseId)")

        // 6. Delete old sets
        let oldSetIds = oldInstance.setIds
        for setId in oldSetIds {
            manager.exerciseSets.removeValue(forKey: setId)
        }

        // 7. Delete old instance
        manager.exerciseInstances.removeValue(forKey: instanceId)

        // 8. Create new exercise instance
        let newInstanceId = "\(workoutId)_ex\(position)"
        var newSetIds: [String] = []

        // 9. Create new sets based on protocol
        for (setIndex, reps) in protocolConfig.reps.enumerated() {
            let setId = "\(newInstanceId)_set\(setIndex)"
            let set = ExerciseSet(
                id: setId,
                exerciseInstanceId: newInstanceId,
                setNumber: setIndex + 1,
                targetWeight: nil,  // Will be calculated on display
                targetReps: reps,
                targetRPE: nil,
                actualWeight: nil,
                actualReps: nil,
                completion: nil,
                startTime: nil,
                endTime: nil,
                notes: nil,
                recordedDate: nil
            )
            manager.exerciseSets[setId] = set
            newSetIds.append(setId)
        }

        // 10. Create new instance with same protocol
        let newInstance = ExerciseInstance(
            id: newInstanceId,
            exerciseId: newExerciseId,
            workoutId: workoutId,
            protocolVariantId: oldInstance.protocolVariantId,
            setIds: newSetIds,
            status: oldInstance.status,
            trainerInstructions: oldInstance.trainerInstructions,
            supersetLabel: oldInstance.supersetLabel
        )
        manager.exerciseInstances[newInstanceId] = newInstance

        // 11. Update workout.exerciseIds
        workout.exerciseIds[position] = newExerciseId
        manager.workouts[workoutId] = workout

        // 12. Update workout.protocolVariantIds if needed (keep same protocol)
        // Protocol stays the same, no change needed

        Logger.log(.info, component: "ExerciseSubstitutionService",
                  message: "Successfully substituted exercise. New instance: \(newInstanceId)")

        // v82.3: Record learned rules from substitution
        // This teaches AI: user prefers newExercise over oldExercise for this split
        var prefs = manager.userExercisePreferences(for: userId)
        let splitDay = workout.splitDay

        // Deprioritize the removed exercise for this split
        prefs.recordLearnedRule(
            exerciseId: oldExerciseId,
            splitDay: splitDay,
            action: .deprioritize,
            source: "user_substituted_away"
        )

        // Prefer the new exercise for this split
        prefs.recordLearnedRule(
            exerciseId: newExerciseId,
            splitDay: splitDay,
            action: .prefer,
            source: "user_substituted_to"
        )

        manager.exercisePreferences[userId] = prefs

        Logger.log(.info, component: "ExerciseSubstitutionService",
                  message: "v82.3: Recorded learned rules - deprioritize \(oldExerciseId), prefer \(newExerciseId) for \(splitDay?.displayName ?? "all splits")")

        // v206: Sync to Firestore (fire-and-forget)
        // Note: Removed legacy disk persistence - Firestore is source of truth
        let workoutToSync = workout
        Task {
            do {
                let instances = manager.exerciseInstances.values.filter { $0.workoutId == workoutId }
                let instanceIds = Set(instances.map { $0.id })
                let sets = manager.exerciseSets.values.filter { instanceIds.contains($0.exerciseInstanceId) }

                try await FirestoreWorkoutRepository.shared.saveFullWorkout(
                    workout: workoutToSync,
                    instances: Array(instances),
                    sets: Array(sets),
                    memberId: userId
                )
            } catch {
                Logger.log(.warning, component: "ExerciseSubstitutionService",
                          message: "⚠️ Firestore sync failed: \(error)")
            }
        }
    }
}
