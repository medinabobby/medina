//
// LibraryExerciseSelector.swift
// Medina
//
// v51.0 - Exercise & Protocol Library (Phase 1b)
// v54.x - Refactored to use Set<String> (removed ExerciseLibraryEntry)
// v58.5 - Library-first with experience level fallback
// v70.0 - Added ExerciseSelectionResult to track library vs introduced exercises
// v80.3.7 - Prevent duplicate baseExercise selection (e.g., two Bicep Curl variants)
// Created: November 5, 2025
//
// Purpose: Multi-pass exercise selection with library priority and experience fallback
// Algorithm: Try library first → If insufficient, expand to all exercises at user's level
//

import Foundation

// MARK: - v70.0 Selection Result

/// Result of exercise selection, tracking which came from library vs introduced
struct ExerciseSelectionResult {
    /// All selected exercise IDs
    let exerciseIds: [String]

    /// Exercise IDs that came from user's library
    let fromLibrary: [String]

    /// Exercise IDs that were introduced (not in user's library)
    let introduced: [String]

    /// Whether the selection used experience-level fallback
    let usedFallback: Bool
}

struct LibraryExerciseSelector {

    // MARK: - Main Selection

    /// Select exercises using library-first approach with experience level fallback
    ///
    /// **v58.5 Algorithm:**
    /// 1. Try to select from user's library (preferred exercises)
    /// 2. If library has insufficient exercises, expand to ALL exercises matching:
    ///    - User's experience level or below
    ///    - Available equipment
    ///    - Target muscle groups
    /// 3. Library exercises get a preference boost in ranking
    ///
    /// - Parameters:
    ///   - criteria: Selection criteria including experience level and library IDs
    /// - Returns: Array of exerciseIds, or error if even fallback fails
    static func select(
        criteria: LibrarySelectionCriteria
    ) -> Result<[String], SelectionError> {

        // STEP 1: Build exercise pool (library-first, then expand if needed)
        let (exercisePool, usedFallback) = buildExercisePool(criteria: criteria)

        if usedFallback {
            Logger.log(.info, component: "LibraryExerciseSelector",
                      message: "📚 Using experience-level fallback (library insufficient)")
        }

        // STEP 2: Filter by available equipment
        let equipmentFiltered = exercisePool.filter { exercise in
            criteria.availableEquipment.contains(exercise.equipment)
        }
        Logger.log(.debug, component: "LibraryExerciseSelector",
                  message: "📚 STEP 2: Equipment filter → \(equipmentFiltered.count) exercises")

        // STEP 3: Filter by split day muscle targets
        let muscleFiltered = equipmentFiltered.filter { exercise in
            !Set(exercise.muscleGroups).intersection(criteria.muscleTargets).isEmpty
        }
        Logger.log(.debug, component: "LibraryExerciseSelector",
                  message: "📚 STEP 3: Muscle filter (\(criteria.muscleTargets.map { $0.rawValue }.joined(separator: ", "))) → \(muscleFiltered.count) exercises")

        // STEP 4: Split into compound and isolation pools
        let compoundPool = muscleFiltered.filter { $0.type == .compound }
        let isolationPool = muscleFiltered.filter { $0.type == .isolation }
        Logger.log(.debug, component: "LibraryExerciseSelector",
                  message: "📚 STEP 4: Split → \(compoundPool.count) compounds, \(isolationPool.count) isolations (need \(criteria.compoundCount) + \(criteria.isolationCount))")

        // STEP 5: Validate sufficient exercises exist (even with fallback)
        guard compoundPool.count >= criteria.compoundCount else {
            return .failure(.insufficientCompound(
                needed: criteria.compoundCount,
                available: compoundPool.count,
                muscleTargets: criteria.muscleTargets,
                equipment: criteria.availableEquipment
            ))
        }

        guard isolationPool.count >= criteria.isolationCount else {
            return .failure(.insufficientIsolation(
                needed: criteria.isolationCount,
                available: isolationPool.count,
                muscleTargets: criteria.muscleTargets,
                equipment: criteria.availableEquipment
            ))
        }

        var selectedExerciseIds: [String] = []

        // STEP 6: Select compound exercises (with library preference)
        // v80.3.6: Pass preferBodyweight flag for home/light equipment workouts
        let selectedCompounds = selectCompounds(
            pool: compoundPool,
            count: criteria.compoundCount,
            emphasizedMuscles: criteria.emphasizedMuscles,
            libraryIds: criteria.libraryExerciseIds,
            preferBodyweight: criteria.preferBodyweightCompounds
        )
        selectedExerciseIds.append(contentsOf: selectedCompounds)

        // STEP 7: Select isolation exercises (with library preference)
        let selectedIsolations = selectIsolations(
            pool: isolationPool,
            count: criteria.isolationCount,
            emphasizedMuscles: criteria.emphasizedMuscles,
            alreadySelectedMuscles: extractMuscles(selectedCompounds, from: muscleFiltered),
            libraryIds: criteria.libraryExerciseIds
        )
        selectedExerciseIds.append(contentsOf: selectedIsolations)

        // STEP 8: Log selection for observability
        let libraryCount = selectedExerciseIds.filter { criteria.libraryExerciseIds.contains($0) }.count
        Logger.log(.info, component: "LibraryExerciseSelector",
                  message: "✅ Selected \(selectedExerciseIds.count) exercises (\(libraryCount) from library, \(selectedExerciseIds.count - libraryCount) from fallback) for \(criteria.splitDay.rawValue)")

        return .success(selectedExerciseIds)
    }

    // MARK: - v70.0 Selection with Result Tracking

    /// Select exercises and return detailed result showing library vs introduced exercises
    ///
    /// **Returns:** `ExerciseSelectionResult` with:
    /// - `exerciseIds`: All selected exercise IDs
    /// - `fromLibrary`: Exercise IDs that were in user's library
    /// - `introduced`: Exercise IDs that were NOT in user's library (newly introduced)
    /// - `usedFallback`: Whether experience-level fallback was used
    ///
    /// - Parameter criteria: Selection criteria
    /// - Returns: Result containing selection breakdown, or error
    static func selectWithResult(
        criteria: LibrarySelectionCriteria
    ) -> Result<ExerciseSelectionResult, SelectionError> {

        // STEP 1: Build exercise pool (library-first, then expand if needed)
        let (exercisePool, usedFallback) = buildExercisePool(criteria: criteria)

        if usedFallback {
            Logger.log(.info, component: "LibraryExerciseSelector",
                      message: "📚 Using experience-level fallback (library insufficient)")
        }

        // STEP 2: Filter by available equipment
        let equipmentFiltered = exercisePool.filter { exercise in
            criteria.availableEquipment.contains(exercise.equipment)
        }

        // STEP 3: Filter by split day muscle targets
        let muscleFiltered = equipmentFiltered.filter { exercise in
            !Set(exercise.muscleGroups).intersection(criteria.muscleTargets).isEmpty
        }

        // STEP 4: Split into compound and isolation pools
        let compoundPool = muscleFiltered.filter { $0.type == .compound }
        let isolationPool = muscleFiltered.filter { $0.type == .isolation }

        // STEP 5: Validate sufficient exercises exist
        guard compoundPool.count >= criteria.compoundCount else {
            return .failure(.insufficientCompound(
                needed: criteria.compoundCount,
                available: compoundPool.count,
                muscleTargets: criteria.muscleTargets,
                equipment: criteria.availableEquipment
            ))
        }

        guard isolationPool.count >= criteria.isolationCount else {
            return .failure(.insufficientIsolation(
                needed: criteria.isolationCount,
                available: isolationPool.count,
                muscleTargets: criteria.muscleTargets,
                equipment: criteria.availableEquipment
            ))
        }

        var selectedExerciseIds: [String] = []

        // STEP 6: Select compound exercises
        // v80.3.6: Pass preferBodyweight flag for home/light equipment workouts
        let selectedCompounds = selectCompounds(
            pool: compoundPool,
            count: criteria.compoundCount,
            emphasizedMuscles: criteria.emphasizedMuscles,
            libraryIds: criteria.libraryExerciseIds,
            preferBodyweight: criteria.preferBodyweightCompounds
        )
        selectedExerciseIds.append(contentsOf: selectedCompounds)

        // STEP 7: Select isolation exercises
        let selectedIsolations = selectIsolations(
            pool: isolationPool,
            count: criteria.isolationCount,
            emphasizedMuscles: criteria.emphasizedMuscles,
            alreadySelectedMuscles: extractMuscles(selectedCompounds, from: muscleFiltered),
            libraryIds: criteria.libraryExerciseIds
        )
        selectedExerciseIds.append(contentsOf: selectedIsolations)

        // STEP 8: Partition into fromLibrary and introduced
        let fromLibrary = selectedExerciseIds.filter { criteria.libraryExerciseIds.contains($0) }
        let introduced = selectedExerciseIds.filter { !criteria.libraryExerciseIds.contains($0) }

        Logger.log(.info, component: "LibraryExerciseSelector",
                  message: "✅ Selected \(selectedExerciseIds.count) exercises (\(fromLibrary.count) from library, \(introduced.count) introduced) for \(criteria.splitDay.rawValue)")

        let result = ExerciseSelectionResult(
            exerciseIds: selectedExerciseIds,
            fromLibrary: fromLibrary,
            introduced: introduced,
            usedFallback: usedFallback
        )

        return .success(result)
    }

    // MARK: - Exercise Pool Building

    /// Build exercise pool: library first, then expand to experience level if needed
    private static func buildExercisePool(
        criteria: LibrarySelectionCriteria
    ) -> (exercises: [Exercise], usedFallback: Bool) {

        // First, try library exercises only
        let libraryExercises = criteria.libraryExerciseIds
            .subtracting(criteria.excludedExerciseIds)
            .compactMap { TestDataManager.shared.exercises[$0] }

        Logger.log(.debug, component: "LibraryExerciseSelector",
                  message: "📚 STEP 1a: Library has \(criteria.libraryExerciseIds.count) IDs, resolved \(libraryExercises.count) exercises")

        // Check if library has enough for this split
        let libraryFiltered = libraryExercises.filter { exercise in
            criteria.availableEquipment.contains(exercise.equipment) &&
            !Set(exercise.muscleGroups).intersection(criteria.muscleTargets).isEmpty
        }

        let libraryCompounds = libraryFiltered.filter { $0.type == .compound }.count
        let libraryIsolations = libraryFiltered.filter { $0.type == .isolation }.count

        let libraryHasEnough = libraryCompounds >= criteria.compoundCount &&
                               libraryIsolations >= criteria.isolationCount

        if libraryHasEnough {
            Logger.log(.debug, component: "LibraryExerciseSelector",
                      message: "📚 STEP 1b: Library sufficient (\(libraryCompounds) compounds, \(libraryIsolations) isolations)")
            return (libraryExercises, false)
        }

        // Library insufficient - expand to ALL exercises at user's experience level
        Logger.log(.debug, component: "LibraryExerciseSelector",
                  message: "📚 STEP 1b: Library insufficient (\(libraryCompounds)/\(criteria.compoundCount) compounds, \(libraryIsolations)/\(criteria.isolationCount) isolations) - expanding to experience level")

        let allExercises = TestDataManager.shared.exercises.values.filter { exercise in
            // Filter by experience level (user can do exercises at their level or below)
            exercise.experienceLevel.rawValue <= criteria.userExperienceLevel.rawValue &&
            // Exclude user's excluded exercises
            !criteria.excludedExerciseIds.contains(exercise.id)
        }

        Logger.log(.debug, component: "LibraryExerciseSelector",
                  message: "📚 STEP 1c: Expanded to \(allExercises.count) exercises at \(criteria.userExperienceLevel.rawValue) level or below")

        return (Array(allExercises), true)
    }

    // MARK: - Compound Selection

    private static func selectCompounds(
        pool: [Exercise],
        count: Int,
        emphasizedMuscles: [MuscleGroup]?,
        libraryIds: Set<String>,
        preferBodyweight: Bool = false
    ) -> [String] {

        // Rank exercises with library preference and emphasis boost
        let ranked = pool.map { exercise -> (exercise: Exercise, score: Double) in
            var score = 1.0

            // v80.3.6: Bodyweight preference boost for home/light equipment (2.0x)
            // This ensures push-ups are chosen over dumbbell bench press for home workouts
            if preferBodyweight && exercise.equipment == .bodyweight {
                score *= 2.0
            }

            // v58.5: Library preference boost (1.2x)
            if libraryIds.contains(exercise.id) {
                score *= 1.2
            }

            // Emphasis boost (1.5x)
            if let emphasized = emphasizedMuscles,
               !Set(exercise.muscleGroups).intersection(emphasized).isEmpty {
                score *= 1.5
            }

            return (exercise, score)
        }.sorted { $0.score > $1.score }

        // Ensure movement pattern diversity and no duplicate base exercises
        var selected: [String] = []
        var usedPatterns: Set<MovementPattern> = []
        var usedBaseExercises: Set<String> = []  // v80.3.7: Prevent duplicate baseExercise

        for (exercise, _) in ranked {
            // v80.3.7: Skip if we already selected an exercise with the same baseExercise
            if usedBaseExercises.contains(exercise.baseExercise) {
                continue
            }

            if let pattern = exercise.movementPattern {
                if usedPatterns.contains(pattern) && selected.count < count {
                    continue
                }
                usedPatterns.insert(pattern)
            }

            selected.append(exercise.id)
            usedBaseExercises.insert(exercise.baseExercise)

            if selected.count == count {
                break
            }
        }

        // Fill remaining if diversity blocked slots
        if selected.count < count {
            let remaining = ranked
                .filter { !selected.contains($0.exercise.id) }
                .filter { !usedBaseExercises.contains($0.exercise.baseExercise) }  // v80.3.7
                .prefix(count - selected.count)
            for item in remaining {
                selected.append(item.exercise.id)
                usedBaseExercises.insert(item.exercise.baseExercise)
            }
        }

        return selected
    }

    // MARK: - Isolation Selection

    private static func selectIsolations(
        pool: [Exercise],
        count: Int,
        emphasizedMuscles: [MuscleGroup]?,
        alreadySelectedMuscles: Set<MuscleGroup>,
        libraryIds: Set<String>
    ) -> [String] {

        let ranked = pool.map { exercise -> (exercise: Exercise, score: Double) in
            var score = 1.0

            // v58.5: Library preference boost (1.2x)
            if libraryIds.contains(exercise.id) {
                score *= 1.2
            }

            // Emphasis boost (1.5x)
            if let emphasized = emphasizedMuscles,
               !Set(exercise.muscleGroups).intersection(emphasized).isEmpty {
                score *= 1.5
            }

            // Muscle balance boost (1.3x)
            let underRepresented = Set(exercise.muscleGroups).subtracting(alreadySelectedMuscles)
            if !underRepresented.isEmpty {
                score *= 1.3
            }

            return (exercise, score)
        }.sorted { $0.score > $1.score }

        // v80.3.7: Prevent duplicate baseExercise selection (e.g., two Bicep Curl variants)
        var selected: [String] = []
        var usedBaseExercises: Set<String> = []

        for (exercise, _) in ranked {
            // Skip if we already selected an exercise with the same baseExercise
            if usedBaseExercises.contains(exercise.baseExercise) {
                continue
            }

            selected.append(exercise.id)
            usedBaseExercises.insert(exercise.baseExercise)

            if selected.count == count {
                break
            }
        }

        return selected
    }

    // MARK: - Helpers

    private static func extractMuscles(
        _ exerciseIds: [String],
        from exercises: [Exercise]
    ) -> Set<MuscleGroup> {
        let selected = exercises.filter { exerciseIds.contains($0.id) }
        return Set(selected.flatMap { $0.muscleGroups })
    }
}

// MARK: - SelectionError

enum SelectionError: LocalizedError {
    case insufficientCompound(needed: Int, available: Int, muscleTargets: [MuscleGroup], equipment: Set<Equipment>)
    case insufficientIsolation(needed: Int, available: Int, muscleTargets: [MuscleGroup], equipment: Set<Equipment>)
    case missingMovementPattern(MovementPattern)

    var errorDescription: String? {
        switch self {
        case .insufficientCompound(let needed, let available, let muscles, let equipment):
            return "Need \(needed) compound exercises, but only \(available) available in library for \(muscleNames(muscles)) with \(equipmentNames(equipment))."
        case .insufficientIsolation(let needed, let available, let muscles, let equipment):
            return "Need \(needed) isolation exercises, but only \(available) available in library for \(muscleNames(muscles)) with \(equipmentNames(equipment))."
        case .missingMovementPattern(let pattern):
            return "No exercises found for \(pattern.displayName) movement pattern."
        }
    }

    /// User-friendly error message with actionable guidance
    var userMessage: String {
        switch self {
        case .insufficientCompound(let needed, let available, let muscles, _):
            return "Not enough compound exercises in your library. Need \(needed) for \(muscleNames(muscles)), but only have \(available). Add more compound exercises to your library."
        case .insufficientIsolation(let needed, let available, let muscles, _):
            return "Not enough isolation exercises in your library. Need \(needed) for \(muscleNames(muscles)), but only have \(available). Add more isolation exercises to your library."
        case .missingMovementPattern(let pattern):
            return "Missing exercises for \(pattern.displayName) movement pattern. Add at least one \(pattern.displayName) exercise to your library."
        }
    }

    // MARK: - Formatting Helpers

    private func muscleNames(_ muscles: [MuscleGroup]) -> String {
        if muscles.isEmpty {
            return "all muscles"
        }
        return muscles.map { $0.rawValue }.joined(separator: ", ")
    }

    private func equipmentNames(_ equipment: Set<Equipment>) -> String {
        if equipment.isEmpty {
            return "no equipment"
        }
        return equipment.map { $0.rawValue }.joined(separator: ", ")
    }
}
