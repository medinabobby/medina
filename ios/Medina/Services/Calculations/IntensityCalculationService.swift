//
// IntensityCalculationService.swift
// Medina
//
// v54.5: Program-level intensity progression calculations
// Created: November 13, 2025
//
// Purpose: Calculate workout base intensity from program progression
// Supports linear interpolation across program duration
//

import Foundation

enum IntensityCalculationService {

    // MARK: - Base Intensity Calculation

    /// Calculate workout's base intensity from program progression
    ///
    /// Performs linear interpolation between program's starting and ending intensity
    /// based on the workout's position in the program timeline.
    ///
    /// - Parameters:
    ///   - workout: The workout to calculate intensity for
    ///   - program: The program containing intensity progression settings
    /// - Returns: Base intensity as decimal (0.0 to 1.0), e.g., 0.6 = 60%
    ///
    /// **Examples:**
    /// - Week 1 of 3-week program (60%→70%) → 0.60 (60%)
    /// - Week 2 of 3-week program (60%→70%) → 0.65 (65%)
    /// - Week 3 of 3-week program (60%→70%) → 0.70 (70%)
    ///
    /// **Edge Cases:**
    /// - Workout before program start → returns startingIntensity
    /// - Workout after program end → returns endingIntensity
    /// - Program with same start/end intensity → returns constant intensity
    static func calculateBaseIntensity(
        workout: Workout,
        program: Program
    ) -> Double {
        // If no scheduled date, use starting intensity
        guard let scheduledDate = workout.scheduledDate else {
            Logger.log(.debug, component: "IntensityCalculationService",
                      message: "No scheduledDate for workout \(workout.id), using startingIntensity")
            return program.startingIntensity
        }

        let calendar = Calendar.current

        // If workout is before program start, use starting intensity
        if scheduledDate < program.startDate {
            Logger.log(.debug, component: "IntensityCalculationService",
                      message: "Workout \(workout.id) before program start, using startingIntensity")
            return program.startingIntensity
        }

        // If workout is after program end, use ending intensity
        if scheduledDate > program.endDate {
            Logger.log(.debug, component: "IntensityCalculationService",
                      message: "Workout \(workout.id) after program end, using endingIntensity")
            return program.endingIntensity
        }

        // Calculate week number (0-indexed from program start)
        let weeksSinceStart = calendar.dateComponents(
            [.weekOfYear],
            from: program.startDate,
            to: scheduledDate
        ).weekOfYear ?? 0

        // Calculate total program duration in weeks
        let totalWeeks = calendar.dateComponents(
            [.weekOfYear],
            from: program.startDate,
            to: program.endDate
        ).weekOfYear ?? 1

        // Handle single-week programs
        if totalWeeks <= 1 {
            Logger.log(.debug, component: "IntensityCalculationService",
                      message: "Program \(program.id) is 1 week or less, using startingIntensity")
            return program.startingIntensity
        }

        // Linear interpolation
        // progressionRatio: 0.0 at start, 1.0 at end
        let progressionRatio = Double(weeksSinceStart) / Double(totalWeeks - 1)

        let intensityRange = program.endingIntensity - program.startingIntensity
        let baseIntensity = program.startingIntensity + (intensityRange * progressionRatio)

        // Clamp to program range (safety check)
        let clampedIntensity = min(max(baseIntensity, program.startingIntensity), program.endingIntensity)

        Logger.log(.debug, component: "IntensityCalculationService",
                  message: "Workout \(workout.id): week \(weeksSinceStart + 1)/\(totalWeeks), " +
                          "intensity \(Int(clampedIntensity * 100))%")

        return clampedIntensity
    }

    // MARK: - Future Extensions

    // TODO: v55.0 - Add support for non-linear progressions
    // - Wave progression (undulating intensity)
    // - Block periodization (stepped intensity)
    // - Deload weeks (reduced intensity)
    //
    // static func calculateWaveIntensity(...) -> Double { }
    // static func calculateBlockIntensity(...) -> Double { }
}
