//
// WorkoutQueryHelpers.swift
// Medina
//
// v168: Extracted from StartWorkoutHandler and SkipWorkoutHandler
// Shared helpers for workout queries and display formatting
//

import Foundation

/// Shared helpers for workout handlers
struct WorkoutQueryHelpers {

    // MARK: - Workout Discovery

    /// Find missed workouts (past-dated, still scheduled) for user
    /// Returns most recent first
    static func findMissedWorkouts(for userId: String) -> [Workout] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return WorkoutResolver.workouts(
            for: userId,
            temporal: .past,
            status: .scheduled,  // Not completed or skipped
            modality: .unspecified,
            splitDay: nil,
            source: nil,
            plan: PlanResolver.activePlan(for: userId),
            program: nil,
            dateInterval: DateInterval(start: Date.distantPast, end: today)
        )
        .sorted { ($0.scheduledDate ?? .distantPast) > ($1.scheduledDate ?? .distantPast) }  // Most recent first
    }

    /// Find next scheduled workout after today
    /// - Parameters:
    ///   - userId: User ID to find workouts for
    ///   - excluding: Optional workout ID to exclude from results (for skip scenarios)
    /// - Returns: Next scheduled workout, or nil if none found
    static func findNextScheduledWorkout(for userId: String, excluding workoutId: String? = nil) -> Workout? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var workouts = WorkoutResolver.workouts(
            for: userId,
            temporal: .upcoming,
            status: .scheduled,
            modality: .unspecified,
            splitDay: nil,
            source: nil,
            plan: PlanResolver.activePlan(for: userId),
            program: nil,
            dateInterval: DateInterval(start: today, end: Date.distantFuture)
        )

        // Exclude specific workout if requested (for skip scenarios)
        if let excludeId = workoutId {
            workouts = workouts.filter { $0.id != excludeId }
        }

        return workouts
            .sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
            .first
    }

    // MARK: - Display Formatting

    /// Build friendly date context like "See you tomorrow!" or "Your next workout is on Monday."
    static func buildDateContext(for workout: Workout) -> String {
        guard let scheduledDate = workout.scheduledDate else {
            return ""
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let workoutDay = calendar.startOfDay(for: scheduledDate)

        let daysUntil = calendar.dateComponents([.day], from: today, to: workoutDay).day ?? 0

        switch daysUntil {
        case 0:
            return "You have another workout today!"
        case 1:
            return "See you tomorrow!"
        case 2:
            return "See you in a couple days!"
        case 3...6:
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            let dayName = formatter.string(from: scheduledDate)
            return "See you on \(dayName)!"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            let dateStr = formatter.string(from: scheduledDate)
            return "Your next workout is on \(dateStr)."
        }
    }

    /// Build exercise preview like ", including Deadlifts and Bench Press"
    static func buildExercisePreview(for workout: Workout) -> String {
        let exerciseIds = workout.exerciseIds
        guard !exerciseIds.isEmpty else { return "" }

        let exerciseNames = exerciseIds.prefix(2).compactMap { id -> String? in
            TestDataManager.shared.exercises[id]?.name
        }

        if exerciseNames.isEmpty {
            return ""
        } else if exerciseNames.count == 1 {
            return ", including \(exerciseNames[0])"
        } else {
            return ", including \(exerciseNames[0]) and \(exerciseNames[1])"
        }
    }
}
