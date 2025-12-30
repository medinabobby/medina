//
// InstanceResolver.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

enum InstanceResolver {

    // MARK: - Permission-Aware Resolution

    /// Get all instances visible to the user (permission-filtered by workout access)
    static func allInstances(for userContext: UserContext) -> [ExerciseInstance] {
        let allInstances = InstanceDataStore.allInstances()
        return allInstances.filter { hasPermission(toView: $0, userContext: userContext) }
    }

    /// Get instances for a specific workout (permission-filtered)
    static func instances(forWorkout workout: Workout, for userContext: UserContext) -> [ExerciseInstance] {
        // First check if user has permission to view the workout
        guard hasWorkoutPermission(workout: workout, userContext: userContext) else {
            return []
        }

        return InstanceDataStore.instances(forWorkout: workout.id)
    }

    /// Get instance for a specific exercise in a workout (permission-filtered)
    static func instance(forExercise exerciseId: String, inWorkout workout: Workout, for userContext: UserContext) -> ExerciseInstance? {
        guard hasWorkoutPermission(workout: workout, userContext: userContext) else {
            return nil
        }

        return InstanceDataStore.instance(forExercise: exerciseId, inWorkout: workout.id)
    }

    /// Get sets for an instance (permission-filtered)
    static func sets(forInstance instance: ExerciseInstance, for userContext: UserContext) -> [ExerciseSet] {
        guard hasPermission(toView: instance, userContext: userContext) else {
            return []
        }

        return InstanceDataStore.sets(forInstance: instance.id)
    }

    // MARK: - Instance with Exercise Data

    /// Get instances with their corresponding exercises for a workout
    static func instancesWithExercises(forWorkout workout: Workout, for userContext: UserContext) -> [(instance: ExerciseInstance, exercise: Exercise)] {
        let instances = instances(forWorkout: workout, for: userContext)

        return instances.compactMap { instance in
            guard let exercise = ExerciseResolver.exercise(byId: instance.exerciseId, for: userContext) else {
                return nil
            }
            return (instance: instance, exercise: exercise)
        }
    }

    /// Get instances for a specific exercise (permission-filtered, sorted by date)
    /// Returns instances with their workouts, sorted by most recent first
    /// Backed by LocalDataStore.shared.exerciseInstances
    static func instancesForExercise(
        exerciseId: String,
        for userContext: UserContext,
        limit: Int? = nil
    ) -> [(instance: ExerciseInstance, workout: Workout)] {
        // Get all instances for this exercise
        let exerciseInstances = InstanceDataStore.allInstances()
            .filter { $0.exerciseId == exerciseId }

        // Filter by permissions and attach workout data
        let instancesWithWorkouts = exerciseInstances.compactMap { instance -> (ExerciseInstance, Workout)? in
            guard hasPermission(toView: instance, userContext: userContext) else {
                return nil
            }

            guard let workout = LocalDataStore.shared.workouts[instance.workoutId] else {
                return nil
            }

            return (instance, workout)
        }

        // Sort by workout date (most recent first)
        let sorted = instancesWithWorkouts.sorted { first, second in
            let date1 = first.1.scheduledDate ?? Date.distantPast
            let date2 = second.1.scheduledDate ?? Date.distantPast
            return date1 > date2  // Descending order (most recent first)
        }

        // Apply limit if specified
        if let limit = limit {
            return Array(sorted.prefix(limit))
        }

        return sorted
    }

    // MARK: - Permission Checking

    /// Check if user has permission to view an instance (based on workout access)
    private static func hasPermission(toView instance: ExerciseInstance, userContext: UserContext) -> Bool {
        // Get the workout for this instance
        guard let workout = LocalDataStore.shared.workouts[instance.workoutId] else {
            return false
        }

        return hasWorkoutPermission(workout: workout, userContext: userContext)
    }

    /// Check if user has permission to view a workout
    private static func hasWorkoutPermission(workout: Workout, userContext: UserContext) -> Bool {
        // For v16.0, use simplified permission model:
        // If the workout is in their accessible workouts (via WorkoutDataStore), they can see it

        // Get the program for this workout
        guard let program = LocalDataStore.shared.programs[workout.programId] else {
            return false
        }

        // Get the plan for this program
        let plans = PlanResolver.allPlans(for: userContext.userId)
        let hasPlanAccess = plans.contains { $0.id == program.planId }

        return hasPlanAccess
    }

    // MARK: - Convenience Methods

    /// Get completion summary for an instance
    static func summary(forInstance instance: ExerciseInstance, for userContext: UserContext) -> InstanceSummary? {
        guard hasPermission(toView: instance, userContext: userContext) else {
            return nil
        }

        return InstanceDataStore.instanceSummary(for: instance)
    }

    /// Check if an instance exists and is visible to user
    static func instanceExists(id: String, for userContext: UserContext) -> Bool {
        guard let instance = InstanceDataStore.instance(byId: id) else {
            return false
        }
        return hasPermission(toView: instance, userContext: userContext)
    }
}
