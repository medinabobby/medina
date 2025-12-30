//
// ExerciseCard.swift
// Medina
//
// v52.5: Extracted from WorkoutDetailView
// v54.4: Fixed button hierarchy (only header tappable for expand/collapse)
// v54.5: Added program-based intensity calculation for target weights
// v72.4: Shows estimated 1RM from equivalent exercises (with ~ indicator)
// Created: November 12, 2025
// Purpose: Workout-specific exercise display with inline set expansion
//

import SwiftUI

struct ExerciseCard: View {
    let exercise: Exercise
    let instance: ExerciseInstance
    let number: String?
    let isExpanded: Bool
    let isActive: Bool  // For dimming in guided mode
    let hasLoggedData: Bool  // Exercise has logged set data
    // v55.0: Removed executionMode (guided-only)
    let isSetInteractive: (Int) -> Bool  // Callback to check if set number is interactive
    let onToggleExpansion: () -> Void
    let onSetLog: (ExerciseSet, Double, Int) -> Void
    let onSkipSet: ((String) -> Void)?  // v55.0 Phase 3: Optional skip handler (receives setId)
    let onUnskipSet: ((String) -> Void)?  // v55.0 Phase 3: Optional unskip handler (receives setId)
    let onSkipExercise: (() -> Void)?  // v55.0 Phase 3: Optional skip exercise handler
    let onResetExercise: (() -> Void)?  // Optional reset exercise handler
    let onSubstituteExercise: (() -> Void)?  // v61.1: Optional substitute exercise handler

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 0) {
                // Exercise header (tappable to expand/collapse)
                Button(action: onToggleExpansion) {
                    HStack(spacing: 12) {
                        // Number badge
                        if let number = number {
                            Text(number)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color("SecondaryText"))
                                .frame(width: 30)
                        }

                        // Exercise name and protocol info (inline)
                        VStack(alignment: .leading, spacing: 2) {
                            // Exercise name
                            Text(exercise.name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color("PrimaryText"))

                            // Line 2: Equipment + Weight/Intensity info
                            // v83.3: Use effective protocol config (applies customizations)
                            if let workout = LocalDataStore.shared.workouts[instance.workoutId],
                               let protocolConfig = InstanceInitializationService.effectiveProtocolConfig(for: instance, in: workout) {
                                Text(equipmentAndWeightInfo(protocolConfig: protocolConfig))
                                    .font(.system(size: 13))
                                    .foregroundColor(Color("SecondaryText"))

                                // Line 3: Protocol + RPE + Tempo
                                Text(protocolExecutionInfo(protocolConfig: protocolConfig))
                                    .font(.system(size: 13))
                                    .foregroundColor(Color("SecondaryText"))
                            }
                        }

                        Spacer()

                        // Expand/collapse chevron
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color("SecondaryText"))
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())  // Make entire header tappable
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("exerciseHeaderButton_\(instance.id)")
                // v55.0 Phase 3: Long-press to skip/reset exercise
                // v61.1: Added substitute exercise option
                .contextMenu {
                    // v61.1: Substitute Exercise (always available - replaces exercise even with logged data)
                    if let onSubstituteExercise = onSubstituteExercise {
                        Button(action: onSubstituteExercise) {
                            Label("Substitute Exercise", systemImage: "arrow.left.arrow.right")
                        }
                        .accessibilityIdentifier("substituteExerciseMenuItem_\(instance.id)")
                    }

                    if isActive || hasLoggedData {
                        if isActive, let onSkipExercise = onSkipExercise {
                            Button(action: onSkipExercise) {
                                Label("Skip Exercise", systemImage: "forward.end")
                            }
                            .accessibilityIdentifier("skipExerciseMenuItem_\(instance.id)")
                        }
                        if hasLoggedData, let onResetExercise = onResetExercise {
                            Button(role: .destructive, action: onResetExercise) {
                                Label("Reset Exercise", systemImage: "arrow.counterclockwise")
                            }
                            .accessibilityIdentifier("resetExerciseMenuItem_\(instance.id)")
                        }
                    }
                }

                // Inline content (when expanded) - NOT wrapped in button
                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        // Sets list only (protocol info shown at workout level)
                        exerciseInlineSets()
                    }
                    .padding(.top, 6)
                    .padding(.leading, 11)
                }
            }
            .padding(.leading, 19)
            .padding(.trailing, 16)
            .background(Color("BackgroundSecondary"))
            .cornerRadius(10)
            .opacity(!isActive ? 0.4 : 1.0)  // v55.0: Dim inactive exercises (guided-only)

            // Status stripe (covers full height)
            RoundedRectangle(cornerRadius: 10)
                .fill(statusColor)
                .frame(width: 3)
        }
        .accessibilityIdentifier("exerciseCard_\(instance.id)")
    }

    // MARK: - Helpers

    /// Status color (blue for active exercise, otherwise status-based)
    /// v55.0: Guided-only (always check isActive)
    private var statusColor: Color {
        if isActive {
            return .blue
        }
        return instance.status.statusInfo().1
    }

    /// Build line 2: Equipment + Weight/Intensity info
    private func equipmentAndWeightInfo(protocolConfig: ProtocolConfig) -> String {
        var parts: [String] = []

        // Add equipment prefix (e.g., "Barbell", "Cable", "Dumbbell")
        let equipmentPrefix = exercise.equipment.exercisePrefix
        if !equipmentPrefix.isEmpty {
            parts.append(equipmentPrefix)
        }

        // Get memberId from instance → workout → program → plan hierarchy
        let memberId: String = {
            guard let workout = LocalDataStore.shared.workouts[instance.workoutId],
                  let program = LocalDataStore.shared.programs[workout.programId],
                  let plan = LocalDataStore.shared.plans[program.planId] else {
                return "bobby"  // Fallback
            }
            return plan.memberId
        }()

        // Add exercise-type-specific target info
        switch exercise.type {
        case .compound:
            // v72.4: Compounds: Show "1RM: 195 lb • 60%" or "Est. 1RM: ~180 lb • 60%"
            if let oneRMResult = WeightCalculationService.get1RMWithEstimate(memberId: memberId, exerciseId: exercise.id) {
                // Show estimated indicator if applicable
                let prefix = oneRMResult.isEstimated ? "Est. 1RM: " : "1RM: "
                let valueStr = oneRMResult.displayString
                parts.append("\(prefix)\(valueStr) lb")

                // Calculate intensity from actual target weights in sets
                let sets = instance.setIds.compactMap { LocalDataStore.shared.exerciseSets[$0] }
                let targetWeights = sets.compactMap { $0.targetWeight }

                if !targetWeights.isEmpty {
                    let intensities = targetWeights.map { ($0 / oneRMResult.value) * 100 }
                    let minIntensity = intensities.min() ?? 0
                    let maxIntensity = intensities.max() ?? 0

                    // Show single value if all sets same intensity, otherwise range
                    if abs(minIntensity - maxIntensity) < 1.0 {
                        parts.append("\(Int(minIntensity.rounded()))%")
                    } else {
                        parts.append("\(Int(minIntensity.rounded()))-\(Int(maxIntensity.rounded()))%")
                    }
                }
            } else {
                // Show calibration needed for compounds without 1RM (no estimation available either)
                parts.append("Calibration needed")
            }

        case .isolation:
            // Isolations: Show "Working: 25-30 lb" or "Calibration needed"
            if let (lowEnd, highEnd) = WeightCalculationService.getWorkingWeightRange(
                memberId: memberId,
                exerciseId: exercise.id
            ) {
                if lowEnd == highEnd {
                    parts.append("Working: \(Int(lowEnd)) lb")
                } else {
                    parts.append("Working: \(Int(lowEnd))-\(Int(highEnd)) lb")
                }
            } else {
                parts.append("Calibration needed")
            }

        case .warmup, .cooldown, .cardio:
            // No weight info for warmup, cooldown, or cardio exercises
            break
        }

        return parts.joined(separator: " • ")
    }

    /// Build line 3: Protocol + RPE + Tempo
    private func protocolExecutionInfo(protocolConfig: ProtocolConfig) -> String {
        var parts: [String] = []

        // Add protocol variant name (e.g., "Linear 5x5", "3x10 RPE 8")
        parts.append(protocolConfig.variantName)

        // Add RPE if available
        if let rpeValues = protocolConfig.rpe, !rpeValues.isEmpty {
            let minRPE = rpeValues.min() ?? 0
            let maxRPE = rpeValues.max() ?? 0
            if minRPE == maxRPE {
                parts.append("RPE \(Int(minRPE))")
            } else {
                parts.append("RPE \(Int(minRPE))-\(Int(maxRPE))")
            }
        }

        // Add tempo if available
        if let tempo = protocolConfig.tempo {
            parts.append(tempo)
        }

        return parts.joined(separator: " • ")
    }

    /// Render inline sets with InteractiveSetCard
    @ViewBuilder
    private func exerciseInlineSets() -> some View {
        if let memberId = LocalDataStore.shared.currentUserId {
            // Apply deltas to get latest set data
            let baseSets = instance.setIds.compactMap { LocalDataStore.shared.exerciseSets[$0] }
            let setsDict = Dictionary(uniqueKeysWithValues: baseSets.map { ($0.id, $0) })
            let updatedSetsDict = DeltaStore.shared.applySetDeltas(to: setsDict)
            let sets = instance.setIds.compactMap { updatedSetsDict[$0] }
                .sorted { $0.setNumber < $1.setNumber }

            if !sets.isEmpty {
                // Get protocol config for per-set data
                // v83.3: Use effective protocol config (applies customizations)
                let protocolConfig: ProtocolConfig? = {
                    guard let workout = LocalDataStore.shared.workouts[instance.workoutId] else {
                        return LocalDataStore.shared.protocolConfigs[instance.protocolVariantId]
                    }
                    return InstanceInitializationService.effectiveProtocolConfig(for: instance, in: workout)
                }()

                // Get program to calculate base intensity
                let program: Program? = {
                    guard let workout = LocalDataStore.shared.workouts[instance.workoutId],
                          let prog = LocalDataStore.shared.programs[workout.programId] else {
                        return nil
                    }
                    return prog
                }()

                // Calculate base intensity for this workout
                let baseIntensity: Double = {
                    guard let workout = LocalDataStore.shared.workouts[instance.workoutId],
                          let prog = program else {
                        return 1.0  // Default to 100% if no program
                    }
                    return IntensityCalculationService.calculateBaseIntensity(
                        workout: workout,
                        program: prog
                    )
                }()

                ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                    let setIndex = set.setNumber - 1  // Convert to 0-indexed for array access

                    // Always recalculate target weight from current calibration data
                    // (Don't trust persisted targetWeight - calibration may have changed)
                    let calculatedTargetWeight: Double? = {
                        if let protocolConfig = protocolConfig,
                           setIndex < protocolConfig.intensityAdjustments.count {
                            let intensityOffset = protocolConfig.intensityAdjustments[setIndex]

                            // Get RPE for this specific set
                            let setRPE: Int? = {
                                guard let rpeArray = protocolConfig.rpe, setIndex < rpeArray.count else {
                                    return nil
                                }
                                return Int(rpeArray[setIndex])
                            }()

                            return WeightCalculationService.calculateTargetWeight(
                                memberId: memberId,
                                exerciseId: exercise.id,
                                exerciseType: exercise.type,
                                baseIntensity: baseIntensity,
                                intensityOffset: intensityOffset,
                                rpe: setRPE ?? 9
                            )
                        }
                        return nil
                    }()

                    // Create set with calculated target weight (always use calculated, ignore persisted)
                    let setWithTargets: ExerciseSet = {
                        var mutableSet = set
                        // Always use calculated weight (from current calibration data)
                        // Ignore persisted targetWeight (may be stale if calibration removed)
                        mutableSet.targetWeight = calculatedTargetWeight
                        return mutableSet
                    }()

                    InteractiveSetCard(
                        set: setWithTargets,
                        isDisabled: !isSetInteractive(set.setNumber),
                        completionBehavior: .automatic,  // v55.0: Guided-only (always automatic)
                        onLog: { weight, reps in
                            onSetLog(set, weight, reps)
                        },
                        onSkip: onSkipSet != nil ? {
                            onSkipSet?(set.id)
                        } : nil,
                        onUnskip: onUnskipSet != nil ? {
                            onUnskipSet?(set.id)
                        } : nil
                    )
                }
            } else {
                Text("No sets found")
                    .font(.body)
                    .foregroundColor(Color("SecondaryText"))
            }
        } else {
            Text("User not found")
                .font(.body)
                .foregroundColor(Color("SecondaryText"))
        }
    }

    // Note: isSetInteractive logic handled by parent view (WorkoutDetailView)
    // This includes session state, rest timer enforcement, and progressive set unlocking
}

// MARK: - Previews

#Preview("Regular Exercise - Guided Mode") {
    let exercise = Exercise(
        id: "squat",
        name: "Barbell Squat",
        baseExercise: "squat",
        equipment: .barbell,
        type: .compound,
        muscleGroups: [.quadriceps, .glutes],
        movementPattern: .squat,
        description: "Squat with barbell",
        instructions: "Squat down and up",
        videoLink: nil,
        experienceLevel: .intermediate,
        createdByMemberId: nil,
        createdByTrainerId: nil,
        createdByGymId: nil
    )

    let instance = ExerciseInstance(
        id: "test_instance",
        exerciseId: "squat",
        workoutId: "test_workout",
        protocolVariantId: "squat_hyp_basic",
        setIds: ["set1", "set2", "set3"],
        status: .inProgress,
        trainerInstructions: nil,
        supersetLabel: nil
    )

    ExerciseCard(
        exercise: exercise,
        instance: instance,
        number: "1",
        isExpanded: true,
        isActive: true,
        hasLoggedData: true,
        // v55.0: Removed executionMode parameter (guided-only)
        isSetInteractive: { setNum in setNum == 1 },  // Guided mode: only set 1 unlocked
        onToggleExpansion: {
            print("Toggle expansion")
        },
        onSetLog: { set, weight, reps in
            print("Logged: \(weight) lbs × \(reps) reps")
        },
        onSkipSet: { setId in
            print("Skipped set: \(setId)")
        },
        onUnskipSet: { setId in
            print("Unskipped set: \(setId)")
        },
        onSkipExercise: {
            print("Skipped exercise")
        },
        onResetExercise: {
            print("Reset exercise")
        },
        onSubstituteExercise: {
            print("Substitute exercise")
        }
    )
    .padding()
}

#Preview("Superset Exercise - Guided Mode") {
    let exercise = Exercise(
        id: "pullup",
        name: "Pull-Up",
        baseExercise: "pullup",
        equipment: .pullupBar,
        type: .compound,
        muscleGroups: [.lats, .biceps],
        movementPattern: .pull,
        description: "Pull-up exercise",
        instructions: "Pull yourself up",
        videoLink: nil,
        experienceLevel: .intermediate,
        createdByMemberId: nil,
        createdByTrainerId: nil,
        createdByGymId: nil
    )

    let instance = ExerciseInstance(
        id: "test_instance_superset",
        exerciseId: "pullup",
        workoutId: "test_workout",
        protocolVariantId: "pullup_str_basic",
        setIds: ["set1", "set2", "set3", "set4"],
        status: .inProgress,
        trainerInstructions: nil,
        supersetLabel: "1a"
    )

    ExerciseCard(
        exercise: exercise,
        instance: instance,
        number: "1a",
        isExpanded: true,
        isActive: true,
        hasLoggedData: true,
        // v55.0: Removed executionMode parameter (guided-only)
        isSetInteractive: { setNum in setNum == 1 },  // Guided mode: only set 1 unlocked
        onToggleExpansion: {
            print("Toggle expansion")
        },
        onSetLog: { set, weight, reps in
            print("Logged: \(weight) lbs × \(reps) reps")
        },
        onSkipSet: { setId in
            print("Skipped set: \(setId)")
        },
        onUnskipSet: { setId in
            print("Unskipped set: \(setId)")
        },
        onSkipExercise: {
            print("Skipped exercise")
        },
        onResetExercise: {
            print("Reset exercise")
        },
        onSubstituteExercise: {
            print("Substitute exercise")
        }
    )
    .padding()
}
