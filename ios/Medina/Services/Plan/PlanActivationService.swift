//
// PlanActivationService.swift
// Medina
//
// v46 - Plan Activation Service
// v68.0 - Added activateWithAutoDeactivate() for overlap handling
// v70.0 - Auto-add introduced exercises to user library on activation
// v172 - Removed abandoned status; simplified to draft/active/completed
// Created: October 29, 2025
//
// Purpose: Handle plan status transitions (draft → active → completed)
// Critical for beta: Members create plans (draft) then activate them
//

import Foundation

/// Result of plan activation with optional auto-deactivation info
struct PlanActivationResult {
    let activatedPlan: Plan
    let deactivatedPlan: Plan?      // nil if no overlap
    let skippedWorkoutCount: Int    // 0 if no overlap
    let addedExerciseCount: Int     // v70.0: Count of exercises added to library

    /// Voice-ready summary for AI tool responses
    var voiceSummary: String {
        var summary: String

        if let deactivated = deactivatedPlan {
            if skippedWorkoutCount > 0 {
                summary = "I've activated '\(activatedPlan.name)'. Your previous plan '\(deactivated.name)' was ended early with \(skippedWorkoutCount) remaining \(skippedWorkoutCount == 1 ? "workout" : "workouts") marked as skipped."
            } else {
                summary = "I've activated '\(activatedPlan.name)'. Your previous plan '\(deactivated.name)' was ended."
            }
        } else {
            summary = "I've activated '\(activatedPlan.name)'. You're all set to start your workouts!"
        }

        // v70.0: Add library update message
        if addedExerciseCount > 0 {
            summary += " I've added \(addedExerciseCount) new \(addedExerciseCount == 1 ? "exercise" : "exercises") to your library."
        }

        return summary
    }
}

/// Errors that can occur during plan activation
enum PlanActivationError: LocalizedError {
    case overlapDetected(String)
    case invalidTransition(String)
    case alreadyActive(String)
    case persistenceError(String)

    var errorDescription: String? {
        switch self {
        case .overlapDetected(let message):
            return message
        case .invalidTransition(let message):
            return message
        case .alreadyActive(let message):
            return message
        case .persistenceError(let message):
            return message
        }
    }

    /// User-friendly error message
    var userMessage: String {
        switch self {
        case .overlapDetected(let message):
            return message
        case .invalidTransition(let message):
            return message
        case .alreadyActive(let message):
            return message
        case .persistenceError:
            return "Failed to save plan changes. Please try again."
        }
    }
}

/// Service for plan status transitions
enum PlanActivationService {

    // MARK: - Activation

    /// Activate a plan (draft → active)
    /// - Parameter plan: Plan to activate
    /// - Returns: Updated plan with active status
    /// - Throws: PlanActivationError if activation fails
    static func activate(plan: Plan) async throws -> Plan {
        // 1. Validation: Check if plan can be activated
        try validateCanActivate(plan: plan)

        // 2. Check for overlapping active plans
        let overlappingPlans = findOverlappingActivePlans(for: plan)
        if let overlappingPlan = overlappingPlans.first {
            throw PlanActivationError.overlapDetected(
                "Cannot activate '\(plan.name)' because it overlaps with active plan '\(overlappingPlan.name)' (\(DateFormatters.shortMonthDayFormatter.string(from: overlappingPlan.startDate)) - \(DateFormatters.shortMonthDayFormatter.string(from: overlappingPlan.endDate))). Complete or archive the existing plan first."
            )
        }

        // 3. Status transition (draft → active)
        var updatedPlan = plan
        updatedPlan.status = .active
        // Note: activatedDate field doesn't exist in Plan model yet
        // Future v47: Add activatedDate: Date? field to track when plan was activated

        // 4. Cascade: Activate programs (mark as active)
        // Note: Program status is derived from dates (startDate, endDate) not explicit field
        // Programs automatically become "active" when their startDate arrives
        // No explicit cascade needed for programs

        // 5. Cascade: Workouts are already scheduled during plan creation
        // WorkoutScheduler populated scheduledDate during creation
        // No additional cascade needed

        // 6. Persist
        // Update in-memory store
        TestDataManager.shared.plans[updatedPlan.id] = updatedPlan

        // v206: Removed legacy disk persistence - Firestore is source of truth
        // v204: Sync status to Firestore
        Task {
            do {
                try await FirestorePlanRepository.shared.savePlan(updatedPlan)
                Logger.log(.info, component: "PlanActivationService",
                          message: "☁️ Synced plan status to Firestore: \(updatedPlan.status.rawValue)")
            } catch {
                Logger.log(.error, component: "PlanActivationService",
                          message: "⚠️ Firestore sync failed: \(error)")
            }
        }

        // 7. v70.0: Auto-add exercises to library
        let addedCount = await autoAddExercisesToLibrary(for: plan, userId: plan.memberId)

        Logger.log(.info, component: "PlanActivationService",
                   message: "Activated plan: \(plan.name) (id: \(plan.id)), added \(addedCount) exercises to library")

        // 8. Side effects (future)
        // await notifyTrainer(plan: updatedPlan)  // Future: Notify trainer of activation
        // await logActivationEvent(plan: updatedPlan)  // Future: Analytics tracking

        return updatedPlan
    }

    // MARK: - Activation with Auto-Deactivate (v68.0)

    /// Activate a plan with automatic deactivation of overlapping plans
    /// - Parameter plan: Plan to activate
    /// - Returns: PlanActivationResult with activated plan and any deactivated plan info
    /// - Throws: PlanActivationError if activation fails (but NOT for overlap - that's handled)
    static func activateWithAutoDeactivate(plan: Plan) async throws -> PlanActivationResult {
        // 1. Validation: Check if plan can be activated (excludes overlap check)
        try validateCanActivateExcludingOverlap(plan: plan)

        // 2. Check for overlapping active plans
        let overlappingPlans = findOverlappingActivePlans(for: plan)

        var deactivatedPlan: Plan? = nil
        var skippedWorkoutCount = 0

        // 3. If overlap exists, abandon the overlapping plan first
        if let overlapping = overlappingPlans.first {
            Logger.log(.info, component: "PlanActivationService",
                       message: "Auto-deactivating overlapping plan '\(overlapping.name)' to activate '\(plan.name)'")

            // Count remaining scheduled workouts before abandoning
            skippedWorkoutCount = countRemainingWorkouts(for: overlapping)

            // Abandon the overlapping plan (cascades skip to remaining workouts)
            deactivatedPlan = try await PlanAbandonmentService.abandon(plan: overlapping)
        }

        // 4. Now activate the new plan (no overlap after abandonment)
        var updatedPlan = plan
        updatedPlan.status = .active

        // 5. Persist plan activation
        TestDataManager.shared.plans[updatedPlan.id] = updatedPlan

        // v206: Removed legacy disk persistence - Firestore is source of truth
        // v204: Sync status to Firestore
        Task {
            do {
                try await FirestorePlanRepository.shared.savePlan(updatedPlan)
                Logger.log(.info, component: "PlanActivationService",
                          message: "☁️ Synced plan status to Firestore: \(updatedPlan.status.rawValue)")
            } catch {
                Logger.log(.error, component: "PlanActivationService",
                          message: "⚠️ Firestore sync failed: \(error)")
            }
        }

        // 6. v70.0: Auto-add exercises to library
        let addedExerciseCount = await autoAddExercisesToLibrary(for: plan, userId: plan.memberId)

        Logger.log(.info, component: "PlanActivationService",
                   message: "Activated plan '\(plan.name)' (auto-deactivated: \(deactivatedPlan?.name ?? "none"), skipped: \(skippedWorkoutCount) workouts, added \(addedExerciseCount) exercises to library)")

        return PlanActivationResult(
            activatedPlan: updatedPlan,
            deactivatedPlan: deactivatedPlan,
            skippedWorkoutCount: skippedWorkoutCount,
            addedExerciseCount: addedExerciseCount
        )
    }

    /// Check for overlapping active plans without throwing (for UI pre-check)
    /// - Parameter plan: Plan to check
    /// - Returns: Array of overlapping active plans (empty if none)
    static func checkForOverlap(plan: Plan) -> [Plan] {
        return findOverlappingActivePlans(for: plan)
    }

    /// Count remaining scheduled workouts for a plan (for cascade info display)
    static func countRemainingWorkouts(for plan: Plan) -> Int {
        let now = Date()
        let programs = TestDataManager.shared.programs.values.filter { $0.planId == plan.id }
        let programIds = Set(programs.map { $0.id })
        let workouts = TestDataManager.shared.workouts.values.filter { programIds.contains($0.programId) }

        return workouts.filter { workout in
            workout.status == .scheduled &&
            workout.scheduledDate != nil &&
            workout.scheduledDate! > now
        }.count
    }

    // MARK: - Deactivation

    /// Complete an active plan (active → completed)
    /// v172: Simplified - only transition to completed (no more abandoned)
    static func deactivate(plan: Plan, newStatus: PlanStatus) async throws -> Plan {
        // Validate transition
        guard plan.status == .active else {
            throw PlanActivationError.invalidTransition("Can only deactivate active plans. This plan is '\(plan.status.displayName)'.")
        }

        guard newStatus == .completed else {
            throw PlanActivationError.invalidTransition("Can only deactivate to 'completed' status.")
        }

        // Status transition
        var updatedPlan = plan
        updatedPlan.status = newStatus

        // Persist
        // Update in-memory store
        TestDataManager.shared.plans[updatedPlan.id] = updatedPlan

        // v206: Sync to Firestore (fire-and-forget)
        let planToSync = updatedPlan
        Task {
            do {
                try await FirestorePlanRepository.shared.savePlan(planToSync)
            } catch {
                Logger.log(.warning, component: "PlanActivationService",
                          message: "⚠️ Firestore sync failed: \(error)")
            }
        }

        Logger.log(.info, component: "PlanActivationService", message: "Completed plan: \(plan.name)")

        return updatedPlan
    }

    // MARK: - Validation Helpers

    /// Validate plan can be activated (full validation including overlap)
    private static func validateCanActivate(plan: Plan) throws {
        try validateCanActivateExcludingOverlap(plan: plan)
        // Note: Overlap check is done separately in activate() method
    }

    /// Validate plan can be activated (excludes overlap check, for activateWithAutoDeactivate)
    private static func validateCanActivateExcludingOverlap(plan: Plan) throws {
        // Check current status
        if plan.status == .active {
            throw PlanActivationError.alreadyActive("Plan '\(plan.name)' is already active.")
        }

        // Only draft plans can be activated (not completed/abandoned)
        guard plan.status == .draft else {
            throw PlanActivationError.invalidTransition("Can only activate draft plans. This plan is '\(plan.status.displayName)'.")
        }

        // Validate plan has programs
        let programs = TestDataManager.shared.programs.values.filter { $0.planId == plan.id }
        guard !programs.isEmpty else {
            throw PlanActivationError.invalidTransition("Cannot activate plan '\(plan.name)' because it has no programs. Plans must have at least one program.")
        }

        // Validate programs have workouts
        let programIds = programs.map { $0.id }
        let workouts = TestDataManager.shared.workouts.values.filter { programIds.contains($0.programId) }
        guard !workouts.isEmpty else {
            throw PlanActivationError.invalidTransition("Cannot activate plan '\(plan.name)' because its programs have no workouts. Create workouts first.")
        }
    }

    /// Find overlapping active plans (same member & intersecting date range)
    /// v101.2: Excludes single workout plans from overlap detection - they coexist independently
    private static func findOverlappingActivePlans(for plan: Plan) -> [Plan] {
        // v101.2: If the plan being activated is a single workout, skip overlap check entirely
        // Single workouts should just activate without conflict
        if plan.isSingleWorkout {
            return []
        }

        let memberPlans = PlanDataStore.allPlans(for: plan.memberId)

        return memberPlans.filter { existingPlan in
            guard existingPlan.id != plan.id else { return false }
            guard existingPlan.effectiveStatus == .active else { return false }
            // v101.2: Skip single workout plans - they coexist independently
            guard !existingPlan.isSingleWorkout else { return false }
            return datesOverlap(plan1Start: plan.startDate,
                                plan1End: plan.endDate,
                                plan2Start: existingPlan.startDate,
                                plan2End: existingPlan.endDate)
        }
    }

    /// Check if two date ranges overlap
    private static func datesOverlap(plan1Start: Date, plan1End: Date, plan2Start: Date, plan2End: Date) -> Bool {
        // Treat ranges as inclusive of start and end date (calendar-day overlap)
        return !(plan1End < plan2Start || plan1Start > plan2End)
    }

    // MARK: - v70.0 Library Auto-Add (v71.0: Added protocols)

    /// Automatically add plan's exercises and protocols to user's library on activation
    ///
    /// **Algorithm:**
    /// 1. Collect all unique exercise IDs from the plan's workouts
    /// 2. Collect all unique protocol IDs from the plan's workouts
    /// 3. Add them to the library using LibraryPersistenceService
    ///
    /// - Parameters:
    ///   - plan: Plan being activated
    ///   - userId: User ID to update library for
    /// - Returns: Count of exercises added to library
    @MainActor
    private static func autoAddExercisesToLibrary(for plan: Plan, userId: String) -> Int {
        // 1. Get all workouts from this plan's programs
        let programs = TestDataManager.shared.programs.values.filter { $0.planId == plan.id }
        let programIds = Set(programs.map { $0.id })
        let workouts = TestDataManager.shared.workouts.values.filter { programIds.contains($0.programId) }

        // 2. Collect all unique exercise IDs from workouts
        let allExerciseIds = Set(workouts.flatMap { $0.exerciseIds })

        // 3. Collect all unique protocol IDs from workouts
        let allProtocolIds = Set(workouts.flatMap { $0.protocolVariantIds.values })

        // 4. Get current library
        let library = TestDataManager.shared.libraries[userId]
        let existingExerciseIds = library?.exercises ?? []
        let existingProtocolIds = Set(library?.protocols.map { $0.protocolConfigId } ?? [])

        // 5. Find new items not already in library
        let newExerciseIds = allExerciseIds.subtracting(existingExerciseIds)
        let newProtocolIds = allProtocolIds.subtracting(existingProtocolIds)

        // 6. Add new exercises to library
        var addedExerciseCount = 0
        if !newExerciseIds.isEmpty {
            do {
                try LibraryPersistenceService.addExercises(Array(newExerciseIds), userId: userId)
                addedExerciseCount = newExerciseIds.count
                Logger.log(.info, component: "PlanActivationService",
                          message: "📚 Added \(newExerciseIds.count) exercises to library: \(newExerciseIds.prefix(5).joined(separator: ", "))\(newExerciseIds.count > 5 ? "..." : "")")
            } catch {
                Logger.log(.error, component: "PlanActivationService",
                          message: "Failed to add exercises to library: \(error)")
            }
        }

        // 7. Add new protocols to library
        if !newProtocolIds.isEmpty {
            do {
                try LibraryPersistenceService.addProtocols(Array(newProtocolIds), userId: userId)
                Logger.log(.info, component: "PlanActivationService",
                          message: "📚 Added \(newProtocolIds.count) protocols to library: \(newProtocolIds.joined(separator: ", "))")
            } catch {
                Logger.log(.error, component: "PlanActivationService",
                          message: "Failed to add protocols to library: \(error)")
            }
        }

        if newExerciseIds.isEmpty && newProtocolIds.isEmpty {
            Logger.log(.debug, component: "PlanActivationService",
                      message: "All exercises and protocols already in library, no additions needed")
        }

        return addedExerciseCount
    }
}
