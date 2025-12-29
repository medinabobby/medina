//
// PlanScheduleAnalyzer.swift
// Medina
//
// v79.6: Analyze plan schedule progress and detect behind-schedule status
// Created: December 3, 2025
//
// Compares scheduled workouts vs completed workouts for a plan
// Detects when user is significantly behind and suggests remediation actions

import Foundation

// MARK: - Schedule Analysis Result

struct PlanScheduleAnalysis {
    let isBehindSchedule: Bool
    let missedWorkouts: Int
    let completedWorkouts: Int
    let totalScheduledWorkouts: Int
    let daysBehind: Int
    let expectedCompletedByNow: Int
    let suggestedActions: [ScheduleAction]

    /// User-friendly summary of the schedule status
    var statusSummary: String {
        if !isBehindSchedule {
            if completedWorkouts == 0 && totalScheduledWorkouts > 0 {
                return "Ready to start"
            }
            return "On track"
        }

        if missedWorkouts >= 10 {
            return "Significantly behind schedule"
        } else if missedWorkouts >= 5 {
            return "Behind schedule"
        } else {
            return "Slightly behind"
        }
    }
}

// MARK: - Suggested Actions

enum ScheduleAction: String, CaseIterable {
    case reschedule = "reschedule"
    case createNewPlan = "create_new_plan"
    case markMissedAsSkipped = "mark_missed_skipped"
    case continueFromHere = "continue_from_here"

    var displayName: String {
        switch self {
        case .reschedule:
            return "Reschedule the plan to start from today"
        case .createNewPlan:
            return "Create a new plan with fresh dates"
        case .markMissedAsSkipped:
            return "Mark missed workouts as skipped and continue"
        case .continueFromHere:
            return "Continue with the next scheduled workout"
        }
    }

    var shortName: String {
        switch self {
        case .reschedule: return "Reschedule plan"
        case .createNewPlan: return "Create new plan"
        case .markMissedAsSkipped: return "Skip missed workouts"
        case .continueFromHere: return "Continue from here"
        }
    }
}

// MARK: - Plan Schedule Analyzer

enum PlanScheduleAnalyzer {

    /// Analyze a plan's schedule progress
    /// Returns analysis with behind-schedule detection and suggested actions
    static func analyze(plan: Plan, memberId: String) -> PlanScheduleAnalysis {
        // Get all workouts for this plan
        let allWorkouts = WorkoutDataStore.workouts(forPlanId: plan.id)

        // Count by status
        let completedWorkouts = allWorkouts.filter { $0.status == .completed }.count
        let skippedWorkouts = allWorkouts.filter { $0.status == .skipped }.count
        let totalScheduled = allWorkouts.count

        // Calculate how many workouts should have been completed by now
        let now = Date()
        let expectedByNow = allWorkouts.filter { workout in
            guard let scheduledDate = workout.scheduledDate else { return false }
            return scheduledDate < now
        }.count

        // Missed = expected by now - (completed + skipped)
        let accountedFor = completedWorkouts + skippedWorkouts
        let missedWorkouts = max(0, expectedByNow - accountedFor)

        // Calculate days behind
        // Find the first incomplete workout that's past its scheduled date
        let daysBehind = calculateDaysBehind(workouts: allWorkouts, now: now)

        // Determine if behind schedule
        // Behind if: missed 3+ workouts OR more than 7 days since a scheduled workout passed
        let isBehind = missedWorkouts >= 3 || daysBehind >= 7

        // Suggest actions based on severity
        let actions = suggestActions(
            missedWorkouts: missedWorkouts,
            daysBehind: daysBehind,
            completedWorkouts: completedWorkouts,
            totalScheduled: totalScheduled
        )

        return PlanScheduleAnalysis(
            isBehindSchedule: isBehind,
            missedWorkouts: missedWorkouts,
            completedWorkouts: completedWorkouts,
            totalScheduledWorkouts: totalScheduled,
            daysBehind: daysBehind,
            expectedCompletedByNow: expectedByNow,
            suggestedActions: actions
        )
    }

    // MARK: - Private Helpers

    private static func calculateDaysBehind(workouts: [Workout], now: Date) -> Int {
        // Find earliest incomplete workout that's past its scheduled date
        let overdueWorkouts = workouts.filter { workout in
            guard let scheduledDate = workout.scheduledDate else { return false }
            let isOverdue = scheduledDate < now
            let isIncomplete = workout.status != .completed && workout.status != .skipped
            return isOverdue && isIncomplete
        }
        .sorted { ($0.scheduledDate ?? .distantPast) < ($1.scheduledDate ?? .distantPast) }

        guard let earliestOverdue = overdueWorkouts.first,
              let scheduledDate = earliestOverdue.scheduledDate else {
            return 0
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: scheduledDate, to: now)
        return max(0, components.day ?? 0)
    }

    private static func suggestActions(
        missedWorkouts: Int,
        daysBehind: Int,
        completedWorkouts: Int,
        totalScheduled: Int
    ) -> [ScheduleAction] {
        var actions: [ScheduleAction] = []

        // If severely behind (10+ missed or 21+ days), suggest creating new plan
        if missedWorkouts >= 10 || daysBehind >= 21 {
            actions.append(.createNewPlan)
            actions.append(.reschedule)
        }
        // If moderately behind, suggest reschedule first
        else if missedWorkouts >= 5 || daysBehind >= 14 {
            actions.append(.reschedule)
            actions.append(.createNewPlan)
        }
        // If slightly behind, suggest continuing or marking skipped
        else if missedWorkouts >= 3 || daysBehind >= 7 {
            actions.append(.continueFromHere)
            actions.append(.markMissedAsSkipped)
            actions.append(.reschedule)
        }
        // If just a bit behind, simple options
        else if missedWorkouts > 0 {
            actions.append(.continueFromHere)
            actions.append(.markMissedAsSkipped)
        }

        return actions
    }

    // MARK: - Quick Analysis Methods

    /// Quick check if a plan is behind schedule (for summary views)
    static func isBehindSchedule(plan: Plan, memberId: String) -> Bool {
        analyze(plan: plan, memberId: memberId).isBehindSchedule
    }

    /// Get the number of missed workouts for a plan
    static func missedWorkoutCount(plan: Plan, memberId: String) -> Int {
        analyze(plan: plan, memberId: memberId).missedWorkouts
    }
}
