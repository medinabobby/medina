//
// SupersetGroup.swift
// Medina
//
// v50: Superset support for grouped exercise execution
// Created: November 2025
//
// Purpose: Defines superset groupings where exercises are performed in alternating sets
// Example: Superset 1a/1b with exercises at positions [2,3] alternates between them
//
// Execution Pattern:
// - Exercise 1a Set 1 → rest restBetweenExercises[0] → Exercise 1b Set 1 → rest restBetweenExercises[1]
// - Exercise 1a Set 2 → rest restBetweenExercises[0] → Exercise 1b Set 1 → rest restBetweenExercises[1]
// - Repeat until all sets complete
//

import Foundation

/// Defines a group of exercises performed as a superset (alternating sets)
struct SupersetGroup: Identifiable, Codable, Hashable {

    // MARK: - Properties

    /// Unique identifier for this superset group
    let id: String

    /// Display number for the group (e.g., 1 for "1a/1b", 2 for "2a/2b")
    let groupNumber: Int

    /// Positions of exercises in the workout.exerciseIds array that belong to this group
    /// Example: [2, 3] means exercises at indices 2 and 3 form a superset pair
    let exercisePositions: [Int]

    /// Rest duration (in seconds) after each exercise in the superset rotation
    /// Array length must equal exercisePositions.count
    /// Example: [30, 60] = rest 30s after first exercise, 60s after second before cycling
    var restBetweenExercises: [Int]

    // MARK: - Computed Properties

    /// Number of exercises in this superset group
    var exerciseCount: Int {
        exercisePositions.count
    }

    /// Check if this group contains a specific workout exercise position
    func contains(position: Int) -> Bool {
        exercisePositions.contains(position)
    }

    /// Get the superset label for a position (e.g., "1a", "1b", "2a")
    /// - Parameter position: Exercise position in workout.exerciseIds
    /// - Returns: Display label like "1a", "1b", or nil if position not in group
    func label(for position: Int) -> String? {
        guard let index = exercisePositions.firstIndex(of: position) else {
            return nil
        }

        // Convert index to letter: 0 = "a", 1 = "b", 2 = "c", etc.
        let letter = String(UnicodeScalar(97 + index)!) // 97 is ASCII for 'a'
        return "\(groupNumber)\(letter)"
    }

    /// Get the next exercise position in the superset rotation
    /// - Parameters:
    ///   - currentPosition: Current exercise position in workout.exerciseIds
    ///   - wrapAround: If true, cycles back to first exercise; if false, returns nil at end
    /// - Returns: Next position in rotation, or nil if at end and not wrapping
    func nextPosition(after currentPosition: Int, wrapAround: Bool = true) -> Int? {
        guard let currentIndex = exercisePositions.firstIndex(of: currentPosition) else {
            return nil
        }

        let nextIndex = currentIndex + 1

        if nextIndex < exercisePositions.count {
            return exercisePositions[nextIndex]
        } else if wrapAround {
            return exercisePositions[0] // Cycle back to first exercise
        } else {
            return nil // End of superset cycle
        }
    }

    /// Get rest duration after completing a set at the given position
    /// - Parameter position: Exercise position in workout.exerciseIds
    /// - Returns: Rest duration in seconds, or nil if position not in group
    func restDuration(after position: Int) -> Int? {
        guard let index = exercisePositions.firstIndex(of: position),
              index < restBetweenExercises.count else {
            return nil
        }

        return restBetweenExercises[index]
    }

    // MARK: - Validation

    /// Validate that rest durations match exercise count
    var isValid: Bool {
        return restBetweenExercises.count == exercisePositions.count
    }
}

// MARK: - Convenience Initializers

extension SupersetGroup {

    /// Create a simple 2-exercise superset with symmetric rest times
    /// - Parameters:
    ///   - groupNumber: Display number (1 for "1a/1b", 2 for "2a/2b")
    ///   - position1: First exercise position in workout
    ///   - position2: Second exercise position in workout
    ///   - restBetweenSets: Rest duration in seconds (used for both exercises)
    static func pair(
        groupNumber: Int,
        position1: Int,
        position2: Int,
        restBetweenSets: Int
    ) -> SupersetGroup {
        let id = "superset_\(groupNumber)_\(position1)_\(position2)"
        return SupersetGroup(
            id: id,
            groupNumber: groupNumber,
            exercisePositions: [position1, position2],
            restBetweenExercises: [restBetweenSets, restBetweenSets]
        )
    }

    /// Create a 2-exercise superset with asymmetric rest times
    /// - Parameters:
    ///   - groupNumber: Display number
    ///   - position1: First exercise position
    ///   - position2: Second exercise position
    ///   - restAfterFirst: Rest in seconds after first exercise
    ///   - restAfterSecond: Rest in seconds after second exercise
    static func pair(
        groupNumber: Int,
        position1: Int,
        position2: Int,
        restAfterFirst: Int,
        restAfterSecond: Int
    ) -> SupersetGroup {
        let id = "superset_\(groupNumber)_\(position1)_\(position2)"
        return SupersetGroup(
            id: id,
            groupNumber: groupNumber,
            exercisePositions: [position1, position2],
            restBetweenExercises: [restAfterFirst, restAfterSecond]
        )
    }
}
