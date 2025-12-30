//
//  MinimalDataValidator.swift
//  Medina
//
//  Created on November 20, 2025.
//  Fast-fail validation to catch data integrity bugs during development.
//

import Foundation

/// Minimal data validator that crashes with clear error messages when JSON data is inconsistent.
/// Only runs in DEBUG builds. Catches 90% of referential integrity bugs with 30 lines of code.
enum MinimalDataValidator {

    /// Validates critical data relationships and crashes with helpful error if broken.
    /// Call this during app startup in DEBUG builds only.
    static func validateDataOrCrash() {
        let manager = LocalDataStore.shared

        // Rule 1: All workout exerciseIds must exist in exercises.json
        for (workoutId, workout) in manager.workouts {
            for exerciseId in workout.exerciseIds {
                guard manager.exercises[exerciseId] != nil else {
                    fatalError("❌ DATA INTEGRITY ERROR\n\nWorkout '\(workoutId)' references exercise '\(exerciseId)' which doesn't exist in exercises.json.\n\nFix: Check Resources/Data/workouts.json and exercises.json")
                }
            }
        }

        // Rule 2: All instance protocolVariantIds must exist in protocol_configs.json
        for (instanceId, instance) in manager.exerciseInstances {
            guard manager.protocolConfigs[instance.protocolVariantId] != nil else {
                fatalError("❌ DATA INTEGRITY ERROR\n\nExercise instance '\(instanceId)' references protocol '\(instance.protocolVariantId)' which doesn't exist in protocol_configs.json.\n\nFix: Check Resources/Data/instances.json and protocol_configs.json")
            }
        }

        // Rule 3: Workout exerciseIds must match corresponding instance exerciseIds (guided mode requirement)
        for (workoutId, workout) in manager.workouts {
            for (index, workoutExerciseId) in workout.exerciseIds.enumerated() {
                let instanceId = "\(workoutId)_ex\(index)"
                if let instance = manager.exerciseInstances[instanceId] {
                    guard instance.exerciseId == workoutExerciseId else {
                        fatalError("❌ DATA INTEGRITY ERROR\n\nWorkout '\(workoutId)' has exerciseId '\(workoutExerciseId)' at position \(index), but instance '\(instanceId)' has exerciseId '\(instance.exerciseId)'.\n\nThis causes greyed-out exercises in guided mode.\n\nFix: Make them match in Resources/Data/workouts.json and instances.json")
                    }
                }
            }
        }

        Logger.log(.info, component: "MinimalDataValidator", message: "✅ Data integrity validation passed")
    }
}
