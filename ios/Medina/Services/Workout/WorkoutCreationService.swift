//
// WorkoutCreationService.swift
// Medina
//
// v60.0 - AI Workout Creation: Entity Creation Service
// v81.0 - AI-first exercise selection: AI provides exerciseIds, Swift validates
// v82.0 - Duration-aware workout building: Iterative select-assign-verify loop
// Two paths:
// - createFromIntent(): Primary path - Uses DurationAwareWorkoutBuilder
// - createFromValidatedData(): Flexible path with AI-specified exercises + protocols
// Last reviewed: December 2025
//

import Foundation

/// v101.3: Result from workout creation - includes both plan and the created workout
struct WorkoutCreationResult {
    let plan: Plan
    let workout: Workout
}

/// Intent data for AI-first workout creation
/// v81.0: AI now provides exerciseIds selected from context
/// v82.4: AI can optionally customize protocols (±2 sets, ±3 reps, ±30s rest)
/// v83.0: Superset support via supersetStyle + supersetGroups
/// v101.1: Added sessionType for cardio vs strength workout differentiation
struct WorkoutIntentData {
    let name: String
    let splitDay: SplitDay
    let scheduledDate: Date
    let duration: Int
    let effortLevel: EffortLevel

    // v101.1: Session type - cardio vs strength
    // Determines exercise filtering (cardio exercises only), protocol selection (duration-based),
    // and workout.type assignment
    let sessionType: SessionType?  // nil defaults to .strength for backward compatibility

    // v80.3: Equipment constraints for home workouts
    let trainingLocation: TrainingLocation?
    let availableEquipment: Set<Equipment>?

    // v81.0: AI-first exercise selection
    let exerciseIds: [String]?  // If provided, use these instead of auto-selection
    let selectionReasoning: String?  // AI's explanation for exercise choices

    // v82.4: AI protocol customization
    let protocolCustomizations: [Int: ProtocolCustomization]?  // position -> customization

    // v83.0: Superset configuration
    let supersetStyle: SupersetStyle?  // none, antagonist, agonist, compound_isolation, circuit, explicit
    let supersetGroups: [SupersetGroupIntent]?  // For explicit mode - user-specified pairings

    // v84.1: Preserve protocol when modifying workouts
    // If set, ALL exercises will use this protocol ID instead of auto-selected protocols
    let preserveProtocolId: String?

    // v85.0: Movement pattern filtering
    // When specified, exercises are filtered to these movement patterns ONLY
    // v87.0: This is now the PRIMARY filter for movement-based requests
    // Example: ["squat", "pull"] for "squat pull workout"
    let movementPatternFilter: [MovementPattern]?
    // v87.0: Removed targetMuscles - use movementPatterns instead for movement-based requests

    // v103: Exercise count override for image-based workout creation
    // When specified, use this count instead of calculating from duration
    // Example: Image shows 6 exercises → exerciseCountOverride: 6
    let exerciseCountOverride: Int?
}

/// v87.0: Error for insufficient exercises when movement pattern filtering is too restrictive
/// This allows the handler to return a clarification request instead of creating a bad workout
struct InsufficientExercisesError: LocalizedError {
    let requestedPatterns: [MovementPattern]
    let exerciseCount: Int

    var errorDescription: String? {
        "Only \(exerciseCount) exercises found for patterns: \(requestedPatterns.map { $0.rawValue }.joined(separator: ", "))"
    }

    /// Message for AI to relay to user
    var clarificationMessage: String {
        let patternNames = requestedPatterns.map { $0.displayName.lowercased() }.joined(separator: " and ")
        return """
        I could only find \(exerciseCount) exercises for "\(patternNames)" movements.

        Could you clarify what you're looking for?
        - Specific exercises? (e.g., "back squats and chin-ups")
        - A different focus? (e.g., "legs and back" or "lower body")
        - Or should I proceed with these \(exerciseCount) exercises?
        """
    }
}

/// Service for creating workouts from AI-generated JSON
enum WorkoutCreationService {

    // MARK: - v60.0: Fast Path (Intent-Only)

    /// Create workout from intent data using local exercise selection
    /// - Parameters:
    ///   - intent: Intent data (no exercise IDs - they're selected locally)
    ///   - userId: User ID
    /// - Returns: WorkoutCreationResult with plan and created workout
    /// - Throws: Error if creation or persistence fails
    static func createFromIntent(
        _ intent: WorkoutIntentData,
        userId: String
    ) async throws -> WorkoutCreationResult {

        // v101.2: Check for active plan first - insert workout there instead of creating new plan
        // This prevents plan conflicts when user creates a one-off workout while having an active training plan
        if let activePlan = PlanDataStore.activePlan(for: userId),
           !activePlan.isSingleWorkout,  // Don't insert into other single workouts
           let program = TestDataManager.shared.programs.values.first(where: { $0.planId == activePlan.id }) {
            Logger.log(.info, component: "WorkoutCreationService",
                message: "v101.2: Found active plan '\(activePlan.name)' - inserting workout into it")
            return try await insertWorkoutIntoActivePlan(
                intent,
                plan: activePlan,
                program: program,
                userId: userId
            )
        }

        // 1. Get user data
        guard let user = TestDataManager.shared.users[userId] else {
            throw NSError(domain: "WorkoutCreation", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "User not found: \(userId)"
            ])
        }

        let profile = user.memberProfile ?? MemberProfile(
            fitnessGoal: .strength,
            experienceLevel: .intermediate,
            preferredSessionDuration: 60,
            membershipStatus: .active,
            memberSince: Date()
        )

        // 2. Create Plan (only reached if no active plan exists)
        let planId = "plan_\(userId)_ai_\(UUID().uuidString.prefix(8))"
        let splitType = splitTypeForSplitDay(intent.splitDay)

        // v80.3: Prefer intent equipment params over profile (critical for home workouts)
        let effectiveLocation = intent.trainingLocation ?? profile.trainingLocation ?? .gym

        var plan = Plan(
            id: planId,
            memberId: userId,
            isSingleWorkout: true,
            status: .active,  // v141: Single workouts auto-activate (no approval flow)
            name: intent.name,
            description: "AI-generated workout via natural language",
            goal: profile.fitnessGoal,
            weightliftingDays: 1,
            cardioDays: 0,
            splitType: splitType,
            targetSessionDuration: intent.duration,
            trainingLocation: effectiveLocation,
            compoundTimeAllocation: 0.70,
            isolationApproach: .minimal,
            preferredDays: [],
            startDate: intent.scheduledDate,
            endDate: intent.scheduledDate,
            emphasizedMuscleGroups: profile.emphasizedMuscleGroups,
            excludedMuscleGroups: profile.excludedMuscleGroups,
            experienceLevel: profile.experienceLevel
        )

        // v80.3: Override available equipment if specified in intent
        // v82.6: Default to bodyweight when home location but no equipment specified
        // v82.7: Default to full gym equipment when gym location but no equipment specified
        if let intentEquipment = intent.availableEquipment {
            plan.availableEquipment = intentEquipment
        } else if effectiveLocation == .home {
            // AI didn't specify equipment but user said "home" → default to bodyweight
            plan.availableEquipment = Set([.bodyweight, .none])
            Logger.log(.info, component: "WorkoutCreationService",
                message: "v82.6: Home workout without equipment spec → defaulting to bodyweight")
        } else if effectiveLocation == .gym {
            // AI didn't specify equipment but user said "gym" → default to full gym equipment
            plan.availableEquipment = Equipment.fullGymEquipment
            Logger.log(.info, component: "WorkoutCreationService",
                message: "v82.7: Gym workout without equipment spec → defaulting to full gym equipment")
        }

        // 3. Create Program
        let intensity = intent.effortLevel.intensity

        let program = Program(
            id: "program_\(planId)_ai",
            planId: planId,
            name: "\(intent.effortLevel.displayName) Session",
            focus: .development,
            rationale: intent.effortLevel.description,
            startDate: intent.scheduledDate,
            endDate: intent.scheduledDate,
            startingIntensity: intensity,
            endingIntensity: intensity,
            progressionType: .linear,
            status: .active
        )

        // 4. Create initial Workout
        // v101.1: Use sessionType from intent (defaults to strength)
        let workoutId = "\(userId)_ai_\(UUID().uuidString.prefix(8))"
        let effectiveSessionType = intent.sessionType ?? .strength

        var workout = Workout(
            id: workoutId,
            programId: program.id,
            name: intent.name,
            scheduledDate: intent.scheduledDate,
            type: effectiveSessionType,  // v101.1: Use intent's sessionType
            splitDay: intent.splitDay,
            status: .scheduled,
            completedDate: nil,
            exerciseIds: [],  // Will be populated below
            protocolVariantIds: [:],  // Will be populated by ProtocolAssignmentService
            exercisesSelectedAt: nil,  // Will be set after selection
            supersetGroups: nil,
            protocolCustomizations: intent.protocolCustomizations  // v82.4: AI protocol adjustments
        )

        Logger.log(.info, component: "WorkoutCreationService",
            message: "v101.1: Creating workout with type=\(effectiveSessionType.rawValue)")

        // 5. Exercise selection - three paths:
        // v101.1: Cardio workout → simple single-exercise with duration protocol
        // v83.1: Explicit superset mode with specified exercises → use directly (no filtering/supplementation)
        // Otherwise → use DurationAwareWorkoutBuilder for duration-targeted selection

        let isExplicitSupersetWithExercises = (
            intent.supersetStyle == .explicit &&
            intent.exerciseIds != nil &&
            !intent.exerciseIds!.isEmpty
        )

        // v101.1: Cardio workout path - use single exercise with matching duration protocol
        if effectiveSessionType == .cardio {
            let cardioResult = createCardioWorkout(
                intent: intent,
                workout: &workout,
                userId: userId
            )

            if !cardioResult.success {
                throw NSError(domain: "WorkoutCreation", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: cardioResult.error ?? "Failed to create cardio workout"
                ])
            }

            Logger.log(.info, component: "WorkoutCreationService",
                message: "✅ v101.1 Cardio workout: \(workout.exerciseIds.count) exercises, \(intent.duration)min duration")
        } else if isExplicitSupersetWithExercises {
            // v83.1: User specified exact exercises for explicit superset - honor them exactly
            // No muscle filtering, no duration supplementation
            let exerciseIds = intent.exerciseIds!

            // Validate exercises exist (but don't filter by muscle group)
            let validExercises = exerciseIds.filter { TestDataManager.shared.exercises[$0] != nil }

            guard !validExercises.isEmpty else {
                throw NSError(domain: "WorkoutCreation", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: "No valid exercises found. Check exercise IDs."
                ])
            }

            workout.exerciseIds = validExercises

            // Assign protocols to the explicit exercises
            workout.protocolVariantIds = assignProtocolsForExercises(
                validExercises,
                program: program,
                plan: plan,
                userId: userId
            )

            Logger.log(.info, component: "WorkoutCreationService",
                message: "✅ v83.1 Explicit superset: Using \(validExercises.count) user-specified exercises directly (no filtering)")
        } else {
            // v82.0: Duration-aware workout building
            // Uses iterative select-assign-verify loop to ensure actual duration matches target
            // v85.0: Pass movementPatternFilter to filter by movement pattern
            // v87.0: Movement patterns are now PRIMARY filter (muscle-based is fallback for standard splits)
            // v87.3: Pass preserveProtocolId so builder uses correct protocol for duration calculation
            // v103: Pass exerciseCountOverride for image-based workout creation
            let buildResult = DurationAwareWorkoutBuilder.build(
                targetDuration: intent.duration,
                splitDay: intent.splitDay,
                plan: plan,
                program: program,
                userId: userId,
                aiExerciseIds: intent.exerciseIds,  // Will use AI exercises if provided and valid
                movementPatternFilter: intent.movementPatternFilter,  // v87.0: PRIMARY filter for movement requests
                overrideProtocolId: intent.preserveProtocolId,  // v87.3: Ensures duration accuracy when protocol specified
                exerciseCountOverride: intent.exerciseCountOverride  // v103: Override for image extraction
            )

            // v80.4: Fail fast if no exercises were selected (prevents empty workouts)
            guard !buildResult.exerciseIds.isEmpty else {
                throw NSError(domain: "WorkoutCreation", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: "No exercises available for this workout configuration. Try adjusting equipment or muscle groups."
                ])
            }

            // v95.0: Fail fast if duration shortfall is too large (>50% of target)
            // This prevents creating a 4-minute workout when user requested 45 minutes
            let maxAcceptableShortfall = intent.duration / 2  // 50% of target duration
            if buildResult.durationShortfall > maxAcceptableShortfall {
                Logger.log(.error, component: "WorkoutCreationService",
                    message: "v95.0: Duration shortfall too large - actual=\(buildResult.actualDuration)min, target=\(buildResult.targetDuration)min, shortfall=\(buildResult.durationShortfall)min")
                throw NSError(domain: "WorkoutCreation", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: "Not enough exercises available to create a \(intent.duration)-minute workout. Only \(buildResult.exerciseIds.count) exercises found (\(buildResult.actualDuration) minutes). Try a different muscle group or check your exercise library."
                ])
            }

            // v87.0: Smart fallback - if movement patterns were specified but we got <3 exercises,
            // throw a clarification error so the handler can ask the user for more info
            if let patterns = intent.movementPatternFilter, !patterns.isEmpty,
               buildResult.exerciseIds.count < 3 {
                Logger.log(.warning, component: "WorkoutCreationService",
                    message: "v87.0: Movement pattern filter returned only \(buildResult.exerciseIds.count) exercises - requesting clarification")
                throw InsufficientExercisesError(
                    requestedPatterns: patterns,
                    exerciseCount: buildResult.exerciseIds.count
                )
            }

            // Apply build result to workout
            workout.exerciseIds = buildResult.exerciseIds
            workout.protocolVariantIds = buildResult.protocolVariantIds

            Logger.log(.info, component: "WorkoutCreationService",
                message: "✅ v82.0 Duration-aware build: \(buildResult.exerciseIds.count) exercises, actual=\(buildResult.actualDuration)min, target=\(buildResult.targetDuration)min, iterations=\(buildResult.iterationsUsed)")
        }

        // v78.3: Mark exercises as selected NOW to prevent RuntimeExerciseSelector from reselecting
        workout.exercisesSelectedAt = Date()

        // v84.1: Override all protocols if preserveProtocolId is set
        // This ensures modified workouts keep their original protocol (e.g., GBC) for all exercises
        // v87.2: Also check for empty string (AI might send "" instead of nil)
        if let preservedProtocol = intent.preserveProtocolId, !preservedProtocol.isEmpty {
            var overriddenProtocols: [Int: String] = [:]
            for (index, _) in workout.exerciseIds.enumerated() {
                overriddenProtocols[index] = preservedProtocol
            }
            workout.protocolVariantIds = overriddenProtocols
            Logger.log(.info, component: "WorkoutCreationService",
                message: "✅ v84.1: Preserved protocol '\(preservedProtocol)' for all \(workout.exerciseIds.count) exercises")
        }

        // v83.4: Auto-detect superset intent from name if AI forgot to pass supersetStyle
        let effectiveStyle: SupersetStyle? = {
            if let style = intent.supersetStyle, style != .none {
                return style
            }
            // If name contains "superset" but no style passed, default to antagonist
            if workout.name.lowercased().contains("superset") {
                Logger.log(.info, component: "WorkoutCreationService",
                    message: "v83.4: Auto-detected superset intent from name '\(workout.name)', defaulting to antagonist")
                return .antagonist
            }
            return nil
        }()

        // v83.0: Create superset groups if requested
        if let style = effectiveStyle {
            let groups = SupersetPairingService.createGroups(
                exerciseIds: workout.exerciseIds,
                style: style,
                explicitGroups: intent.supersetGroups,
                userLevel: profile.experienceLevel
            )

            if let groups = groups {
                // Reorder exercises so superset pairs are adjacent (1a, 1b, 2a, 2b, then unpaired)
                let (reorderedIds, reorderedGroups) = SupersetPairingService.reorderForAdjacentPairs(
                    exerciseIds: workout.exerciseIds,
                    groups: groups
                )
                workout.exerciseIds = reorderedIds
                workout.supersetGroups = reorderedGroups

                Logger.log(.info, component: "WorkoutCreationService",
                    message: "✅ v83.0 Superset: Created \(groups.count) group(s) with style '\(style.rawValue)', reordered for adjacent pairs")
            } else {
                workout.supersetGroups = nil
                Logger.log(.info, component: "WorkoutCreationService",
                    message: "⚠️ v83.0 Superset: No groups created (insufficient exercises or invalid config)")
            }
        }

        // 6. Initialize instances and sets
        let workoutIntensities = [workout.id: program.startingIntensity]
        InstanceInitializationService.initializeInstances(
            for: [workout],
            memberId: userId,
            weeklyIntensities: workoutIntensities
        )

        // 8. Save to TestDataManager
        TestDataManager.shared.plans[plan.id] = plan
        TestDataManager.shared.programs[program.id] = program
        TestDataManager.shared.workouts[workout.id] = workout

        Logger.log(.info, component: "WorkoutCreationService",
                  message: "Created AI workout '\(intent.name)' (id: \(workout.id), \(workout.exerciseIds.count) exercises, fast path)")

        // 9. Persist to disk
        do {
            try await persistWorkoutData(plan: plan, program: program, workout: workout, userId: userId)
        } catch {
            Logger.log(.error, component: "WorkoutCreationService",
                      message: "Persistence failed: \(error)")
            throw error
        }

        // 10. v89: Auto-add exercises and protocols to user's library
        // This ensures the library grows as user creates workouts
        await addWorkoutItemsToLibrary(workout: workout, userId: userId)

        // v101.3: Return both plan and workout so caller knows exact workout created
        return WorkoutCreationResult(plan: plan, workout: workout)
    }

    // MARK: - Flexible Path (AI-Specified Exercises)

    /// Create workout from validated AI-generated JSON
    /// - Parameters:
    ///   - validatedData: Validated workout data from JSONValidator
    ///   - userId: User ID
    /// - Returns: WorkoutCreationResult with plan and created workout
    /// - Throws: Error if creation or persistence fails
    static func createFromValidatedData(
        _ validatedData: ValidatedWorkoutData,
        userId: String
    ) async throws -> WorkoutCreationResult {

        // 1. Get user data
        guard let user = TestDataManager.shared.users[userId] else {
            throw NSError(domain: "WorkoutCreation", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "User not found: \(userId)"
            ])
        }

        let profile = user.memberProfile ?? MemberProfile(
            fitnessGoal: .strength,
            experienceLevel: .intermediate,
            preferredSessionDuration: 60,
            membershipStatus: .active,
            memberSince: Date()
        )

        // 2. Create Plan (isSingleWorkout: true, auto-activated)
        let planId = "plan_\(userId)_ai_\(UUID().uuidString.prefix(8))"

        let splitType = splitTypeForSplitDay(validatedData.splitDay)

        let plan = Plan(
            id: planId,
            memberId: userId,
            isSingleWorkout: true,        // v58.3: Single workout flag
            status: .active,              // v141: Auto-activate (no approval flow for single workouts)
            name: validatedData.name,
            description: "AI-generated workout via natural language",
            goal: profile.fitnessGoal,
            weightliftingDays: 1,
            cardioDays: 0,
            splitType: splitType,
            targetSessionDuration: validatedData.duration,
            trainingLocation: profile.trainingLocation ?? .gym,
            compoundTimeAllocation: 0.70,
            isolationApproach: .minimal,
            preferredDays: [],
            startDate: validatedData.scheduledDate,
            endDate: validatedData.scheduledDate,  // Single day
            emphasizedMuscleGroups: profile.emphasizedMuscleGroups,
            excludedMuscleGroups: profile.excludedMuscleGroups,
            experienceLevel: profile.experienceLevel
        )

        // 3. Create Program (static intensity from effortLevel)
        let intensity = validatedData.effortLevel.intensity

        let program = Program(
            id: "program_\(planId)_ai",
            planId: planId,
            name: "\(validatedData.effortLevel.displayName) Session",
            focus: .development,
            rationale: validatedData.effortLevel.description,
            startDate: validatedData.scheduledDate,
            endDate: validatedData.scheduledDate,
            startingIntensity: intensity,
            endingIntensity: intensity,      // No progression for single workouts
            progressionType: .linear,
            status: .active
        )

        // 4. Create Workout
        let workoutId = "\(userId)_ai_\(UUID().uuidString.prefix(8))"

        let workout = Workout(
            id: workoutId,
            programId: program.id,
            name: validatedData.name,
            scheduledDate: validatedData.scheduledDate,
            type: .strength,                // AI creates strength workouts only (v59.6)
            splitDay: validatedData.splitDay,
            status: .scheduled,
            completedDate: nil,
            exerciseIds: validatedData.exerciseIds,
            protocolVariantIds: validatedData.protocolVariantIds,
            exercisesSelectedAt: Date(),    // v78.3: Mark as selected
            supersetGroups: nil,            // No supersets in v59.6
            protocolCustomizations: nil     // v82.4: Legacy path doesn't support customizations
        )

        // 5. Initialize instances and sets
        let weeklyIntensities = [workout.id: intensity]

        InstanceInitializationService.initializeInstances(
            for: [workout],
            memberId: userId,
            weeklyIntensities: weeklyIntensities
        )

        // 6. Save to TestDataManager
        TestDataManager.shared.plans[plan.id] = plan
        TestDataManager.shared.programs[program.id] = program
        TestDataManager.shared.workouts[workout.id] = workout

        Logger.log(.info, component: "WorkoutCreationService",
                  message: "Created AI workout '\(validatedData.name)' (id: \(workout.id), status: draft)")

        // 7. Persist to disk
        do {
            try await persistWorkoutData(plan: plan, program: program, workout: workout, userId: userId)
        } catch {
            Logger.log(.error, component: "WorkoutCreationService",
                      message: "Persistence failed: \(error)")
            throw error
        }

        // 8. v89: Auto-add exercises and protocols to user's library
        await addWorkoutItemsToLibrary(workout: workout, userId: userId)

        // v101.3: Return both plan and workout
        return WorkoutCreationResult(plan: plan, workout: workout)
    }

    // MARK: - v89: Library Auto-Add

    /// Auto-add exercises and protocols from workout to user's library
    /// This grows the library as users create workouts (fallback mechanism for empty libraries)
    @MainActor
    private static func addWorkoutItemsToLibrary(workout: Workout, userId: String) {
        // Add exercises
        let exerciseIds = workout.exerciseIds
        if !exerciseIds.isEmpty {
            do {
                try LibraryPersistenceService.addExercises(exerciseIds, userId: userId)
                Logger.log(.info, component: "WorkoutCreationService",
                    message: "v89: Auto-added \(exerciseIds.count) exercises to library")
            } catch {
                Logger.log(.warning, component: "WorkoutCreationService",
                    message: "v89: Failed to auto-add exercises: \(error)")
            }
        }

        // Add protocols
        let protocolIds = Array(Set(workout.protocolVariantIds.values))  // Deduplicate
        if !protocolIds.isEmpty {
            do {
                try LibraryPersistenceService.addProtocols(protocolIds, userId: userId)
                Logger.log(.info, component: "WorkoutCreationService",
                    message: "v89: Auto-added \(protocolIds.count) protocols to library")
            } catch {
                Logger.log(.warning, component: "WorkoutCreationService",
                    message: "v89: Failed to auto-add protocols: \(error)")
            }
        }
    }

    /// v206: Sync workout data to Firestore
    private static func persistWorkoutData(
        plan: Plan,
        program: Program,
        workout: Workout,
        userId: String
    ) async throws {
        // v206: Removed legacy disk persistence - Firestore is source of truth
        // syncToFirestore() handles plan and workout sync separately
        Logger.log(.info, component: "WorkoutCreationService",
                  message: "Workout data prepared for Firestore sync")
    }

    /// Map split day to split type for Plan creation
    private static func splitTypeForSplitDay(_ splitDay: SplitDay) -> SplitType {
        switch splitDay {
        case .upper, .lower:
            return .upperLower
        case .push, .pull, .legs:
            return .pushPullLegs
        case .fullBody:
            return .fullBody
        case .chest, .back, .shoulders, .arms:
            return .bodyPart
        case .notApplicable:
            return .fullBody
        }
    }

    /// v83.1: Assign protocols to exercises (for explicit superset mode)
    /// Matches protocol based on exercise type, intensity, and goal
    /// v173: Added protocol-exercise type validation
    private static func assignProtocolsForExercises(
        _ exerciseIds: [String],
        program: Program,
        plan: Plan,
        userId: String
    ) -> [Int: String] {
        var protocolIds: [Int: String] = [:]

        // Get user library for protocol selection
        let library = TestDataManager.shared.libraries[userId] ?? UserLibrary(userId: userId)

        for (index, exerciseId) in exerciseIds.enumerated() {
            guard let exercise = TestDataManager.shared.exercises[exerciseId] else {
                continue
            }

            // Get exercise type (default to compound if nil)
            let exerciseType = exercise.exerciseType ?? .compound

            // Match protocol from library
            var protocolId: String?
            if let matchedId = LibraryProtocolSelector.match(
                from: library,
                exerciseType: exerciseType,
                currentIntensity: program.startingIntensity,
                goal: plan.goal,
                equipment: exercise.equipment
            ) {
                protocolId = matchedId
            } else {
                // v173: Use compatible fallback based on exercise type
                protocolId = ProtocolAssignmentService.getCompatibleFallbackProtocol(
                    for: exerciseType,
                    intensity: program.startingIntensity
                )
            }

            // v173: Validate compatibility and fix if needed
            if let assignedProtocol = protocolId,
               !ProtocolAssignmentService.isProtocolExerciseCompatible(protocolId: assignedProtocol, exerciseId: exerciseId) {
                protocolId = ProtocolAssignmentService.getCompatibleFallbackProtocol(
                    for: exerciseType,
                    intensity: program.startingIntensity
                )
            }

            protocolIds[index] = protocolId
        }

        return protocolIds
    }

    // MARK: - v80.5: Duration-Aware Exercise Filling

    /// Add exercises until workout fills target duration
    /// - Parameters:
    ///   - workout: Current workout with initial exercises
    ///   - plan: Plan for exercise selection context
    ///   - program: Program for protocol assignment
    ///   - targetDuration: User's requested duration in minutes
    ///   - userId: User ID
    /// - Returns: Updated workout with additional exercises if needed
    private static func fillWorkoutToTargetDuration(
        workout: inout Workout,
        plan: Plan,
        program: Program,
        targetDuration: Int,
        userId: String
    ) {
        let tolerance = 5 // Within 5 min of target is acceptable
        let maxIterations = 5 // Safety cap

        for iteration in 0..<maxIterations {
            // Calculate current workout time
            let instances = TestDataManager.shared.exerciseInstances.values
                .filter { $0.workoutId == workout.id }
            let protocolConfigs = instances.compactMap { instance in
                TestDataManager.shared.protocolConfigs[instance.protocolVariantId]
            }
            // v132: Include transition time to match DurationAwareWorkoutBuilder
            let currentDuration = ExerciseTimeCalculator.calculateWorkoutTime(
                protocolConfigs: protocolConfigs,
                workoutType: .strength,
                restBetweenExercises: 90
            )

            // Check if we've reached target (within tolerance)
            if currentDuration >= targetDuration - tolerance {
                Logger.log(.info, component: "WorkoutCreationService",
                    message: "✅ Duration target met: \(currentDuration)min >= \(targetDuration - tolerance)min target")
                break
            }

            // Try to add one more exercise
            guard let additionalExercise = selectAdditionalExercise(
                currentWorkout: workout,
                plan: plan,
                userId: userId
            ) else {
                Logger.log(.warning, component: "WorkoutCreationService",
                    message: "⚠️ No more exercises available to fill time (\(currentDuration)min < \(targetDuration)min)")
                break
            }

            // Add to workout
            workout.exerciseIds.append(additionalExercise)

            // Assign protocol to new exercise
            let (workoutsWithProtocols, intensities) = ProtocolAssignmentService.assignProtocols(
                for: [workout],
                program: program,
                userId: userId,
                goal: plan.goal
            )

            if let updatedWorkout = workoutsWithProtocols.first {
                workout = updatedWorkout
            }

            // Initialize instance for new exercise
            InstanceInitializationService.initializeInstances(
                for: [workout],
                memberId: userId,
                weeklyIntensities: intensities
            )

            Logger.log(.info, component: "WorkoutCreationService",
                message: "➕ Added exercise \(additionalExercise) to fill duration (iteration \(iteration + 1))")
        }
    }

    /// Select one additional exercise that fits the workout
    /// - Parameters:
    ///   - currentWorkout: Current workout to add exercise to
    ///   - plan: Plan with equipment/muscle constraints
    ///   - userId: User ID for library access
    /// - Returns: Exercise ID if found, nil if no suitable exercise available
    private static func selectAdditionalExercise(
        currentWorkout: Workout,
        plan: Plan,
        userId: String
    ) -> String? {
        // Get exercises already in workout
        let existingIds = Set(currentWorkout.exerciseIds)

        // Get target muscles for this split
        let targetMuscles: Set<MuscleGroup>
        if let splitDay = currentWorkout.splitDay {
            targetMuscles = Set(muscleTargetsForSplit(splitDay))
        } else {
            // Default to full body if no split specified
            targetMuscles = Set([.chest, .back, .quadriceps, .hamstrings, .shoulders])
        }

        // Get eligible exercises from library
        guard let library = TestDataManager.shared.libraries[userId] else {
            return nil
        }

        let eligible = library.exercises.filter { exerciseId in
            // Skip if already in workout
            guard !existingIds.contains(exerciseId) else { return false }

            guard let exercise = TestDataManager.shared.exercises[exerciseId] else {
                return false
            }

            // Check equipment compatibility
            if let availableEquipment = plan.availableEquipment {
                guard availableEquipment.contains(exercise.equipment) else {
                    return false
                }
            }

            // Check muscle group compatibility with split
            let exerciseMuscles = Set(exercise.muscleGroups)
            return !targetMuscles.intersection(exerciseMuscles).isEmpty
        }

        // Return first eligible exercise (could improve with smart selection later)
        return eligible.first
    }

    /// Map split day to target muscle groups
    private static func muscleTargetsForSplit(_ splitDay: SplitDay) -> [MuscleGroup] {
        switch splitDay {
        case .upper: return [.chest, .back, .shoulders, .biceps, .triceps]
        case .lower: return [.quadriceps, .hamstrings, .glutes, .calves]
        case .push: return [.chest, .shoulders, .triceps]
        case .pull: return [.back, .biceps, .traps, .lats]
        case .legs: return [.quadriceps, .hamstrings, .glutes, .calves]
        case .fullBody: return [.chest, .back, .quadriceps, .hamstrings, .shoulders]
        case .chest: return [.chest, .triceps]
        case .back: return [.back, .biceps, .traps]
        case .shoulders: return [.shoulders, .traps]
        case .arms: return [.biceps, .triceps, .forearms]
        case .notApplicable: return []
        }
    }

    // MARK: - v101.1: Cardio Workout Creation

    /// Result from cardio workout creation
    private struct CardioWorkoutResult {
        let success: Bool
        let error: String?
    }

    /// Create a cardio workout with duration-based protocol
    /// Cardio workouts are simpler than strength - typically 1 exercise with a duration protocol
    /// - Parameters:
    ///   - intent: Workout intent data
    ///   - workout: Workout to populate (inout)
    ///   - userId: User ID
    /// - Returns: Result indicating success or error
    private static func createCardioWorkout(
        intent: WorkoutIntentData,
        workout: inout Workout,
        userId: String
    ) -> CardioWorkoutResult {

        // 1. Get exercise(s) - either from AI or select default cardio exercise
        var exerciseIds: [String] = []

        if let aiExerciseIds = intent.exerciseIds, !aiExerciseIds.isEmpty {
            // AI provided exercise IDs - validate they're cardio exercises
            for exerciseId in aiExerciseIds {
                if let exercise = TestDataManager.shared.exercises[exerciseId],
                   exercise.exerciseType == .cardio {
                    exerciseIds.append(exerciseId)
                } else {
                    Logger.log(.warning, component: "WorkoutCreationService",
                        message: "v101.1: Skipping non-cardio exercise '\(exerciseId)' for cardio workout")
                }
            }
        }

        // If no valid cardio exercises from AI, select default based on duration
        if exerciseIds.isEmpty {
            // Default cardio exercises (prefer treadmill_run as most common)
            let defaultCardioExercises = ["treadmill_run", "bike_steady_state", "rower_intervals", "outdoor_run"]

            // Find first available cardio exercise
            for exerciseId in defaultCardioExercises {
                if TestDataManager.shared.exercises[exerciseId] != nil {
                    exerciseIds.append(exerciseId)
                    break
                }
            }
        }

        // Fail if no cardio exercises available
        guard !exerciseIds.isEmpty else {
            return CardioWorkoutResult(
                success: false,
                error: "No cardio exercises available. Please add cardio exercises to your library."
            )
        }

        // 2. Select appropriate cardio protocol based on duration
        let protocolId = selectCardioProtocol(duration: intent.duration)

        // 3. Assign exercise and protocol to workout
        workout.exerciseIds = exerciseIds
        workout.protocolVariantIds = Dictionary(uniqueKeysWithValues:
            exerciseIds.indices.map { ($0, protocolId) }
        )

        Logger.log(.info, component: "WorkoutCreationService",
            message: "v101.1: Cardio workout created - exercises=\(exerciseIds), protocol=\(protocolId)")

        return CardioWorkoutResult(success: true, error: nil)
    }

    /// Select the best matching cardio protocol for the requested duration
    /// - Parameter duration: Target duration in minutes
    /// - Returns: Protocol ID (e.g., "cardio_30min_steady")
    private static func selectCardioProtocol(duration: Int) -> String {
        // Available cardio protocols with their durations
        let cardioProtocols: [(id: String, durationMinutes: Int)] = [
            ("cardio_20min_steady", 20),
            ("cardio_30min_steady", 30),
            ("cardio_45min_steady", 45),
            ("cardio_intervals_hiit_20min", 20),
            ("cardio_intervals_moderate_30min", 30)
        ]

        // Prefer steady-state protocols unless user specifically requested intervals
        let steadyProtocols = cardioProtocols.filter { $0.id.contains("steady") }

        // Find closest match
        var bestMatch = "cardio_30min_steady"  // Default
        var bestDiff = Int.max

        for proto in steadyProtocols {
            let diff = abs(proto.durationMinutes - duration)
            if diff < bestDiff {
                bestDiff = diff
                bestMatch = proto.id
            }
        }

        // If duration is exactly 20, 30, or 45, we should have an exact match
        // Otherwise we'll use the closest one

        Logger.log(.info, component: "WorkoutCreationService",
            message: "v101.1: Selected cardio protocol '\(bestMatch)' for \(duration)min request")

        return bestMatch
    }

    // MARK: - v101.2: Insert Workout Into Active Plan

    /// Insert a one-off workout into an existing active plan's program
    /// This allows users to add workouts (like cardio) without creating plan conflicts
    /// - Parameters:
    ///   - intent: Workout intent data
    ///   - plan: The active plan to insert into
    ///   - program: The program to attach the workout to
    ///   - userId: User ID
    /// - Returns: WorkoutCreationResult with the plan and created workout
    private static func insertWorkoutIntoActivePlan(
        _ intent: WorkoutIntentData,
        plan: Plan,
        program: Program,
        userId: String
    ) async throws -> WorkoutCreationResult {

        // Create workout attached to existing program
        let workoutId = "\(userId)_ai_\(UUID().uuidString.prefix(8))"
        let effectiveSessionType = intent.sessionType ?? .strength

        var workout = Workout(
            id: workoutId,
            programId: program.id,  // Attach to existing program
            name: intent.name,
            scheduledDate: intent.scheduledDate,
            type: effectiveSessionType,
            splitDay: intent.splitDay,
            status: .scheduled,
            completedDate: nil,
            exerciseIds: [],
            protocolVariantIds: [:],
            exercisesSelectedAt: nil,
            supersetGroups: nil,
            protocolCustomizations: intent.protocolCustomizations
        )

        Logger.log(.info, component: "WorkoutCreationService",
            message: "v101.2: Creating workout '\(intent.name)' in active plan '\(plan.name)'")

        // Exercise selection - reuse existing logic based on session type
        if effectiveSessionType == .cardio {
            let cardioResult = createCardioWorkout(
                intent: intent,
                workout: &workout,
                userId: userId
            )

            if !cardioResult.success {
                throw NSError(domain: "WorkoutCreation", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: cardioResult.error ?? "Failed to create cardio workout"
                ])
            }
        } else {
            // v128: Create a workout-specific plan copy with intent's equipment/location
            // This is critical for "home workout" when user has an active gym plan
            // Without this, the builder uses the active plan's gym equipment
            var workoutPlan = plan
            if let intentLocation = intent.trainingLocation {
                workoutPlan.trainingLocation = intentLocation
                Logger.log(.info, component: "WorkoutCreationService",
                    message: "v128: Overriding plan location from \(plan.trainingLocation.rawValue) → \(intentLocation.rawValue)")
            }

            // v133: For home workouts, use PROFILE equipment, not AI's guess
            // AI often sends equipment like "dumbbells" when user has none configured
            if workoutPlan.trainingLocation == .home {
                // Get user's profile to check configured home equipment
                let userProfile = TestDataManager.shared.users[userId]?.memberProfile

                if let profileEquipment = userProfile?.availableEquipment, !profileEquipment.isEmpty {
                    // User has configured home equipment - use it
                    workoutPlan.availableEquipment = profileEquipment
                    Logger.log(.info, component: "WorkoutCreationService",
                        message: "v133: Home workout using PROFILE equipment: \(profileEquipment.map { $0.rawValue })")
                } else {
                    // User has no home equipment configured → bodyweight only
                    workoutPlan.availableEquipment = Set([.bodyweight, .none])
                    Logger.log(.info, component: "WorkoutCreationService",
                        message: "v133: Home workout with no profile equipment → bodyweight only")
                }

                // Log if AI sent different equipment (for debugging)
                if let intentEquipment = intent.availableEquipment {
                    Logger.log(.debug, component: "WorkoutCreationService",
                        message: "v133: Ignored AI equipment guess: \(intentEquipment.map { $0.rawValue })")
                }
            } else if let intentEquipment = intent.availableEquipment {
                // Non-home workout: use AI's equipment if specified
                workoutPlan.availableEquipment = intentEquipment
                Logger.log(.info, component: "WorkoutCreationService",
                    message: "v128: Overriding plan equipment to intent-specified: \(intentEquipment.map { $0.rawValue })")
            }

            // Use DurationAwareWorkoutBuilder for strength workouts
            // v103: Pass exerciseCountOverride for image-based workout creation
            let buildResult = DurationAwareWorkoutBuilder.build(
                targetDuration: intent.duration,
                splitDay: intent.splitDay,
                plan: workoutPlan,  // v128: Use workout-specific plan with intent's equipment
                program: program,
                userId: userId,
                aiExerciseIds: intent.exerciseIds,
                movementPatternFilter: intent.movementPatternFilter,
                overrideProtocolId: intent.preserveProtocolId,
                exerciseCountOverride: intent.exerciseCountOverride  // v103: Override for image extraction
            )

            guard !buildResult.exerciseIds.isEmpty else {
                throw NSError(domain: "WorkoutCreation", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: "No exercises available for this workout configuration."
                ])
            }

            workout.exerciseIds = buildResult.exerciseIds
            workout.protocolVariantIds = buildResult.protocolVariantIds
        }

        // Mark exercises as selected
        workout.exercisesSelectedAt = Date()

        // Initialize instances and sets
        let workoutIntensities = [workout.id: program.startingIntensity]
        InstanceInitializationService.initializeInstances(
            for: [workout],
            memberId: userId,
            weeklyIntensities: workoutIntensities
        )

        // Save to TestDataManager
        TestDataManager.shared.workouts[workout.id] = workout

        Logger.log(.info, component: "WorkoutCreationService",
            message: "v101.2: Inserted workout '\(workout.name)' (id: \(workout.id)) into plan '\(plan.name)'")

        // Persist workout data
        try await persistInsertedWorkout(workout: workout, plan: plan, program: program, userId: userId)

        // Auto-add exercises and protocols to user's library
        await addWorkoutItemsToLibrary(workout: workout, userId: userId)

        // v101.3: Return both plan and workout
        return WorkoutCreationResult(plan: plan, workout: workout)
    }

    /// v206: Sync inserted workout to Firestore
    private static func persistInsertedWorkout(
        workout: Workout,
        plan: Plan,
        program: Program,
        userId: String
    ) async throws {
        // v206: Sync to Firestore
        let instances = TestDataManager.shared.exerciseInstances.values.filter { $0.workoutId == workout.id }
        let instanceIds = Set(instances.map { $0.id })
        let sets = TestDataManager.shared.exerciseSets.values.filter { instanceIds.contains($0.exerciseInstanceId) }

        try await FirestoreWorkoutRepository.shared.saveFullWorkout(
            workout: workout,
            instances: Array(instances),
            sets: Array(sets),
            memberId: userId
        )

        Logger.log(.info, component: "WorkoutCreationService",
            message: "v206: Synced inserted workout to Firestore")
    }
}
