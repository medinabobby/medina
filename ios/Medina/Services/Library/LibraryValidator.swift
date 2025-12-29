//
// LibraryValidator.swift
// Medina
//
// v51.0 - Exercise & Protocol Library (Phase 1.5)
// Created: November 6, 2025
//
// Purpose: Validates library completeness before plan creation
// Checks: Movement pattern coverage, muscle group coverage, protocol availability
//

import Foundation

/// Validation result for a user's library
struct LibraryValidationResult {
    let isValid: Bool
    let warnings: [String]
    let missingPatterns: [MovementPattern]
    let missingMuscles: [MuscleGroup]
    let insufficientProtocols: [ExerciseType]

    var hasWarnings: Bool {
        !warnings.isEmpty
    }

    var summaryMessage: String {
        if isValid {
            return "Your library is complete and ready for plan creation."
        } else {
            let count = warnings.count
            return "Your library has \(count) gap\(count == 1 ? "" : "s") that may limit plan quality."
        }
    }
}

enum LibraryValidator {

    // MARK: - Validation Rules

    /// Core movement patterns that should be covered
    private static let requiredPatterns: [MovementPattern] = [
        .squat,
        .hinge,
        .horizontalPress,
        .verticalPress,
        .horizontalPull,
        .verticalPull,
        .lunge
    ]

    /// Major muscle groups that should be covered
    private static let requiredMuscles: [MuscleGroup] = [
        .chest,
        .back,
        .shoulders,
        .biceps,
        .triceps,
        .quadriceps,
        .hamstrings,
        .glutes,
        .calves,
        .core
    ]

    /// Minimum protocol count by exercise type
    private static let minProtocolsCompound = 3
    private static let minProtocolsIsolation = 2

    // MARK: - Main Validation

    /// Validate library completeness
    /// Returns validation result with warnings and missing coverage
    static func validate(_ library: UserLibrary) -> LibraryValidationResult {
        var warnings: [String] = []
        var missingPatterns: [MovementPattern] = []
        var missingMuscles: [MuscleGroup] = []
        var insufficientProtocols: [ExerciseType] = []

        // Get enabled exercises (join to Exercise model)
        let exerciseIds = library.exercises
        let exercises = exerciseIds.compactMap { TestDataManager.shared.exercises[$0] }
        let protocols = library.enabledProtocols()

        // Check 1: Movement pattern coverage
        let coveredPatterns = Set(exercises.compactMap { $0.movementPattern })
        for pattern in requiredPatterns {
            if !coveredPatterns.contains(pattern) {
                missingPatterns.append(pattern)
                warnings.append("No exercises for \(pattern.displayName) pattern")
            }
        }

        // Check 2: Muscle group coverage
        let coveredMuscles = Set(exercises.flatMap { $0.muscleGroups })
        for muscle in requiredMuscles {
            if !coveredMuscles.contains(muscle) {
                missingMuscles.append(muscle)
                warnings.append("No exercises targeting \(muscle.displayName)")
            }
        }

        // Check 3: Protocol availability for compound exercises
        let compoundProtocols = protocols.filter { $0.applicableTo.contains(.compound) }
        if compoundProtocols.count < minProtocolsCompound {
            insufficientProtocols.append(.compound)
            warnings.append("Only \(compoundProtocols.count) protocol(s) for compound exercises (need \(minProtocolsCompound))")
        }

        // Check 4: Protocol availability for isolation exercises
        let isolationProtocols = protocols.filter { $0.applicableTo.contains(.isolation) }
        if isolationProtocols.count < minProtocolsIsolation {
            insufficientProtocols.append(.isolation)
            warnings.append("Only \(isolationProtocols.count) protocol(s) for isolation exercises (need \(minProtocolsIsolation))")
        }

        // Check 5: Minimum exercise count
        if exercises.count < 10 {
            warnings.append("Library has only \(exercises.count) exercises (recommended: 20+)")
        }

        let isValid = warnings.isEmpty

        return LibraryValidationResult(
            isValid: isValid,
            warnings: warnings,
            missingPatterns: missingPatterns,
            missingMuscles: missingMuscles,
            insufficientProtocols: insufficientProtocols
        )
    }

    // MARK: - Specific Checks

    /// Check if library has sufficient exercises for a specific split type
    static func validateForSplitType(_ library: UserLibrary, splitType: SplitType) -> Bool {
        let exerciseIds = library.exercises
        let exercises = exerciseIds.compactMap { TestDataManager.shared.exercises[$0] }

        switch splitType {
        case .fullBody:
            // Need exercises for all major patterns
            let patterns = Set(exercises.compactMap { $0.movementPattern })
            return patterns.contains(MovementPattern.squat) &&
                   patterns.contains(MovementPattern.hinge) &&
                   patterns.contains(MovementPattern.horizontalPress) &&
                   patterns.contains(MovementPattern.horizontalPull)

        case .upperLower:
            // Need upper and lower body exercises
            let muscles = Set(exercises.flatMap { $0.muscleGroups })
            let hasUpper = muscles.contains(MuscleGroup.chest) && muscles.contains(MuscleGroup.back)
            let hasLower = muscles.contains(MuscleGroup.quadriceps) && muscles.contains(MuscleGroup.hamstrings)
            return hasUpper && hasLower

        case .pushPull, .pushPullLegs:
            // Need push, pull, and leg exercises
            let patterns = Set(exercises.compactMap { $0.movementPattern })
            let hasPush = patterns.contains(MovementPattern.horizontalPress) || patterns.contains(MovementPattern.verticalPress)
            let hasPull = patterns.contains(MovementPattern.horizontalPull) || patterns.contains(MovementPattern.verticalPull)
            let hasLegs = patterns.contains(MovementPattern.squat) || patterns.contains(MovementPattern.hinge)
            return hasPush && hasPull && hasLegs

        case .bodyPart:
            // Need exercises for major muscle groups
            let muscles = Set(exercises.flatMap { $0.muscleGroups })
            return muscles.count >= 6  // At least 6 different muscle groups
        }
    }

    /// Get recommended exercises to fill gaps
    static func getRecommendations(for result: LibraryValidationResult) -> [String] {
        var recommendations: [String] = []

        // Recommend exercises for missing patterns
        for pattern in result.missingPatterns {
            switch pattern {
            case .squat:
                recommendations.append("Add a squat exercise (e.g., Barbell Back Squat, Goblet Squat)")
            case .hinge:
                recommendations.append("Add a hinge exercise (e.g., Romanian Deadlift, Hip Thrust)")
            case .horizontalPress:
                recommendations.append("Add a horizontal press (e.g., Bench Press, Push-ups)")
            case .verticalPress:
                recommendations.append("Add a vertical press (e.g., Overhead Press, Shoulder Press)")
            case .horizontalPull:
                recommendations.append("Add a horizontal pull (e.g., Barbell Row, Cable Row)")
            case .verticalPull:
                recommendations.append("Add a vertical pull (e.g., Pull-ups, Lat Pulldown)")
            case .lunge:
                recommendations.append("Add a lunge exercise (e.g., Walking Lunges, Bulgarian Split Squat)")
            default:
                break
            }
        }

        // Recommend exercises for missing muscles
        for muscle in result.missingMuscles {
            if !result.missingPatterns.contains(where: { pattern in
                // Avoid duplicate recommendations if pattern already covers muscle
                switch pattern {
                case .squat: return [.quadriceps, .glutes].contains(muscle)
                case .hinge: return [.hamstrings, .glutes].contains(muscle)
                case .horizontalPress, .verticalPress: return [.chest, .shoulders, .triceps].contains(muscle)
                case .horizontalPull, .verticalPull: return [.back, .biceps].contains(muscle)
                default: return false
                }
            }) {
                recommendations.append("Add an exercise targeting \(muscle.displayName)")
            }
        }

        // Recommend protocols
        if result.insufficientProtocols.contains(.compound) {
            recommendations.append("Add more compound protocol templates (strength/power focused)")
        }
        if result.insufficientProtocols.contains(.isolation) {
            recommendations.append("Add more isolation protocol templates (hypertrophy focused)")
        }

        return recommendations
    }
}
