//
// EntityActionProvider.swift
// Medina
//
// v49: Single source of truth for entity actions
// Created: November 2025
//
// Purpose: Determines which actions are available for an entity based on:
// - Entity type (plan, workout, program, exercise)
// - Current status (draft, active, scheduled, in progress, etc.)
// - User role (member, trainer, admin)
//
// Replaces: Inline logic from ChatCardView.buildContextActions()
//

import Foundation

// MARK: - Protocol

/// Provides available actions for an entity given its current state
protocol EntityActionProviding {
    /// Returns actions available for the given entity descriptor
    /// - Parameter descriptor: Entity context (type, ID, status, role)
    /// - Returns: Array of available actions (empty if none available)
    func actions(for descriptor: EntityDescriptor) -> [EntityAction]
}

// MARK: - Default Implementation

enum EntityActionProvider {

    static func actions(for descriptor: EntityDescriptor) -> [EntityAction] {
        switch descriptor.entityType {
        case .plan:
            return planActions(for: descriptor)
        case .workout:
            return workoutActions(for: descriptor)
        case .program:
            return programActions(for: descriptor)
        case .exercise:
            return exerciseActions(for: descriptor)
        default:
            // No actions for other entity types (yet)
            // Note: Protocol actions removed - protocols are not Entity enum members
            return []
        }
    }

    // MARK: - Plan Actions

    private static func planActions(for descriptor: EntityDescriptor) -> [EntityAction] {
        var actions: [EntityAction] = []

        // Activate: Draft plans only
        if descriptor.status == "Draft" {
            actions.append(EntityAction(
                type: .activatePlan,
                title: "Activate Plan",
                icon: "play.circle",
                isDestructive: false,
                confirmationMessage: nil
            ))
        }

        // Abandon: Active plans only
        if descriptor.status == "Active" {
            actions.append(EntityAction(
                type: .abandonPlan,
                title: "Abandon Plan",
                icon: "xmark.circle",
                isDestructive: true,
                confirmationMessage: "Are you sure you want to abandon this plan? You can reactivate it later."
            ))
        }

        // Delete: Draft or Abandoned plans only
        if descriptor.status == "Draft" || descriptor.status == "Abandoned" {
            actions.append(EntityAction(
                type: .deletePlan,
                title: "Delete Plan",
                icon: "trash",
                isDestructive: true,
                confirmationMessage: "Are you sure you want to permanently delete this plan? This cannot be undone."
            ))
        }

        return actions
    }

    // MARK: - Workout Actions

    private static func workoutActions(for descriptor: EntityDescriptor) -> [EntityAction] {
        var actions: [EntityAction] = []

        // Get workout from LocalDataStore
        guard let workout = LocalDataStore.shared.workouts[descriptor.entityId] else {
            return actions
        }

        // Check if workout belongs to draft plan (shouldn't allow start/skip)
        let isDraftPlan = isWorkoutInDraftPlan(workoutId: descriptor.entityId)

        // v55.0: Guided-only workout execution
        // Start Workout: Scheduled workouts only (and plan must be active)
        if descriptor.status == "Scheduled" && !isDraftPlan {
            actions.append(EntityAction(
                type: .startWorkout,
                title: "Start Workout",
                icon: "play.fill",
                isDestructive: false,
                confirmationMessage: nil
            ))
        }

        // Continue: In Progress workouts only
        if descriptor.status == "In Progress" {
            actions.append(EntityAction(
                type: .continueWorkout,
                title: "Continue Workout",
                icon: "play.circle.fill",
                isDestructive: false,
                confirmationMessage: nil
            ))
        }

        // Skip: Scheduled workouts only (and plan must be active)
        // Don't show if workout is in progress - use "End Workout Early" instead
        if descriptor.status == "Scheduled" && !isDraftPlan {
            actions.append(EntityAction(
                type: .skipWorkout,
                title: "Skip Workout",
                icon: "forward.fill",
                isDestructive: false,  // Skipping is common, not destructive
                confirmationMessage: nil
            ))
        }

        // End Workout Early: Only show when in-progress with at least 1 set completed
        // Marks remaining sets as skipped and ends the session
        if workout.status == .inProgress && hasCompletedSets(workout: workout) {
            actions.append(EntityAction(
                type: .completeWorkout,
                title: "End Workout Early",
                icon: "stop.circle",
                isDestructive: true,  // Ending early is somewhat destructive
                confirmationMessage: "End this workout early? Remaining sets will be marked as skipped."
            ))
        }

        // Reset Workout: Only show if deltas exist (simple check - good enough for beta)
        if DeltaStore.shared.hasWorkoutDeltas(workout.id) {
            actions.append(EntityAction(
                type: .resetWorkout,
                title: "Reset Workout",
                icon: "arrow.counterclockwise",
                isDestructive: true,
                confirmationMessage: nil
            ))
        }

        // v162: Removed refreshExercises - feature was never scoped/requested

        return actions
    }

    // MARK: - Helpers

    /// Check if workout belongs to a draft plan
    private static func isWorkoutInDraftPlan(workoutId: String) -> Bool {
        guard let workout = LocalDataStore.shared.workouts[workoutId],
              let program = LocalDataStore.shared.programs[workout.programId],
              let plan = LocalDataStore.shared.plans[program.planId] else {
            return false
        }

        return plan.status == .draft
    }

    /// Check if workout has at least one completed set
    private static func hasCompletedSets(workout: Workout) -> Bool {
        let manager = LocalDataStore.shared

        // Check all exercise instances for this workout
        for (index, _) in workout.exerciseIds.enumerated() {
            let instanceId = "\(workout.id)_ex\(index)"

            // Check if any sets for this instance are completed
            let instanceSets = manager.exerciseSets.values.filter { set in
                set.exerciseInstanceId == instanceId && set.completion == .completed
            }

            if !instanceSets.isEmpty {
                return true
            }
        }

        return false
    }

    // MARK: - Program Actions

    private static func programActions(for descriptor: EntityDescriptor) -> [EntityAction] {
        // v49: No program actions yet
        // v50+: Could add reschedule, change progression, etc.
        return []
    }

    // MARK: - Exercise Actions

    private static func exerciseActions(for descriptor: EntityDescriptor) -> [EntityAction] {
        // v49: No exercise actions yet
        // v50+: Could add "Mark Done", "Jump to Execution", etc.
        return []
    }

    // MARK: - Protocol Actions
    // v53.0 Phase 2: Removed - protocols are not Entity enum members
    // Protocol actions (enable/disable/remove) are handled separately in library UI
}
