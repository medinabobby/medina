//
// ProtocolAssignmentService.swift
// Medina
//
// v43 Phase 2: Protocol assignment based on program intensity progression
// v51.0 Phase 1b: Library-first protocol assignment
// v173: Added protocol-exercise type validation
// Created: October 28, 2025
// Updated: November 5, 2025
//

import Foundation

/// Protocol assignment service using user library
///
/// **v51.0: Library-First Selection**
///
/// Uses LibraryProtocolSelector to match protocols from user's curated library:
/// 1. Exercise type (compound vs isolation)
/// 2. Weekly intensity from program progression (60% → 80% over 3 weeks)
/// 3. Goal preference matching
/// 4. Selection weight ranking
///
/// **Fallback:** If user has no library (legacy users), falls back to hard-coded protocol mapping
///
/// **Usage:**
/// ```swift
/// let workoutsWithProtocols = ProtocolAssignmentService.assignProtocols(
///     for: workoutsWithExercises,
///     program: program,
///     userId: memberId,
///     goal: plan.goal
/// )
/// ```
enum ProtocolAssignmentService {

    // MARK: - Public API

    /// Assign protocols to all workouts in a program
    ///
    /// **v51.0 Process:**
    /// 1. Load user's library from LocalDataStore
    /// 2. Calculate weekly intensity progression for program
    /// 3. For each workout, determine week number
    /// 4. For each exercise, use LibraryProtocolSelector or fallback to hard-coded mapping
    /// 5. Map protocol to exercise position: {0: "protocol_5x5", 1: "protocol_3x8", ...}
    ///
    /// - Parameters:
    ///   - workouts: Workouts with exerciseIds populated (from Phase 1)
    ///   - program: Program with intensity progression fields
    ///   - userId: User ID to load library for
    ///   - goal: Fitness goal for protocol preference matching
    /// - Returns: Tuple of (workouts with protocolVariantIds populated, workout ID → intensity mapping)
    static func assignProtocols(for workouts: [Workout], program: Program, userId: String, goal: FitnessGoal) -> (workouts: [Workout], intensities: [String: Double]) {
        // v51.0: Load user's library
        let library = LocalDataStore.shared.libraries[userId]
        // Calculate weekly intensity progression
        let weeklyIntensities = calculateWeeklyIntensities(for: program)

        var workoutIntensities: [String: Double] = [:]

        let updatedWorkouts = workouts.map { workout in
            var updated = workout

            // Determine week number for this workout
            let weekNumber = calculateWeekNumber(
                workoutDate: workout.scheduledDate ?? program.startDate,
                programStart: program.startDate
            )

            // Get intensity for this week (clamp to available weeks)
            let weekIndex = min(weekNumber - 1, weeklyIntensities.count - 1)
            let weeklyIntensity = weeklyIntensities[weekIndex]

            // Store intensity for this workout
            workoutIntensities[workout.id] = weeklyIntensity

            // Assign protocol for each exercise
            updated.protocolVariantIds = assignProtocolsForExercises(
                exerciseIds: workout.exerciseIds,
                weeklyIntensity: weeklyIntensity,
                progressionType: program.progressionType,
                library: library,
                goal: goal
            )

            return updated
        }

        return (updatedWorkouts, workoutIntensities)
    }

    // MARK: - Weekly Intensity Calculation

    /// Calculate weekly intensity progression for program
    ///
    /// **Algorithm:**
    /// - Linear: Straight line from startingIntensity → endingIntensity
    /// - Undulating: Wave pattern with 2-week cycles (up week, down week)
    /// - Static: Constant intensity (no progression)
    ///
    /// **Example (Linear, 3 weeks, 60% → 90%):**
    /// ```
    /// Week 1: 60% (starting)
    /// Week 2: 75% (midpoint)
    /// Week 3: 90% (ending)
    /// Delta: 30% / 3 weeks = 10% per week
    /// ```
    ///
    /// - Parameter program: Program with intensity fields
    /// - Returns: Array of weekly intensities (one per week)
    private static func calculateWeeklyIntensities(for program: Program) -> [Double] {
        let calendar = Calendar.current
        let weeks = calendar.dateComponents([.weekOfYear], from: program.startDate, to: program.endDate).weekOfYear ?? 1
        let weekCount = max(1, weeks)

        // v58.3: Guard against single-week programs (single workouts)
        // No progression needed - just return starting intensity
        if weekCount <= 1 {
            return [program.startingIntensity]
        }

        var intensities: [Double] = []

        switch program.progressionType {
        case .linear:
            // Linear progression: Straight line from start → end
            let delta = program.endingIntensity - program.startingIntensity
            let incrementPerWeek = delta / Double(weekCount - 1)

            for week in 0..<weekCount {
                let intensity = program.startingIntensity + (incrementPerWeek * Double(week))
                intensities.append(intensity)
            }

        case .undulating:
            // Undulating progression: Wave pattern (2-week cycles)
            // Odd weeks: Progress toward ending intensity
            // Even weeks: Drop back 10% for recovery
            let delta = program.endingIntensity - program.startingIntensity
            let incrementPerWeek = delta / Double(weekCount / 2)

            for week in 0..<weekCount {
                if week % 2 == 0 {
                    // Odd week (progress)
                    let intensity = program.startingIntensity + (incrementPerWeek * Double(week / 2))
                    intensities.append(intensity)
                } else {
                    // Even week (recovery - drop back 10%)
                    let previousIntensity = intensities[week - 1]
                    intensities.append(previousIntensity - 0.10)
                }
            }

        case .staticProgression:
            // Static: No progression, use starting intensity throughout
            for _ in 0..<weekCount {
                intensities.append(program.startingIntensity)
            }
        }

        return intensities
    }

    /// Calculate week number for a workout date
    ///
    /// - Parameters:
    ///   - workoutDate: Scheduled workout date
    ///   - programStart: Program start date
    /// - Returns: Week number (1-based, e.g., Week 1, Week 2, etc.)
    private static func calculateWeekNumber(workoutDate: Date, programStart: Date) -> Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: programStart, to: workoutDate).day ?? 0
        return max(1, (days / 7) + 1)
    }

    // MARK: - Protocol Selection

    /// Assign protocols for all exercises in a workout
    ///
    /// **v51.0 Logic:**
    /// - If library available: Use LibraryProtocolSelector for protocol matching
    /// - If library unavailable: Fall back to hard-coded protocol selection
    ///
    /// - Parameters:
    ///   - exerciseIds: Exercise IDs for workout
    ///   - weeklyIntensity: Intensity for this week (0.5-1.0)
    ///   - progressionType: Progression type (affects protocol style)
    ///   - library: User's protocol library (optional)
    ///   - goal: Fitness goal for protocol preference matching
    /// - Returns: Dictionary mapping position → protocolVariantId
    private static func assignProtocolsForExercises(
        exerciseIds: [String],
        weeklyIntensity: Double,
        progressionType: ProgressionType,
        library: UserLibrary?,
        goal: FitnessGoal
    ) -> [Int: String] {
        var protocolVariantIds: [Int: String] = [:]

        for (index, exerciseId) in exerciseIds.enumerated() {
            guard let exercise = LocalDataStore.shared.exercises[exerciseId] else {
                continue
            }

            // v51.0: Use library selector if available
            // v80.5: Pass equipment to filter incompatible protocols for bands/bodyweight
            var protocolId: String?
            if let library = library {
                protocolId = LibraryProtocolSelector.match(
                    from: library,
                    exerciseType: exercise.type,
                    currentIntensity: weeklyIntensity,
                    goal: goal,
                    equipment: exercise.equipment
                )
            }

            // Fallback to hard-coded selection if library unavailable or no match
            if protocolId == nil {
                protocolId = selectProtocol(
                    exerciseType: exercise.type,
                    intensity: weeklyIntensity,
                    progressionType: progressionType
                )
            }

            // v173: Validate protocol-exercise compatibility and fix if needed
            if let assignedProtocol = protocolId,
               !isProtocolExerciseCompatible(protocolId: assignedProtocol, exerciseId: exerciseId) {
                // Replace with compatible fallback
                let fallbackProtocol = getCompatibleFallbackProtocol(
                    for: exercise.type,
                    intensity: weeklyIntensity
                )
                Logger.log(.info, component: "ProtocolAssignmentService",
                    message: "✅ v173: Replaced incompatible protocol '\(assignedProtocol)' with '\(fallbackProtocol)' for exercise '\(exerciseId)'")
                protocolId = fallbackProtocol
            }

            protocolVariantIds[index] = protocolId
        }

        return protocolVariantIds
    }

    // MARK: - v58.4 Data-Driven Protocol Selection

    /// Select protocol config for an exercise using data-driven matching
    ///
    /// **v58.4: Rule-Based Selection**
    /// 1. Query available protocol configs from LocalDataStore
    /// 2. Filter by exercise type (compound → lower reps, isolation → higher reps)
    /// 3. Match intensity to protocol's average RPE
    /// 4. Fallback to defaults if no match
    ///
    /// **Intensity → RPE Mapping:**
    /// - Low intensity (0.5-0.65): RPE 6-7 (foundation building)
    /// - Medium intensity (0.65-0.80): RPE 7-8 (development)
    /// - High intensity (0.80-1.0): RPE 8-9.5 (peaking)
    ///
    /// - Parameters:
    ///   - exerciseType: Compound or isolation
    ///   - intensity: Weekly intensity (0.5-1.0)
    ///   - progressionType: Linear, undulating, or static
    /// - Returns: Protocol config ID
    private static func selectProtocol(
        exerciseType: ExerciseType,
        intensity: Double,
        progressionType: ProgressionType
    ) -> String {
        // v58.4: Try data-driven selection first
        if let matchedProtocol = selectProtocolDataDriven(
            exerciseType: exerciseType,
            intensity: intensity,
            progressionType: progressionType
        ) {
            return matchedProtocol
        }

        // Fallback to defaults if data-driven selection fails
        return selectProtocolDefault(
            exerciseType: exerciseType,
            intensity: intensity,
            progressionType: progressionType
        )
    }

    /// Data-driven protocol selection based on protocol configs
    private static func selectProtocolDataDriven(
        exerciseType: ExerciseType,
        intensity: Double,
        progressionType: ProgressionType
    ) -> String? {
        let allConfigs = LocalDataStore.shared.protocolConfigs

        // Map intensity to target RPE range
        let targetRPE: ClosedRange<Double> = {
            if intensity < 0.65 {
                return 6.0...7.5  // Low intensity = lower RPE
            } else if intensity < 0.80 {
                return 7.0...8.5  // Medium intensity
            } else {
                return 8.0...10.0 // High intensity
            }
        }()

        // Map exercise type to rep range
        let targetReps: ClosedRange<Int> = {
            switch exerciseType {
            case .compound:
                return intensity < 0.65 ? 5...8 : (intensity < 0.80 ? 3...6 : 1...5)
            case .isolation:
                return intensity < 0.65 ? 10...15 : (intensity < 0.80 ? 8...12 : 6...10)
            default:
                return 8...12
            }
        }()

        // Filter and rank protocol configs
        let candidates = allConfigs.values.filter { config in
            // Check rep range matches exercise type
            let avgReps = config.reps.reduce(0, +) / max(1, config.reps.count)
            guard targetReps.contains(avgReps) else { return false }

            // Check RPE matches intensity (skip if no RPE data)
            guard let rpeArray = config.rpe, !rpeArray.isEmpty else { return false }
            let avgRPE = rpeArray.reduce(0.0, +) / Double(rpeArray.count)
            guard targetRPE.contains(avgRPE) else { return false }

            return true
        }

        // Rank by how close to target intensity
        let ranked = candidates.sorted { config1, config2 in
            let rpe1 = (config1.rpe ?? []).reduce(0.0, +) / Double(max(1, (config1.rpe ?? []).count))
            let rpe2 = (config2.rpe ?? []).reduce(0.0, +) / Double(max(1, (config2.rpe ?? []).count))
            let targetRPEValue = intensity * 10  // 0.75 → 7.5 RPE
            return abs(rpe1 - targetRPEValue) < abs(rpe2 - targetRPEValue)
        }

        if let best = ranked.first {
            Logger.log(.debug, component: "ProtocolAssignmentService",
                      message: "📋 Data-driven match: \(best.id) for \(exerciseType.displayName) at \(Int(intensity * 100))%")
            return best.id
        }

        return nil
    }

    /// Default protocol selection (fallback)
    private static func selectProtocolDefault(
        exerciseType: ExerciseType,
        intensity: Double,
        progressionType: ProgressionType
    ) -> String {
        // v58.4: Configurable intensity thresholds
        let lowThreshold = 0.65
        let mediumThreshold = 0.80

        switch exerciseType {
        case .compound:
            if intensity < lowThreshold {
                return "strength_3x5_moderate"
            } else if intensity < mediumThreshold {
                return "strength_3x5_heavy"
            } else {
                return progressionType == .linear ? "strength_3x3_heavy" : "waves_5_4_3_2_1_variant"
            }

        case .isolation:
            if intensity < lowThreshold {
                return "accessory_3x12_light"
            } else if intensity < mediumThreshold {
                return "accessory_3x10_rpe8"
            } else {
                return "accessory_3x8_rpe8"
            }

        case .warmup, .cooldown:
            return "accessory_3x10_rpe8"

        case .cardio:
            // v173: Return a cardio protocol for cardio exercises (not strength!)
            return "cardio_30min_steady"
        }
    }

    // MARK: - v173 Protocol-Exercise Compatibility Validation

    /// Validate that a protocol is compatible with an exercise type
    ///
    /// **Rules:**
    /// - Cardio protocols (protocolFamily contains "cardio") → only for cardio exercises
    /// - Strength protocols → only for compound/isolation exercises
    /// - Warmup/cooldown exercises are flexible (can use either)
    ///
    /// - Parameters:
    ///   - protocolId: Protocol config ID to validate
    ///   - exerciseId: Exercise ID to validate against
    /// - Returns: true if compatible, false if mismatch detected
    static func isProtocolExerciseCompatible(protocolId: String, exerciseId: String) -> Bool {
        guard let exercise = LocalDataStore.shared.exercises[exerciseId],
              let protocolConfig = LocalDataStore.shared.protocolConfigs[protocolId] else {
            return true  // Allow if we can't validate (missing data)
        }

        let isCardioProtocol = protocolConfig.protocolFamily?.contains("cardio") ?? false
        let isCardioExercise = exercise.type == .cardio

        // Warmup/cooldown exercises are flexible
        if exercise.type == .warmup || exercise.type == .cooldown {
            return true
        }

        // Cardio protocols should only go to cardio exercises
        // Strength protocols should only go to strength exercises (compound/isolation)
        if isCardioProtocol != isCardioExercise {
            Logger.log(.warning, component: "ProtocolAssignmentService",
                message: "⚠️ v173: Protocol-exercise mismatch detected! Protocol '\(protocolId)' (cardio=\(isCardioProtocol)) assigned to exercise '\(exerciseId)' (cardio=\(isCardioExercise))")
            return false
        }

        return true
    }

    /// Get a compatible fallback protocol when a mismatch is detected
    ///
    /// - Parameters:
    ///   - exerciseType: The exercise type that needs a protocol
    ///   - intensity: Current intensity level
    /// - Returns: A protocol ID that is compatible with the exercise type
    static func getCompatibleFallbackProtocol(for exerciseType: ExerciseType, intensity: Double) -> String {
        switch exerciseType {
        case .cardio:
            // Return cardio protocol
            if intensity < 0.65 {
                return "cardio_20min_steady"
            } else if intensity < 0.80 {
                return "cardio_30min_steady"
            } else {
                return "cardio_intervals_hiit_20min"  // High intensity cardio
            }

        case .compound:
            if intensity < 0.65 {
                return "strength_3x5_moderate"
            } else if intensity < 0.80 {
                return "strength_3x5_heavy"
            } else {
                return "strength_3x3_heavy"
            }

        case .isolation:
            if intensity < 0.65 {
                return "accessory_3x12_light"
            } else if intensity < 0.80 {
                return "accessory_3x10_rpe8"
            } else {
                return "accessory_3x8_rpe8"
            }

        case .warmup, .cooldown:
            return "accessory_3x10_rpe8"
        }
    }

    // MARK: - v236: Protocol Config Lookup

    /// Get effective protocol configuration for an exercise instance
    ///
    /// Looks up the protocol by ID from the cached protocol configs.
    /// Used for displaying RPE, tempo, and other protocol info during workout execution.
    ///
    /// - Parameters:
    ///   - instance: The exercise instance to get config for
    ///   - workout: The workout containing the instance (for protocolVariantIds lookup)
    /// - Returns: ProtocolConfig if found, nil otherwise
    static func effectiveProtocolConfig(for instance: ExerciseInstance, in workout: Workout) -> ProtocolConfig? {
        // Get the protocol ID for this instance
        let protocolId = instance.protocolVariantId

        // Try to find in cached protocol configs
        return LocalDataStore.shared.protocolConfigs[protocolId]
    }
}
