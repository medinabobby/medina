//
// WorkoutCalibrationService.swift
// Medina
//
// v79.4: Auto-calibrate 1RM from workout performance
// Created: December 2025
// Purpose: Update ExerciseTarget when workout performance exceeds existing estimates
//
// User decision: "Yes, auto-update" - workout performance automatically updates 1RM
//
// Progressive overload principle:
// - Only updates if new estimate > existing (never downgrades)
// - Uses "workout" calibration source for tracking
//

import Foundation

enum WorkoutCalibrationService {

    /// Update exercise targets based on workout performance
    /// Called on workout completion
    ///
    /// - Parameters:
    ///   - workoutId: The completed workout ID
    ///   - memberId: User ID for target storage
    static func calibrateFromWorkout(workoutId: String, memberId: String) {
        guard let workout = TestDataManager.shared.workouts[workoutId] else {
            Logger.log(.warning, component: "WorkoutCalibrationService",
                      message: "Cannot calibrate: Workout not found")
            return
        }

        Logger.log(.info, component: "WorkoutCalibrationService",
                  message: "Starting auto-calibration for workout: \(workout.displayName)")

        var calibratedCount = 0
        var skippedCount = 0

        // Process each exercise in the workout
        for exerciseId in workout.exerciseIds {
            // Find the instance for this exercise
            guard let instance = TestDataManager.shared.exerciseInstances.values.first(where: {
                $0.workoutId == workoutId && $0.exerciseId == exerciseId
            }) else {
                continue
            }

            // Get completed sets for this instance
            let completedSets = instance.setIds.compactMap { setId -> SetDataForRM? in
                guard let set = TestDataManager.shared.exerciseSets[setId],
                      let weight = set.actualWeight,
                      let reps = set.actualReps,
                      set.completion == .completed,
                      weight > 0, reps > 0 else {
                    return nil
                }
                return SetDataForRM(
                    weight: weight,
                    reps: reps,
                    setIndex: instance.setIds.firstIndex(of: setId) ?? 0
                )
            }

            // Skip if no completed sets
            guard !completedSets.isEmpty else {
                continue
            }

            // Calculate estimated 1RM from completed sets
            guard let estimated1RM = OneRMCalculationService.selectBest1RM(from: completedSets) else {
                continue
            }

            // Check existing target
            let targetId = "\(memberId)-\(exerciseId)"
            let existingTarget = TestDataManager.shared.targets[targetId]
            let existing1RM = existingTarget?.currentTarget

            // Progressive overload: only update if new estimate is higher
            if let existing = existing1RM, estimated1RM <= existing {
                skippedCount += 1
                Logger.log(.debug, component: "WorkoutCalibrationService",
                          message: "Skipping \(exerciseId): new \(Int(estimated1RM)) <= existing \(Int(existing))")
                continue
            }

            // Update the target
            updateTarget(
                targetId: targetId,
                exerciseId: exerciseId,
                memberId: memberId,
                new1RM: estimated1RM,
                existingTarget: existingTarget
            )
            calibratedCount += 1
        }

        // v206: Removed legacy disk persistence - Firestore is source of truth
        // TODO: Add Firestore target sync when ready
        if calibratedCount > 0 {
            Logger.log(.info, component: "WorkoutCalibrationService",
                      message: "Auto-calibrated \(calibratedCount) exercises, skipped \(skippedCount) (existing >= new)")
        } else {
            Logger.log(.debug, component: "WorkoutCalibrationService",
                      message: "No exercises calibrated (all existing >= new)")
        }
    }

    // MARK: - Private Helpers

    /// Update or create an ExerciseTarget with new 1RM from workout
    private static func updateTarget(
        targetId: String,
        exerciseId: String,
        memberId: String,
        new1RM: Double,
        existingTarget: ExerciseTarget?
    ) {
        // Round to nearest 5 lbs for cleaner display
        let rounded1RM = (new1RM / 5.0).rounded() * 5.0

        // Create or update target
        var target = existingTarget ?? ExerciseTarget(
            id: targetId,
            exerciseId: exerciseId,
            memberId: memberId,
            targetType: .max,
            currentTarget: nil,
            lastCalibrated: nil,
            targetHistory: []
        )

        let previousValue = target.currentTarget
        target.currentTarget = rounded1RM
        target.lastCalibrated = Date()

        // Add to history with "workout" source
        let historyEntry = ExerciseTarget.TargetEntry(
            date: Date(),
            target: rounded1RM,
            calibrationSource: "workout"
        )
        target.targetHistory.append(historyEntry)

        // Save to TestDataManager
        TestDataManager.shared.targets[targetId] = target

        let exerciseName = TestDataManager.shared.exercises[exerciseId]?.name ?? exerciseId
        let changeDesc = previousValue.map { " (was \(Int($0)))" } ?? " (new)"

        Logger.log(.info, component: "WorkoutCalibrationService",
                  message: "Updated \(exerciseName): \(Int(rounded1RM)) lbs\(changeDesc)")
    }
}
