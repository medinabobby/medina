//
// LibrarySelectionCriteria.swift
// Medina
//
// v51.0 - Exercise & Protocol Library (Phase 1a)
// Created: November 5, 2025
//
// Purpose: Input parameters for library exercise/protocol selection
// Passed to LibraryExerciseSelector and LibraryProtocolSelector
//

import Foundation

struct LibrarySelectionCriteria {
    let splitDay: SplitDay
    let muscleTargets: [MuscleGroup]
    let compoundCount: Int
    let isolationCount: Int
    let emphasizedMuscles: [MuscleGroup]?
    let availableEquipment: Set<Equipment>
    let excludedExerciseIds: Set<String>
    let goal: FitnessGoal
    let currentIntensity: Double  // For protocol matching (0.0-1.0)

    // v58.5: Experience level fallback support
    let userExperienceLevel: ExperienceLevel  // For fallback to all exercises
    let libraryExerciseIds: Set<String>       // User's library (for preference boost)

    // v80.3.6: Prefer bodyweight for compound movements (for home/light equipment workouts)
    let preferBodyweightCompounds: Bool

    // Default initializer for backward compatibility
    init(
        splitDay: SplitDay,
        muscleTargets: [MuscleGroup],
        compoundCount: Int,
        isolationCount: Int,
        emphasizedMuscles: [MuscleGroup]?,
        availableEquipment: Set<Equipment>,
        excludedExerciseIds: Set<String>,
        goal: FitnessGoal,
        currentIntensity: Double,
        userExperienceLevel: ExperienceLevel,
        libraryExerciseIds: Set<String>,
        preferBodyweightCompounds: Bool = false
    ) {
        self.splitDay = splitDay
        self.muscleTargets = muscleTargets
        self.compoundCount = compoundCount
        self.isolationCount = isolationCount
        self.emphasizedMuscles = emphasizedMuscles
        self.availableEquipment = availableEquipment
        self.excludedExerciseIds = excludedExerciseIds
        self.goal = goal
        self.currentIntensity = currentIntensity
        self.userExperienceLevel = userExperienceLevel
        self.libraryExerciseIds = libraryExerciseIds
        self.preferBodyweightCompounds = preferBodyweightCompounds
    }
}
