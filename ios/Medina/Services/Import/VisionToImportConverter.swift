//
// VisionToImportConverter.swift
// Medina
//
// v79.5: Convert Vision extraction results to ImportedWorkoutData
// Created: December 3, 2025
//
// Bridges VisionExtractionResult → ImportedWorkoutData for existing pipeline
//

import Foundation

enum VisionToImportConverter {

    /// Convert vision extraction results to ImportedWorkoutData
    /// This allows photo imports to flow through the same pipeline as CSV imports
    static func convert(_ result: VisionExtractionResult, userId: String) -> ImportedWorkoutData {
        // 1. Convert extracted exercises to ImportedExerciseData (aggregated)
        var exercises: [ImportedExerciseData] = []
        var exercisesByName: [String: ImportedExerciseData] = [:]

        for extracted in result.exercises {
            let normalizedName = extracted.name.trimmingCharacters(in: .whitespaces)

            // Try to match to our exercise database
            let matchedId = ImportProcessingService.matchExerciseToLibrary(normalizedName)

            // Get best 1RM from sets
            let importedSets = extracted.sets.compactMap { set -> ImportedSet? in
                guard let weight = set.weight else { return nil }
                return ImportedSet(
                    reps: set.reps ?? 1,
                    weight: weight,
                    equipment: nil
                )
            }
            let best1RM = ImportProcessingService.calculateBest1RM(from: importedSets)

            // Get most recent weight/reps
            let recentSet = extracted.sets.last { $0.weight != nil }

            // Aggregate by exercise name (multiple instances = take best 1RM)
            if var existing = exercisesByName[normalizedName] {
                // Update with better 1RM if found
                if let new1RM = best1RM, (existing.oneRepMax ?? 0) < new1RM {
                    existing.oneRepMax = new1RM
                }
                // Update with more recent date if available
                if let newDate = extracted.date,
                   existing.datePerformed == nil || newDate > (existing.datePerformed ?? .distantPast) {
                    existing.datePerformed = newDate
                    existing.recentWeight = recentSet?.weight
                    existing.recentReps = recentSet?.reps
                }
                exercisesByName[normalizedName] = existing
            } else {
                // Create new entry
                var exerciseData = ImportedExerciseData(
                    exerciseName: normalizedName,
                    matchedExerciseId: matchedId,
                    matchConfidence: matchedId != nil ? 0.8 : nil,
                    oneRepMax: best1RM,
                    recentWeight: recentSet?.weight,
                    recentReps: recentSet?.reps,
                    datePerformed: extracted.date
                )
                exercisesByName[normalizedName] = exerciseData
            }
        }

        exercises = Array(exercisesByName.values)

        // 2. Convert to ImportedSessions (full history with dates)
        let sessions = createSessions(from: result)

        // 3. Create ImportedWorkoutData
        return ImportedWorkoutData(
            userId: userId,
            exercises: exercises,
            sessions: sessions,
            source: .screenshot  // Photo imports use screenshot source type
        )
    }

    // MARK: - Session Creation

    /// Create ImportedSession records from extraction result
    /// Groups by date if available, otherwise creates single session
    private static func createSessions(from result: VisionExtractionResult) -> [ImportedSession] {
        // Group exercises by date
        var exercisesByDate: [Date: [ExtractedExercise]] = [:]
        var exercisesWithoutDate: [ExtractedExercise] = []

        for exercise in result.exercises {
            if let date = exercise.date {
                let dateKey = Calendar.current.startOfDay(for: date)
                exercisesByDate[dateKey, default: []].append(exercise)
            } else {
                exercisesWithoutDate.append(exercise)
            }
        }

        var sessions: [ImportedSession] = []
        var sessionNumber = 1

        // Create sessions for dated exercises
        for (date, exercises) in exercisesByDate.sorted(by: { $0.key < $1.key }) {
            let sessionExercises = exercises.map { createSessionExercise(from: $0) }
            let session = ImportedSession(
                sessionNumber: sessionNumber,
                date: date,
                exercises: sessionExercises
            )
            sessions.append(session)
            sessionNumber += 1
        }

        // Create single session for undated exercises (use today's date)
        if !exercisesWithoutDate.isEmpty {
            let sessionExercises = exercisesWithoutDate.map { createSessionExercise(from: $0) }
            let session = ImportedSession(
                sessionNumber: sessionNumber,
                date: Date(),
                exercises: sessionExercises
            )
            sessions.append(session)
        }

        // If no sessions were created but we have global dates from result, use first date
        if sessions.isEmpty && !(result.dates?.isEmpty ?? true), let firstDate = result.dates?.first {
            // Create single session with all exercises at that date
            let sessionExercises = result.exercises.map { createSessionExercise(from: $0) }
            let session = ImportedSession(
                sessionNumber: 1,
                date: firstDate,
                exercises: sessionExercises
            )
            sessions.append(session)
        }

        return sessions
    }

    /// Convert ExtractedExercise to ImportedSessionExercise
    private static func createSessionExercise(from extracted: ExtractedExercise) -> ImportedSessionExercise {
        let normalizedName = extracted.name.trimmingCharacters(in: .whitespaces)
        let matchedId = ImportProcessingService.matchExerciseToLibrary(normalizedName)

        // Convert sets
        let sets = extracted.sets.compactMap { set -> ImportedSet? in
            guard let weight = set.weight else { return nil }
            return ImportedSet(
                reps: set.reps ?? 1,
                weight: weight,
                equipment: nil
            )
        }

        // Calculate 1RM for this exercise instance
        let estimated1RM = ImportProcessingService.calculateBest1RM(from: sets)

        var sessionExercise = ImportedSessionExercise(
            exerciseName: normalizedName,
            matchedExerciseId: matchedId,
            sets: sets
        )
        sessionExercise.estimated1RM = estimated1RM

        return sessionExercise
    }
}
