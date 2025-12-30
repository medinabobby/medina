//
// WorkoutSummaryService.swift
// Medina
//
// Created: November 13, 2025
// Purpose: Calculate summary metrics from completed workouts
//

import Foundation

// MARK: - Data Structures

struct CompletedWorkoutSummary {
    let workoutId: String
    let workoutName: String
    let scheduledDate: Date
    let duration: DurationBreakdown

    // Metrics using ProgressBreakdown (from MetricsCalculator)
    let exercises: ProgressBreakdown
    let sets: ProgressBreakdown
    let reps: ProgressBreakdown
    let volume: VolumeBreakdown

    // Detailed exercise list
    let exerciseDetails: [ExerciseSummary]
}

struct DurationBreakdown {
    let actual: TimeInterval  // seconds
    let estimated: TimeInterval  // seconds
    let percentage: Double  // 0.0 to 1.0 (actual / estimated)

    init(actual: TimeInterval, estimated: TimeInterval) {
        self.actual = actual
        self.estimated = estimated
        self.percentage = estimated > 0 ? actual / estimated : 0.0
    }

    var formattedPercentage: String {
        String(format: "%.0f%%", percentage * 100)
    }
}

struct VolumeBreakdown {
    let actual: Double  // lbs
    let target: Double  // lbs
    let percentage: Double  // 0.0 to 1.0
    let hasTarget: Bool  // v62.0: Whether target weights were available

    init(actual: Double, target: Double) {
        self.actual = actual
        self.target = target
        self.hasTarget = target > 0
        self.percentage = target > 0 ? actual / target : 0.0
    }

    var formattedPercentage: String {
        String(format: "%.0f%%", percentage * 100)
    }

    // v62.0: Display text - shows percentage if target exists, otherwise just actual
    var displayText: String {
        if hasTarget {
            return "\(Int(actual)) / \(Int(target)) lbs (\(formattedPercentage))"
        } else {
            return "\(Int(actual)) lbs lifted"
        }
    }
}

struct SetSummary {
    let setNumber: Int
    let actualWeight: Double?
    let actualReps: Int?
    let targetWeight: Double?
    let targetReps: Int?
    let completion: ExecutionStatus?

    var volumePercentage: Double {
        guard let actualWeight = actualWeight,
              let actualReps = actualReps,
              let targetWeight = targetWeight,
              let targetReps = targetReps,
              targetWeight > 0, targetReps > 0 else {
            return 0.0
        }
        let actualVolume = actualWeight * Double(actualReps)
        let targetVolume = targetWeight * Double(targetReps)
        return actualVolume / targetVolume
    }

    var formattedVolumePercentage: String {
        String(format: "%.0f%%", volumePercentage * 100)
    }
}

struct ExerciseSummary {
    let exerciseName: String
    let status: ExecutionStatus
    let setsCompleted: Int
    let setsTotal: Int
    let totalReps: Int
    let targetReps: Int
    let totalVolume: Double  // lbs
    let targetVolume: Double  // lbs
    let supersetLabel: String?
    let sets: [SetSummary]  // Detailed set breakdown

    var setsPercentage: Double {
        setsTotal > 0 ? Double(setsCompleted) / Double(setsTotal) : 0.0
    }

    var repsPercentage: Double {
        targetReps > 0 ? Double(totalReps) / Double(targetReps) : 0.0
    }

    var volumePercentage: Double {
        targetVolume > 0 ? totalVolume / targetVolume : 0.0
    }

    var formattedSetsPercentage: String {
        String(format: "%.0f%%", setsPercentage * 100)
    }

    var formattedRepsPercentage: String {
        String(format: "%.0f%%", repsPercentage * 100)
    }

    var formattedVolumePercentage: String {
        String(format: "%.0f%%", volumePercentage * 100)
    }
}

// MARK: - Service

class WorkoutSummaryService {

    /// Generate summary for a completed workout
    static func generateSummary(for workoutId: String, memberId: String) -> CompletedWorkoutSummary? {
        // Get workout
        guard let workout = LocalDataStore.shared.workouts[workoutId] else {
            return nil
        }

        // Use MetricsCalculator for exercises/sets/reps breakdown
        let metrics = MetricsCalculator.workoutProgress(for: workout, memberId: memberId)

        // Get session to calculate actual duration
        let session = LocalDataStore.shared.sessions.values.first { session in
            session.workoutId == workoutId && session.status == .completed
        }
        let actualDuration = session?.activeDuration ?? 0

        // Calculate estimated duration from protocol configs
        let estimatedMinutes = calculateEstimatedDuration(for: workout)
        let estimatedDuration = TimeInterval(estimatedMinutes * 60)  // Convert minutes to seconds

        let durationBreakdown = DurationBreakdown(actual: actualDuration, estimated: estimatedDuration)

        // Calculate volume breakdown (actual vs target)
        let volumeData = calculateVolumeBreakdown(for: workout, memberId: memberId)

        // Build exercise details for list display
        let exerciseDetails = buildExerciseDetails(for: workout)

        return CompletedWorkoutSummary(
            workoutId: workoutId,
            workoutName: workout.name,
            scheduledDate: workout.scheduledDate ?? Date(),
            duration: durationBreakdown,
            exercises: metrics.exercises,
            sets: metrics.sets,
            reps: metrics.reps,
            volume: volumeData,
            exerciseDetails: exerciseDetails
        )
    }

    // MARK: - Duration Calculation

    private static func calculateEstimatedDuration(for workout: Workout) -> Int {
        // Get protocol configs for all exercises in the workout
        var protocolConfigs: [ProtocolConfig] = []

        for (index, _) in workout.exerciseIds.enumerated() {
            let protocolVariantId = workout.protocolVariantIds[index] ?? "strength_3x8_moderate"
            if let protocolConfig = LocalDataStore.shared.protocolConfigs[protocolVariantId] {
                protocolConfigs.append(protocolConfig)
            }
        }

        // Use ExerciseTimeCalculator to estimate workout duration
        // v132: Include transition time to match DurationAwareWorkoutBuilder
        let estimatedMinutes = ExerciseTimeCalculator.calculateWorkoutTime(
            protocolConfigs: protocolConfigs,
            workoutType: workout.type,
            restBetweenExercises: 90
        )

        return estimatedMinutes
    }

    // MARK: - Volume Calculation

    private static func calculateVolumeBreakdown(for workout: Workout, memberId: String) -> VolumeBreakdown {
        // Apply deltas to get latest set data
        let updatedSets = DeltaStore.shared.applySetDeltas(to: LocalDataStore.shared.exerciseSets)
        let updatedInstances = DeltaStore.shared.applyInstanceDeltas(to: LocalDataStore.shared.exerciseInstances)

        // Build lookup of instances by exerciseId
        let instancesByExercise: [String: ExerciseInstance] = updatedInstances.values
            .filter { $0.workoutId == workout.id }
            .reduce(into: [:]) { $0[$1.exerciseId] = $1 }

        var actualVolume: Double = 0
        var targetVolume: Double = 0

        // v58.3: "Assigned Universe" - iterate ALL exercises, not just instances
        for (index, exerciseId) in workout.exerciseIds.enumerated() {
            // Get protocol config for target volume calculation
            let protocolVariantId = workout.protocolVariantIds[index] ?? "strength_3x8_moderate"
            let protocolConfig = LocalDataStore.shared.protocolConfigs[protocolVariantId]

            if let instance = instancesByExercise[exerciseId] {
                // Exercise has instance - use actual set data
                let sets = instance.setIds.compactMap { updatedSets[$0] }

                for set in sets {
                    // Actual volume (logged)
                    if let weight = set.actualWeight, let reps = set.actualReps {
                        actualVolume += weight * Double(reps)
                    }

                    // Target volume (prescribed)
                    if let targetWeight = set.targetWeight, let targetReps = set.targetReps {
                        targetVolume += targetWeight * Double(targetReps)
                    }
                }
            } else if protocolConfig != nil {
                // Exercise was skipped (no instance) - add target volume to denominator
                // Use protocol config to estimate expected volume
                // Note: We can't know exact target weight without 1RM, so use 0 for actual
                // This means skipped exercises with no prior data won't affect volume %
                // But exercises with instances that were skipped will count
            }
            // If no instance and no config, this exercise contributes 0 to both
        }

        return VolumeBreakdown(actual: actualVolume, target: targetVolume)
    }

    // MARK: - Exercise Details

    private static func buildExerciseDetails(for workout: Workout) -> [ExerciseSummary] {
        let updatedSets = DeltaStore.shared.applySetDeltas(to: LocalDataStore.shared.exerciseSets)
        var updatedInstances = LocalDataStore.shared.exerciseInstances
        updatedInstances = DeltaStore.shared.applyInstanceDeltas(to: updatedInstances)

        let instances = updatedInstances.values.filter {
            $0.workoutId == workout.id
        }.sorted { i1, i2 in
            let index1 = workout.exerciseIds.firstIndex(of: i1.exerciseId) ?? 0
            let index2 = workout.exerciseIds.firstIndex(of: i2.exerciseId) ?? 0
            return index1 < index2
        }

        var details: [ExerciseSummary] = []

        for instance in instances {
            guard let exercise = LocalDataStore.shared.exercises[instance.exerciseId] else {
                continue
            }

            let sets = instance.setIds.compactMap { updatedSets[$0] }
            var setsCompleted = 0
            var totalReps = 0
            var totalVolume: Double = 0
            var targetReps = 0
            var targetVolume: Double = 0
            var setSummaries: [SetSummary] = []

            for set in sets {
                // Build set summary
                setSummaries.append(SetSummary(
                    setNumber: set.setNumber,
                    actualWeight: set.actualWeight,
                    actualReps: set.actualReps,
                    targetWeight: set.targetWeight,
                    targetReps: set.targetReps,
                    completion: set.completion
                ))

                // Calculate actual totals
                if set.completion == .completed,
                   let weight = set.actualWeight,
                   let reps = set.actualReps {
                    setsCompleted += 1
                    totalReps += reps
                    totalVolume += weight * Double(reps)
                }

                // Calculate target totals
                if let targetWeight = set.targetWeight,
                   let targetRepsValue = set.targetReps {
                    targetReps += targetRepsValue
                    targetVolume += targetWeight * Double(targetRepsValue)
                }
            }

            let exerciseIndex = workout.exerciseIds.firstIndex(of: instance.exerciseId) ?? 0
            let supersetLabel = workout.exerciseDisplayLabel(at: exerciseIndex)

            details.append(ExerciseSummary(
                exerciseName: exercise.name,
                status: instance.status,
                setsCompleted: setsCompleted,
                setsTotal: sets.count,
                totalReps: totalReps,
                targetReps: targetReps,
                totalVolume: totalVolume,
                targetVolume: targetVolume,
                supersetLabel: supersetLabel,
                sets: setSummaries
            ))
        }

        return details
    }
}
