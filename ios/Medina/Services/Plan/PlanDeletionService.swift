//
// PlanDeletionService.swift
// Medina
//
// v46.1 - Plan Deletion Service
// v50.3 - Fixed cascade deletion to persist instances/sets removal to disk
// v172 - Removed abandoned status; draft and completed plans can be deleted
// v205.1 - Sync deletions to Firestore (synchronous + parallel for speed)
// Created: October 29, 2025
//
// Purpose: Handle cascading plan deletion (plan → programs → workouts → instances → sets)
// Critical for beta: Members can delete draft or completed plans with full cascade
//

import Foundation

/// Errors that can occur during plan deletion
enum PlanDeletionError: LocalizedError {
    case cannotDeleteActive(String)
    case persistenceError(String)

    var errorDescription: String? {
        switch self {
        case .cannotDeleteActive(let message):
            return message
        case .persistenceError(let message):
            return message
        }
    }

    /// User-friendly error message
    var userMessage: String {
        switch self {
        case .cannotDeleteActive(let message):
            return message
        case .persistenceError:
            return "Failed to delete plan. Please try again."
        }
    }
}

/// Service for cascading plan deletion
enum PlanDeletionService {

    // MARK: - Deletion

    /// Delete a plan with full cascade (programs → workouts → instances → sets)
    /// v172: Draft and completed plans can be deleted (active plans must be completed first)
    /// - Parameter plan: Plan to delete
    /// - Throws: PlanDeletionError if deletion fails
    static func delete(plan: Plan) async throws {
        // 1. Validation: Can only delete draft or completed plans (not active)
        guard plan.status == .draft || plan.status == .completed else {
            throw PlanDeletionError.cannotDeleteActive(
                "Cannot delete active plan '\(plan.name)'. End it first using 'end plan early'."
            )
        }

        // 2. Find all programs for this plan
        let programs = TestDataManager.shared.programs.values.filter { $0.planId == plan.id }
        let programIds = Set(programs.map { $0.id })

        // 3. Find all workouts for these programs
        let workouts = TestDataManager.shared.workouts.values.filter { programIds.contains($0.programId) }
        let workoutIds = Set(workouts.map { $0.id })

        // 4. Find all instances for these workouts
        let instances = TestDataManager.shared.exerciseInstances.values.filter {
            workoutIds.contains($0.workoutId)
        }
        let instanceIds = Set(instances.map { $0.id })

        // 5. Find all sets for these instances
        let sets = TestDataManager.shared.exerciseSets.values.filter {
            instanceIds.contains($0.exerciseInstanceId)
        }

        // Log cascade summary
        Logger.log(.info, component: "PlanDeletionService",
                   message: "Deleting plan '\(plan.name)' will cascade delete: \(programs.count) programs, \(workouts.count) workouts, \(instances.count) instances, \(sets.count) sets")

        // 6. Delete in reverse order (sets → instances → workouts → programs → plan)
        for set in sets {
            TestDataManager.shared.exerciseSets.removeValue(forKey: set.id)
        }
        for instance in instances {
            TestDataManager.shared.exerciseInstances.removeValue(forKey: instance.id)
        }
        for workout in workouts {
            TestDataManager.shared.workouts.removeValue(forKey: workout.id)
        }
        for program in programs {
            TestDataManager.shared.programs.removeValue(forKey: program.id)
        }
        TestDataManager.shared.plans.removeValue(forKey: plan.id)

        // v205.1: Sync deletions to Firestore (await completion, parallel for speed)
        do {
            // Delete workouts in parallel for speed
            try await withThrowingTaskGroup(of: Void.self) { group in
                for workout in workouts {
                    group.addTask {
                        try await FirestoreWorkoutRepository.shared.deleteWorkout(workout.id, memberId: plan.memberId)
                    }
                }
                try await group.waitForAll()
            }

            // Delete the plan (includes programs in subcollection)
            try await FirestorePlanRepository.shared.deletePlan(plan.id, memberId: plan.memberId)

            Logger.log(.info, component: "PlanDeletionService",
                      message: "☁️ Synced deletion to Firestore: \(plan.name)")
        } catch {
            Logger.log(.error, component: "PlanDeletionService",
                      message: "⚠️ Firestore deletion failed: \(error)")
        }

        // v206: Removed legacy disk persistence - Firestore sync handled above

        Logger.log(.info, component: "PlanDeletionService",
                   message: "✅ Successfully deleted plan '\(plan.name)' and cascade deleted \(programs.count) programs, \(workouts.count) workouts, \(instances.count) instances, \(sets.count) sets")
    }

    /// Get deletion summary (for confirmation dialog)
    static func deletionSummary(for plan: Plan) -> DeletionSummary {
        let programs = TestDataManager.shared.programs.values.filter { $0.planId == plan.id }
        let programIds = Set(programs.map { $0.id })
        let workouts = TestDataManager.shared.workouts.values.filter { programIds.contains($0.programId) }
        let workoutIds = Set(workouts.map { $0.id })
        let instances = TestDataManager.shared.exerciseInstances.values.filter { workoutIds.contains($0.workoutId) }
        let instanceIds = Set(instances.map { $0.id })
        let sets = TestDataManager.shared.exerciseSets.values.filter { instanceIds.contains($0.exerciseInstanceId) }

        return DeletionSummary(
            planName: plan.name,
            programCount: programs.count,
            workoutCount: workouts.count,
            instanceCount: instances.count,
            setCount: sets.count
        )
    }
}

/// Summary of what will be deleted (for confirmation)
struct DeletionSummary {
    let planName: String
    let programCount: Int
    let workoutCount: Int
    let instanceCount: Int
    let setCount: Int

    var confirmationMessage: String {
        """
        ⚠️ Delete Plan?

        This will permanently delete:
        • Plan: \(planName)
        • \(programCount) program\(programCount == 1 ? "" : "s")
        • \(workoutCount) workout\(workoutCount == 1 ? "" : "s")
        • All exercise data (\(instanceCount) instances, \(setCount) sets)

        This cannot be undone.
        """
    }
}
