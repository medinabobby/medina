//
// IntensityRecommendationService.swift
// Medina
//
// v111: Recommends intensity adjustments when user misses workouts
// Created: December 12, 2025
//
// Purpose: When user skips workouts, calculate whether they should
// stay at current intensity or step back to avoid jumping too fast
//

import Foundation

/// Represents an intensity recommendation based on missed workout analysis
struct IntensityRecommendation {
    /// The recommended intensity (0.0-1.0)
    let suggestedIntensity: Double

    /// What the intensity would normally be based on calendar
    let originalIntensity: Double

    /// Human-readable reason for the recommendation
    let reason: String

    /// Number of workouts missed in the analysis period
    let missedWorkoutCount: Int

    /// Whether an adjustment is being recommended
    var hasAdjustment: Bool {
        abs(suggestedIntensity - originalIntensity) > 0.01
    }

    /// Format the intensity as a percentage string
    var suggestedPercentage: String {
        "\(Int(suggestedIntensity * 100))%"
    }

    var originalPercentage: String {
        "\(Int(originalIntensity * 100))%"
    }
}

enum IntensityRecommendationService {

    // MARK: - Public API

    /// Calculate recommended intensity based on workout completion history
    ///
    /// Analyzes the user's recent workout history and recommends whether
    /// to stay at current intensity or step back if they've missed workouts.
    ///
    /// - Parameters:
    ///   - program: The active program with intensity progression
    ///   - memberId: The user's member ID
    /// - Returns: Intensity recommendation with reasoning
    static func calculateRecommendation(
        program: Program,
        memberId: String
    ) -> IntensityRecommendation {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Get all workouts for this program
        let allWorkouts = WorkoutDataStore.workouts(forProgramId: program.id)

        // Calculate what week we're in
        let weeksSinceStart = calendar.dateComponents(
            [.weekOfYear],
            from: program.startDate,
            to: today
        ).weekOfYear ?? 0
        let currentWeek = weeksSinceStart + 1

        // Calculate current calendar-based intensity
        let dummyWorkout = Workout(
            id: "temp",
            programId: program.id,
            name: "temp",
            scheduledDate: today,
            type: .strength,
            splitDay: nil,
            status: .scheduled,
            completedDate: nil,
            exerciseIds: [],
            protocolVariantIds: [:],
            exercisesSelectedAt: nil,
            supersetGroups: nil,
            protocolCustomizations: nil
        )
        let originalIntensity = IntensityCalculationService.calculateBaseIntensity(
            workout: dummyWorkout,
            program: program
        )

        // Count completed vs missed workouts in the last 2 weeks
        guard let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: today) else {
            return IntensityRecommendation(
                suggestedIntensity: originalIntensity,
                originalIntensity: originalIntensity,
                reason: "Unable to analyze workout history",
                missedWorkoutCount: 0
            )
        }

        let recentWorkouts = allWorkouts.filter { workout in
            guard let date = workout.scheduledDate else { return false }
            return date >= twoWeeksAgo && date < today
        }

        let completedCount = recentWorkouts.filter { $0.status == .completed }.count
        let missedCount = recentWorkouts.filter { $0.status == .scheduled }.count // Still scheduled = missed
        let skippedCount = recentWorkouts.filter { $0.status == .skipped }.count
        let totalMissed = missedCount + skippedCount

        // If no recent workouts, no recommendation needed
        if recentWorkouts.isEmpty {
            return IntensityRecommendation(
                suggestedIntensity: originalIntensity,
                originalIntensity: originalIntensity,
                reason: "No recent workout history to analyze",
                missedWorkoutCount: 0
            )
        }

        // Calculate completion rate
        let totalScheduled = recentWorkouts.count
        let completionRate = totalScheduled > 0 ? Double(completedCount) / Double(totalScheduled) : 0

        // Decision logic for intensity adjustment
        return calculateAdjustment(
            originalIntensity: originalIntensity,
            program: program,
            currentWeek: currentWeek,
            completedCount: completedCount,
            missedCount: totalMissed,
            completionRate: completionRate
        )
    }

    // MARK: - Private Helpers

    private static func calculateAdjustment(
        originalIntensity: Double,
        program: Program,
        currentWeek: Int,
        completedCount: Int,
        missedCount: Int,
        completionRate: Double
    ) -> IntensityRecommendation {

        // Rule 1: If completion rate is 50% or lower, recommend staying at previous week's intensity
        if completionRate <= 0.5 && missedCount >= 2 {
            let suggestedIntensity = calculatePreviousWeekIntensity(
                program: program,
                currentWeek: currentWeek
            )

            return IntensityRecommendation(
                suggestedIntensity: suggestedIntensity,
                originalIntensity: originalIntensity,
                reason: "You completed \(Int(completionRate * 100))% of workouts recently. " +
                        "Recommend staying at \(Int(suggestedIntensity * 100))% to build consistency.",
                missedWorkoutCount: missedCount
            )
        }

        // Rule 2: If completion rate is 50-75%, suggest slight reduction
        if completionRate < 0.75 && missedCount >= 1 {
            // Reduce by half the weekly increment
            let weeklyIncrement = calculateWeeklyIncrement(program: program)
            let suggestedIntensity = max(
                program.startingIntensity,
                originalIntensity - (weeklyIncrement / 2)
            )

            if suggestedIntensity < originalIntensity - 0.01 {
                return IntensityRecommendation(
                    suggestedIntensity: suggestedIntensity,
                    originalIntensity: originalIntensity,
                    reason: "You missed \(missedCount) workout(s) recently. " +
                            "Recommend \(Int(suggestedIntensity * 100))% instead of \(Int(originalIntensity * 100))%.",
                    missedWorkoutCount: missedCount
                )
            }
        }

        // Rule 3: Good completion rate (75%+), use original intensity
        return IntensityRecommendation(
            suggestedIntensity: originalIntensity,
            originalIntensity: originalIntensity,
            reason: "On track with \(Int(completionRate * 100))% completion rate. " +
                    "Intensity at \(Int(originalIntensity * 100))%.",
            missedWorkoutCount: missedCount
        )
    }

    /// Calculate the intensity that was used the previous week
    private static func calculatePreviousWeekIntensity(
        program: Program,
        currentWeek: Int
    ) -> Double {
        let calendar = Calendar.current
        let totalWeeks = calendar.dateComponents(
            [.weekOfYear],
            from: program.startDate,
            to: program.endDate
        ).weekOfYear ?? 1

        // If we're in week 1, use starting intensity
        if currentWeek <= 1 {
            return program.startingIntensity
        }

        // Calculate intensity for previous week
        let previousWeek = currentWeek - 1
        let progressionRatio = Double(previousWeek - 1) / Double(max(1, totalWeeks - 1))
        let intensityRange = program.endingIntensity - program.startingIntensity
        let previousIntensity = program.startingIntensity + (intensityRange * progressionRatio)

        return min(max(previousIntensity, program.startingIntensity), program.endingIntensity)
    }

    /// Calculate the weekly intensity increment
    private static func calculateWeeklyIncrement(program: Program) -> Double {
        let calendar = Calendar.current
        let totalWeeks = calendar.dateComponents(
            [.weekOfYear],
            from: program.startDate,
            to: program.endDate
        ).weekOfYear ?? 1

        guard totalWeeks > 1 else { return 0 }

        let intensityRange = program.endingIntensity - program.startingIntensity
        return intensityRange / Double(totalWeeks - 1)
    }
}
