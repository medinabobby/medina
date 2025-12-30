//
// PlanAbandonmentService.swift
// Medina
//
// v46.1 - Plan Abandonment Service
// v172 - Now sets to .completed instead of .abandoned (simplified status model)
// Created: October 29, 2025
//
// Purpose: Handle plan early completion (ending plan before endDate)
// Critical for beta: Members can end active plans early (injury, life changes)
//

import Foundation

/// Errors that can occur during plan early completion
enum PlanAbandonmentError: LocalizedError {
    case notActive(String)
    case persistenceError(String)

    var errorDescription: String? {
        switch self {
        case .notActive(let message):
            return message
        case .persistenceError(let message):
            return message
        }
    }
}

/// Service for completing plans early
/// v172: Renamed from "abandonment" semantically - now sets to .completed
enum PlanAbandonmentService {

    /// Complete an active plan early (user ending before scheduled endDate)
    /// v172: Sets status to .completed instead of .abandoned
    /// - Parameter plan: Plan to complete early
    /// - Returns: Updated plan with completed status
    /// - Throws: PlanAbandonmentError if completion fails
    static func abandon(plan: Plan) async throws -> Plan {
        // 1. Validation: Only complete early from active plans
        guard plan.status == .active else {
            throw PlanAbandonmentError.notActive(
                "Can only end active plans early. Plan '\(plan.name)' is '\(plan.status.displayName)'."
            )
        }

        // 2. Status transition (active → completed)
        // v172: Changed from .abandoned to .completed
        var updatedPlan = plan
        updatedPlan.status = .completed

        // 3. Cancel remaining scheduled workouts (mark as skipped)
        let now = Date()
        let programs = LocalDataStore.shared.programs.values.filter { $0.planId == plan.id }
        let programIds = Set(programs.map { $0.id })
        let workouts = Array(LocalDataStore.shared.workouts.values.filter { programIds.contains($0.programId) })

        var cancelledCount = 0
        for workout in workouts {
            // Only cancel future scheduled workouts (not in progress or completed)
            if workout.status == .scheduled,
               let scheduledDate = workout.scheduledDate,
               scheduledDate > now {
                var updatedWorkout = workout
                updatedWorkout.status = .skipped
                LocalDataStore.shared.workouts[workout.id] = updatedWorkout
                cancelledCount += 1
            }
        }

        // 4. Persist
        LocalDataStore.shared.plans[updatedPlan.id] = updatedPlan

        // v206: Sync to Firestore (fire-and-forget)
        let planToSync = updatedPlan
        Task {
            do {
                try await FirestorePlanRepository.shared.savePlan(planToSync)
            } catch {
                Logger.log(.warning, component: "PlanAbandonmentService",
                          message: "⚠️ Firestore sync failed: \(error)")
            }
        }

        Logger.log(.info, component: "PlanAbandonmentService",
                   message: "Completed plan '\(plan.name)' early, cancelled \(cancelledCount) remaining workouts")

        return updatedPlan
    }
}
