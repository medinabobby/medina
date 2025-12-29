//
// ExerciseTemplates.swift
// Medina
//
// v43 Phase 1: Hard-coded exercise templates per split type
// Created: October 28, 2025
//

import Foundation

/// Hard-coded exercise templates for each split type
///
/// **Philosophy: Hard-code common patterns for simplicity**
///
/// Instead of dynamic exercise selection with complex filtering, we pre-define
/// proven exercise combinations for each split type. This ensures:
/// - Fast implementation (no algorithm complexity)
/// - Proven exercise combinations (industry best practices)
/// - Consistent workouts (same exercises throughout program)
/// - Easy debugging (no dynamic selection bugs)
///
/// **Exercise Selection Criteria:**
/// - 5 exercises per split type (optimal for 45-75 min sessions)
/// - Prioritize compounds first (2-3), isolations last (2-3)
/// - Balance muscle groups within split
/// - Use common equipment (barbell, dumbbell, cable, machines)
/// - Suitable for intermediate experience level
///
/// **Usage:**
/// ```swift
/// let exercises = ExerciseTemplates.template(for: .upper)
/// // Returns: ["barbell_bench_press", "barbell_row", ...]
/// ```
enum ExerciseTemplates {

    // MARK: - Upper/Lower Split

    /// Upper Day Template (5 exercises)
    ///
    /// Focus: Horizontal push/pull, vertical push/pull, arms
    /// - Compound: Bench Press (chest), Barbell Row (back)
    /// - Compound: Shoulder Press (shoulders), Lat Pulldown (lats)
    /// - Isolation: Barbell Curl (biceps)
    /// v47.1: Fixed exercise IDs to match exercises.json
    static let upperDay: [String] = [
        "barbell_bench_press",          // Horizontal push (chest, triceps, front delts)
        "barbell_row",                  // Horizontal pull (lats, rhomboids, rear delts)
        "dual_dumbbell_seated_press",   // Vertical push (shoulders, triceps)
        "lat_pulldown",                 // Vertical pull (lats, biceps)
        "barbell_curl"                  // Isolation (biceps)
    ]

    /// Lower Day Template (5 exercises)
    ///
    /// Focus: Quad-dominant, hip-dominant, accessories
    /// - Compound: Back Squat (quads, glutes), Deadlift (posterior chain)
    /// - Isolation: Leg Curl (hamstrings), Leg Extension (quads)
    /// - Isolation: Calf Raise (calves)
    static let lowerDay: [String] = [
        "barbell_back_squat",       // Quad-dominant (quads, glutes, core)
        "conventional_deadlift",    // Hip-dominant (hamstrings, glutes, back)
        "leg_curl",                 // Hamstring isolation
        "leg_extension",            // Quad isolation
        "calf_raise"                // Calf isolation
    ]

    // MARK: - Push/Pull/Legs Split

    /// Push Day Template (5 exercises)
    ///
    /// Focus: Chest, shoulders, triceps
    /// - Compound: Bench Press (chest), Overhead Press (shoulders)
    /// - Compound: Dumbbell Bench (chest variation)
    /// - Isolation: Tricep Extension (triceps), Lateral Raise (side delts)
    /// v47.1: Fixed exercise IDs to match exercises.json
    static let pushDay: [String] = [
        "barbell_bench_press",      // Horizontal push (chest, front delts, triceps)
        "overhead_press",           // Vertical push (shoulders, triceps)
        "dumbbell_bench_press",     // Chest variation (upper chest focus)
        "tricep_extension",         // Tricep isolation
        "dumbbell_lateral_raise"    // Side delt isolation
    ]

    /// Pull Day Template (5 exercises)
    ///
    /// Focus: Back, rear delts, biceps
    /// - Compound: Deadlift (posterior chain), Barbell Row (mid back)
    /// - Compound: Lat Pulldown (lats)
    /// - Isolation: Face Pull (rear delts), Barbell Curl (biceps)
    /// v47.1: Fixed exercise IDs to match exercises.json
    static let pullDay: [String] = [
        "conventional_deadlift",    // Hip-dominant (hamstrings, glutes, back)
        "barbell_row",              // Horizontal pull (lats, rhomboids, rear delts)
        "lat_pulldown",             // Vertical pull (lats, biceps)
        "face_pull",                // Rear delt isolation
        "barbell_curl"              // Bicep isolation
    ]

    /// Legs Day Template (5 exercises)
    ///
    /// Focus: Quads, hamstrings, glutes, calves
    /// - Compound: Back Squat (quads), Romanian Deadlift (hamstrings)
    /// - Compound: Leg Press (quads, glutes)
    /// - Isolation: Leg Curl (hamstrings), Calf Raise (calves)
    static let legsDay: [String] = [
        "barbell_back_squat",       // Quad-dominant (quads, glutes, core)
        "romanian_deadlift",        // Hip-dominant (hamstrings, glutes)
        "leg_press",                // Quad/glute focus (less technical than squat)
        "leg_curl",                 // Hamstring isolation
        "calf_raise"                // Calf isolation
    ]

    // MARK: - Full Body Split

    /// Full Body Day Template (5 exercises)
    ///
    /// Focus: Balanced compound movements hitting all major muscle groups
    /// - Compound: Squat (lower body), Bench Press (push), Row (pull)
    /// - Compound: Overhead Press (shoulders), Romanian Deadlift (posterior)
    static let fullBody: [String] = [
        "barbell_back_squat",       // Lower body (quads, glutes, core)
        "barbell_bench_press",      // Upper push (chest, triceps, front delts)
        "barbell_row",              // Upper pull (lats, rhomboids, rear delts)
        "overhead_press",           // Shoulders (shoulders, triceps)
        "romanian_deadlift"         // Posterior chain (hamstrings, glutes, back)
    ]

    // MARK: - Cardio Split

    /// Cardio Session Template (1 exercise)
    ///
    /// Focus: Simple steady-state cardio
    /// - Cardio: Treadmill running (cardiovascular conditioning)
    ///
    /// **Note:** Beta MVP uses simple single-exercise cardio template
    /// Post-beta will support intervals, bike/rowing variations, etc.
    static let cardioSession: [String] = [
        "treadmill_run"             // Steady-state cardio (cardiovascular conditioning)
    ]

    // MARK: - Template Lookup

    /// Get exercise template for a given split day
    ///
    /// **Usage:**
    /// ```swift
    /// let workout = Workout(splitDay: .upper, ...)
    /// let exercises = ExerciseTemplates.template(for: workout.splitDay)
    /// // Returns: ["barbell_bench_press", "barbell_row", ...]
    /// ```
    ///
    /// - Parameter splitDay: The split day type (upper, lower, push, pull, legs, fullBody)
    /// - Returns: Array of exercise IDs (5 exercises)
    static func template(for splitDay: SplitDay?) -> [String] {
        guard let splitDay = splitDay else {
            return fullBody  // Default to full body if no split specified
        }

        switch splitDay {
        case .upper:
            return upperDay
        case .lower:
            return lowerDay
        case .push:
            return pushDay
        case .pull:
            return pullDay
        case .legs:
            return legsDay
        case .fullBody:
            return fullBody
        case .chest:
            return pushDay  // Chest day uses push template
        case .back:
            return pullDay  // Back day uses pull template
        case .shoulders:
            return pushDay  // Shoulders day uses push template
        case .arms:
            return [
                "barbell_curl",
                "tricep_pushdown",
                "dumbbell_hammer_curl",
                "overhead_tricep_extension",
                "cable_curl"
            ]
        case .notApplicable:
            return cardioSession  // Cardio sessions use simple 1-exercise template
        }
    }
}
