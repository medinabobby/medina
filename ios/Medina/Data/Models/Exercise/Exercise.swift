//
// Exercise.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

struct Exercise: Identifiable, Codable {
    let id: String
    var name: String                      // "Flat Barbell Bench Press" (concrete exercise name)
    var baseExercise: String              // "bench_press" (for grouping similar exercises)
    var equipment: Equipment              // Equipment type used
    var type: ExerciseType                // compound/isolation/warmup/cooldown
    var muscleGroups: [MuscleGroup]       // Primary muscle groups
    var movementPattern: MovementPattern? // push/pull/hinge/squat/carry/rotation
    var description: String               // Exercise description
    var instructions: String              // How to perform the exercise
    var videoLink: String?                // Optional video demonstration link
    var experienceLevel: ExperienceLevel  // Difficulty level

    // Custom Exercise Support
    var createdByMemberId: String?
    var createdByTrainerId: String?
    var createdByGymId: String?

    // V13.0 Computed properties for ExerciseShow compatibility
    var primaryMuscle: MuscleGroup? {
        return muscleGroups.first
    }

    var secondaryMuscles: [MuscleGroup] {
        return Array(muscleGroups.dropFirst())
    }

    var difficulty: ExperienceLevel {
        return experienceLevel
    }

    var exerciseType: ExerciseType? {
        return type
    }
}