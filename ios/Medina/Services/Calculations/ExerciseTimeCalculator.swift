//
// ExerciseTimeCalculator.swift
// Medina
//
// Time estimation service for exercises and workouts
// v101.0: Updated to use duration field for cardio (replaces tempo hack)
//

import Foundation

enum ExerciseTimeCalculator {

    // MARK: - Exercise Time Calculation

    /// Calculate total time for a single exercise based on protocol configuration
    /// - Parameters:
    ///   - protocolConfig: The protocol configuration containing reps, tempo, and rest times
    ///   - workoutType: The workout type (strength, cardio, etc.) to determine tempo parsing
    /// - Returns: Total time in seconds for the exercise
    static func calculateExerciseTime(protocolConfig: ProtocolConfig, workoutType: SessionType) -> Int {
        // v101.0: Use duration field for cardio protocols (replaces tempo hack)
        if let duration = protocolConfig.duration {
            return duration
        }

        // Parse tempo based on workout type (fallback for legacy cardio data)
        let tempoSeconds: Int
        switch workoutType {
        case .cardio:
            tempoSeconds = parseCardioTempo(tempo: protocolConfig.tempo)
        case .strength, .mobility, .class, .hybrid:
            tempoSeconds = parseStrengthTempo(tempo: protocolConfig.tempo)
        }

        // If tempo is special (continuous/static), return 0 (no calculation)
        guard tempoSeconds > 0 else { return 0 }

        // Calculate time for all sets: sum(reps[i] * tempo_seconds)
        let setTime = protocolConfig.reps.reduce(0) { total, reps in
            total + (reps * tempoSeconds)
        }

        // Calculate rest time: sum(restBetweenSets)
        let restTime = protocolConfig.restBetweenSets.reduce(0, +)

        return setTime + restTime
    }

    // MARK: - Workout Time Calculation

    /// Calculate total time for a workout based on all exercise protocols
    /// - Parameters:
    ///   - protocolConfigs: Array of protocol configurations for each exercise
    ///   - workoutType: The workout type (strength, cardio, etc.) to determine tempo parsing
    ///   - restBetweenExercises: Rest time in seconds between exercises (default 0, TBD)
    /// - Returns: Total time in minutes
    static func calculateWorkoutTime(protocolConfigs: [ProtocolConfig?], workoutType: SessionType, restBetweenExercises: Int = 0) -> Int {
        // Sum time for all exercises
        var totalSeconds = 0

        for config in protocolConfigs {
            if let config = config {
                totalSeconds += calculateExerciseTime(protocolConfig: config, workoutType: workoutType)
            }
        }

        // Add rest between exercises (n-1 rest periods for n exercises)
        let exerciseCount = protocolConfigs.count
        if exerciseCount > 1 {
            totalSeconds += (exerciseCount - 1) * restBetweenExercises
        }

        // Convert to minutes (round up)
        return Int(ceil(Double(totalSeconds) / 60.0))
    }

    // MARK: - Time Formatting

    /// Format time in seconds to human-readable string
    /// - Parameter seconds: Time in seconds
    /// - Returns: Formatted string like "5 min" or "45 sec"
    static func formatTime(seconds: Int) -> String {
        if seconds >= 60 {
            let minutes = Int(ceil(Double(seconds) / 60.0))
            return minutes == 1 ? "1 min" : "\(minutes) min"
        } else {
            return "\(seconds) sec"
        }
    }

    // MARK: - Tempo Parsing

    /// Parse strength tempo to seconds per rep (original working logic)
    /// - Parameter tempo: Tempo string like "2010", "20X0", "continuous", "static"
    /// - Returns: Total seconds per rep, or 0 for special tempos
    private static func parseStrengthTempo(tempo: String?) -> Int {
        guard let tempo = tempo, !tempo.isEmpty else { return 0 }

        // Handle special tempo cases
        let lowerTempo = tempo.lowercased()
        if lowerTempo == "continuous" || lowerTempo == "static" {
            return 0
        }

        // Parse standard tempo format (4 digits: eccentric-pause-concentric-pause)
        // Example: "2010" = 2 + 0 + 1 + 0 = 3 seconds
        // Example: "20X0" = 2 + 0 + 1 + 0 = 3 seconds (X = explosive = 1)
        var totalSeconds = 0

        for char in tempo {
            if char.isNumber {
                if let digit = Int(String(char)) {
                    totalSeconds += digit
                }
            } else if char.uppercased() == "X" {
                // X means explosive - count as 1 second
                totalSeconds += 1
            }
            // Ignore other characters (like dashes or spaces)
        }

        return totalSeconds
    }

    /// Parse cardio tempo as total duration in seconds (legacy fallback)
    /// - Parameter tempo: Numeric duration string like "1200" (20 min), "1800" (30 min)
    /// - Returns: Total duration in seconds
    ///
    /// v101.0: RESOLVED - Added dedicated `duration` field to ProtocolConfig.
    /// This function is now only a fallback for legacy data that hasn't been migrated.
    /// New cardio protocols should use `duration: Int` field instead of `tempo: String`.
    private static func parseCardioTempo(tempo: String?) -> Int {
        guard let tempo = tempo, !tempo.isEmpty else { return 0 }

        // Handle special tempo cases
        let lowerTempo = tempo.lowercased()
        if lowerTempo == "continuous" || lowerTempo == "static" {
            return 0
        }

        // Parse as total duration in seconds
        // Example: "1800" = 1800 seconds = 30 minutes
        if let duration = Int(tempo), tempo.allSatisfy({ $0.isNumber }) {
            return duration
        }

        return 0
    }
}
