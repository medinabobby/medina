//
// GreetingContext.swift
// Medina
//
// v99.7: Rich context data for trainer-style greetings
//

import Foundation

/// Context data for building rich, trainer-style greetings
/// Assembled by GreetingContextBuilder, consumed by GreetingMessageComposer
struct GreetingContext {

    // MARK: - Plan Context

    /// Active plan name (e.g., "Q4 2025 Strength")
    let planName: String?

    /// Plan completion percentage (0-100)
    let planProgressPercent: Int?

    /// Weeks remaining in current plan
    let weeksRemaining: Int?

    // MARK: - Today's Workout

    /// Today's scheduled workout (if any)
    let todaysWorkout: Workout?

    // MARK: - v136: Next Workout (fallback when no workout today)

    /// Next scheduled workout if no workout today
    let nextWorkout: Workout?

    /// Workout type for display
    let workoutType: SessionType?

    /// Split day for strength workouts
    let splitDay: SplitDay?

    /// Number of exercises in today's workout
    let exerciseCount: Int

    /// Estimated duration in minutes
    let durationMinutes: Int?

    // MARK: - In-Progress Context

    /// Workout currently in progress (if any)
    let inProgressWorkout: Workout?

    /// Exercises completed in in-progress workout
    let completedExercises: Int

    /// Total exercises in in-progress workout
    let totalExercises: Int

    // MARK: - Adherence Metrics

    /// Days since last completed workout
    let daysSinceLastWorkout: Int?

    /// Workouts completed this week
    let completedThisWeek: Int

    /// Target workouts per week from plan
    let targetThisWeek: Int

    /// Workouts remaining this week (scheduled but not completed)
    let remainingThisWeek: Int

    // MARK: - Computed Properties

    /// True if user has a workout in progress
    var hasInProgressWorkout: Bool {
        inProgressWorkout != nil
    }

    /// True if user has a workout scheduled today
    var hasWorkoutToday: Bool {
        todaysWorkout != nil
    }

    /// True if user is behind on workouts (missed 3+ days)
    var isBehindSchedule: Bool {
        guard let days = daysSinceLastWorkout else { return false }
        return days >= 3
    }

    /// True if user has good weekly adherence (>= 50% of target)
    var hasGoodAdherence: Bool {
        guard targetThisWeek > 0 else { return true }
        return Double(completedThisWeek) / Double(targetThisWeek) >= 0.5
    }
}
