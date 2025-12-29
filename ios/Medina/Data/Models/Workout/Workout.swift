//
// Workout.swift
// Medina
//
// Last reviewed: October 2025
// v71.0: Added exercisesSelectedAt for runtime exercise selection
// v82.4: Added protocolCustomizations for AI-driven protocol adjustments
//

import Foundation

// MARK: - Workout
struct Workout: Identifiable, Codable {
    // Identity
    let id: String
    let programId: String
    
    // Basic Info
    var name: String
    var scheduledDate: Date?
    var type: SessionType
    var splitDay: SplitDay?  // v16.7: Which day of training split (upper, lower, push, pull, etc.)

    // Status
    // v21.0: Renamed completion → status, ExecutionStatus → ExecutionStatus
    var status: ExecutionStatus
    var completedDate: Date?
    
    // Exercise Content
    var exerciseIds: [String]                    // Ordered exercise IDs (defines sequence)
    var protocolVariantIds: [Int: String]        // position -> protocolVariantId

    // v71.0: Runtime Exercise Selection
    // When nil: exercises not yet selected (select on preview/start)
    // When set: exercises were selected at this time (cache until next day)
    var exercisesSelectedAt: Date?

    // v50: Superset Support
    var supersetGroups: [SupersetGroup]?         // Optional superset groupings (e.g., 1a/1b, 2a/2b)

    // v82.4: AI Protocol Customization
    // Optional per-position customizations to base protocols (±2 sets, ±3 reps, ±30s rest)
    var protocolCustomizations: [Int: ProtocolCustomization]?
}

// MARK: - Superset Helpers (v50)

extension Workout {

    /// Check if an exercise position belongs to a superset group
    /// - Parameter position: Index in exerciseIds array
    /// - Returns: The SupersetGroup if position is in a superset, nil otherwise
    func supersetGroup(for position: Int) -> SupersetGroup? {
        return supersetGroups?.first { $0.contains(position: position) }
    }

    /// Check if a position is in any superset
    /// - Parameter position: Index in exerciseIds array
    /// - Returns: True if position belongs to a superset group
    func isInSuperset(position: Int) -> Bool {
        return supersetGroup(for: position) != nil
    }

    /// Get the display label for an exercise (e.g., "1", "2a", "2b", "3")
    /// - Parameter position: Index in exerciseIds array
    /// - Returns: Display label for exercise numbering
    func exerciseDisplayLabel(at position: Int) -> String {
        // Check if exercise is in a superset
        if let group = supersetGroup(for: position) {
            return group.label(for: position) ?? "\(position + 1)"
        }

        // Standalone exercise - calculate number accounting for supersets
        var displayNumber = 1
        var supersetGroupsSeen: Set<Int> = []

        for i in 0..<position {
            if let group = supersetGroup(for: i) {
                // Only count each superset group once
                if !supersetGroupsSeen.contains(group.groupNumber) {
                    supersetGroupsSeen.insert(group.groupNumber)
                    displayNumber += 1
                }
            } else {
                // Standalone exercise
                displayNumber += 1
            }
        }

        return "\(displayNumber)"
    }

    /// Get the total count of exercises/groups for display (e.g., "Exercise 2a of 4")
    /// - Returns: Total number of exercises or exercise groups
    func totalExerciseCount() -> Int {
        var count = 0
        var supersetGroupsSeen: Set<Int> = []

        for i in 0..<exerciseIds.count {
            if let group = supersetGroup(for: i) {
                if !supersetGroupsSeen.contains(group.groupNumber) {
                    supersetGroupsSeen.insert(group.groupNumber)
                    count += 1
                }
            } else {
                count += 1
            }
        }

        return count
    }

    /// Determine the next exercise position after completing a set
    /// - Parameters:
    ///   - currentPosition: Current position in exerciseIds
    ///   - currentSet: Current set index (0-based)
    ///   - totalSets: Total number of sets for current exercise
    /// - Returns: Next exercise position, or nil if workout complete
    func nextExercisePosition(
        after currentPosition: Int,
        currentSet: Int,
        totalSets: Int
    ) -> Int? {
        // Check if in superset
        if let group = supersetGroup(for: currentPosition) {
            // Still have sets remaining in this superset cycle
            if currentSet < totalSets - 1 {
                // Rotate to next exercise in superset group
                if let nextPos = group.nextPosition(after: currentPosition, wrapAround: true) {
                    return nextPos
                }
            } else {
                // Completed all sets - move past superset group
                let maxPositionInGroup = group.exercisePositions.max() ?? currentPosition
                let nextPos = maxPositionInGroup + 1
                return nextPos < exerciseIds.count ? nextPos : nil
            }
        }

        // Standalone exercise - simple increment
        let nextPos = currentPosition + 1
        return nextPos < exerciseIds.count ? nextPos : nil
    }

    /// Get the rest duration after completing a set at the given position
    /// - Parameters:
    ///   - position: Position in exerciseIds
    ///   - protocolConfig: The protocol config for the exercise (fallback for standalone exercises)
    ///   - setIndex: Current set index (for protocol-based rest lookup)
    /// - Returns: Rest duration in seconds
    func restDuration(
        after position: Int,
        protocolConfig: ProtocolConfig,
        setIndex: Int
    ) -> Int {
        // Check if exercise is in superset - use superset rest times
        if let group = supersetGroup(for: position),
           let supersetRest = group.restDuration(after: position) {
            return supersetRest
        }

        // Standalone exercise - use protocol rest times
        guard setIndex < protocolConfig.restBetweenSets.count else {
            return protocolConfig.restBetweenSets.last ?? 60
        }
        return protocolConfig.restBetweenSets[setIndex]
    }

    /// Computed display name for user-facing contexts (UI, TTS)
    /// Format: "Mon, Nov 10" (day of week + short date)
    /// Falls back to stored name if scheduledDate is nil
    var displayName: String {
        guard let date = scheduledDate else {
            return name
        }

        let calendar = Calendar.current
        let dayOfWeekIndex = calendar.component(.weekday, from: date)
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let dayName = dayNames[dayOfWeekIndex - 1]

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let dateStr = formatter.string(from: date)

        return "\(dayName), \(dateStr)"
    }
}

// MARK: - Workout Session
struct WorkoutSession: Identifiable, Codable {
    // Identity
    let id: String
    let workoutId: String
    let memberId: String
    
    // Timing
    var startTime: Date
    var endTime: Date?
    
    // State
    var isActive: Bool
    var currentExerciseIndex: Int
    
    // Notes
    var sessionNotes: String?
}

