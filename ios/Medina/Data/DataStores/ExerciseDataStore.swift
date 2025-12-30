//
// ExerciseDataStore.swift
// Medina
//
// Last reviewed: October 2025
// v79.3: Added baseExercise search and grouping methods
//

import Foundation

enum ExerciseDataStore {

    private static var manager: LocalDataStore { LocalDataStore.shared }

    // MARK: - Basic Retrieval

    /// Get all exercises in the system (no permission filtering - handled in resolver)
    static func allExercises() -> [Exercise] {
        return Array(manager.exercises.values)
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Get a specific exercise by ID
    static func exercise(byId id: String) -> Exercise? {
        return manager.exercises[id]
    }

    /// Get multiple exercises by IDs, preserving order
    static func exercises(forIds ids: [String]) -> [Exercise] {
        return ids.compactMap { manager.exercises[$0] }
    }

    // MARK: - Filtering Methods

    /// Get exercises by equipment type
    static func exercises(byEquipment equipment: Equipment) -> [Exercise] {
        return allExercises().filter { $0.equipment == equipment }
    }

    /// Get exercises by type (compound, isolation, etc.)
    static func exercises(byType type: ExerciseType) -> [Exercise] {
        return allExercises().filter { $0.type == type }
    }

    /// Get exercises by muscle group
    static func exercises(byMuscleGroup muscleGroup: MuscleGroup) -> [Exercise] {
        return allExercises().filter { $0.muscleGroups.contains(muscleGroup) }
    }

    /// Get exercises by movement pattern
    static func exercises(byMovementPattern pattern: MovementPattern) -> [Exercise] {
        return allExercises().filter { $0.movementPattern == pattern }
    }

    /// Get exercises by experience level
    static func exercises(byExperienceLevel level: ExperienceLevel) -> [Exercise] {
        return allExercises().filter { $0.experienceLevel == level }
    }

    // MARK: - Search Methods

    /// Search exercises by name, description, and baseExercise
    /// v79.3: Enhanced to include baseExercise in search
    static func searchExercises(query: String) -> [Exercise] {
        let lowercaseQuery = query.lowercased()
        return allExercises().filter { exercise in
            exercise.name.lowercased().contains(lowercaseQuery) ||
            exercise.description.lowercased().contains(lowercaseQuery) ||
            exercise.baseExercise.lowercased().contains(lowercaseQuery.replacingOccurrences(of: " ", with: "_"))
        }
    }

    // MARK: - BaseExercise Methods (v79.3)

    /// Get all variants of a base exercise (e.g., all "deadlift" variants)
    /// Returns exercises sorted by equipment preference (barbell first, then dumbbells, etc.)
    static func variants(ofBaseExercise baseExercise: String) -> [Exercise] {
        return allExercises()
            .filter { $0.baseExercise == baseExercise }
            .sorted { equipmentSortOrder($0.equipment) < equipmentSortOrder($1.equipment) }
    }

    /// Get one representative exercise per baseExercise (for grouped library display)
    /// Returns the "primary" variant (typically barbell) for each base exercise
    static func uniqueBaseExercises() -> [Exercise] {
        let grouped = exercisesGroupedByBase()
        return grouped.values
            .compactMap { variants in
                // Return the variant with lowest equipment sort order (barbell preferred)
                variants.min { equipmentSortOrder($0.equipment) < equipmentSortOrder($1.equipment) }
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Get all exercises grouped by their baseExercise field
    /// Key: baseExercise string, Value: array of Exercise variants
    static func exercisesGroupedByBase() -> [String: [Exercise]] {
        return Dictionary(grouping: allExercises()) { $0.baseExercise }
    }

    /// Get all unique baseExercise identifiers
    static func allBaseExerciseIds() -> [String] {
        return Array(Set(allExercises().map { $0.baseExercise })).sorted()
    }

    /// Count of variants for a given baseExercise
    static func variantCount(forBaseExercise baseExercise: String) -> Int {
        return allExercises().filter { $0.baseExercise == baseExercise }.count
    }

    /// Find exercises with same baseExercise but different equipment (for equipment swap)
    static func alternateEquipmentVariants(for exercise: Exercise) -> [Exercise] {
        return variants(ofBaseExercise: exercise.baseExercise)
            .filter { $0.id != exercise.id }
    }

    /// Equipment sort order for consistent variant display
    /// Lower number = higher priority (shown first)
    private static func equipmentSortOrder(_ equipment: Equipment) -> Int {
        switch equipment {
        case .barbell: return 0
        case .dumbbells: return 1
        case .kettlebell: return 2
        case .cableMachine: return 3
        case .machine: return 4
        case .bodyweight: return 5
        case .pullupBar, .dipStation: return 6
        default: return 10
        }
    }

    // MARK: - Ownership Queries

    /// Get all global exercises (no creator fields set)
    static func globalExercises() -> [Exercise] {
        return allExercises().filter { exercise in
            exercise.createdByMemberId == nil &&
            exercise.createdByTrainerId == nil &&
            exercise.createdByGymId == nil
        }
    }

    /// Get exercises created by a specific gym
    static func exercises(createdByGymId gymId: String) -> [Exercise] {
        return allExercises().filter { $0.createdByGymId == gymId }
    }

    /// Get exercises created by a specific trainer
    static func exercises(createdByTrainerId trainerId: String) -> [Exercise] {
        return allExercises().filter { $0.createdByTrainerId == trainerId }
    }

    /// Get exercises created by a specific member
    static func exercises(createdByMemberId memberId: String) -> [Exercise] {
        return allExercises().filter { $0.createdByMemberId == memberId }
    }
}
