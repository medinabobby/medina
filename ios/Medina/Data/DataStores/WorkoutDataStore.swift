//
// WorkoutDataStore.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

enum WorkoutDataStore {

    private static var manager: TestDataManager { TestDataManager.shared }
    private static var calendar: Calendar { Calendar.current }

    static func nextWorkout(
        for memberId: String,
        temporal: TemporalSlot,
        status: WorkoutStatus?,
        modality: ModalitySlot,
        splitDay: SplitDay? = nil,
        source: EntityRelationship?,
        plan: Plan?,
        program: Program? = nil,
        dateInterval: DateInterval?
    ) -> Workout? {
        _ = source
        let candidates = workouts(
            for: memberId,
            temporal: temporal,
            status: status,
            modality: modality,
            splitDay: splitDay,
            source: source,
            plan: plan,
            program: program,
            dateInterval: dateInterval
        )

        switch status {
        case .skipped, .completed:
            return candidates.first
        case nil:
            // For unspecified status, return next available workout (not completed or skipped)
            return candidates.first(where: { workout in
                workout.status != .completed && workout.status != .skipped
            })
        case .scheduled, .inProgress:
            // For scheduled/inProgress, only return incomplete workouts
            return candidates.first(where: WorkoutFilteringService.isIncomplete)
        }
    }

    static func workouts(
        for memberId: String,
        temporal: TemporalSlot,
        status: WorkoutStatus? = nil,
        modality: ModalitySlot = .unspecified,
        splitDay: SplitDay? = nil,
        source: EntityRelationship? = nil,
        plan: Plan? = nil,
        program: Program? = nil,
        dateInterval: DateInterval? = nil
    ) -> [Workout] {
        _ = source
        let allWorkouts = relevantWorkouts(for: memberId)

        let filtered = WorkoutFilteringService.applyFilters(
            to: allWorkouts,
            temporal: temporal,
            status: status,
            modality: modality,
            splitDay: splitDay,
            plan: plan,
            program: program,
            dateInterval: dateInterval
        )

        // v41.6: Sort descending by date (most recent/upcoming first)
        // Matches "show active first" pattern from plans/programs
        return filtered.sorted {
            ($0.scheduledDate ?? .distantPast) > ($1.scheduledDate ?? .distantPast)
        }
    }

    // MARK: - Plan and Program Specific Queries

    static func workouts(forProgramId programId: String) -> [Workout] {
        manager.workouts.values
            .filter { $0.programId == programId }
            .sorted { ($0.scheduledDate ?? Date.distantPast) < ($1.scheduledDate ?? Date.distantPast) }
    }

    static func workouts(forPlanId planId: String) -> [Workout] {
        let programIds = ProgramDataStore.programs(for: planId).map { $0.id }
        guard !programIds.isEmpty else { return [] }
        return manager.workouts.values
            .filter { programIds.contains($0.programId) }
            .sorted { ($0.scheduledDate ?? Date.distantPast) < ($1.scheduledDate ?? Date.distantPast) }
    }

    // MARK: - Data Retrieval

    private static func relevantWorkouts(for memberId: String) -> [Workout] {
        var results: [String: Workout] = [:]

        // v42.1: Include workouts from ALL plans (including drafts)
        // Now that plan creation is a feature, draft plans are REAL plans waiting to start
        // Previously (v23.0): Excluded drafts thinking they were "theoretical like sales leads"
        let allPrograms = ProgramDataStore.allPrograms(for: memberId)
        let allPlans = PlanDataStore.allPlans(for: memberId)
        let allPlanIds = Set(allPlans.map { $0.id })
        let memberPrograms = allPrograms.filter { allPlanIds.contains($0.planId) }
        let memberProgramIds = Set(memberPrograms.map { $0.id })

        // Prefer workouts tied to the member via ACTIVE sessions only
        // v31.0: Exclude completed sessions to prevent blocking fallback logic
        let sessions = manager.sessions.values
            .filter { $0.memberId == memberId && $0.status != .completed }

        for session in sessions {
            if let workout = manager.workouts[session.workoutId] {
                // SAFETY: Verify workout actually belongs to member's programs
                if memberProgramIds.contains(workout.programId) {
                    results[workout.id] = workout
                }
            }
        }

        // v45: Always load ALL workouts (not just session workouts)
        // Previously: Only loaded all workouts if results.isEmpty (no active session)
        // Problem: Bobby In-Progress had active session, so only Oct 29 workout loaded
        // Fix: Always load all workouts regardless of session (session workouts already added above)
        // Find workouts that belong to this member's programs
        for workout in manager.workouts.values {
            if memberProgramIds.contains(workout.programId) {
                results[workout.id] = workout
            }
        }

        // v45: Removed legacy ID prefix fallback - no longer needed since we load all workouts above
        // DO NOT fall back to all workouts - fail fast to expose data integrity issues
        return Array(results.values)
    }

}
