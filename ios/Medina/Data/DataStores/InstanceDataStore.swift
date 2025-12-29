//
// InstanceDataStore.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

enum InstanceDataStore {

    private static var manager: TestDataManager { TestDataManager.shared }

    // MARK: - Instance Retrieval

    /// Get all instances in the system (no permission filtering - handled in resolver)
    static func allInstances() -> [ExerciseInstance] {
        return Array(manager.exerciseInstances.values)
    }

    /// Get a specific instance by ID
    static func instance(byId id: String) -> ExerciseInstance? {
        return manager.exerciseInstances[id]
    }

    /// Get instances for a specific workout (sorted by workout.exerciseIds order)
    static func instances(forWorkout workoutId: String) -> [ExerciseInstance] {
        let instances = allInstances().filter { $0.workoutId == workoutId }

        // Sort by workout.exerciseIds order (maintains exercise sequence)
        guard let workout = manager.workouts[workoutId] else {
            return instances
        }

        return instances.sorted { lhs, rhs in
            let lhsIndex = workout.exerciseIds.firstIndex(of: lhs.exerciseId) ?? Int.max
            let rhsIndex = workout.exerciseIds.firstIndex(of: rhs.exerciseId) ?? Int.max
            return lhsIndex < rhsIndex
        }
    }

    /// Get instance for a specific exercise in a workout
    static func instance(forExercise exerciseId: String, inWorkout workoutId: String) -> ExerciseInstance? {
        return allInstances().first { $0.exerciseId == exerciseId && $0.workoutId == workoutId }
    }

    // MARK: - Set Retrieval

    /// Get all sets for a specific instance
    static func sets(forInstance instanceId: String) -> [ExerciseSet] {
        return allSets().filter { $0.exerciseInstanceId == instanceId }
            .sorted { $0.setNumber < $1.setNumber }
    }

    /// Get all sets in the system
    private static func allSets() -> [ExerciseSet] {
        return Array(manager.exerciseSets.values)
    }

    /// Get a specific set by ID
    static func set(byId id: String) -> ExerciseSet? {
        return manager.exerciseSets[id]
    }

    // MARK: - Completion Status

    /// Get completion status for an instance
    static func completionStatus(forInstance instance: ExerciseInstance) -> ExecutionStatus {
        // v21.0: Instance status is stored directly
        return instance.status
    }

    // MARK: - Statistics

    /// Get summary statistics for an instance
    static func instanceSummary(for instance: ExerciseInstance) -> InstanceSummary {
        let sets = sets(forInstance: instance.id)
        let completedSets = sets.filter { $0.completion == .completed }

        return InstanceSummary(
            totalSets: sets.count,
            completedSets: completedSets.count,
            completion: completionStatus(forInstance: instance)
        )
    }
}

// MARK: - Supporting Types

struct InstanceSummary {
    let totalSets: Int
    let completedSets: Int
    let completion: ExecutionStatus

    var displayText: String {
        if totalSets == 0 {
            return "No sets"
        }
        return "\(completedSets)/\(totalSets) sets completed"
    }
}
