//
// DurationAwareWorkoutBuilder.swift
// Medina
//
// v82.0 - Duration-Aware Workout Building
// Created: December 2025
//
// Problem: Exercise count decided BEFORE protocols assigned → duration unknown
// Solution: Iterative select-assign-verify loop until target duration reached
//
// The key insight is that bodyweight protocols may have different durations than
// gym protocols (e.g., tempo-based bodyweight takes longer than generic accessory).
// This builder selects exercises, assigns protocols, verifies actual duration,
// and adds/removes exercises until the target is met.
//

import Foundation

/// Result of duration-aware workout building
struct DurationAwareWorkoutResult {
    let exerciseIds: [String]
    let protocolVariantIds: [Int: String]
    let actualDuration: Int  // Minutes
    let targetDuration: Int  // Minutes
    let iterationsUsed: Int

    // v82.0: Track when builder had to supplement AI's selection
    let aiExerciseCount: Int      // How many exercises AI originally provided
    let supplementedCount: Int    // How many exercises were added from library

    /// True if builder added exercises beyond what AI suggested to meet duration
    var wasSupplemented: Bool { supplementedCount > 0 }

    /// Shortfall in minutes if target wasn't fully met
    var durationShortfall: Int { max(0, targetDuration - actualDuration) }
}

/// Service for building workouts that actually match requested duration
enum DurationAwareWorkoutBuilder {

    // MARK: - Configuration

    /// Tolerance for duration matching (workout can be this many minutes under target)
    private static let toleranceMinutes = 5

    /// Maximum iterations to prevent infinite loops
    private static let maxIterations = 10

    /// v124: Time between exercises for setup/transition (walk to equipment, load weights, adjust seat)
    /// Industry standard: real workouts take ~7-10 min per exercise including setup, not just work time
    private static let transitionTimeSeconds = 90  // 1.5 min between exercises

    /// Equipment-aware average time estimates (minutes per exercise)
    /// v124: Updated to include realistic setup/transition time
    /// Industry research: real workouts take ~7-10 min per exercise total, not 5-6 min pure work time
    private static func estimatedTimePerExercise(equipment: Equipment) -> Double {
        switch equipment {
        case .bodyweight:
            // Bodyweight: minimal setup, but includes transition
            return 8.0
        case .resistanceBand:
            // Bands: quick setup, includes transition
            return 8.0
        case .cableMachine:
            // Cables: adjusting pulleys, selecting weight
            return 8.5
        case .machine:
            // Machines: seat adjustment, pin selection
            return 8.0
        default:
            // Barbell/dumbbell: most setup time (loading plates, finding weights)
            return 9.5
        }
    }

    // MARK: - Main Builder

    /// Build workout with iterative select-assign-verify loop
    /// - Parameters:
    ///   - targetDuration: Requested workout duration in minutes
    ///   - splitDay: Workout split day
    ///   - plan: Plan for equipment/muscle constraints
    ///   - program: Program for protocol assignment
    ///   - userId: User ID for library access
    ///   - aiExerciseIds: Optional AI-provided exercise IDs (will be used if valid)
    ///   - movementPatternFilter: v87.0 - Movement pattern constraint (PRIMARY filter when provided)
    ///   - overrideProtocolId: v87.3 - If set, use this protocol for ALL exercises (ensures duration accuracy)
    ///   - exerciseCountOverride: v103 - If set, use this exact count instead of calculating from duration
    /// - Returns: Result with exercise IDs, protocol IDs, and actual duration
    static func build(
        targetDuration: Int,
        splitDay: SplitDay,
        plan: Plan,
        program: Program,
        userId: String,
        aiExerciseIds: [String]? = nil,
        movementPatternFilter: [MovementPattern]? = nil,  // v87.0: PRIMARY filter
        overrideProtocolId: String? = nil,  // v87.3: Override all protocols for duration accuracy
        exerciseCountOverride: Int? = nil  // v103: Override count for image extraction
    ) -> DurationAwareWorkoutResult {

        // 1. Determine primary equipment type for time estimation
        let primaryEquipment = determinePrimaryEquipment(
            location: plan.trainingLocation,
            availableEquipment: plan.availableEquipment
        )

        // 2. Calculate initial exercise count (conservative)
        // v103: Use override if provided (for image-based workout creation)
        var targetExerciseCount: Int
        if let override = exerciseCountOverride {
            targetExerciseCount = override
            Logger.log(.info, component: "DurationAwareWorkoutBuilder",
                message: "v103: Using exercise count override: \(override)")
        } else {
            let avgTimePerExercise = estimatedTimePerExercise(equipment: primaryEquipment)
            targetExerciseCount = Int(floor(Double(targetDuration) / avgTimePerExercise))
            // Ensure at least 3 exercises
            targetExerciseCount = max(3, targetExerciseCount)
        }

        Logger.log(.info, component: "DurationAwareWorkoutBuilder",
            message: "Starting build: target=\(targetDuration)min, equipment=\(primaryEquipment.rawValue), exercises=\(targetExerciseCount)\(exerciseCountOverride != nil ? " (override)" : "")")


        // 3. Count AI-provided exercises (before merging with library)
        let aiExerciseCount = aiExerciseIds?.count ?? 0

        // v85.0: Log movement pattern filter if specified
        if let patterns = movementPatternFilter, !patterns.isEmpty {
            Logger.log(.info, component: "DurationAwareWorkoutBuilder",
                message: "v85.0: Movement pattern filter active: \(patterns.map { $0.rawValue })")
        }

        // 4. Get candidate exercises (AI + library)
        // v87.0: When movementPatternFilter provided, it's the PRIMARY filter (no muscle fallback)
        let candidateExercises = getCandidateExercises(
            splitDay: splitDay,
            plan: plan,
            userId: userId,
            aiExerciseIds: aiExerciseIds,
            movementPatternFilter: movementPatternFilter  // v87.0: PRIMARY filter
        )

        guard !candidateExercises.isEmpty else {
            Logger.log(.error, component: "DurationAwareWorkoutBuilder",
                message: "No candidate exercises available")
            return DurationAwareWorkoutResult(
                exerciseIds: [],
                protocolVariantIds: [:],
                actualDuration: 0,
                targetDuration: targetDuration,
                iterationsUsed: 0,
                aiExerciseCount: aiExerciseCount,
                supplementedCount: 0
            )
        }

        // v95.0: Safety check - minimum 3 exercises for any workout
        // If we have fewer candidates than needed for a basic workout, log a warning
        // This prevents the "4 minute workout for 45 minute request" bug
        let minExercisesForBasicWorkout = 3
        if candidateExercises.count < minExercisesForBasicWorkout {
            Logger.log(.warning, component: "DurationAwareWorkoutBuilder",
                message: "⚠️ v95.0: Only \(candidateExercises.count) candidate exercises available (minimum \(minExercisesForBasicWorkout) recommended for target \(targetDuration)min)")
        }

        // 5. Iterative select-assign-verify loop
        // v82.0: Bidirectional adjustment - add if under, remove if over
        // v193: Skip iteration when exerciseCountOverride is set - honor the exact count from image
        var selectedExercises: [String] = []
        var protocolIds: [Int: String] = [:]
        var actualDuration = 0
        var iteration = 0
        var lastDirection: String? = nil  // Track to prevent oscillation

        // v193: When exerciseCountOverride is provided (e.g., from image extraction),
        // honor that exact count - don't add/remove exercises based on duration
        let honorExactCount = exerciseCountOverride != nil

        while iteration < maxIterations {
            iteration += 1

            // Select exercises up to target count
            selectedExercises = Array(candidateExercises.prefix(targetExerciseCount))

            // Assign protocols to selected exercises
            // v87.3: Pass overrideProtocolId if AI specified a protocol
            protocolIds = assignProtocols(
                exerciseIds: selectedExercises,
                program: program,
                plan: plan,
                userId: userId,
                overrideProtocolId: overrideProtocolId
            )

            // Calculate actual duration
            actualDuration = calculateActualDuration(
                exerciseIds: selectedExercises,
                protocolIds: protocolIds
            )

            Logger.log(.debug, component: "DurationAwareWorkoutBuilder",
                message: "Iteration \(iteration): \(selectedExercises.count) exercises = \(actualDuration)min")

            // v193: If exerciseCountOverride was provided, use exactly that count - no iteration
            if honorExactCount {
                Logger.log(.info, component: "DurationAwareWorkoutBuilder",
                    message: "v193: Honoring exerciseCountOverride=\(exerciseCountOverride!) - using exactly \(selectedExercises.count) exercises (\(actualDuration)min)")
                break
            }

            // v82.0: Check if within acceptable range (target ± tolerance)
            let lowerBound = targetDuration - toleranceMinutes
            let upperBound = targetDuration + toleranceMinutes

            if actualDuration >= lowerBound && actualDuration <= upperBound {
                Logger.log(.info, component: "DurationAwareWorkoutBuilder",
                    message: "✅ Target met: \(actualDuration)min within \(lowerBound)-\(upperBound)min range")
                break
            }

            // Under target - try to add more exercises
            if actualDuration < lowerBound {
                if targetExerciseCount < candidateExercises.count && lastDirection != "remove" {
                    targetExerciseCount += 1
                    lastDirection = "add"
                    Logger.log(.debug, component: "DurationAwareWorkoutBuilder",
                        message: "Under target (\(actualDuration)min < \(lowerBound)min), adding exercise")
                } else {
                    Logger.log(.warning, component: "DurationAwareWorkoutBuilder",
                        message: "⚠️ Cannot reach target. Best: \(actualDuration)min (target: \(targetDuration)min)")
                    break
                }
            }
            // Over target - try to remove exercises (but keep minimum 3)
            else if actualDuration > upperBound {
                if targetExerciseCount > 3 && lastDirection != "add" {
                    targetExerciseCount -= 1
                    lastDirection = "remove"
                    Logger.log(.debug, component: "DurationAwareWorkoutBuilder",
                        message: "Over target (\(actualDuration)min > \(upperBound)min), removing exercise")
                } else {
                    Logger.log(.warning, component: "DurationAwareWorkoutBuilder",
                        message: "⚠️ Cannot reduce further. Best: \(actualDuration)min (target: \(targetDuration)min)")
                    break
                }
            }
        }

        // Calculate how many exercises were supplemented from library
        let supplementedCount = max(0, selectedExercises.count - aiExerciseCount)

        if supplementedCount > 0 {
            Logger.log(.info, component: "DurationAwareWorkoutBuilder",
                message: "📊 Supplemented AI selection: AI provided \(aiExerciseCount), added \(supplementedCount) from library to meet \(targetDuration)min target")
        }

        return DurationAwareWorkoutResult(
            exerciseIds: selectedExercises,
            protocolVariantIds: protocolIds,
            actualDuration: actualDuration,
            targetDuration: targetDuration,
            iterationsUsed: iteration,
            aiExerciseCount: aiExerciseCount,
            supplementedCount: supplementedCount
        )
    }

    // MARK: - Equipment Detection

    /// Determine primary equipment type from location/available equipment
    private static func determinePrimaryEquipment(
        location: TrainingLocation,
        availableEquipment: Set<Equipment>?
    ) -> Equipment {
        // If specific equipment available, check for bodyweight/band only
        if let available = availableEquipment {
            if available == [.bodyweight] || available == [.bodyweight, .none] {
                return .bodyweight
            }
            if available.contains(.resistanceBand) && !available.contains(.barbell) && !available.contains(.dumbbells) {
                return .resistanceBand
            }
        }

        // Otherwise infer from location
        switch location {
        case .home:
            return .bodyweight  // Conservative assumption for home
        case .gym, .outdoor, .hybrid:
            return .barbell  // Assume full gym equipment
        }
    }

    // MARK: - Exercise Selection

    /// Get candidate exercises for the workout
    /// v82.0: AI exercises are prioritized but supplemented with library exercises to meet duration
    /// v85.0: movementPatternFilter restricts exercises to specified patterns
    /// v87.0: MOVEMENT-FIRST - when patterns provided, filter ALL exercises by pattern (skip muscle check)
    /// v104: Also checks baseExercise to prevent dumbbell + barbell variants of same exercise
    /// v127: Forces bodyweight-only filter EARLY for home workouts with no equipment
    private static func getCandidateExercises(
        splitDay: SplitDay,
        plan: Plan,
        userId: String,
        aiExerciseIds: [String]?,
        movementPatternFilter: [MovementPattern]? = nil  // v87.0: PRIMARY filter
    ) -> [String] {
        var candidates: [String] = []

        // v127: For home workouts with no equipment, force bodyweight-only filter BEFORE any selection
        // This is the ROOT FIX - prevents gym exercises from ever entering the candidate pool
        let isHomeNoEquipment = plan.trainingLocation == .home &&
            (plan.availableEquipment == nil ||
             plan.availableEquipment == [.bodyweight] ||
             plan.availableEquipment == [.bodyweight, .none] ||
             plan.availableEquipment == [.none])

        if isHomeNoEquipment {
            Logger.log(.info, component: "DurationAwareWorkoutBuilder",
                message: "v127: HOME + NO EQUIPMENT detected → forcing bodyweight-only filter for ALL exercise selection")
        }

        // If AI provided exercises, validate and add them first (priority)
        // v87.0: Pass movementPatternFilter as PRIMARY filter
        // v127: Pass isHomeNoEquipment to force bodyweight filter
        if let aiExercises = aiExerciseIds, !aiExercises.isEmpty {
            let validatedExercises = validateAIExercises(
                aiExercises,
                splitDay: splitDay,
                plan: plan,
                userId: userId,
                movementPatternFilter: movementPatternFilter,  // v87.0: PRIMARY filter
                forceBodyweightOnly: isHomeNoEquipment  // v127: Force bodyweight filter
            )
            candidates.append(contentsOf: validatedExercises)
        }

        // v104: Build set of baseExercises already in candidates
        var usedBaseExercises: Set<String> = []
        for exerciseId in candidates {
            if let exercise = LocalDataStore.shared.exercises[exerciseId] {
                usedBaseExercises.insert(exercise.baseExercise)
            }
        }

        // Always supplement with library exercises to ensure we can meet duration target
        // Library exercises are added after AI exercises (lower priority)
        // v87.0: Pass movementPatternFilter as PRIMARY filter
        // v127: Pass isHomeNoEquipment to force bodyweight filter
        let libraryExercises = selectExercisesFromLibrary(
            splitDay: splitDay,
            plan: plan,
            userId: userId,
            movementPatternFilter: movementPatternFilter,  // v87.0: PRIMARY filter
            forceBodyweightOnly: isHomeNoEquipment  // v127: Force bodyweight filter
        )

        // Add library exercises that aren't already in candidates
        // v104: Also check baseExercise to prevent dumbbell + barbell variants
        for exerciseId in libraryExercises {
            if !candidates.contains(exerciseId) {
                // v104: Check baseExercise isn't already used
                if let exercise = LocalDataStore.shared.exercises[exerciseId] {
                    if usedBaseExercises.contains(exercise.baseExercise) {
                        Logger.log(.debug, component: "DurationAwareWorkoutBuilder",
                            message: "v104: Skipping library exercise \(exerciseId) - baseExercise '\(exercise.baseExercise)' already in candidates")
                        continue
                    }
                    usedBaseExercises.insert(exercise.baseExercise)
                }
                candidates.append(exerciseId)
            }
        }

        return candidates
    }

    /// Validate AI-provided exercises against constraints
    /// v82.6: Now also validates muscle group compatibility (not just equipment)
    /// v85.0: Filters exercises by movement pattern
    /// v87.0: MOVEMENT-FIRST - when patterns provided, filter ALL exercises by pattern (skip muscle check)
    /// v102.4: Uses ExerciseFuzzyMatcher to handle AI ID typos, returns CORRECTED IDs
    /// v104: Prevents duplicate baseExercise entries (e.g., dumbbell + barbell bench press)
    /// v127: forceBodyweightOnly rejects ANY exercise that requires equipment
    private static func validateAIExercises(
        _ exerciseIds: [String],
        splitDay: SplitDay,
        plan: Plan,
        userId: String,
        movementPatternFilter: [MovementPattern]? = nil,  // v87.0: PRIMARY filter
        forceBodyweightOnly: Bool = false  // v127: Force bodyweight filter for home workouts
    ) -> [String] {
        // v104: Track used base exercises to prevent duplicates
        var usedBaseExercises: Set<String> = []

        // v87.0: MOVEMENT-FIRST PATH
        // When movement patterns are specified, filter by pattern ONLY (no muscle check)
        if let patterns = movementPatternFilter, !patterns.isEmpty {
            let expandedPatterns = MovementPattern.expand(patterns)

            Logger.log(.info, component: "DurationAwareWorkoutBuilder",
                message: "v87.0: MOVEMENT-FIRST mode - filtering by patterns: \(patterns.map { $0.rawValue }) → expanded: \(expandedPatterns.map { $0.rawValue })")

            // v102.4: Use compactMap to return CORRECTED IDs from fuzzy matcher
            return exerciseIds.compactMap { exerciseId -> String? in
                // v102.4: Use fuzzy matcher instead of direct lookup
                guard let exercise = ExerciseFuzzyMatcher.match(exerciseId) else {
                    Logger.log(.warning, component: "DurationAwareWorkoutBuilder",
                        message: "⚠️ v102.4: AI exercise ID '\(exerciseId)' NOT FOUND even with fuzzy match - rejected")
                    return nil
                }

                // v127: STRICT bodyweight filter for home workouts with no equipment
                // This OVERRIDES any equipment compatibility check - only bodyweight allowed
                if forceBodyweightOnly {
                    guard exercise.equipment == .bodyweight || exercise.equipment == .none else {
                        Logger.log(.warning, component: "DurationAwareWorkoutBuilder",
                            message: "v127: REJECTED \(exercise.id) - requires \(exercise.equipment.rawValue), home workout needs bodyweight only")
                        return nil
                    }
                }

                // v104: Reject if baseExercise already used (prevents dumbbell + barbell bench press in same workout)
                if usedBaseExercises.contains(exercise.baseExercise) {
                    Logger.log(.warning, component: "DurationAwareWorkoutBuilder",
                        message: "v104: REJECTED \(exercise.id) - baseExercise '\(exercise.baseExercise)' already used")
                    return nil
                }

                // Check equipment compatibility (skipped if forceBodyweightOnly already handled)
                if !forceBodyweightOnly, let availableEquipment = plan.availableEquipment {
                    guard availableEquipment.contains(exercise.equipment) else {
                        return nil
                    }
                }

                // v87.0: ALL exercises must match one of the expanded movement patterns
                guard let exercisePattern = exercise.movementPattern,
                      expandedPatterns.contains(exercisePattern) else {
                    Logger.log(.debug, component: "DurationAwareWorkoutBuilder",
                        message: "v87.0: REJECTED \(exercise.name) - pattern '\(exercise.movementPattern?.rawValue ?? "nil")' not in expanded filter")
                    return nil
                }

                // v104: Track this baseExercise as used
                usedBaseExercises.insert(exercise.baseExercise)

                // v102.4: Return the CORRECTED exercise ID (not the AI's potentially wrong ID)
                return exercise.id
            }
        }

        // STANDARD PATH: Muscle-based filtering for standard splits
        let targetMuscles = Set(muscleTargetsForSplit(splitDay))

        // v102.4: Use compactMap to return CORRECTED IDs from fuzzy matcher
        return exerciseIds.compactMap { exerciseId -> String? in
            // v102.4: Use fuzzy matcher instead of direct lookup
            guard let exercise = ExerciseFuzzyMatcher.match(exerciseId) else {
                Logger.log(.warning, component: "DurationAwareWorkoutBuilder",
                    message: "⚠️ v102.4: AI exercise ID '\(exerciseId)' NOT FOUND even with fuzzy match - rejected")
                return nil
            }

            // v127: STRICT bodyweight filter for home workouts with no equipment
            // This OVERRIDES any equipment compatibility check - only bodyweight allowed
            if forceBodyweightOnly {
                guard exercise.equipment == .bodyweight || exercise.equipment == .none else {
                    Logger.log(.warning, component: "DurationAwareWorkoutBuilder",
                        message: "v127: REJECTED \(exercise.id) - requires \(exercise.equipment.rawValue), home workout needs bodyweight only")
                    return nil
                }
            }

            // v104: Reject if baseExercise already used (prevents dumbbell + barbell bench press in same workout)
            if usedBaseExercises.contains(exercise.baseExercise) {
                Logger.log(.warning, component: "DurationAwareWorkoutBuilder",
                    message: "v104: REJECTED \(exercise.id) - baseExercise '\(exercise.baseExercise)' already used")
                return nil
            }

            // Check equipment compatibility (skipped if forceBodyweightOnly already handled)
            if !forceBodyweightOnly, let availableEquipment = plan.availableEquipment {
                guard availableEquipment.contains(exercise.equipment) else {
                    return nil
                }
            }

            // Check muscle group compatibility
            let exerciseMuscles = Set(exercise.muscleGroups)
            let intersection = targetMuscles.intersection(exerciseMuscles)
            guard !intersection.isEmpty else {
                Logger.log(.debug, component: "DurationAwareWorkoutBuilder",
                    message: "v82.6: AI exercise REJECTED \(exercise.id) - no muscle overlap with \(splitDay.rawValue)")
                return nil
            }

            // v104: Track this baseExercise as used
            usedBaseExercises.insert(exercise.baseExercise)

            // v102.4: Return the CORRECTED exercise ID (not the AI's potentially wrong ID)
            return exercise.id
        }
    }

    /// Select exercises from user library matching split and constraints
    /// v82.5: Falls back to global exercise database if user has no library (new users)
    /// v85.0: Filters exercises by movement pattern
    /// v87.0: MOVEMENT-FIRST - when patterns provided, filter ALL exercises by pattern (skip muscle check)
    /// v124.1: Movement patterns now search FULL catalog (not just library) for better variety
    /// v127: forceBodyweightOnly rejects ANY exercise that requires equipment
    private static func selectExercisesFromLibrary(
        splitDay: SplitDay,
        plan: Plan,
        userId: String,
        movementPatternFilter: [MovementPattern]? = nil,  // v87.0: PRIMARY filter
        forceBodyweightOnly: Bool = false  // v127: Force bodyweight filter for home workouts
    ) -> [String] {
        // v124.1: For movement pattern requests, use FULL catalog (libraries are too small)
        // For standard splits (legs, upper, etc.), use library first then fall back
        let exerciseIdsToSearch: [String]

        if let patterns = movementPatternFilter, !patterns.isEmpty {
            // v124.1: Movement patterns need full catalog for variety
            exerciseIdsToSearch = Array(LocalDataStore.shared.exercises.keys)
            Logger.log(.info, component: "DurationAwareWorkoutBuilder",
                message: "v124.1: Movement pattern filter - using full catalog (\(exerciseIdsToSearch.count) exercises)")
        } else if forceBodyweightOnly {
            // v130: Home workouts need FULL CATALOG because user's library likely has gym exercises only
            // If we use library, bodyweight filter leaves 0-1 exercises → short workouts
            exerciseIdsToSearch = Array(LocalDataStore.shared.exercises.keys)
            Logger.log(.info, component: "DurationAwareWorkoutBuilder",
                message: "v130: Home workout - using full catalog (\(exerciseIdsToSearch.count) exercises) to find bodyweight options")
        } else if let library = LocalDataStore.shared.libraries[userId], !library.exercises.isEmpty {
            exerciseIdsToSearch = Array(library.exercises)
        } else {
            // New user or empty library - use all available exercises
            exerciseIdsToSearch = Array(LocalDataStore.shared.exercises.keys)
            Logger.log(.info, component: "DurationAwareWorkoutBuilder",
                message: "v82.5: No user library, using global exercises (\(exerciseIdsToSearch.count) available)")
        }

        // v87.0: MOVEMENT-FIRST PATH
        // When movement patterns are specified, filter by pattern ONLY (no muscle check)
        if let patterns = movementPatternFilter, !patterns.isEmpty {
            let expandedPatterns = MovementPattern.expand(patterns)

            Logger.log(.info, component: "DurationAwareWorkoutBuilder",
                message: "v87.0: LIBRARY SELECTION - movement-first mode, patterns: \(patterns.map { $0.rawValue }) → expanded: \(expandedPatterns.map { $0.rawValue })")

            // Filter exercises by movement pattern
            let eligibleExercises = exerciseIdsToSearch.compactMap { exerciseId -> (String, Exercise)? in
                guard let exercise = LocalDataStore.shared.exercises[exerciseId] else {
                    return nil
                }

                // v127: STRICT bodyweight filter for home workouts with no equipment
                if forceBodyweightOnly {
                    guard exercise.equipment == .bodyweight || exercise.equipment == .none else {
                        return nil
                    }
                }

                // Check equipment compatibility (skipped if forceBodyweightOnly already handled)
                if !forceBodyweightOnly, let availableEquipment = plan.availableEquipment {
                    guard availableEquipment.contains(exercise.equipment) else {
                        return nil
                    }
                }

                // v87.0: ALL exercises must match one of the expanded movement patterns
                guard let exercisePattern = exercise.movementPattern,
                      expandedPatterns.contains(exercisePattern) else {
                    return nil
                }

                return (exerciseId, exercise)
            }

            // v87.0: Group by movement pattern for diversity (not by muscle)
            var patternGroups: [String: [(String, Exercise)]] = [:]

            for (id, exercise) in eligibleExercises {
                let patternKey = exercise.movementPattern?.rawValue ?? "other"
                patternGroups[patternKey, default: []].append((id, exercise))
            }

            // Sort each pattern group: compounds first, then by name
            for key in patternGroups.keys {
                patternGroups[key]?.sort { a, b in
                    if a.1.exerciseType != b.1.exerciseType {
                        return a.1.exerciseType == .compound
                    }
                    return a.1.name < b.1.name
                }
            }

            // Round-robin select from each pattern group for diversity
            var result: [String] = []
            var indices: [String: Int] = [:]
            let sortedPatternKeys = patternGroups.keys.sorted()

            var addedAny = true
            while addedAny {
                addedAny = false
                for pattern in sortedPatternKeys {
                    guard let exercises = patternGroups[pattern] else { continue }
                    let idx = indices[pattern, default: 0]
                    if idx < exercises.count {
                        result.append(exercises[idx].0)
                        indices[pattern] = idx + 1
                        addedAny = true
                    }
                }
            }

            Logger.log(.info, component: "DurationAwareWorkoutBuilder",
                message: "v87.0: Movement-first selection from \(patternGroups.count) pattern groups, \(result.count) exercises")

            return result
        }

        // STANDARD PATH: Muscle-based selection for standard splits
        let targetMuscles = Set(muscleTargetsForSplit(splitDay))

        // Filter and sort exercises
        let eligibleExercises = exerciseIdsToSearch.compactMap { exerciseId -> (String, Exercise)? in
            guard let exercise = LocalDataStore.shared.exercises[exerciseId] else {
                return nil
            }

            // v127: STRICT bodyweight filter for home workouts with no equipment
            if forceBodyweightOnly {
                guard exercise.equipment == .bodyweight || exercise.equipment == .none else {
                    return nil
                }
            }

            // Check equipment compatibility (skipped if forceBodyweightOnly already handled)
            if !forceBodyweightOnly, let availableEquipment = plan.availableEquipment {
                guard availableEquipment.contains(exercise.equipment) else {
                    return nil
                }
            }

            // Check muscle group compatibility
            let exerciseMuscles = Set(exercise.muscleGroups)
            let intersection = targetMuscles.intersection(exerciseMuscles)
            guard !intersection.isEmpty else { return nil }

            return (exerciseId, exercise)
        }

        // v82.5: Group by primary muscle for diversity, then select round-robin
        // This ensures variety (e.g., not 3 push-up variants in a row)
        var muscleGroups: [String: [(String, Exercise)]] = [:]

        for (id, exercise) in eligibleExercises {
            let primaryMuscle = exercise.muscleGroups.first?.rawValue ?? "other"
            muscleGroups[primaryMuscle, default: []].append((id, exercise))
        }

        // Sort each muscle group: compounds first, then by name
        for key in muscleGroups.keys {
            muscleGroups[key]?.sort { a, b in
                if a.1.exerciseType != b.1.exerciseType {
                    return a.1.exerciseType == .compound
                }
                return a.1.name < b.1.name
            }
        }

        // Round-robin select from each muscle group for diversity
        // v82.6: Only select from TARGET muscle groups (not all groups found in filtered exercises)
        // This prevents exercises like Mountain Climbers (abs primary, quads secondary) from appearing in lower body workouts
        var result: [String] = []
        var indices: [String: Int] = [:]
        let targetMuscleStrings = Set(targetMuscles.map { $0.rawValue })
        let sortedMuscleKeys = muscleGroups.keys
            .filter { targetMuscleStrings.contains($0) }
            .sorted()

        // Keep going until we have all exercises
        var addedAny = true
        while addedAny {
            addedAny = false
            for muscle in sortedMuscleKeys {
                guard let exercises = muscleGroups[muscle] else { continue }
                let idx = indices[muscle, default: 0]
                if idx < exercises.count {
                    result.append(exercises[idx].0)
                    indices[muscle] = idx + 1
                    addedAny = true
                }
            }
        }

        Logger.log(.info, component: "DurationAwareWorkoutBuilder",
            message: "v82.5: Diverse selection from \(muscleGroups.count) muscle groups, \(result.count) exercises")

        return result
    }

    // MARK: - Protocol Assignment

    /// Assign protocols to selected exercises
    /// - Parameters:
    ///   - exerciseIds: Exercise IDs to assign protocols to
    ///   - program: Program for intensity context
    ///   - plan: Plan for goal context
    ///   - userId: User ID for library access
    ///   - overrideProtocolId: v87.3 - If set, use this protocol for ALL exercises
    private static func assignProtocols(
        exerciseIds: [String],
        program: Program,
        plan: Plan,
        userId: String,
        overrideProtocolId: String? = nil
    ) -> [Int: String] {
        var protocolIds: [Int: String] = [:]

        // v87.3: If override protocol is specified AND EXISTS, use it for ALL exercises
        // This ensures duration calculation matches the final protocol assignment
        if let overrideId = overrideProtocolId, !overrideId.isEmpty {
            // Safety check: only use override if protocol exists
            if LocalDataStore.shared.protocolConfigs[overrideId] != nil {
                for index in 0..<exerciseIds.count {
                    protocolIds[index] = overrideId
                }
                Logger.log(.info, component: "DurationAwareWorkoutBuilder",
                    message: "v87.3: Using override protocol '\(overrideId)' for all \(exerciseIds.count) exercises")
                return protocolIds
            } else {
                Logger.log(.warning, component: "DurationAwareWorkoutBuilder",
                    message: "v87.3: Override protocol '\(overrideId)' not found - using library/defaults")
            }
        }

        // Get user library for protocol selection
        let library = LocalDataStore.shared.libraries[userId] ?? UserLibrary(userId: userId)

        for (index, exerciseId) in exerciseIds.enumerated() {
            guard let exercise = LocalDataStore.shared.exercises[exerciseId] else {
                continue
            }

            // Get exercise type (default to compound if nil)
            let exerciseType = exercise.exerciseType ?? .compound

            // Match protocol from library
            if let protocolId = LibraryProtocolSelector.match(
                from: library,
                exerciseType: exerciseType,
                currentIntensity: program.startingIntensity,
                goal: plan.goal,
                equipment: exercise.equipment
            ) {
                protocolIds[index] = protocolId
            } else {
                // Fallback to default protocols
                let fallbackId = defaultProtocol(for: exerciseType)
                protocolIds[index] = fallbackId
            }
        }

        return protocolIds
    }

    /// Get default protocol for exercise type
    private static func defaultProtocol(for exerciseType: ExerciseType) -> String {
        switch exerciseType {
        case .compound:
            return "strength_3x5_moderate"
        case .isolation:
            return "accessory_3x10_rpe8"
        default:
            return "strength_3x5_moderate"
        }
    }

    // MARK: - Duration Calculation

    /// Calculate actual duration from exercises and protocols
    /// v124: Now includes transition time between exercises for realistic total
    private static func calculateActualDuration(
        exerciseIds: [String],
        protocolIds: [Int: String]
    ) -> Int {
        let protocolConfigs: [ProtocolConfig?] = exerciseIds.enumerated().map { index, _ in
            guard let protocolId = protocolIds[index] else { return nil }
            return LocalDataStore.shared.protocolConfigs[protocolId]
        }

        // v124: Pass transition time to calculator for realistic duration
        return ExerciseTimeCalculator.calculateWorkoutTime(
            protocolConfigs: protocolConfigs,
            workoutType: .strength,
            restBetweenExercises: transitionTimeSeconds
        )
    }

    // MARK: - Muscle Targets

    /// Map split day to target muscle groups
    private static func muscleTargetsForSplit(_ splitDay: SplitDay) -> [MuscleGroup] {
        switch splitDay {
        // v82.6: Added .lats to upper/pull/back splits so lat-primary exercises get selected
        case .upper: return [.chest, .back, .lats, .shoulders, .biceps, .triceps]
        case .lower: return [.quadriceps, .hamstrings, .glutes, .calves]
        case .push: return [.chest, .shoulders, .triceps]
        case .pull: return [.back, .lats, .biceps, .traps]
        case .legs: return [.quadriceps, .hamstrings, .glutes, .calves]
        case .fullBody: return [.chest, .back, .lats, .quadriceps, .hamstrings, .shoulders, .biceps, .triceps, .glutes]
        case .chest: return [.chest, .triceps]
        case .back: return [.back, .lats, .biceps, .traps]
        case .shoulders: return [.shoulders, .traps]
        case .arms: return [.biceps, .triceps, .forearms]
        case .notApplicable: return MuscleGroup.allCases
        }
    }
}
