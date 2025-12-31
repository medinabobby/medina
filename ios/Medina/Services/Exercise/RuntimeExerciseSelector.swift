//
// RuntimeExerciseSelector.swift
// Medina
//
// v71.0: Runtime exercise selection - select exercises on preview/start instead of plan creation
// Created: December 1, 2025
//
// Purpose: Ensure exercises are selected for a workout when the user actually needs them
// Benefits:
// - Library changes (add/remove) immediately affect future selections
// - No stale exercise selections for workouts months out
// - Same exercises shown if user previews then starts same day (cached)
//

import Foundation

/// Runtime exercise selection service
///
/// **v71.0 Architecture:**
/// - Called when user previews or starts a workout
/// - Checks if exercises need selection (empty or stale)
/// - Uses ExerciseSelectionService for actual selection logic
/// - Updates workout with selected exercises and timestamp
/// - Persists changes to LocalDataStore and disk
///
/// **Caching Strategy:**
/// - If `exercisesSelectedAt` is today → use cached exercises
/// - If `exercisesSelectedAt` is older or nil → reselect
/// - This ensures consistent experience within a day (preview → start)
///
@MainActor
enum RuntimeExerciseSelector {

    // MARK: - Error State (for UI surfacing)

    /// Last error message for UI display
    /// Set when selection fails, cleared on success
    static var lastError: String?

    // MARK: - Public API

    /// Ensure exercises are selected for a workout, selecting if needed
    ///
    /// **Call this when:**
    /// 1. User previews a workout (WorkoutDetailView.onAppear)
    /// 2. User starts a workout (StartWorkoutHandler)
    ///
    /// **Behavior:**
    /// - If exercises already selected today → returns workout unchanged
    /// - If exercises not selected or stale → selects now and persists
    ///
    /// - Parameters:
    ///   - workout: The workout to ensure exercises for
    ///   - plan: The plan containing this workout (for selection criteria)
    ///   - userId: User ID for library and persistence
    /// - Returns: Workout with exercises populated (may be same as input if cached)
    static func ensureExercisesSelected(
        for workout: Workout,
        plan: Plan,
        userId: String
    ) -> Workout {
        // Skip if cardio (no exercise selection needed)
        guard workout.type == .strength else {
            return workout
        }

        // Check if exercises are already selected and still valid
        if shouldUseCache(workout: workout) {
            Logger.log(.debug, component: "RuntimeExerciseSelector",
                      message: "Using cached exercises for workout \(workout.id) (selected at \(workout.exercisesSelectedAt?.description ?? "nil"))")
            return workout
        }

        // Need to select exercises
        Logger.log(.info, component: "RuntimeExerciseSelector",
                  message: "🎯 Selecting exercises for workout \(workout.id) (\(workout.splitDay?.rawValue ?? "unknown") day)")

        return selectAndPersist(workout: workout, plan: plan, userId: userId)
    }

    /// Force re-selection of exercises (user requested refresh)
    ///
    /// **Use case:** User wants different exercises than what was auto-selected
    /// Called from workout menu "Refresh Exercises" action
    ///
    /// - Parameters:
    ///   - workout: The workout to refresh exercises for
    ///   - plan: The plan containing this workout
    ///   - userId: User ID for library and persistence
    /// - Returns: Workout with newly selected exercises
    static func refreshExercises(
        for workout: Workout,
        plan: Plan,
        userId: String
    ) -> Workout {
        Logger.log(.info, component: "RuntimeExerciseSelector",
                  message: "🔄 Refreshing exercises for workout \(workout.id)")

        return selectAndPersist(workout: workout, plan: plan, userId: userId)
    }

    /// Check if a workout needs exercise selection
    ///
    /// - Parameter workout: Workout to check
    /// - Returns: True if exercises need to be selected
    static func needsSelection(_ workout: Workout) -> Bool {
        // Cardio workouts don't need selection
        guard workout.type == .strength else { return false }

        // Empty exercises always need selection
        if workout.exerciseIds.isEmpty { return true }

        // Check if selection is stale (not today)
        return !shouldUseCache(workout: workout)
    }

    // MARK: - Private Helpers

    /// Check if cached exercises should be used (selected today)
    private static func shouldUseCache(workout: Workout) -> Bool {
        // No exercises = no cache
        guard !workout.exerciseIds.isEmpty else { return false }

        // No timestamp = treat as stale
        guard let selectedAt = workout.exercisesSelectedAt else { return false }

        // Check if selected today
        let calendar = Calendar.current
        return calendar.isDateInToday(selectedAt)
    }

    /// Select exercises and persist to storage
    /// v78.3: Now also assigns protocols and initializes instances (full WorkoutCreationService flow)
    private static func selectAndPersist(
        workout: Workout,
        plan: Plan,
        userId: String
    ) -> Workout {
        // Use ExerciseSelectionService for selection logic
        let library = LocalDataStore.shared.libraries[userId]
        let exerciseIds = selectExercisesForWorkout(workout: workout, plan: plan, library: library)

        // Update workout with selected exercises
        var updatedWorkout = workout
        updatedWorkout.exerciseIds = exerciseIds
        updatedWorkout.exercisesSelectedAt = Date()

        // v78.3: Get program for protocol assignment
        guard let program = LocalDataStore.shared.programs[workout.programId] else {
            Logger.log(.warning, component: "RuntimeExerciseSelector",
                      message: "Cannot assign protocols - missing program for workout \(workout.id)")
            LocalDataStore.shared.workouts[workout.id] = updatedWorkout
            persistWorkout(updatedWorkout, userId: userId)
            return updatedWorkout
        }

        // v78.3: Assign protocols to exercises (matches WorkoutCreationService flow)
        let (workoutsWithProtocols, workoutIntensities) = ProtocolAssignmentService.assignProtocols(
            for: [updatedWorkout],
            program: program,
            userId: userId,
            goal: plan.goal
        )

        if let workoutWithProtocols = workoutsWithProtocols.first {
            updatedWorkout = workoutWithProtocols
        }

        // v236: Instances now created by Firebase when workout is built/synced
        // No local instance initialization needed

        // Persist to LocalDataStore
        LocalDataStore.shared.workouts[workout.id] = updatedWorkout

        // v236: Sync workout to Firestore (instances created server-side)
        persistWorkout(updatedWorkout, userId: userId)

        Logger.log(.info, component: "RuntimeExerciseSelector",
                  message: "✅ Selected \(exerciseIds.count) exercises with protocols for workout \(workout.id)")

        return updatedWorkout
    }

    /// Select exercises for a single workout using library-first approach
    ///
    /// **v77.0 Fix:** Per ARCHITECTURE.md, implements proper fallback expansion:
    /// 1. First try: Library exercises at user's experience level
    /// 2. Fallback: ALL exercises at ANY experience level (no filter)
    /// 3. Only return [] if even the unrestricted pool fails
    private static func selectExercisesForWorkout(
        workout: Workout,
        plan: Plan,
        library: UserLibrary?
    ) -> [String] {
        // Cardio workouts: Use simple template
        if workout.type == .cardio {
            return ExerciseTemplates.cardioSession
        }

        // Build selection criteria (same logic as ExerciseSelectionService)
        let user = LocalDataStore.shared.users[plan.memberId]
        let memberProfile = user?.memberProfile
        let splitDay = workout.splitDay ?? .fullBody

        // v51.3: Filter equipment based on training location
        let availableEquipment: Set<Equipment>
        if plan.trainingLocation == .home {
            let homeEquipment = memberProfile?.availableEquipment ?? []
            availableEquipment = homeEquipment.isEmpty ? [.bodyweight] : homeEquipment
        } else {
            availableEquipment = Set(Equipment.allCases)
        }

        // Dynamic exercise counts based on duration
        let exerciseCounts = calculateExerciseCounts(
            duration: plan.targetSessionDuration,
            compoundTimeAllocation: plan.compoundTimeAllocation,
            splitDay: splitDay
        )

        // Get library exercise IDs
        let libraryExerciseIds: Set<String> = library?.exercises ?? []
        let userExperienceLevel = plan.experienceLevel ?? memberProfile?.experienceLevel ?? .intermediate

        let criteria = LibrarySelectionCriteria(
            splitDay: splitDay,
            muscleTargets: muscleTargetsForSplit(splitDay),
            compoundCount: exerciseCounts.compounds,
            isolationCount: exerciseCounts.isolations,
            emphasizedMuscles: plan.emphasizedMuscleGroups?.isEmpty == false ? Array(plan.emphasizedMuscleGroups!) : nil,
            availableEquipment: availableEquipment,
            excludedExerciseIds: (plan.excludedMuscleGroups.map { exercisesTargetingMuscles($0) } ?? Set())
                .union(memberProfile?.excludedExerciseIds ?? []),
            goal: plan.goal,
            currentIntensity: 0.75,
            userExperienceLevel: userExperienceLevel,
            libraryExerciseIds: libraryExerciseIds
        )

        // ATTEMPT 1: Use library selector (has built-in experience-level fallback)
        let result = LibraryExerciseSelector.select(criteria: criteria)

        switch result {
        case .success(let exerciseIds):
            return exerciseIds

        case .failure(let error):
            // v77.0 Fix: Per ARCHITECTURE.md, expand to ALL exercises and retry
            Logger.log(.warning, component: "RuntimeExerciseSelector",
                      message: "⚠️ Library selection failed: \(error.userMessage). Expanding to ALL exercises...")

            // ATTEMPT 2: Build expanded criteria with ALL exercises (no experience filter)
            // This matches ARCHITECTURE.md: "expand to all experience-appropriate exercises"
            // We go even further - ALL exercises regardless of experience level
            let allExerciseIds = Set(LocalDataStore.shared.exercises.keys)
                .subtracting(criteria.excludedExerciseIds)

            let expandedCriteria = LibrarySelectionCriteria(
                splitDay: criteria.splitDay,
                muscleTargets: criteria.muscleTargets,
                compoundCount: criteria.compoundCount,
                isolationCount: criteria.isolationCount,
                emphasizedMuscles: criteria.emphasizedMuscles,
                availableEquipment: criteria.availableEquipment,
                excludedExerciseIds: criteria.excludedExerciseIds,
                goal: criteria.goal,
                currentIntensity: criteria.currentIntensity,
                // Use advanced experience level to include all exercises in pool
                userExperienceLevel: .advanced,
                libraryExerciseIds: allExerciseIds
            )

            let retryResult = LibraryExerciseSelector.select(criteria: expandedCriteria)

            switch retryResult {
            case .success(let exerciseIds):
                Logger.log(.info, component: "RuntimeExerciseSelector",
                          message: "✅ Fallback selection succeeded with \(exerciseIds.count) exercises from expanded pool")
                return exerciseIds

            case .failure(let retryError):
                // Even the expanded pool failed - this is a database gap
                Logger.log(.error, component: "RuntimeExerciseSelector",
                          message: "❌ Selection failed even with expanded pool: \(retryError.userMessage)")
                RuntimeExerciseSelector.lastError = retryError.userMessage
                return []
            }
        }
    }

    // MARK: - Helper Methods (copied from ExerciseSelectionService for encapsulation)

    private static func muscleTargetsForSplit(_ splitDay: SplitDay) -> [MuscleGroup] {
        switch splitDay {
        case .upper: return [.chest, .back, .shoulders, .biceps, .triceps]
        case .lower: return [.quadriceps, .hamstrings, .glutes, .calves]
        case .push: return [.chest, .shoulders, .triceps]
        case .pull: return [.back, .biceps, .traps]
        case .legs: return [.quadriceps, .hamstrings, .glutes, .calves]
        case .fullBody: return [.chest, .back, .quadriceps, .hamstrings, .shoulders]
        case .chest: return [.chest, .triceps]
        case .back: return [.back, .biceps, .traps]
        case .shoulders: return [.shoulders, .traps]
        case .arms: return [.biceps, .triceps, .forearms]
        case .notApplicable: return []
        }
    }

    private static func calculateExerciseCounts(
        duration: Int,
        compoundTimeAllocation: Double,
        splitDay: SplitDay
    ) -> (compounds: Int, isolations: Int) {
        let avgCompoundTime = 7.0
        let avgIsolationTime = 5.0
        let exerciseTime = Double(duration) * 0.90

        let compoundTimeBudget = exerciseTime * compoundTimeAllocation
        let isolationTimeBudget = exerciseTime * (1.0 - compoundTimeAllocation)

        var compoundCount = Int(floor(compoundTimeBudget / avgCompoundTime))
        var isolationCount = Int(floor(isolationTimeBudget / avgIsolationTime))

        // Split-specific adjustments
        switch splitDay {
        case .fullBody:
            compoundCount = max(compoundCount, 3)
            isolationCount = min(isolationCount, 2)
        case .arms:
            compoundCount = min(compoundCount, 2)
            isolationCount = max(isolationCount, 3)
        case .chest, .back, .shoulders:
            compoundCount = min(compoundCount, 3)
        case .notApplicable:
            return (0, 0)
        default:
            break
        }

        compoundCount = max(1, min(6, compoundCount))
        isolationCount = max(0, min(5, isolationCount))

        return (compoundCount, isolationCount)
    }

    private static func exercisesTargetingMuscles(_ muscles: Set<MuscleGroup>) -> Set<String> {
        return Set(
            LocalDataStore.shared.exercises.values
                .filter { exercise in
                    !Set(exercise.muscleGroups).intersection(muscles).isEmpty
                }
                .map { $0.id }
        )
    }

    /// v206: Sync workout to Firestore (fire-and-forget)
    private static func persistWorkout(_ workout: Workout, userId: String) {
        Task {
            do {
                try await FirestoreWorkoutRepository.shared.saveWorkout(workout, memberId: userId)
            } catch {
                Logger.log(.warning, component: "RuntimeExerciseSelector",
                          message: "⚠️ Firestore sync failed: \(error)")
            }
        }
    }

    // v236: persistWorkoutWithInstances removed - instances now created by Firebase
}
