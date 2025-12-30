//
// WorkoutModificationService.swift
// Medina
//
// v60.1 - Workout Modification Service
// v83.2 - Preserve original structure (exercises, supersets, protocols) during modification
// Enables conversational workout modifications (delete + recreate pattern)
// Created: November 2025
//

import Foundation

/// Errors that can occur during workout modification
enum WorkoutModificationError: LocalizedError {
    case workoutNotFound(String)
    case planNotFound(String)
    case cannotModifyActiveWorkout(String)
    case cannotModifyCompletedWorkout(String)
    case recreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .workoutNotFound(let id):
            return "Workout not found: \(id)"
        case .planNotFound(let id):
            return "Plan not found for workout: \(id)"
        case .cannotModifyActiveWorkout(let name):
            return "Cannot modify active workout '\(name)'. End or abandon it first."
        case .cannotModifyCompletedWorkout(let name):
            return "Cannot modify completed workout '\(name)'. This is a historical record."
        case .recreationFailed(let reason):
            return "Failed to recreate workout: \(reason)"
        }
    }

    /// User-friendly message for AI response
    var userMessage: String {
        switch self {
        case .workoutNotFound:
            return "I couldn't find that workout. It may have been deleted."
        case .planNotFound:
            return "I couldn't find the plan for that workout."
        case .cannotModifyActiveWorkout(let name):
            return "The workout '\(name)' is currently active. You'll need to end or abandon it before making changes."
        case .cannotModifyCompletedWorkout(let name):
            return "The workout '\(name)' has been completed and can't be modified. Would you like me to create a new one instead?"
        case .recreationFailed(let reason):
            return "I had trouble updating the workout: \(reason). Would you like to try again?"
        }
    }
}

/// Data for workout modification
/// v101.1: Added newSessionType for strength <-> cardio conversion
/// v129: Added newTrainingLocation for gym <-> home conversion
struct WorkoutModificationData {
    let workoutId: String
    let newDuration: Int?
    let newSplitDay: SplitDay?
    let newEffortLevel: EffortLevel?
    let newName: String?
    let newScheduledDate: Date?

    // v101.1: Session type change (strength <-> cardio)
    // When changing to cardio, exercises will be completely replaced with cardio exercises
    let newSessionType: SessionType?

    // v129: Training location change (gym <-> home)
    // When changing to home, exercises will be replaced with bodyweight alternatives
    let newTrainingLocation: TrainingLocation?

    // v83.2: Protocol customizations to apply to specific positions
    // Keys are exercise positions (0-indexed), values are customizations
    let protocolCustomizations: [Int: ProtocolCustomization]?

    // v83.2: Whether to preserve original exercises (default: true when not changing split/duration)
    // When true: keeps original exerciseIds, supersetGroups, protocolVariantIds
    // When false: selects new exercises based on split/duration
    let preserveExercises: Bool
    // v87.0: Removed targetMuscles - use movementPatterns for movement-based requests

    init(
        workoutId: String,
        newDuration: Int? = nil,
        newSplitDay: SplitDay? = nil,
        newEffortLevel: EffortLevel? = nil,
        newName: String? = nil,
        newScheduledDate: Date? = nil,
        newSessionType: SessionType? = nil,
        newTrainingLocation: TrainingLocation? = nil,
        protocolCustomizations: [Int: ProtocolCustomization]? = nil,
        preserveExercises: Bool = true
    ) {
        self.workoutId = workoutId
        self.newDuration = newDuration
        self.newSplitDay = newSplitDay
        self.newEffortLevel = newEffortLevel
        self.newName = newName
        self.newScheduledDate = newScheduledDate
        self.newSessionType = newSessionType
        self.newTrainingLocation = newTrainingLocation
        self.protocolCustomizations = protocolCustomizations
        self.preserveExercises = preserveExercises
    }
}

/// Service for modifying existing workouts
enum WorkoutModificationService {

    // MARK: - Modification

    /// Modify a workout by deleting and recreating with new parameters
    /// - Parameters:
    ///   - modification: Modification data specifying what to change
    ///   - userId: User ID
    /// - Returns: Tuple of (new workout ID, new Plan)
    /// - Throws: WorkoutModificationError if modification fails
    static func modifyWorkout(
        _ modification: WorkoutModificationData,
        userId: String
    ) async throws -> (newWorkoutId: String, plan: Plan) {

        // 1. Find the workout
        guard let workout = LocalDataStore.shared.workouts[modification.workoutId] else {
            throw WorkoutModificationError.workoutNotFound(modification.workoutId)
        }

        // 2. Find the program and plan
        guard let program = LocalDataStore.shared.programs[workout.programId] else {
            throw WorkoutModificationError.planNotFound(modification.workoutId)
        }

        guard let plan = LocalDataStore.shared.plans[program.planId] else {
            throw WorkoutModificationError.planNotFound(modification.workoutId)
        }

        // 3. Validate workout can be modified
        switch workout.status {
        case .inProgress:
            throw WorkoutModificationError.cannotModifyActiveWorkout(workout.name)
        case .completed:
            throw WorkoutModificationError.cannotModifyCompletedWorkout(workout.name)
        case .scheduled, .skipped:
            // OK to modify
            break
        }

        // 4. Capture original values (use new if specified, otherwise keep original)
        let originalName = workout.name
        let originalDate = workout.scheduledDate ?? Date()
        let originalSplitDay = workout.splitDay ?? .fullBody
        let originalDuration = plan.targetSessionDuration
        let originalEffortLevel = effortLevelFromProgram(program)

        // v82.2: Capture equipment constraints BEFORE deleting plan
        let originalTrainingLocation = plan.trainingLocation
        let originalAvailableEquipment = plan.availableEquipment

        // v83.2: Capture original workout structure BEFORE deleting
        let originalExerciseIds = workout.exerciseIds
        let originalSupersetGroups = workout.supersetGroups
        let originalProtocolVariantIds = workout.protocolVariantIds
        let originalProtocolCustomizations = workout.protocolCustomizations

        let newSplitDay = modification.newSplitDay ?? originalSplitDay
        let newDate = modification.newScheduledDate ?? originalDate

        // v60.2.3: Auto-generate name if split changed but no explicit name provided
        let newName: String
        if let explicitName = modification.newName {
            newName = explicitName
        } else if modification.newSplitDay != nil {
            // Split changed - generate new name to match
            newName = generateWorkoutName(for: newSplitDay)
        } else {
            newName = originalName
        }
        let newDuration = modification.newDuration ?? originalDuration
        let newEffortLevel = modification.newEffortLevel ?? originalEffortLevel

        // v83.2: Determine if we should preserve original exercises
        // Preserve when: no ACTUAL split/duration change AND preserveExercises flag is true
        // Key fix: Only consider it a structural change if the value actually DIFFERS from original
        let splitActuallyChanged = modification.newSplitDay != nil && modification.newSplitDay != originalSplitDay
        let durationActuallyChanged = modification.newDuration != nil && modification.newDuration != originalDuration
        let structuralChange = splitActuallyChanged || durationActuallyChanged
        let shouldPreserveExercises = modification.preserveExercises && !structuralChange

        Logger.log(.info, component: "WorkoutModificationService",
                  message: "v83.2 Modifying '\(originalName)': duration=\(originalDuration)→\(newDuration) (changed=\(durationActuallyChanged)), split=\(originalSplitDay)→\(newSplitDay) (changed=\(splitActuallyChanged)), preserveExercises=\(shouldPreserveExercises), originalExercises=\(originalExerciseIds.count), supersetGroups=\(originalSupersetGroups?.count ?? 0)")

        // 5. Delete the old workout (cascade: instances, sets)
        try deleteWorkout(workoutId: modification.workoutId, userId: userId)

        // 6. Also delete the plan and program since single workouts have 1:1:1 relationship
        LocalDataStore.shared.programs.removeValue(forKey: program.id)
        LocalDataStore.shared.plans.removeValue(forKey: plan.id)

        // 7. Persist deletions
        try persistAfterDeletion(userId: userId)

        // 8. v83.2: Merge protocol customizations (new ones override existing)
        var mergedCustomizations: [Int: ProtocolCustomization]? = nil
        if shouldPreserveExercises {
            // Start with original customizations
            mergedCustomizations = originalProtocolCustomizations ?? [:]
            // Merge in new customizations (override existing)
            if let newCustomizations = modification.protocolCustomizations {
                for (position, customization) in newCustomizations {
                    mergedCustomizations?[position] = customization
                }
            }
            // If empty after merge, set to nil
            if mergedCustomizations?.isEmpty == true {
                mergedCustomizations = nil
            }
        } else {
            // Not preserving - use new customizations only
            mergedCustomizations = modification.protocolCustomizations
        }

        // 9. v83.5: When preserving exercises, ALWAYS use explicit mode to bypass DurationAwareWorkoutBuilder
        // This ensures exercises aren't rebuilt/reselected when only changing protocol customizations
        // Key fix: Even if no superset groups, using .explicit + exerciseIds preserves the exact exercises
        let supersetStyle: SupersetStyle? = shouldPreserveExercises ? .explicit : nil

        // 9.5 v84.1: Detect if all exercises had the same protocol (e.g., GBC applied to all)
        // If so, preserve that protocol for all exercises in the new workout
        var preserveProtocolId: String? = nil
        let protocolValues = Array(originalProtocolVariantIds.values)
        if !protocolValues.isEmpty {
            let uniqueProtocols = Set(protocolValues)
            if uniqueProtocols.count == 1, let commonProtocol = uniqueProtocols.first {
                preserveProtocolId = commonProtocol
                Logger.log(.info, component: "WorkoutModificationService",
                          message: "v84.1: All exercises had same protocol '\(commonProtocol)' - will preserve for modified workout")
            } else {
                Logger.log(.info, component: "WorkoutModificationService",
                          message: "v84.1: Original workout had mixed protocols (\(uniqueProtocols.count) unique) - using default protocols for new exercises")
            }
        }

        // 10. Create new workout with modified parameters
        // v83.2: Preserve original structure when not making structural changes
        // v84.1: Pass preserveProtocolId so all exercises get the same protocol
        // v101.1: Use new session type if specified, otherwise preserve original
        let effectiveSessionType = modification.newSessionType ?? workout.type
        let sessionTypeChanged = modification.newSessionType != nil && modification.newSessionType != workout.type

        // v101.1: When changing session type, don't preserve exercises (they're incompatible)
        // Also don't preserve protocol (strength vs cardio protocols differ fundamentally)
        // v129: Same logic applies when changing training location (gym → home)
        let locationChanged = modification.newTrainingLocation != nil && modification.newTrainingLocation != originalTrainingLocation
        let finalPreserveExercises = (sessionTypeChanged || locationChanged) ? false : shouldPreserveExercises
        let finalPreserveProtocol = sessionTypeChanged ? nil : preserveProtocolId

        if sessionTypeChanged {
            Logger.log(.info, component: "WorkoutModificationService",
                message: "v101.1: Session type changing from \(workout.type.rawValue) to \(effectiveSessionType.rawValue) - exercises will be replaced")
        }

        // v129: Handle training location change
        let effectiveTrainingLocation = modification.newTrainingLocation ?? originalTrainingLocation
        var effectiveAvailableEquipment = originalAvailableEquipment

        if locationChanged {
            Logger.log(.info, component: "WorkoutModificationService",
                message: "v129: Training location changing from \(originalTrainingLocation.rawValue) to \(effectiveTrainingLocation.rawValue) - exercises will be replaced")

            // v129: When changing to home, override equipment to bodyweight
            if effectiveTrainingLocation == .home {
                effectiveAvailableEquipment = Set([.bodyweight, .none])
                Logger.log(.info, component: "WorkoutModificationService",
                    message: "v129: Home workout → forcing bodyweight-only equipment")
            }
        }

        let intent = WorkoutIntentData(
            name: newName,
            splitDay: newSplitDay,
            scheduledDate: newDate,
            duration: newDuration,
            effortLevel: newEffortLevel,
            sessionType: effectiveSessionType,  // v101.1: Use new type if specified
            trainingLocation: effectiveTrainingLocation,  // v129: Use new location if specified
            availableEquipment: effectiveAvailableEquipment,  // v129: Override for home
            exerciseIds: finalPreserveExercises ? originalExerciseIds : nil,
            selectionReasoning: finalPreserveExercises ? "Preserved from original workout during modification" : nil,
            protocolCustomizations: mergedCustomizations,
            supersetStyle: supersetStyle,
            supersetGroups: finalPreserveExercises ? convertToIntents(originalSupersetGroups) : nil,
            preserveProtocolId: finalPreserveProtocol,
            movementPatternFilter: nil,  // v87.0: No pattern filter when modifying existing workouts
            exerciseCountOverride: nil   // v103: Not used for modifications
        )

        do {
            // v101.3: Use WorkoutCreationResult which returns both plan and workout
            let result = try await WorkoutCreationService.createFromIntent(intent, userId: userId)

            Logger.log(.info, component: "WorkoutModificationService",
                      message: "✅ Successfully modified workout: old=\(modification.workoutId) → new=\(result.workout.id)")

            return (newWorkoutId: result.workout.id, plan: result.plan)

        } catch {
            Logger.log(.error, component: "WorkoutModificationService",
                      message: "Recreation failed: \(error)")
            throw WorkoutModificationError.recreationFailed(error.localizedDescription)
        }
    }

    // MARK: - Deletion

    /// Delete a workout and its related instances and sets
    /// - Parameters:
    ///   - workoutId: Workout ID to delete
    ///   - userId: User ID (for persistence)
    /// - Throws: WorkoutModificationError if deletion fails
    static func deleteWorkout(workoutId: String, userId: String) throws {

        guard let workout = LocalDataStore.shared.workouts[workoutId] else {
            throw WorkoutModificationError.workoutNotFound(workoutId)
        }

        // Find all instances for this workout
        let instances = LocalDataStore.shared.exerciseInstances.values.filter {
            $0.workoutId == workoutId
        }
        let instanceIds = Set(instances.map { $0.id })

        // Find all sets for these instances
        let sets = LocalDataStore.shared.exerciseSets.values.filter {
            instanceIds.contains($0.exerciseInstanceId)
        }

        Logger.log(.info, component: "WorkoutModificationService",
                  message: "Deleting workout '\(workout.name)': \(instances.count) instances, \(sets.count) sets")

        // Delete in reverse order (sets → instances → workout)
        for set in sets {
            LocalDataStore.shared.exerciseSets.removeValue(forKey: set.id)
        }
        for instance in instances {
            LocalDataStore.shared.exerciseInstances.removeValue(forKey: instance.id)
        }
        LocalDataStore.shared.workouts.removeValue(forKey: workoutId)

        Logger.log(.info, component: "WorkoutModificationService",
                  message: "✅ Deleted workout '\(workout.name)' and \(instances.count) instances, \(sets.count) sets")
    }

    // MARK: - Helpers

    /// v206: Deletion syncs to Firestore via cascade delete
    private static func persistAfterDeletion(userId: String) throws {
        // v206: Removed legacy disk persistence - Firestore sync handled by delete operations
        Logger.log(.info, component: "WorkoutModificationService",
                  message: "Deletion complete - Firestore sync handled by caller")
    }

    /// Extract effort level from program intensity
    private static func effortLevelFromProgram(_ program: Program) -> EffortLevel {
        let intensity = program.startingIntensity
        if intensity < 0.7 {
            return .recovery
        } else if intensity < 0.85 {
            return .standard
        } else {
            return .pushIt
        }
    }

    /// v60.2.3: Generate workout name based on split day
    private static func generateWorkoutName(for splitDay: SplitDay) -> String {
        switch splitDay {
        case .upper:
            return "Upper Body Strength"
        case .lower:
            return "Lower Body Strength"
        case .push:
            return "Push Day"
        case .pull:
            return "Pull Day"
        case .legs:
            return "Leg Day - Strength Focus"
        case .fullBody:
            return "Full Body Strength"
        case .chest:
            return "Chest Focus"
        case .back:
            return "Back Focus"
        case .shoulders:
            return "Shoulders Focus"
        case .arms:
            return "Arms Focus"
        case .notApplicable:
            return "Workout"
        }
    }

    /// v83.2: Convert SupersetGroup array to SupersetGroupIntent array for WorkoutIntentData
    /// This preserves superset structure when modifying a workout
    private static func convertToIntents(_ groups: [SupersetGroup]?) -> [SupersetGroupIntent]? {
        guard let groups = groups, !groups.isEmpty else {
            return nil
        }

        return groups.map { group in
            // Extract rest between (all except last) and rest after (last) from the rest array
            let restBetween: Int
            let restAfter: Int

            if group.restBetweenExercises.count >= 2 {
                // Use first rest as "between" and last as "after"
                restBetween = group.restBetweenExercises.first ?? 30
                restAfter = group.restBetweenExercises.last ?? 60
            } else if group.restBetweenExercises.count == 1 {
                // Single rest value - use for both
                let rest = group.restBetweenExercises[0]
                restBetween = rest
                restAfter = rest
            } else {
                // No rest values - use defaults
                restBetween = 30
                restAfter = 60
            }

            return SupersetGroupIntent(
                positions: group.exercisePositions,
                restBetween: restBetween,
                restAfter: restAfter
            )
        }
    }
}
