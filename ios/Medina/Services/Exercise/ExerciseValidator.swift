//
// ExerciseValidator.swift
// Medina
//
// v81.0 - AI-First Exercise Validation
// Created: December 4, 2025
//
// Purpose: Validate AI-selected exercise IDs before creating workouts
// Ensures all exercises exist, match equipment constraints, and aren't excluded
//

import Foundation

/// Validation result for AI-selected exercises
struct ExerciseValidationResult {
    let isValid: Bool
    let validExerciseIds: [String]
    let errors: [String]
    let warnings: [String]

    /// Create a successful validation result
    static func success(_ ids: [String], warnings: [String] = []) -> ExerciseValidationResult {
        ExerciseValidationResult(isValid: true, validExerciseIds: ids, errors: [], warnings: warnings)
    }

    /// Create a failed validation result
    static func failure(_ errors: [String]) -> ExerciseValidationResult {
        ExerciseValidationResult(isValid: false, validExerciseIds: [], errors: errors, warnings: [])
    }
}

/// Validates AI-selected exercises before workout creation
enum ExerciseValidator {

    // MARK: - Main Validation

    /// Validate exercise IDs from AI selection
    /// Checks:
    /// 1. Exercises exist in database
    /// 2. Exercises match equipment constraints
    /// 3. Exercises aren't excluded by user
    /// 4. Exercise count matches duration
    static func validate(
        exerciseIds: [String],
        userId: String,
        trainingLocation: TrainingLocation?,
        availableEquipment: Set<Equipment>?,
        duration: Int,
        splitDay: SplitDay?
    ) -> ExerciseValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        var validIds: [String] = []

        let prefs = TestDataManager.shared.userExercisePreferences(for: userId)
        let allExercises = TestDataManager.shared.exercises

        // Resolve equipment
        let user = TestDataManager.shared.users[userId]
        let equipment = resolveEquipment(
            user: user,
            trainingLocation: trainingLocation,
            availableEquipment: availableEquipment
        )

        // Validate each exercise
        for exerciseId in exerciseIds {
            // 1. Check existence
            guard let exercise = allExercises[exerciseId] else {
                errors.append("Exercise '\(exerciseId)' not found in database")
                continue
            }

            // 2. Check not excluded
            if prefs.isExcluded(exerciseId) {
                errors.append("Exercise '\(exercise.name)' is excluded by user")
                continue
            }

            // 3. Check equipment match
            if !equipment.contains(exercise.equipment) {
                // Warning if it's a favorite (user might have it even without proper equipment)
                if prefs.isFavorite(exerciseId) {
                    warnings.append("'\(exercise.name)' requires \(exercise.equipment.displayName) which may not be available - included because it's a favorite")
                } else {
                    errors.append("'\(exercise.name)' requires \(exercise.equipment.displayName) but user has: \(formatEquipment(equipment))")
                    continue
                }
            }

            // 4. Check muscle group relevance (warning only)
            if let split = splitDay {
                let targetMuscles = muscleGroupsForSplit(split)
                let exerciseMuscles = Set(exercise.muscleGroups)
                if exerciseMuscles.isDisjoint(with: targetMuscles) {
                    warnings.append("'\(exercise.name)' targets \(exercise.muscleGroups.first?.displayName ?? "unknown") - may not match \(split.rawValue) split")
                }
            }

            validIds.append(exerciseId)
        }

        // 5. Check exercise count
        let expectedCount = exerciseCountForDuration(duration)
        if validIds.count < expectedCount - 1 {
            warnings.append("Only \(validIds.count) valid exercises (expected \(expectedCount) for \(duration)min)")
        }

        // Return result
        if errors.isEmpty || validIds.count >= 3 {
            // Success if no errors, or enough valid exercises despite some errors
            return ExerciseValidationResult(
                isValid: true,
                validExerciseIds: validIds,
                errors: errors,
                warnings: warnings
            )
        } else {
            return ExerciseValidationResult.failure(errors)
        }
    }

    // MARK: - Equipment Resolution

    private static func resolveEquipment(
        user: UnifiedUser?,
        trainingLocation: TrainingLocation?,
        availableEquipment: Set<Equipment>?
    ) -> Set<Equipment> {
        // 1. Explicit equipment parameter takes priority
        if let explicit = availableEquipment, !explicit.isEmpty {
            return explicit.union([.bodyweight])
        }

        // 2. Training location determines equipment
        if let location = trainingLocation {
            switch location {
            case .gym:
                return Set(Equipment.allCases)
            case .home:
                if let homeEquipment = user?.memberProfile?.availableEquipment, !homeEquipment.isEmpty {
                    return homeEquipment.union([.bodyweight])
                }
                return [.bodyweight]
            case .outdoor:
                return [.bodyweight]
            case .hybrid:
                return Set(Equipment.allCases)
            }
        }

        // 3. User profile default
        if let defaultLocation = user?.memberProfile?.trainingLocation {
            return resolveEquipment(user: user, trainingLocation: defaultLocation, availableEquipment: nil)
        }

        // 4. Fallback: full gym
        return Set(Equipment.allCases)
    }

    // MARK: - Helpers

    private static func exerciseCountForDuration(_ duration: Int) -> Int {
        switch duration {
        case ...30: return 3
        case 31...45: return 4
        case 46...60: return 5
        case 61...75: return 6
        default: return 7
        }
    }

    private static func muscleGroupsForSplit(_ split: SplitDay) -> Set<MuscleGroup> {
        switch split {
        case .upper:
            return [.chest, .shoulders, .back, .biceps, .triceps, .forearms, .lats]
        case .lower, .legs:
            return [.quadriceps, .hamstrings, .glutes, .calves]
        case .push:
            return [.chest, .shoulders, .triceps]
        case .pull:
            return [.back, .biceps, .forearms, .lats, .traps]
        case .fullBody:
            return Set(MuscleGroup.allCases)
        case .chest:
            return [.chest, .triceps]
        case .back:
            return [.back, .biceps, .lats]
        case .shoulders:
            return [.shoulders, .triceps, .traps]
        case .arms:
            return [.biceps, .triceps, .forearms]
        case .notApplicable:
            return Set(MuscleGroup.allCases)  // Allow any muscle group
        }
    }

    private static func formatEquipment(_ equipment: Set<Equipment>) -> String {
        if equipment.count == Equipment.allCases.count {
            return "full gym"
        }
        return equipment.sorted { $0.rawValue < $1.rawValue }.map { $0.displayName }.joined(separator: ", ")
    }
}

// MARK: - Quick Validation for Common Cases

extension ExerciseValidator {

    /// Quick check if an exercise ID is valid (exists and not excluded)
    static func isValid(_ exerciseId: String, userId: String) -> Bool {
        guard TestDataManager.shared.exercises[exerciseId] != nil else { return false }
        let prefs = TestDataManager.shared.userExercisePreferences(for: userId)
        return !prefs.isExcluded(exerciseId)
    }

    /// Get valid exercise IDs from a list, silently filtering invalid ones
    static func filterValid(_ exerciseIds: [String], userId: String) -> [String] {
        exerciseIds.filter { isValid($0, userId: userId) }
    }
}
