//
// InstanceInitializationService.swift
// Medina
//
// v47.3: Create ExerciseInstances and ExerciseSets during plan creation
// Fixes: "This workout has no exercises yet" error when starting workouts
// v101.0: Added cardio support with targetDuration for time-based exercises
//
// Created: November 2025
//

import Foundation

enum InstanceInitializationService {

    /// Initialize exercise instances and sets for all workouts
    /// Called after ProtocolAssignmentService during plan creation
    /// - Parameters:
    ///   - workouts: Workouts with exerciseIds and protocolVariantIds populated
    ///   - memberId: Member ID for weight calculations based on 1RM
    ///   - weeklyIntensities: Dictionary mapping workout ID to program intensity for that week
    static func initializeInstances(for workouts: [Workout], memberId: String, weeklyIntensities: [String: Double]) {
        for workout in workouts {
            let programIntensity = weeklyIntensities[workout.id] ?? 0.65  // Default to 65% if not found
            createInstances(for: workout, memberId: memberId, programIntensity: programIntensity)
        }

        Logger.log(.info, component: "InstanceInitializationService",
                  message: "Created instances and sets for \(workouts.count) workouts")
    }

    /// Create exercise instances and sets for a single workout
    /// - Parameters:
    ///   - workout: Workout with exerciseIds and protocolVariantIds populated
    ///   - memberId: Member ID for weight calculations based on 1RM
    ///   - programIntensity: Program's weekly intensity for this workout
    private static func createInstances(for workout: Workout, memberId: String, programIntensity: Double) {
        guard !workout.exerciseIds.isEmpty else {
            Logger.log(.warning, component: "InstanceInitializationService",
                      message: "Workout \(workout.id) has no exerciseIds, skipping instance creation")
            return
        }

        for (index, exerciseId) in workout.exerciseIds.enumerated() {
            createInstance(
                for: workout,
                exerciseId: exerciseId,
                position: index,
                memberId: memberId,
                programIntensity: programIntensity
            )
        }
    }

    /// Create an exercise instance and its sets for one exercise in a workout
    /// - Parameters:
    ///   - workout: Parent workout
    ///   - exerciseId: Exercise ID (e.g., "barbell_bench_press")
    ///   - position: Position in workout (0-indexed)
    ///   - memberId: Member ID for weight calculations based on 1RM
    ///   - programIntensity: Program's weekly intensity for this workout
    private static func createInstance(for workout: Workout, exerciseId: String, position: Int, memberId: String, programIntensity: Double) {
        // Instance ID pattern: {workoutId}_ex{position}
        let instanceId = "\(workout.id)_ex\(position)"

        // Get protocol variant ID from workout's protocolVariantIds dictionary
        guard let protocolVariantId = workout.protocolVariantIds[position] else {
            Logger.log(.warning, component: "InstanceInitializationService",
                      message: "No protocol variant found for workout \(workout.id) position \(position)")
            return
        }

        // Get protocol config to determine set count
        guard let baseProtocolConfig = LocalDataStore.shared.protocolConfigs[protocolVariantId] else {
            Logger.log(.warning, component: "InstanceInitializationService",
                      message: "Protocol config not found: \(protocolVariantId)")
            return
        }

        // v82.4: Apply AI protocol customizations if present
        let protocolConfig: ProtocolConfig
        if let customization = workout.protocolCustomizations?[position] {
            protocolConfig = customization.apply(to: baseProtocolConfig)
            Logger.log(.info, component: "InstanceInitializationService",
                      message: "v82.4: Applied customization at position \(position): tempo=\(customization.tempoOverride ?? "base"), rpe=\(customization.rpeOverride.map { String($0) } ?? "base")")
        } else {
            protocolConfig = baseProtocolConfig
        }

        // Create set IDs based on protocol's rep count
        let setCount = protocolConfig.reps.count
        let setIds = (1...setCount).map { "\(instanceId)_s\($0)" }

        // v50: Calculate superset label if exercise is in a superset group
        let supersetLabel: String? = {
            if let supersetGroup = workout.supersetGroup(for: position) {
                return supersetGroup.label(for: position)
            }
            return nil
        }()

        // Create exercise instance
        let instance = ExerciseInstance(
            id: instanceId,
            exerciseId: exerciseId,
            workoutId: workout.id,
            protocolVariantId: protocolVariantId,
            setIds: setIds,
            status: .scheduled,
            trainerInstructions: nil,
            supersetLabel: supersetLabel
        )

        // Store in LocalDataStore
        LocalDataStore.shared.exerciseInstances[instanceId] = instance

        // Create sets
        createSets(
            for: instance,
            protocolConfig: protocolConfig,
            memberId: memberId,
            exerciseId: exerciseId,
            programIntensity: programIntensity
        )
    }

    /// Create exercise sets for an instance
    /// - Parameters:
    ///   - instance: Parent exercise instance
    ///   - protocolConfig: Protocol configuration with reps/intensity data
    ///   - memberId: Member ID for weight calculations based on 1RM
    ///   - exerciseId: Exercise ID for looking up 1RM targets
    ///   - programIntensity: Program's weekly intensity (e.g., 0.65 for week 2 of 60%-70% progression)
    private static func createSets(for instance: ExerciseInstance, protocolConfig: ProtocolConfig, memberId: String, exerciseId: String, programIntensity: Double) {
        // Get exercise to determine type (compound vs isolation)
        guard let exercise = LocalDataStore.shared.exercises[exerciseId] else {
            Logger.log(.warning, component: "InstanceInitializationService",
                      message: "Exercise not found: \(exerciseId)")
            return
        }

        for (index, setId) in instance.setIds.enumerated() {
            let setNumber = index + 1  // Sets are 1-indexed

            // Get target reps from protocol config
            let targetReps = index < protocolConfig.reps.count ? protocolConfig.reps[index] : nil

            // Get target RPE from protocol config (for this specific set)
            let targetRPE: Int? = {
                guard let rpeArray = protocolConfig.rpe, index < rpeArray.count else {
                    return nil
                }
                return Int(rpeArray[index])
            }()

            // v80.5: Calculate target weight based on exercise type AND equipment
            // Resistance bands and bodyweight use RPE, not weight
            let targetWeight: Double? = {
                // Skip weight calculation for equipment that uses RPE
                switch exercise.equipment {
                case .resistanceBand, .bodyweight:
                    // These use RPE-based intensity, not weight
                    // targetRPE is already populated from protocolConfig
                    return nil

                default:
                    // Standard equipment (barbell, dumbbells, machine, cable) uses weight
                    break
                }

                switch exercise.type {
                case .compound:
                    // Compound exercises: Use 1RM × (base intensity + protocol offset)
                    let intensityOffset = index < protocolConfig.intensityAdjustments.count
                        ? protocolConfig.intensityAdjustments[index]
                        : 0.0

                    return WeightCalculationService.calculateTargetWeight(
                        memberId: memberId,
                        exerciseId: exerciseId,
                        exerciseType: .compound,
                        baseIntensity: programIntensity,
                        intensityOffset: intensityOffset
                    )

                case .isolation:
                    // Isolation exercises: Use working weight approach
                    return WeightCalculationService.calculateTargetWeight(
                        memberId: memberId,
                        exerciseId: exerciseId,
                        exerciseType: .isolation,
                        baseIntensity: programIntensity,
                        intensityOffset: 0.0,
                        rpe: targetRPE ?? 9  // Default to RPE 9 if not specified
                    )

                case .warmup, .cooldown, .cardio:
                    // No target weight for warmup, cooldown, or cardio exercises
                    return nil
                }
            }()

            // v101.0: Calculate target duration for cardio exercises
            let targetDuration: Int? = {
                if exercise.type == .cardio, let duration = protocolConfig.duration {
                    // Cardio exercises use duration from protocol config
                    return duration
                }
                return nil
            }()

            // Create set
            // v80.5: Include targetRPE for bands/bodyweight (when targetWeight is nil)
            // v101.0: Include targetDuration for cardio exercises
            let set = ExerciseSet(
                id: setId,
                exerciseInstanceId: instance.id,
                setNumber: setNumber,
                targetWeight: targetWeight,
                targetReps: targetReps,
                targetRPE: targetWeight == nil && targetDuration == nil ? (targetRPE ?? 7) : nil,  // Only set RPE when no weight and not cardio
                actualWeight: nil,
                actualReps: nil,
                targetDuration: targetDuration,
                targetDistance: nil,  // Distance can be set per-exercise if needed
                actualDuration: nil,
                actualDistance: nil,
                completion: .scheduled,
                startTime: nil,
                endTime: nil,
                notes: nil,
                recordedDate: nil
            )

            // Store in LocalDataStore
            LocalDataStore.shared.exerciseSets[setId] = set
        }
        // v63.0: Removed per-instance logging (was causing 6000+ lines for plan creation)
        // Summary log at initializeInstances() level is sufficient
    }


    // MARK: - v83.3: Effective Protocol Config

    /// Get the effective ProtocolConfig for an instance, applying any customizations
    /// This should be used by UI to display customized values instead of base protocol
    /// - Parameters:
    ///   - instance: Exercise instance
    ///   - workout: Parent workout (to get customizations)
    /// - Returns: ProtocolConfig with customizations applied, or nil if base not found
    static func effectiveProtocolConfig(for instance: ExerciseInstance, in workout: Workout) -> ProtocolConfig? {
        // Get base protocol config
        guard let baseConfig = LocalDataStore.shared.protocolConfigs[instance.protocolVariantId] else {
            return nil
        }

        // Find position of this instance in workout
        // Instance ID format: {workoutId}_ex{position}
        let positionStr = instance.id.replacingOccurrences(of: "\(workout.id)_ex", with: "")
        guard let position = Int(positionStr) else {
            return baseConfig
        }

        // Apply customization if present
        if let customization = workout.protocolCustomizations?[position] {
            return customization.apply(to: baseConfig)
        }

        return baseConfig
    }
}

// v101.0: Removed ExerciseSet memberwise initializer extension
// ExerciseSet now has a built-in memberwise initializer in ExerciseSet.swift with cardio fields
