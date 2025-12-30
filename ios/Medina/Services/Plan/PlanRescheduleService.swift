//
// PlanRescheduleService.swift
// Medina
//
// v69.4 - Plan Rescheduling Service
// Created: November 2025
//
// Purpose: Reschedule existing plans without losing completed workout progress
// Preserves completed/in-progress workouts, regenerates scheduled (future) workouts
//

import Foundation

/// Errors that can occur during plan rescheduling
enum PlanRescheduleError: LocalizedError {
    case notEnoughDays(message: String)
    case cannotRescheduleCompleted(message: String)
    case persistenceError(message: String)

    var errorDescription: String? {
        switch self {
        case .notEnoughDays(let message): return message
        case .cannotRescheduleCompleted(let message): return message
        case .persistenceError(let message): return message
        }
    }
}

/// Service for rescheduling existing plans
enum PlanRescheduleService {

    /// Result of rescheduling operation
    struct RescheduleResult {
        let plan: Plan
        let rescheduledCount: Int   // Future workouts regenerated
        let preservedCount: Int     // Completed workouts kept
        let deletedCount: Int       // Scheduled workouts that were removed
    }

    // MARK: - Public API

    /// Reschedule an existing plan with new preferred days
    /// - Parameters:
    ///   - plan: The plan to reschedule
    ///   - newPreferredDays: New set of training days
    ///   - newDaysPerWeek: New total days per week (optional)
    ///   - newCardioDays: New number of cardio days (optional - keeps existing if nil)
    ///   - dayAssignments: AI-provided day→type mapping (optional)
    ///   - userId: The user ID for persistence
    /// - Returns: RescheduleResult with statistics
    static func reschedule(
        plan: Plan,
        newPreferredDays: Set<DayOfWeek>,
        newDaysPerWeek: Int? = nil,
        newCardioDays: Int? = nil,
        dayAssignments: [DayOfWeek: SessionType]? = nil,
        userId: String
    ) async throws -> RescheduleResult {

        // 1. Validate: Cannot reschedule completed plans
        guard plan.status != .completed else {
            throw PlanRescheduleError.cannotRescheduleCompleted(
                message: "Cannot reschedule completed plan '\(plan.name)'. Create a new plan instead."
            )
        }

        // 2. Get all programs for this plan
        let programs = Array(LocalDataStore.shared.programs.values.filter { $0.planId == plan.id })
        let programIds = Set(programs.map { $0.id })

        // 3. Get all workouts for this plan
        let allWorkouts = Array(LocalDataStore.shared.workouts.values.filter { programIds.contains($0.programId) })

        // 4. Separate completed vs scheduled workouts
        let completedWorkouts = allWorkouts.filter { $0.status == .completed || $0.status == .inProgress }
        let scheduledWorkouts = allWorkouts.filter { $0.status == .scheduled || $0.status == .skipped }

        Logger.log(.info, component: "PlanRescheduleService",
                  message: "📅 Rescheduling plan '\(plan.name)': \(completedWorkouts.count) completed, \(scheduledWorkouts.count) scheduled")

        // 5. Delete scheduled (future) workouts and their instances/sets
        for workout in scheduledWorkouts {
            await deleteWorkoutCascade(workout)
        }

        // 6. Update plan with new schedule
        var updatedPlan = plan
        updatedPlan.preferredDays = newPreferredDays

        // Calculate new strength days
        let totalDays = newDaysPerWeek ?? newPreferredDays.count
        let cardioDays = newCardioDays ?? plan.cardioDays
        let strengthDays = max(totalDays - cardioDays, 1)

        updatedPlan.weightliftingDays = strengthDays
        updatedPlan.cardioDays = cardioDays

        // 7. Regenerate future workouts for each program
        var totalNewWorkouts = 0
        let today = Calendar.current.startOfDay(for: Date())

        for program in programs {
            // Start from today or program start, whichever is later
            let startDate = max(program.startDate, today)

            // Skip if program is entirely in the past
            guard startDate < program.endDate else {
                Logger.log(.info, component: "PlanRescheduleService",
                          message: "⏭️ Skipping program (entirely in past): \(program.id)")
                continue
            }

            // Generate new workouts with AI day assignments
            let scheduledWorkouts = WorkoutScheduler.generateWorkouts(
                programId: program.id,
                startDate: startDate,
                endDate: program.endDate,
                daysPerWeek: strengthDays,
                splitType: updatedPlan.splitType,
                preferredDays: newPreferredDays,
                cardioDays: cardioDays,
                dayAssignments: dayAssignments
            )

            Logger.log(.info, component: "PlanRescheduleService",
                      message: "✅ Generated \(scheduledWorkouts.count) workouts for program \(program.id)")

            // Populate exercises from library
            let workoutsWithExercises = ExerciseSelectionService.populateExercises(
                for: scheduledWorkouts,
                plan: updatedPlan,
                userId: userId
            )

            // Assign protocols
            let (workoutsWithProtocols, workoutIntensities) = ProtocolAssignmentService.assignProtocols(
                for: workoutsWithExercises,
                program: program,
                userId: userId,
                goal: updatedPlan.goal
            )

            // Initialize instances and sets
            InstanceInitializationService.initializeInstances(
                for: workoutsWithProtocols,
                memberId: userId,
                weeklyIntensities: workoutIntensities
            )

            // Save workouts to LocalDataStore
            for workout in workoutsWithProtocols {
                LocalDataStore.shared.workouts[workout.id] = workout
            }

            totalNewWorkouts += workoutsWithProtocols.count
        }

        // 8. Save updated plan
        LocalDataStore.shared.plans[updatedPlan.id] = updatedPlan

        // 9. Persist all changes to disk
        persistChanges(plan: updatedPlan, userId: userId)

        Logger.log(.info, component: "PlanRescheduleService",
                  message: "✅ Rescheduled plan '\(updatedPlan.name)': \(totalNewWorkouts) new workouts, \(completedWorkouts.count) preserved")

        return RescheduleResult(
            plan: updatedPlan,
            rescheduledCount: totalNewWorkouts,
            preservedCount: completedWorkouts.count,
            deletedCount: scheduledWorkouts.count
        )
    }

    // MARK: - Private Helpers

    /// Delete a workout and its instances/sets
    private static func deleteWorkoutCascade(_ workout: Workout) async {
        // Find instances for this workout
        let instances = LocalDataStore.shared.exerciseInstances.values.filter { $0.workoutId == workout.id }
        let instanceIds = Set(instances.map { $0.id })

        // Find sets for these instances
        let sets = LocalDataStore.shared.exerciseSets.values.filter { instanceIds.contains($0.exerciseInstanceId) }

        // Delete in reverse order
        for set in sets {
            LocalDataStore.shared.exerciseSets.removeValue(forKey: set.id)
        }
        for instance in instances {
            LocalDataStore.shared.exerciseInstances.removeValue(forKey: instance.id)
        }
        LocalDataStore.shared.workouts.removeValue(forKey: workout.id)
    }

    /// v206: Sync changes to Firestore
    private static func persistChanges(plan: Plan, userId: String) {
        // v206: Removed legacy disk persistence - Firestore is source of truth
        // Sync plan and workouts to Firestore
        Task {
            do {
                try await FirestorePlanRepository.shared.savePlan(plan)

                // Sync all workouts for this plan
                let programs = LocalDataStore.shared.programs.values.filter { $0.planId == plan.id }
                let programIds = Set(programs.map { $0.id })
                let workouts = LocalDataStore.shared.workouts.values.filter { programIds.contains($0.programId) }

                for workout in workouts {
                    let instances = LocalDataStore.shared.exerciseInstances.values.filter { $0.workoutId == workout.id }
                    let instanceIds = Set(instances.map { $0.id })
                    let sets = LocalDataStore.shared.exerciseSets.values.filter { instanceIds.contains($0.exerciseInstanceId) }

                    try await FirestoreWorkoutRepository.shared.saveFullWorkout(
                        workout: workout,
                        instances: Array(instances),
                        sets: Array(sets),
                        memberId: userId
                    )
                }

                Logger.log(.info, component: "PlanRescheduleService",
                          message: "☁️ Synced rescheduled plan to Firestore")
            } catch {
                Logger.log(.warning, component: "PlanRescheduleService",
                          message: "⚠️ Firestore sync failed: \(error)")
            }
        }
    }
}
