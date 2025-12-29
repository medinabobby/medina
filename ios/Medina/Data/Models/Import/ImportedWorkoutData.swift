//
// ImportedWorkoutData.swift
// Medina
//
// v72.0: Data models for workout history import
// v74.6: Added ImportedSession/ImportedSet for full history storage
// Created: December 1, 2025
//

import Foundation

/// Source of imported data
enum ImportSource: String, Codable, CaseIterable {
    case screenshot     // Photo of PR board, workout log, app screenshot
    case csv           // CSV file export from other apps
    case peloton       // Peloton API integration
    case appleHealth   // Apple HealthKit
    case manual        // User typed directly
    case url           // v106: URL import from articles/Reddit/etc.

    var displayName: String {
        switch self {
        case .screenshot: return "Screenshot"
        case .csv: return "CSV File"
        case .peloton: return "Peloton"
        case .appleHealth: return "Apple Health"
        case .manual: return "Manual Entry"
        case .url: return "URL Import"
        }
    }

    var icon: String {
        switch self {
        case .screenshot: return "camera.fill"
        case .csv: return "doc.fill"
        case .peloton: return "bicycle"
        case .appleHealth: return "heart.fill"
        case .manual: return "pencil"
        case .url: return "link"
        }
    }
}

/// Data extracted from any import source
struct ImportedWorkoutData: Codable, Identifiable {
    let id: String
    let userId: String
    var exercises: [ImportedExerciseData]       // Aggregated per-exercise summary
    var sessions: [ImportedSession]             // Full session history (v74.6)
    let source: ImportSource
    let importDate: Date
    var rawDataReference: String?               // File path or reference to original data

    /// Session count for display
    var sessionCount: Int { sessions.count }

    /// Total sets across all sessions
    var totalSets: Int {
        sessions.flatMap { $0.exercises.flatMap { $0.sets } }.count
    }

    /// Date range of imported sessions
    var dateRange: (start: Date, end: Date)? {
        let dates = sessions.map { $0.date }.sorted()
        guard let first = dates.first, let last = dates.last else { return nil }
        return (first, last)
    }

    init(userId: String, exercises: [ImportedExerciseData], source: ImportSource) {
        self.id = UUID().uuidString
        self.userId = userId
        self.exercises = exercises
        self.sessions = []
        self.source = source
        self.importDate = Date()
    }

    init(userId: String, exercises: [ImportedExerciseData], sessions: [ImportedSession], source: ImportSource) {
        self.id = UUID().uuidString
        self.userId = userId
        self.exercises = exercises
        self.sessions = sessions
        self.source = source
        self.importDate = Date()
    }
}

// MARK: - Session-Based Models (v74.6)

/// Individual workout session from import (e.g., "Workout #1 on Nov 1")
struct ImportedSession: Codable, Identifiable {
    let id: String
    let sessionNumber: Int          // Original workout number from CSV
    let date: Date                  // When workout was performed
    var exercises: [ImportedSessionExercise]

    init(sessionNumber: Int, date: Date, exercises: [ImportedSessionExercise] = []) {
        self.id = UUID().uuidString
        self.sessionNumber = sessionNumber
        self.date = date
        self.exercises = exercises
    }
}

/// Exercise within a session with set-by-set data
struct ImportedSessionExercise: Codable, Identifiable {
    let id: String
    var exerciseName: String
    var matchedExerciseId: String?
    var sets: [ImportedSet]
    var estimated1RM: Double?       // Best 1RM from these sets

    init(exerciseName: String, matchedExerciseId: String? = nil, sets: [ImportedSet] = []) {
        self.id = UUID().uuidString
        self.exerciseName = exerciseName
        self.matchedExerciseId = matchedExerciseId
        self.sets = sets
        self.estimated1RM = nil
    }

    /// Summary string for display (e.g., "3×8 @ 135 lbs")
    var summaryString: String {
        guard !sets.isEmpty else { return "No sets" }

        // Group sets by reps and weight for compact display
        let firstSet = sets[0]
        let allSame = sets.allSatisfy { $0.reps == firstSet.reps && $0.weight == firstSet.weight }

        if allSame {
            return "\(sets.count)×\(firstSet.reps) @ \(Int(firstSet.weight)) lbs"
        } else {
            // Variable sets - show range
            let weights = sets.map { $0.weight }
            let minW = Int(weights.min() ?? 0)
            let maxW = Int(weights.max() ?? 0)
            return "\(sets.count) sets @ \(minW)-\(maxW) lbs"
        }
    }
}

/// Individual set data from import
struct ImportedSet: Codable {
    let reps: Int
    let weight: Double
    let equipment: String?

    init(reps: Int, weight: Double, equipment: String? = nil) {
        self.reps = reps
        self.weight = weight
        self.equipment = equipment
    }
}

/// Individual exercise data from import
struct ImportedExerciseData: Codable, Identifiable {
    let id: String
    var exerciseName: String        // Raw name from source (e.g., "Bench Press")
    var matchedExerciseId: String?  // Matched to our database (e.g., "barbell_bench_press")
    var matchConfidence: Double?    // 0-1 confidence score for auto-match

    // Performance data - at least one should be set
    var oneRepMax: Double?          // Calculated or stated 1RM in lbs
    var recentWeight: Double?       // Most recent working weight in lbs
    var recentReps: Int?            // Most recent rep count
    var datePerformed: Date?        // When they performed this

    // Calculated 1RM from weight/reps using Brzycki formula
    var estimated1RM: Double? {
        guard let weight = recentWeight, let reps = recentReps, reps > 0, reps <= 12 else {
            return oneRepMax
        }
        // Brzycki formula: 1RM = weight * (36 / (37 - reps))
        return weight * (36.0 / (37.0 - Double(reps)))
    }

    // Best available 1RM value
    var effectiveMax: Double? {
        oneRepMax ?? estimated1RM
    }

    init(exerciseName: String) {
        self.id = UUID().uuidString
        self.exerciseName = exerciseName
    }

    init(
        exerciseName: String,
        matchedExerciseId: String? = nil,
        matchConfidence: Double? = nil,
        oneRepMax: Double? = nil,
        recentWeight: Double? = nil,
        recentReps: Int? = nil,
        datePerformed: Date? = nil
    ) {
        self.id = UUID().uuidString
        self.exerciseName = exerciseName
        self.matchedExerciseId = matchedExerciseId
        self.matchConfidence = matchConfidence
        self.oneRepMax = oneRepMax
        self.recentWeight = recentWeight
        self.recentReps = recentReps
        self.datePerformed = datePerformed
    }
}

/// Result of exercise name matching
struct ExerciseMatchResult {
    let exerciseId: String
    let exerciseName: String
    let confidence: Double  // 0-1

    var isHighConfidence: Bool { confidence >= 0.8 }
    var isMediumConfidence: Bool { confidence >= 0.5 && confidence < 0.8 }
    var isLowConfidence: Bool { confidence < 0.5 }
}
