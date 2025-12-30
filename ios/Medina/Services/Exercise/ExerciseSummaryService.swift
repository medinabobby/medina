//
// ExerciseSummaryService.swift
// Medina
//
// v47.6: Sidebar exercises navigation
// Created: November 3, 2025
//
// Lightweight service for sidebar exercise display
// Resolves member ownership via workout → program → plan chain
//

import Foundation

/// Lightweight service for sidebar exercise display
enum ExerciseSummaryService {

    /// Exercise summary for sidebar display
    struct ExerciseSummary {
        let exerciseId: String
        let exercise: Exercise
        let lastLoggedDate: Date?
        let current1RM: Double?
        let totalLogs: Int
    }

    /// Get recently logged exercises (completed instances within window)
    ///
    /// **Member Resolution Pattern:**
    /// Workout does NOT have memberId - must use chain:
    /// `workout.programId → program.planId → plan.memberId`
    ///
    /// - Parameters:
    ///   - memberId: User ID
    ///   - limit: Max exercises to return (default 4 for sidebar)
    ///   - window: Days to look back (default 30)
    /// - Returns: Exercises sorted by most recently logged
    static func getRecentExercises(
        memberId: String,
        limit: Int = 4,
        window: Int = 30
    ) -> [ExerciseSummary] {

        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -window,
            to: Date()
        ) ?? Date()

        // Step 1: Get all plans for this member
        let memberPlans = LocalDataStore.shared.plans.values
            .filter { $0.memberId == memberId }
        let memberPlanIds = Set(memberPlans.map { $0.id })

        // Step 2: Get programs for those plans
        let memberPrograms = LocalDataStore.shared.programs.values
            .filter { memberPlanIds.contains($0.planId) }
        let memberProgramIds = Set(memberPrograms.map { $0.id })

        // Step 3: Get workouts for those programs
        let memberWorkouts = LocalDataStore.shared.workouts.values
            .filter { memberProgramIds.contains($0.programId) }
        let workoutIds = Set(memberWorkouts.map { $0.id })

        // Step 4: Get completed instances within window
        let completedInstances = LocalDataStore.shared.exerciseInstances.values
            .filter {
                $0.status == .completed &&
                workoutIds.contains($0.workoutId)
            }

        // Group by exerciseId, track most recent date
        var exerciseActivity: [String: (date: Date, count: Int)] = [:]

        for instance in completedInstances {
            guard let workout = LocalDataStore.shared.workouts[instance.workoutId],
                  let scheduledDate = workout.scheduledDate,
                  scheduledDate >= cutoffDate else { continue }

            if let existing = exerciseActivity[instance.exerciseId] {
                exerciseActivity[instance.exerciseId] = (
                    date: max(existing.date, scheduledDate),
                    count: existing.count + 1
                )
            } else {
                exerciseActivity[instance.exerciseId] = (date: scheduledDate, count: 1)
            }
        }

        // Build summaries
        let summaries = exerciseActivity.compactMap { exerciseId, activity -> ExerciseSummary? in
            guard let exercise = LocalDataStore.shared.exercises[exerciseId] else { return nil }

            // Find 1RM target for this member + exercise
            let targetKey = "\(memberId)-\(exerciseId)"
            let target = LocalDataStore.shared.targets[targetKey]

            return ExerciseSummary(
                exerciseId: exerciseId,
                exercise: exercise,
                lastLoggedDate: activity.date,
                current1RM: target?.currentTarget,
                totalLogs: activity.count
            )
        }

        return summaries
            .sorted { ($0.lastLoggedDate ?? .distantPast) > ($1.lastLoggedDate ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    /// Get ALL tracked exercises (no time window limit)
    ///
    /// Used for "show my exercises" command to display full history
    ///
    /// - Parameter memberId: User ID
    /// - Returns: All exercises user has ever logged, sorted by most recent
    static func getAllTrackedExercises(memberId: String) -> [ExerciseSummary] {

        // Step 1: Get all plans for this member
        let memberPlans = LocalDataStore.shared.plans.values
            .filter { $0.memberId == memberId }
        let memberPlanIds = Set(memberPlans.map { $0.id })

        // Step 2: Get programs for those plans
        let memberPrograms = LocalDataStore.shared.programs.values
            .filter { memberPlanIds.contains($0.planId) }
        let memberProgramIds = Set(memberPrograms.map { $0.id })

        // Step 3: Get workouts for those programs
        let memberWorkouts = LocalDataStore.shared.workouts.values
            .filter { memberProgramIds.contains($0.programId) }
        let workoutIds = Set(memberWorkouts.map { $0.id })

        // Step 4: Get ALL completed instances (no date filter)
        let completedInstances = LocalDataStore.shared.exerciseInstances.values
            .filter {
                $0.status == .completed &&
                workoutIds.contains($0.workoutId)
            }

        // Group by exerciseId, track most recent date
        var exerciseActivity: [String: (date: Date, count: Int)] = [:]

        for instance in completedInstances {
            guard let workout = LocalDataStore.shared.workouts[instance.workoutId],
                  let scheduledDate = workout.scheduledDate else { continue }

            if let existing = exerciseActivity[instance.exerciseId] {
                exerciseActivity[instance.exerciseId] = (
                    date: max(existing.date, scheduledDate),
                    count: existing.count + 1
                )
            } else {
                exerciseActivity[instance.exerciseId] = (date: scheduledDate, count: 1)
            }
        }

        // Build summaries
        let summaries = exerciseActivity.compactMap { exerciseId, activity -> ExerciseSummary? in
            guard let exercise = LocalDataStore.shared.exercises[exerciseId] else { return nil }

            // Find 1RM target for this member + exercise
            let targetKey = "\(memberId)-\(exerciseId)"
            let target = LocalDataStore.shared.targets[targetKey]

            return ExerciseSummary(
                exerciseId: exerciseId,
                exercise: exercise,
                lastLoggedDate: activity.date,
                current1RM: target?.currentTarget,
                totalLogs: activity.count
            )
        }

        return summaries
            .sorted { ($0.lastLoggedDate ?? .distantPast) > ($1.lastLoggedDate ?? .distantPast) }
    }

    /// Get total count of exercises with logged history
    ///
    /// **Efficient count** - doesn't build full summaries, just counts unique exercises
    ///
    /// - Parameter memberId: User ID
    /// - Returns: Count of unique exercises user has logged
    static func getTotalTrackedCount(memberId: String) -> Int {

        // Step 1: Get all plans for this member
        let memberPlans = LocalDataStore.shared.plans.values
            .filter { $0.memberId == memberId }
        let memberPlanIds = Set(memberPlans.map { $0.id })

        // Step 2: Get programs for those plans
        let memberPrograms = LocalDataStore.shared.programs.values
            .filter { memberPlanIds.contains($0.planId) }
        let memberProgramIds = Set(memberPrograms.map { $0.id })

        // Step 3: Get workouts for those programs
        let memberWorkouts = LocalDataStore.shared.workouts.values
            .filter { memberProgramIds.contains($0.programId) }
        let workoutIds = Set(memberWorkouts.map { $0.id })

        // Step 4: Count unique exercises in completed instances
        let uniqueExercises = Set(
            LocalDataStore.shared.exerciseInstances.values
                .filter {
                    $0.status == .completed &&
                    workoutIds.contains($0.workoutId)
                }
                .map { $0.exerciseId }
        )

        return uniqueExercises.count
    }

    /// Get exercises from user's active plan workouts (scheduled/upcoming)
    ///
    /// Shows exercises the user is currently working on in their active plan,
    /// regardless of whether they've completed any instances yet.
    ///
    /// - Parameters:
    ///   - memberId: User ID
    ///   - limit: Max exercises to return (default 20 for sidebar)
    /// - Returns: Exercises from active plan workouts
    static func getActivePlanExercises(
        memberId: String,
        limit: Int = 20
    ) -> [ExerciseSummary] {

        // Step 1: Get active plans for this member
        let activePlans = LocalDataStore.shared.plans.values
            .filter { $0.memberId == memberId && $0.status == .active }
        let activePlanIds = Set(activePlans.map { $0.id })

        // Step 2: Get programs for those plans
        let activePrograms = LocalDataStore.shared.programs.values
            .filter { activePlanIds.contains($0.planId) }
        let activeProgramIds = Set(activePrograms.map { $0.id })

        // Step 3: Get workouts for those programs
        let activeWorkouts = LocalDataStore.shared.workouts.values
            .filter { activeProgramIds.contains($0.programId) }

        // Step 4: Collect unique exercises from all active workouts
        var exerciseUsage: [String: Int] = [:]

        for workout in activeWorkouts {
            for exerciseId in workout.exerciseIds {
                exerciseUsage[exerciseId, default: 0] += 1
            }
        }

        // Build summaries
        let summaries = exerciseUsage.compactMap { exerciseId, count -> ExerciseSummary? in
            guard let exercise = LocalDataStore.shared.exercises[exerciseId] else { return nil }

            // Find 1RM target for this member + exercise
            let targetKey = "\(memberId)-\(exerciseId)"
            let target = LocalDataStore.shared.targets[targetKey]

            return ExerciseSummary(
                exerciseId: exerciseId,
                exercise: exercise,
                lastLoggedDate: nil,
                current1RM: target?.currentTarget,
                totalLogs: count
            )
        }

        // Sort by usage count (most used exercises first)
        return summaries
            .sorted { $0.totalLogs > $1.totalLogs }
            .prefix(limit)
            .map { $0 }
    }
}
