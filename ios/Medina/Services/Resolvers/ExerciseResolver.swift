//
// ExerciseResolver.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

enum ExerciseResolver {

    // MARK: - Permission-Aware Resolution

    /// Get all exercises visible to the user (permission-filtered)
    static func allExercises(for userContext: UserContext) -> [Exercise] {
        let allExercises = ExerciseDataStore.allExercises()
        return filterExercisesByPermission(allExercises, for: userContext)
    }

    /// Get a specific exercise by ID if visible to the user
    static func exercise(byId id: String, for userContext: UserContext) -> Exercise? {
        guard let exercise = ExerciseDataStore.exercise(byId: id) else {
            return nil
        }
        return hasPermission(toView: exercise, userContext: userContext) ? exercise : nil
    }

    /// Get multiple exercises by IDs (preserves order), filtered by permissions
    static func exercises(forIds ids: [String], for userContext: UserContext) -> [Exercise] {
        let exercises = ExerciseDataStore.exercises(forIds: ids)
        return filterExercisesByPermission(exercises, for: userContext)
    }

    /// Get exercises for a specific workout
    static func exercises(forWorkout workout: Workout, for userContext: UserContext) -> [Exercise] {
        return exercises(forIds: workout.exerciseIds, for: userContext)
    }

    // MARK: - Search & Filtering

    /// Search exercises by name (permission-filtered)
    static func searchExercises(query: String, for userContext: UserContext) -> [Exercise] {
        let results = ExerciseDataStore.searchExercises(query: query)
        return filterExercisesByPermission(results, for: userContext)
    }

    /// Get exercises by equipment (permission-filtered)
    static func exercises(byEquipment equipment: Equipment, for userContext: UserContext) -> [Exercise] {
        let exercises = ExerciseDataStore.exercises(byEquipment: equipment)
        return filterExercisesByPermission(exercises, for: userContext)
    }

    /// Get exercises by type (permission-filtered)
    static func exercises(byType type: ExerciseType, for userContext: UserContext) -> [Exercise] {
        let exercises = ExerciseDataStore.exercises(byType: type)
        return filterExercisesByPermission(exercises, for: userContext)
    }

    /// Get exercises by muscle group (permission-filtered)
    static func exercises(byMuscleGroup muscleGroup: MuscleGroup, for userContext: UserContext) -> [Exercise] {
        let exercises = ExerciseDataStore.exercises(byMuscleGroup: muscleGroup)
        return filterExercisesByPermission(exercises, for: userContext)
    }

    /// Get exercises by movement pattern (permission-filtered)
    static func exercises(byMovementPattern pattern: MovementPattern, for userContext: UserContext) -> [Exercise] {
        let exercises = ExerciseDataStore.exercises(byMovementPattern: pattern)
        return filterExercisesByPermission(exercises, for: userContext)
    }

    // MARK: - Permission Filtering Logic

    /// Filter exercises based on user permissions
    private static func filterExercisesByPermission(_ exercises: [Exercise], for userContext: UserContext) -> [Exercise] {
        return exercises.filter { hasPermission(toView: $0, userContext: userContext) }
    }

    /// Check if user has permission to view a specific exercise
    private static func hasPermission(toView exercise: Exercise, userContext: UserContext) -> Bool {
        // Get current user
        guard let currentUser = LocalDataStore.shared.users[userContext.userId] else {
            return false
        }

        // 1. Global exercises (all createdBy* fields are null) - visible to all
        if exercise.createdByMemberId == nil &&
           exercise.createdByTrainerId == nil &&
           exercise.createdByGymId == nil {
            return true
        }

        // 2. Gym exercises (createdByGymId set) - visible to gym members/trainers/admins
        if let gymId = exercise.createdByGymId {
            if currentUser.gymId == gymId {
                return true
            }
        }

        // 3. Trainer exercises (createdByTrainerId set) - visible to trainer + assigned members
        if let trainerId = exercise.createdByTrainerId {
            // Creator trainer can see it
            if currentUser.id == trainerId {
                return true
            }
            // Member assigned to this trainer can see it
            if let memberProfile = currentUser.memberProfile,
               memberProfile.trainerId == trainerId {
                return true
            }
        }

        // 4. Member exercises (createdByMemberId set) - visible only to that member
        if let memberId = exercise.createdByMemberId {
            if currentUser.id == memberId {
                return true
            }
        }

        // No permission found
        return false
    }

    // MARK: - Convenience Methods

    /// Get exercise count visible to user
    static func exerciseCount(for userContext: UserContext) -> Int {
        return allExercises(for: userContext).count
    }

    /// Check if exercise exists and is visible to user
    static func exerciseExists(id: String, for userContext: UserContext) -> Bool {
        return exercise(byId: id, for: userContext) != nil
    }

    /// Get exercise statistics for user
    static func exerciseStats(for userContext: UserContext) -> ExerciseStats {
        let exercises = allExercises(for: userContext)

        let globalCount = exercises.filter { exercise in
            exercise.createdByMemberId == nil &&
            exercise.createdByTrainerId == nil &&
            exercise.createdByGymId == nil
        }.count

        let customCount = exercises.count - globalCount

        let compoundCount = exercises.filter { $0.type == .compound }.count
        let isolationCount = exercises.filter { $0.type == .isolation }.count

        return ExerciseStats(
            totalExercises: exercises.count,
            globalExercises: globalCount,
            customExercises: customCount,
            compoundExercises: compoundCount,
            isolationExercises: isolationCount
        )
    }
}

// MARK: - Supporting Types

struct ExerciseStats {
    let totalExercises: Int
    let globalExercises: Int
    let customExercises: Int
    let compoundExercises: Int
    let isolationExercises: Int

    var summary: String {
        return """
        Exercise Statistics:
        • Total Exercises: \(totalExercises)
        • Global Library: \(globalExercises)
        • Custom Exercises: \(customExercises)
        • Compound: \(compoundExercises)
        • Isolation: \(isolationExercises)
        """
    }
}
