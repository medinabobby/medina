//
// CSVImportService.swift
// Medina
//
// v74.4: CSV file import service for workout history
// v74.6: Added ImportedWorkoutData conversion with full session data
// v74.7: Updated to use OneRMCalculationService (Epley + quality scoring)
// Parses CSV workout logs and extracts 1RM estimates
// Created: December 2, 2025
//

import Foundation

// MARK: - Parsed Data Models

struct ParsedWorkout {
    let workoutNumber: Int
    let date: Date
    var exercises: [ParsedExercise]
}

struct ParsedExercise {
    let name: String
    var sets: [ParsedSet]
    var estimated1RM: Double?
    var matchedExerciseId: String?
}

struct ParsedSet {
    let reps: Int
    let weight: Double
    let equipment: String?
}

// MARK: - Import Result

struct CSVImportResult {
    let workouts: [ParsedWorkout]
    let uniqueExercises: [String: Double]  // exerciseName → best1RM
    let totalSets: Int
    let unmatchedExercises: [String]
}

// MARK: - CSV Import Service

struct CSVImportService {

    // MARK: - Main Parse Function

    /// Parse CSV data and return structured workout data
    static func parseCSV(data: Data) throws -> CSVImportResult {
        guard let csvString = String(data: data, encoding: .utf8) else {
            throw CSVImportError.invalidEncoding
        }

        let lines = csvString.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard lines.count > 1 else {
            throw CSVImportError.emptyFile
        }

        // Skip header row
        let dataLines = Array(lines.dropFirst())

        var workouts: [ParsedWorkout] = []
        var currentWorkout: ParsedWorkout?

        for line in dataLines {
            let columns = parseCSVLine(line)
            guard columns.count >= 5 else { continue }

            let workoutNumStr = columns[0].trimmingCharacters(in: .whitespaces)
            let dateStr = columns[1].trimmingCharacters(in: .whitespaces)
            let exerciseName = columns[2].trimmingCharacters(in: .whitespaces)
            let setsRepsStr = columns[3].trimmingCharacters(in: .whitespaces)
            let weightStr = columns[4].trimmingCharacters(in: .whitespaces)

            // Check if this is a new workout (has workout number)
            if !workoutNumStr.isEmpty, let workoutNum = Int(workoutNumStr) {
                // Save previous workout
                if let workout = currentWorkout {
                    workouts.append(workout)
                }

                // Parse date
                let date = parseDate(dateStr) ?? Date()

                currentWorkout = ParsedWorkout(
                    workoutNumber: workoutNum,
                    date: date,
                    exercises: []
                )
            }

            // Parse exercise
            guard !exerciseName.isEmpty else { continue }

            let sets = parseSetsAndWeight(setsRepsStr: setsRepsStr, weightStr: weightStr)
            let estimated1RM = calculateBest1RM(from: sets)

            let exercise = ParsedExercise(
                name: exerciseName,
                sets: sets,
                estimated1RM: estimated1RM,
                matchedExerciseId: matchExerciseToLibrary(exerciseName)
            )

            currentWorkout?.exercises.append(exercise)
        }

        // Don't forget the last workout
        if let workout = currentWorkout {
            workouts.append(workout)
        }

        // Aggregate results
        var uniqueExercises: [String: Double] = [:]
        var totalSets = 0
        var unmatchedExercises: [String] = []

        for workout in workouts {
            for exercise in workout.exercises {
                totalSets += exercise.sets.count

                // Track best 1RM per exercise
                if let rm = exercise.estimated1RM {
                    let existing = uniqueExercises[exercise.name] ?? 0
                    uniqueExercises[exercise.name] = max(existing, rm)
                }

                // Track unmatched exercises
                if exercise.matchedExerciseId == nil && !unmatchedExercises.contains(exercise.name) {
                    unmatchedExercises.append(exercise.name)
                }
            }
        }

        return CSVImportResult(
            workouts: workouts,
            uniqueExercises: uniqueExercises,
            totalSets: totalSets,
            unmatchedExercises: unmatchedExercises
        )
    }

    // MARK: - CSV Line Parser

    /// Parse a CSV line handling quoted fields with commas
    private static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)

        return result
    }

    // MARK: - Date Parser

    /// Parse various date formats
    private static func parseDate(_ dateStr: String) -> Date? {
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.dateFormat = "MMM d, yyyy"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "MM/dd/yyyy"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                return f
            }()
        ]

        for formatter in formatters {
            if let date = formatter.date(from: dateStr) {
                return date
            }
        }
        return nil
    }

    // MARK: - Sets & Reps Parser

    /// Parse "3x8-10" or "2x12, 1x10" format
    private static func parseSetsAndWeight(setsRepsStr: String, weightStr: String) -> [ParsedSet] {
        var result: [ParsedSet] = []

        // Parse weight string to get individual weights
        let weights = parseWeights(weightStr)

        // Parse sets/reps patterns like "3x8-10" or "2x12, 1x10"
        let setGroups = setsRepsStr.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var weightIndex = 0

        for group in setGroups {
            // Parse "3x8-10" or "3x8"
            let parts = group.lowercased().components(separatedBy: "x")
            guard parts.count == 2 else { continue }

            let setCount = Int(parts[0].trimmingCharacters(in: .whitespaces)) ?? 1

            // Parse rep range (e.g., "8-10" → use 10)
            let repPart = parts[1].trimmingCharacters(in: .whitespaces)
            let reps: Int
            if repPart.contains("-") {
                let repRange = repPart.components(separatedBy: "-")
                reps = Int(repRange.last ?? "0") ?? 0  // Use higher end
            } else {
                reps = Int(repPart) ?? 0
            }

            // Create sets with corresponding weights
            for _ in 0..<setCount {
                let weight = weightIndex < weights.count ? weights[weightIndex] : (weights.last ?? 0)
                result.append(ParsedSet(reps: reps, weight: weight, equipment: nil))
                weightIndex += 1
            }
        }

        return result
    }

    // MARK: - Weight Parser

    /// Parse "135 lb barbell" or "45, 50, 55 lb dumbbells"
    private static func parseWeights(_ weightStr: String) -> [Double] {
        var result: [Double] = []

        // Remove equipment descriptors
        var cleanStr = weightStr.lowercased()
        let equipmentWords = ["lb", "lbs", "barbell", "dumbbell", "dumbbells", "kettlebell", "kettlebells", "cable", "machine"]
        for word in equipmentWords {
            cleanStr = cleanStr.replacingOccurrences(of: word, with: "")
        }

        // Handle "2x20" pattern (bilateral kettlebells)
        if cleanStr.contains("x") {
            let parts = cleanStr.components(separatedBy: "x")
            if parts.count == 2,
               let _ = Int(parts[0].trimmingCharacters(in: .whitespaces)),
               let weight = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
                // For bilateral exercises, just use the per-hand weight
                result.append(weight)
                return result
            }
        }

        // Parse comma-separated weights
        let weightParts = cleanStr.components(separatedBy: ",")
        for part in weightParts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if let weight = Double(trimmed) {
                result.append(weight)
            }
        }

        return result
    }

    // MARK: - 1RM Calculator

    /// Calculate best 1RM using quality-weighted Epley formula
    /// Quality factors: rep accuracy (3-5 best) + freshness (earlier sets better)
    static func calculateBest1RM(from sets: [ParsedSet]) -> Double? {
        return OneRMCalculationService.calculateFromParsedSets(sets)
    }

    // MARK: - Exercise Matching

    /// Attempt to match exercise name to library
    private static func matchExerciseToLibrary(_ name: String) -> String? {
        let normalizedName = name.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)

        // Check exact matches first
        for (id, exercise) in LocalDataStore.shared.exercises {
            let exerciseName = exercise.name.lowercased()
            if exerciseName == normalizedName {
                return id
            }
        }

        // Check partial matches
        for (id, exercise) in LocalDataStore.shared.exercises {
            let exerciseName = exercise.name.lowercased()

            // "Squats" → "squat", "Deadlifts" → "deadlift"
            let singularName = normalizedName.hasSuffix("s")
                ? String(normalizedName.dropLast())
                : normalizedName

            if exerciseName.contains(singularName) || singularName.contains(exerciseName) {
                return id
            }
        }

        return nil
    }

    // MARK: - Create ExerciseTargets

    /// Convert import result to ExerciseTarget records
    static func createExerciseTargets(
        from result: CSVImportResult,
        userId: String
    ) -> [ExerciseTarget] {
        var targets: [ExerciseTarget] = []

        // Get all exercises with matched IDs and valid 1RMs
        var exerciseMap: [String: (name: String, rm: Double)] = [:]

        for workout in result.workouts {
            for exercise in workout.exercises {
                guard let exerciseId = exercise.matchedExerciseId,
                      let rm = exercise.estimated1RM else { continue }

                // Keep the best 1RM per exercise
                if let existing = exerciseMap[exerciseId] {
                    if rm > existing.rm {
                        exerciseMap[exerciseId] = (exercise.name, rm)
                    }
                } else {
                    exerciseMap[exerciseId] = (exercise.name, rm)
                }
            }
        }

        // Create ExerciseTarget for each
        for (exerciseId, data) in exerciseMap {
            let target = ExerciseTarget(
                id: "\(userId)-\(exerciseId)",
                exerciseId: exerciseId,
                memberId: userId,
                targetType: .max,
                currentTarget: data.rm,
                lastCalibrated: Date(),
                targetHistory: [
                    ExerciseTarget.TargetEntry(
                        date: Date(),
                        target: data.rm,
                        calibrationSource: "CSV Import"
                    )
                ]
            )
            targets.append(target)
        }

        return targets
    }

    // MARK: - Convert to ImportedWorkoutData (v74.6)

    /// Convert CSV parse result to ImportedWorkoutData with full session history
    static func toImportedWorkoutData(from result: CSVImportResult, userId: String) -> ImportedWorkoutData {
        // Convert workouts to ImportedSessions
        let sessions = result.workouts.map { workout -> ImportedSession in
            let exercises = workout.exercises.map { exercise -> ImportedSessionExercise in
                let sets = exercise.sets.map { ImportedSet(reps: $0.reps, weight: $0.weight, equipment: $0.equipment) }
                var sessionExercise = ImportedSessionExercise(
                    exerciseName: exercise.name,
                    matchedExerciseId: exercise.matchedExerciseId,
                    sets: sets
                )
                sessionExercise.estimated1RM = exercise.estimated1RM
                return sessionExercise
            }
            return ImportedSession(sessionNumber: workout.workoutNumber, date: workout.date, exercises: exercises)
        }

        // Create aggregated exercise data
        var exerciseAggregates: [String: ImportedExerciseData] = [:]

        for workout in result.workouts {
            for exercise in workout.exercises {
                if var existing = exerciseAggregates[exercise.name] {
                    // Update with better 1RM if found
                    if let newRM = exercise.estimated1RM, let existingRM = existing.oneRepMax {
                        if newRM > existingRM {
                            existing.oneRepMax = newRM
                            existing.datePerformed = workout.date
                        }
                    } else if let newRM = exercise.estimated1RM {
                        existing.oneRepMax = newRM
                        existing.datePerformed = workout.date
                    }
                    exerciseAggregates[exercise.name] = existing
                } else {
                    exerciseAggregates[exercise.name] = ImportedExerciseData(
                        exerciseName: exercise.name,
                        matchedExerciseId: exercise.matchedExerciseId,
                        matchConfidence: exercise.matchedExerciseId != nil ? 1.0 : nil,
                        oneRepMax: exercise.estimated1RM,
                        recentWeight: exercise.sets.last?.weight,
                        recentReps: exercise.sets.last?.reps,
                        datePerformed: workout.date
                    )
                }
            }
        }

        let exercises = Array(exerciseAggregates.values)

        return ImportedWorkoutData(
            userId: userId,
            exercises: exercises,
            sessions: sessions,
            source: .csv
        )
    }
}

// MARK: - Errors

enum CSVImportError: LocalizedError {
    case invalidEncoding
    case emptyFile
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Unable to read file encoding. Please ensure the file is UTF-8."
        case .emptyFile:
            return "The file appears to be empty."
        case .invalidFormat:
            return "The file format doesn't match expected CSV structure."
        }
    }
}
