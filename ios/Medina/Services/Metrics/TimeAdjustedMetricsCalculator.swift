//
// TimeAdjustedMetricsCalculator.swift
// Medina
//
// v19.2 - Time-adjusted baseline metrics for plans
// Last reviewed: October 2025
//

import Foundation

/// Calculate time-adjusted metrics for plans (eligible vs total based on time elapsed)
/// Provides "ahead/behind plan" tracking by adjusting denominators based on plan progress
enum TimeAdjustedMetricsCalculator {

    /// Calculate plan progress with time-adjusted eligible totals
    ///
    /// **Time-Adjusted Baseline Logic:**
    /// - If plan is 25% elapsed → eligible workouts = 25% of total
    /// - If plan is 50% elapsed → eligible workouts = 50% of total
    /// - Percentage shown is completed/eligible (not completed/total)
    ///
    /// **Example:**
    /// - Bobby's Fall-25 Plan: 80 total workouts
    /// - At 25% elapsed (20 eligible): 16 completed → 80% (16/20)
    /// - At 50% elapsed (40 eligible): 16 completed → 40% (16/40) - behind plan!
    ///
    /// - Parameters:
    ///   - plan: The plan to analyze
    ///   - memberId: Member ID for progress tracking
    /// - Returns: Metrics with time-adjusted eligible totals (not absolute totals)
    static func timeAdjustedMetrics(for plan: Plan, memberId: String) -> CardProgressMetrics {
        // v20.1d: Filter programs to only include those that have started
        // This prevents future programs (Nov, Dec) from inflating the total counts
        let now = Date()
        let allPrograms = ProgramDataStore.programs(for: plan.id)
        let startedPrograms = allPrograms.filter { $0.startDate <= now }

        // Calculate base metrics only from started programs
        let baseMetrics = startedPrograms.reduce(CardProgressMetrics.zero) { partialResult, program in
            partialResult.adding(MetricsCalculator.programProgress(for: program, memberId: memberId))
        }

        // v20.1d: Also calculate session type breakdown from started programs only
        let allWorkouts = startedPrograms.flatMap { program in
            WorkoutDataStore.workouts(forProgramId: program.id)
        }
        let strengthWorkouts = allWorkouts.filter { $0.type == .strength }
        let cardioWorkouts = allWorkouts.filter { $0.type == .cardio }
        let strengthCompleted = strengthWorkouts.filter { $0.status == .completed }.count
        let cardioCompleted = cardioWorkouts.filter { $0.status == .completed }.count

        // Calculate elapsed percentage (startDate and endDate are non-optional)
        let startDate = plan.startDate
        let endDate = plan.endDate

        let planDuration = endDate.timeIntervalSince(startDate)
        let elapsed = now.timeIntervalSince(startDate)
        let percentElapsed = max(0, min(1, elapsed / planDuration))

        // Calculate eligible totals (time-adjusted)
        let eligibleSessions = max(1, Int(Double(baseMetrics.sessions.total) * percentElapsed))
        let eligibleExercises = max(1, Int(Double(baseMetrics.exercises.total) * percentElapsed))
        let eligibleSets = max(1, Int(Double(baseMetrics.sets.total) * percentElapsed))
        let eligibleReps = max(1, Int(Double(baseMetrics.reps.total) * percentElapsed))

        // v19.3: Cap completed at eligible to prevent >100% percentages
        // User may complete more workouts than expected (ahead of schedule), but UI should show 100% max
        let cappedSessions = min(baseMetrics.sessions.completed, eligibleSessions)
        let cappedExercises = min(baseMetrics.exercises.completed, eligibleExercises)
        let cappedSets = min(baseMetrics.sets.completed, eligibleSets)
        let cappedReps = min(baseMetrics.reps.completed, eligibleReps)

        // v19.3.1: Apply time-adjustment to strength/cardio breakdown
        // v20.1d: Use pre-filtered workout counts (from started programs only)
        let adjustedStrength: ProgressBreakdown?
        let adjustedCardio: ProgressBreakdown?

        if !strengthWorkouts.isEmpty {
            let eligibleStrength = max(1, Int(Double(strengthWorkouts.count) * percentElapsed))
            let cappedStrengthCompleted = min(strengthCompleted, eligibleStrength)
            adjustedStrength = ProgressBreakdown(completed: cappedStrengthCompleted, total: eligibleStrength)
        } else {
            adjustedStrength = nil
        }

        if !cardioWorkouts.isEmpty {
            let eligibleCardio = max(1, Int(Double(cardioWorkouts.count) * percentElapsed))
            let cappedCardioCompleted = min(cardioCompleted, eligibleCardio)
            adjustedCardio = ProgressBreakdown(completed: cappedCardioCompleted, total: eligibleCardio)
        } else {
            adjustedCardio = nil
        }

        // Ahead/behind tracking (use uncapped for tracking)
        let sessionsAhead = baseMetrics.sessions.completed - eligibleSessions

        // Log warning if user is ahead (completed > eligible)
        if sessionsAhead > 0 {
            Logger.log(.warning, component: "PlanProgress", message: "[AHEAD OF PLAN] \(plan.name): User completed \(baseMetrics.sessions.completed) sessions but only \(eligibleSessions) were eligible (capping at 100%)")
        }

        // v19.8: Removed verbose metrics logging (metrics visible in UI cards)

        // v19.3.1: Return metrics with capped completed values and session type breakdown
        return CardProgressMetrics(
            sessions: ProgressBreakdown(completed: cappedSessions, total: eligibleSessions),
            exercises: ProgressBreakdown(completed: cappedExercises, total: eligibleExercises),
            sets: ProgressBreakdown(completed: cappedSets, total: eligibleSets),
            reps: ProgressBreakdown(completed: cappedReps, total: eligibleReps),
            strengthSessions: adjustedStrength,
            cardioSessions: adjustedCardio
        )
    }

    // MARK: - Helpers

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private static func formatPercent(_ completed: Int, _ total: Int) -> String {
        guard total > 0 else { return "0%" }
        let percent = Double(completed) / Double(total) * 100
        return String(format: "%.0f%%", percent)
    }
}
