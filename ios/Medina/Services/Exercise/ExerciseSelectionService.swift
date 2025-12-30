//
// ExerciseSelectionService.swift
// Medina
//
// v43 Phase 1: Simple exercise selection with 2 filters only
// v51.0 Phase 1b: Library-first exercise selection
// v70.0: Added library awareness - tracks fromLibrary vs introduced exercises
// Created: October 28, 2025
// Updated: November 5, 2025, December 1, 2025
//

import Foundation

// MARK: - v70.0 Aggregated Selection Result

/// Aggregated result of exercise selection across all workouts in a plan
struct PlanExerciseSelectionResult {
    /// All workouts with exercises populated
    let workouts: [Workout]

    /// All unique exercise IDs that came from user's library
    let fromLibrary: Set<String>

    /// All unique exercise IDs that were introduced (not in user's library)
    let introduced: Set<String>

    /// Whether any workout used experience-level fallback
    let usedFallback: Bool

    /// Total number of unique exercises selected
    var totalUniqueExercises: Int {
        return fromLibrary.count + introduced.count
    }
}

/// Exercise selection service using user library
///
/// **v51.0: Library-First Selection**
///
/// Uses LibraryExerciseSelector to select exercises from user's curated library:
/// 1. Filter by equipment, muscle targets, and client exclusions
/// 2. Split into compound and isolation pools
/// 3. Rank by selection weight and emphasis alignment
/// 4. Ensure movement pattern diversity
///
/// **Fallback:** If user has no library (legacy users), falls back to template-based selection
///
/// **Usage:**
/// ```swift
/// let workoutsWithExercises = ExerciseSelectionService.populateExercises(
///     for: scheduledWorkouts,
///     plan: plan,
///     userId: memberId
/// )
/// ```
enum ExerciseSelectionService {

    // MARK: - Error State (for UI surfacing)

    /// v58.5: Last error message for UI display
    /// Set when selection fails, cleared on success
    /// Thread-safe via MainActor isolation in callers
    static var lastError: String?

    // MARK: - Public API

    /// Populate exercises for all workouts in a plan
    ///
    /// **v51.0 Process:**
    /// 1. Load user's library from LocalDataStore
    /// 2. For each workout, use LibraryExerciseSelector to select exercises
    /// 3. Fall back to template-based selection if library unavailable
    ///
    /// **Selection:**
    /// - **Library mode:** Uses LibraryExerciseSelector with user's curated exercises
    /// - **Template mode:** Uses hard-coded templates (legacy fallback)
    ///
    /// - Parameters:
    ///   - workouts: Scheduled workouts (from WorkoutScheduler)
    ///   - plan: Plan with strategy fields
    ///   - userId: User ID to load library for
    /// - Returns: Workouts with exerciseIds populated (4-6 exercises per workout)
    static func populateExercises(for workouts: [Workout], plan: Plan, userId: String) -> [Workout] {
        // v51.0: Load user's library
        let library = LocalDataStore.shared.libraries[userId]

        return workouts.map { workout in
            var updated = workout
            updated.exerciseIds = selectExercises(for: workout, plan: plan, library: library)
            return updated
        }
    }

    // MARK: - v70.0 Library-Aware Selection

    /// Populate exercises for all workouts and return detailed library breakdown
    ///
    /// **v70.0 Process:**
    /// 1. For each workout, select exercises and track library vs introduced
    /// 2. Aggregate across all workouts
    /// 3. Return workouts with exercises AND library breakdown
    ///
    /// - Parameters:
    ///   - workouts: Scheduled workouts (from WorkoutScheduler)
    ///   - plan: Plan with strategy fields
    ///   - userId: User ID to load library for
    /// - Returns: PlanExerciseSelectionResult with workouts and library breakdown
    static func populateExercisesWithResult(for workouts: [Workout], plan: Plan, userId: String) -> PlanExerciseSelectionResult {
        let library = LocalDataStore.shared.libraries[userId]
        let libraryExerciseIds = library?.exercises ?? []

        var updatedWorkouts: [Workout] = []
        var allFromLibrary: Set<String> = []
        var allIntroduced: Set<String> = []
        var anyUsedFallback = false

        for workout in workouts {
            var updated = workout

            // Cardio workouts don't have exercise selection
            if workout.type == .cardio {
                updated.exerciseIds = ExerciseTemplates.cardioSession
                updatedWorkouts.append(updated)
                continue
            }

            // Use the new selectWithResult method
            let result = selectFromLibraryWithResult(workout: workout, plan: plan, library: library)

            switch result {
            case .success(let selectionResult):
                updated.exerciseIds = selectionResult.exerciseIds
                allFromLibrary.formUnion(selectionResult.fromLibrary)
                allIntroduced.formUnion(selectionResult.introduced)
                if selectionResult.usedFallback {
                    anyUsedFallback = true
                }
            case .failure(let error):
                Logger.log(.error, component: "ExerciseSelectionService",
                          message: "❌ Selection failed for workout: \(error.userMessage)")
                ExerciseSelectionService.lastError = error.userMessage
                updated.exerciseIds = []
            }

            updatedWorkouts.append(updated)
        }

        Logger.log(.info, component: "ExerciseSelectionService",
                  message: "📊 Plan selection complete: \(allFromLibrary.count) from library, \(allIntroduced.count) introduced")

        return PlanExerciseSelectionResult(
            workouts: updatedWorkouts,
            fromLibrary: allFromLibrary,
            introduced: allIntroduced,
            usedFallback: anyUsedFallback
        )
    }

    /// Select from library and return detailed result
    private static func selectFromLibraryWithResult(
        workout: Workout,
        plan: Plan,
        library: UserLibrary?
    ) -> Result<ExerciseSelectionResult, SelectionError> {
        // Build selection criteria (same as selectFromLibrary)
        let user = LocalDataStore.shared.users[plan.memberId]
        let memberProfile = user?.memberProfile
        let splitDay = workout.splitDay ?? .fullBody

        // v80.3: Plan-level equipment override takes precedence (for AI home workouts)
        // v80.3.6: Always include bodyweight for home workouts
        let availableEquipment: Set<Equipment>
        if let planEquipment = plan.availableEquipment, !planEquipment.isEmpty {
            // v80.3.6: Always include bodyweight - it's always available at home
            availableEquipment = planEquipment.union([.bodyweight])
        } else if plan.trainingLocation == .home {
            let homeEquipment = memberProfile?.availableEquipment ?? []
            availableEquipment = homeEquipment.isEmpty ? [.bodyweight] : homeEquipment.union([.bodyweight])
        } else {
            availableEquipment = defaultEquipment()
        }

        let exerciseCounts = calculateExerciseCounts(
            duration: plan.targetSessionDuration,
            compoundTimeAllocation: plan.compoundTimeAllocation,
            splitDay: splitDay
        )

        let libraryExerciseIds: Set<String> = library?.exercises ?? []
        let userExperienceLevel = plan.experienceLevel ?? memberProfile?.experienceLevel ?? .intermediate

        // v80.3.6: Prefer bodyweight for compounds when user has limited/home equipment
        let isHomeOrLimitedEquipment = plan.trainingLocation == .home ||
                                        plan.availableEquipment != nil

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
            libraryExerciseIds: libraryExerciseIds,
            preferBodyweightCompounds: isHomeOrLimitedEquipment
        )

        // Use the new selectWithResult method
        return LibraryExerciseSelector.selectWithResult(criteria: criteria)
    }

    // MARK: - Private Helpers

    /// Select exercises for a single workout
    ///
    /// **v51.0 Algorithm:**
    /// 1. If library available: Use LibraryExerciseSelector
    /// 2. If library unavailable: Fall back to template-based selection
    ///
    /// **Result:** 4-6 exercises depending on split and filters
    /// - Cardio: 1 exercise (simple template)
    /// - Strength: 4-6 exercises (compound + isolation mix)
    ///
    /// - Parameters:
    ///   - workout: Workout to populate exercises for
    ///   - plan: Plan with strategy fields
    ///   - library: User's exercise library (optional)
    /// - Returns: Array of exercise IDs
    private static func selectExercises(for workout: Workout, plan: Plan, library: UserLibrary?) -> [String] {
        // Cardio workouts: Use simple template, no filtering
        if workout.type == .cardio {
            return ExerciseTemplates.cardioSession
        }

        // v58.5: Library is optional - fallback will use experience level filtering
        // Clear any previous error
        ExerciseSelectionService.lastError = nil

        return selectFromLibrary(workout: workout, plan: plan, library: library)
    }

    // MARK: - v58.5 Library-First Selection

    /// Select exercises using library-first approach with experience level fallback
    private static func selectFromLibrary(workout: Workout, plan: Plan, library: UserLibrary?) -> [String] {
        // Build selection criteria
        let user = LocalDataStore.shared.users[plan.memberId]
        let memberProfile = user?.memberProfile

        // Unwrap splitDay or use fullBody as default
        let splitDay = workout.splitDay ?? .fullBody

        // v51.3: Filter equipment based on training location
        // v80.3: Plan-level equipment override takes precedence (for AI home workouts)
        // v80.3.6: Always include bodyweight for home workouts (bodyweight is always available)
        let availableEquipment: Set<Equipment>
        if let planEquipment = plan.availableEquipment, !planEquipment.isEmpty {
            // v80.3: AI-specified equipment from tool parameters (highest priority)
            // v80.3.6: Always include bodyweight - it's always available at home
            availableEquipment = planEquipment.union([.bodyweight])
            Logger.log(.info, component: "ExerciseSelectionService",
                      message: "🏠 Using plan equipment + bodyweight: \(availableEquipment.map { $0.rawValue })")
        } else if plan.trainingLocation == .home {
            // v58.4: Home workouts use home equipment from profile (Settings → Home Equipment)
            // Falls back to bodyweight-only if no equipment specified
            // v81.2 FIX: Always include bodyweight for home workouts
            let homeEquipment = memberProfile?.availableEquipment ?? []
            availableEquipment = homeEquipment.isEmpty ? [.bodyweight] : homeEquipment.union([.bodyweight])
            Logger.log(.info, component: "ExerciseSelectionService",
                      message: "🏠 Home workout - using equipment: \(availableEquipment.map { $0.rawValue }) (profile had: \(homeEquipment.map { $0.rawValue }))")
        } else {
            // Gym workouts: Use all equipment (gym has everything)
            availableEquipment = defaultEquipment()
            Logger.log(.info, component: "ExerciseSelectionService",
                      message: "🏋️ Gym workout - using all equipment")
        }

        // v58.4: Dynamic exercise counts based on duration
        let exerciseCounts = calculateExerciseCounts(
            duration: plan.targetSessionDuration,
            compoundTimeAllocation: plan.compoundTimeAllocation,
            splitDay: splitDay
        )

        // v58.5: Get library exercise IDs (empty set if no library)
        let libraryExerciseIds: Set<String> = library?.exercises ?? []

        // v58.5: Get experience level (prefer plan override, then profile, then default)
        let userExperienceLevel = plan.experienceLevel ?? memberProfile?.experienceLevel ?? .intermediate

        // v80.3.6: Prefer bodyweight for compounds when user has limited/home equipment
        // This ensures push-ups are chosen over dumbbell bench press for home workouts
        let isHomeOrLimitedEquipment = plan.trainingLocation == .home ||
                                        plan.availableEquipment != nil

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
            currentIntensity: 0.75,  // Default intensity for exercise selection
            userExperienceLevel: userExperienceLevel,
            libraryExerciseIds: libraryExerciseIds,
            preferBodyweightCompounds: isHomeOrLimitedEquipment
        )

        // v58.5: Use library selector (now handles fallback internally)
        let result = LibraryExerciseSelector.select(criteria: criteria)

        switch result {
        case .success(let exerciseIds):
            return exerciseIds
        case .failure(let error):
            // v58.5: Surface error to UI, no silent fallback
            Logger.log(.error, component: "ExerciseSelectionService",
                      message: "❌ Library selection failed - \(error.userMessage)")
            ExerciseSelectionService.lastError = error.userMessage
            return []
        }
    }

    // MARK: - Legacy Template Selection

    /// Select exercises using hard-coded templates (legacy fallback)
    private static func selectFromTemplates(workout: Workout, plan: Plan) -> [String] {
        // Step 1: Get base template
        var exercises = ExerciseTemplates.template(for: workout.splitDay)

        // Step 2: v51.3 Filter by training location
        // v80.3: Plan-level equipment override takes precedence
        if let planEquipment = plan.availableEquipment, !planEquipment.isEmpty {
            exercises = filterByEquipment(exercises, allowedEquipment: planEquipment)
        } else if plan.trainingLocation == .home {
            // v58.4: Use home equipment from profile, fallback to bodyweight
            let user = LocalDataStore.shared.users[plan.memberId]
            let homeEquipment = user?.memberProfile?.availableEquipment ?? []
            let allowedEquipment = homeEquipment.isEmpty ? [Equipment.bodyweight] : homeEquipment
            exercises = filterByEquipment(exercises, allowedEquipment: allowedEquipment)
        }

        // Step 3: Filter excluded muscles
        if let excluded = plan.excludedMuscleGroups, !excluded.isEmpty {
            exercises = filterExcludedMuscles(exercises, excluded: excluded)
        }

        // Step 4: Add bonus for emphasized muscles
        if let emphasized = plan.emphasizedMuscleGroups, !emphasized.isEmpty {
            if let bonusExercise = findBonusExercise(for: emphasized.first!, excluding: exercises, location: plan.trainingLocation) {
                exercises.append(bonusExercise)
            }
        }

        return exercises
    }

    // MARK: - Selection Helpers

    /// Get muscle targets for a split day
    private static func muscleTargetsForSplit(_ splitDay: SplitDay) -> [MuscleGroup] {
        switch splitDay {
        case .upper:
            return [.chest, .back, .shoulders, .biceps, .triceps]
        case .lower:
            return [.quadriceps, .hamstrings, .glutes, .calves]
        case .push:
            return [.chest, .shoulders, .triceps]
        case .pull:
            return [.back, .biceps, .traps]
        case .legs:
            return [.quadriceps, .hamstrings, .glutes, .calves]
        case .fullBody:
            return [.chest, .back, .quadriceps, .hamstrings, .shoulders]
        case .chest:
            return [.chest, .triceps]
        case .back:
            return [.back, .biceps, .traps]
        case .shoulders:
            return [.shoulders, .traps]
        case .arms:
            return [.biceps, .triceps, .forearms]
        case .notApplicable:
            return []
        }
    }

    // MARK: - v58.4 Dynamic Exercise Count Calculation

    /// Calculate compound and isolation exercise counts based on duration and split
    ///
    /// **Formula:**
    /// 1. Total exercise time = duration (accounting for warmup/transitions)
    /// 2. Compound time = exerciseTime × compoundTimeAllocation
    /// 3. Compound count = compoundTime / avgCompoundTime (7 min avg)
    /// 4. Isolation count = (exerciseTime - compoundTime) / avgIsolationTime (5 min avg)
    ///
    /// **Duration Scaling:**
    /// | Duration | Compounds | Isolations | Total |
    /// |----------|-----------|------------|-------|
    /// | 30 min   | 2         | 1          | 3     |
    /// | 45 min   | 3         | 2          | 5     |
    /// | 60 min   | 4         | 2          | 6     |
    /// | 75 min   | 4         | 3          | 7     |
    /// | 90 min   | 5         | 3          | 8     |
    ///
    /// **Split Adjustments:**
    /// - Full Body: Slightly more compounds, fewer isolations
    /// - Arms: Fewer compounds, more isolations
    /// - Standard splits: Use base calculation
    ///
    /// - Parameters:
    ///   - duration: Target session duration in minutes
    ///   - compoundTimeAllocation: Fraction of time for compounds (0.0-1.0)
    ///   - splitDay: Split type for adjustments
    /// - Returns: Tuple of (compounds, isolations) counts
    private static func calculateExerciseCounts(
        duration: Int,
        compoundTimeAllocation: Double,
        splitDay: SplitDay
    ) -> (compounds: Int, isolations: Int) {
        // Constants: Average time per exercise type (minutes)
        let avgCompoundTime = 7.0  // ~3-4 sets × 3-5 reps × rest = 7 min
        let avgIsolationTime = 5.0 // ~3 sets × 10-12 reps × rest = 5 min

        // Account for warmup and transitions (~10% of total time)
        let exerciseTime = Double(duration) * 0.90

        // Calculate time budgets
        let compoundTimeBudget = exerciseTime * compoundTimeAllocation
        let isolationTimeBudget = exerciseTime * (1.0 - compoundTimeAllocation)

        // Base counts from time budgets
        var compoundCount = Int(floor(compoundTimeBudget / avgCompoundTime))
        var isolationCount = Int(floor(isolationTimeBudget / avgIsolationTime))

        // Apply split-specific adjustments
        switch splitDay {
        case .fullBody:
            // Full body: Favor compounds for time efficiency
            compoundCount = max(compoundCount, 3)
            isolationCount = min(isolationCount, 2)
        case .arms:
            // Arms: Fewer compounds, more isolations
            compoundCount = min(compoundCount, 2)
            isolationCount = max(isolationCount, 3)
        case .chest, .back, .shoulders:
            // Single muscle focus: Moderate compounds, more isolations
            compoundCount = min(compoundCount, 3)
        case .notApplicable:
            return (0, 0)
        default:
            // Standard splits (upper, lower, push, pull, legs): Use base calculation
            break
        }

        // Enforce minimum bounds (always have at least 1 compound)
        compoundCount = max(1, compoundCount)
        isolationCount = max(0, isolationCount)

        // Enforce maximum bounds (library may not have enough exercises)
        compoundCount = min(6, compoundCount)
        isolationCount = min(5, isolationCount)

        Logger.log(.info, component: "ExerciseSelectionService",
                  message: "📊 Dynamic counts for \(duration)min \(splitDay.rawValue): \(compoundCount) compounds + \(isolationCount) isolations (allocation: \(Int(compoundTimeAllocation * 100))%)")

        return (compoundCount, isolationCount)
    }

    /// Get exercises that target specific muscle groups
    private static func exercisesTargetingMuscles(_ muscles: Set<MuscleGroup>) -> Set<String> {
        return Set(
            LocalDataStore.shared.exercises.values
                .filter { exercise in
                    !Set(exercise.muscleGroups).intersection(muscles).isEmpty
                }
                .map { $0.id }
        )
    }

    /// Default equipment set (all equipment types)
    private static func defaultEquipment() -> Set<Equipment> {
        return Set(Equipment.allCases)
    }

    /// Filter exercises by allowed equipment (v51.3)
    ///
    /// **Logic:**
    /// - Only keep exercises that use allowed equipment types
    /// - Used for home workouts to filter to bodyweight only
    ///
    /// - Parameters:
    ///   - exercises: Array of exercise IDs
    ///   - allowedEquipment: Set of allowed equipment types
    /// - Returns: Filtered array of exercise IDs
    private static func filterByEquipment(_ exercises: [String], allowedEquipment: Set<Equipment>) -> [String] {
        return exercises.filter { exerciseId in
            guard let exercise = LocalDataStore.shared.exercises[exerciseId] else {
                return false  // Remove if exercise not found
            }

            // Check if exercise's equipment is in allowed set
            return allowedEquipment.contains(exercise.equipment)
        }
    }

    /// Filter out exercises that target excluded muscle groups
    ///
    /// **Logic:**
    /// - If exercise's primary muscle is in excluded list → remove
    /// - If exercise's secondary muscles overlap with excluded → keep (only filter primary)
    ///
    /// **Example:**
    /// ```
    /// excluded: [.chest]
    /// exercises: ["barbell_bench_press", "barbell_row", ...]
    /// result: ["barbell_row", ...] (bench press removed)
    /// ```
    ///
    /// - Parameters:
    ///   - exercises: Array of exercise IDs
    ///   - excluded: Muscle groups to exclude (Set)
    /// - Returns: Filtered array of exercise IDs
    private static func filterExcludedMuscles(_ exercises: [String], excluded: Set<MuscleGroup>) -> [String] {
        return exercises.filter { exerciseId in
            guard let exercise = LocalDataStore.shared.exercises[exerciseId] else {
                return true  // Keep if exercise not found (defensive)
            }

            // Check if primary muscle is in excluded list
            if let primaryMuscle = exercise.muscleGroups.first {
                return !excluded.contains(primaryMuscle)
            }

            return true  // Keep if no muscle groups defined
        }
    }

    /// Find bonus exercise for emphasized muscle group
    ///
    /// **Logic:**
    /// - Search exercises.json for exercise targeting emphasized muscle
    /// - Exclude exercises already in template
    /// - Filter by location (home = bodyweight only, v51.3)
    /// - Prefer isolation exercises (more targeted)
    /// - Return first match found
    ///
    /// **Example:**
    /// ```
    /// emphasized: .glutes
    /// excluding: ["barbell_back_squat", ...]
    /// location: .gym
    /// result: "hip_thrust" (glute isolation exercise)
    /// ```
    ///
    /// - Parameters:
    ///   - muscleGroup: Emphasized muscle group to find exercise for
    ///   - currentExercises: Exercise IDs already in template (to avoid duplicates)
    ///   - location: Training location (filters equipment, v51.3)
    /// - Returns: Exercise ID for bonus exercise, or nil if none found
    private static func findBonusExercise(for muscleGroup: MuscleGroup, excluding currentExercises: [String], location: TrainingLocation) -> String? {
        let allExercises = LocalDataStore.shared.exercises

        // Find exercises that:
        // 1. Target the emphasized muscle (primary muscle)
        // 2. Not already in current exercise list
        // 3. Match location equipment requirements (v51.3)
        // 4. Prefer isolation exercises (more targeted for emphasis)
        let candidates = allExercises.values.filter { exercise in
            // Check primary muscle matches
            guard let primaryMuscle = exercise.muscleGroups.first else { return false }
            guard primaryMuscle == muscleGroup else { return false }

            // Check not already in current exercises
            guard !currentExercises.contains(exercise.id) else { return false }

            // v51.3: Check location equipment requirements
            if location == .home && exercise.equipment != .bodyweight {
                return false
            }

            return true
        }

        // Prefer isolation exercises
        let isolationCandidates = candidates.filter { $0.type == .isolation }
        if let isolation = isolationCandidates.first {
            return isolation.id
        }

        // Fallback to any candidate (compound)
        return candidates.first?.id
    }
}
