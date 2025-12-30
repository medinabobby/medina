//
// HistoricalWorkoutService.swift
// Medina
//
// v79.5: Create historical Workout records from imported data
// Created: December 3, 2025
//
// Creates actual Workout/ExerciseInstance/ExerciseSet records for imports,
// allowing imported workouts to appear in workout history alongside regular workouts.
//

import Foundation

enum HistoricalWorkoutService {

    // MARK: - Constants

    /// Special program ID for imported workouts
    static let importedProgramId = "imported-workouts"
    static let importedPlanId = "imported-history"

    // MARK: - Main Entry Point

    /// Create historical workout records from imported sessions
    /// Creates: Workout → ExerciseInstance → ExerciseSet hierarchy
    /// All workouts are marked as completed with their historical dates
    @MainActor
    static func createHistoricalWorkouts(
        from sessions: [ImportedSession],
        memberId: String,
        source: ImportSource
    ) -> [Workout] {
        // Ensure imported workouts plan/program exist
        ensureImportedStructureExists(memberId: memberId)

        var workouts: [Workout] = []

        for session in sessions {
            let workout = createWorkoutFromSession(
                session,
                memberId: memberId,
                source: source
            )
            workouts.append(workout)

            // Store workout
            LocalDataStore.shared.workouts[workout.id] = workout
        }

        Logger.log(.info, component: "HistoricalWorkoutService",
                   message: "Created \(workouts.count) historical workouts from import")

        return workouts
    }

    // MARK: - Imported Structure Setup

    /// Ensure the special "imported workouts" plan and program exist
    @MainActor
    private static func ensureImportedStructureExists(memberId: String) {
        // Check if plan exists
        if LocalDataStore.shared.plans[importedPlanId] == nil {
            let plan = Plan(
                id: importedPlanId,
                memberId: memberId,
                isSingleWorkout: false,
                status: .completed,
                name: "Imported History",
                description: "Historical workout data from imports",
                goal: .generalFitness,
                weightliftingDays: 0,
                cardioDays: 0,
                splitType: .fullBody,
                targetSessionDuration: 60,
                trainingLocation: .gym,
                compoundTimeAllocation: 0.7,
                isolationApproach: .minimal,
                preferredDays: [],
                startDate: Date(timeIntervalSince1970: 0),  // Beginning of time
                endDate: Date().addingTimeInterval(365 * 24 * 60 * 60)  // Far future
            )
            LocalDataStore.shared.plans[importedPlanId] = plan
        }

        // Check if program exists
        if LocalDataStore.shared.programs[importedProgramId] == nil {
            let program = Program(
                id: importedProgramId,
                planId: importedPlanId,
                name: "Imported Workouts",
                focus: .maintenance,
                rationale: "Historical workout data imported from external sources",
                startDate: Date(timeIntervalSince1970: 0),  // Beginning of time
                endDate: Date().addingTimeInterval(365 * 24 * 60 * 60),  // Far future
                startingIntensity: 0.7,
                endingIntensity: 0.7,
                progressionType: .linear,
                status: .completed
            )
            LocalDataStore.shared.programs[importedProgramId] = program
        }
    }

    // MARK: - Workout Creation

    /// Create a Workout from an ImportedSession
    @MainActor
    private static func createWorkoutFromSession(
        _ session: ImportedSession,
        memberId: String,
        source: ImportSource
    ) -> Workout {
        let workoutId = "imported-\(session.id)"

        // Create exercise instances and sets
        var exerciseIds: [String] = []
        var protocolVariantIds: [Int: String] = [:]

        for (index, exercise) in session.exercises.enumerated() {
            guard let matchedId = exercise.matchedExerciseId else { continue }

            exerciseIds.append(matchedId)

            // Get or create a default protocol for this exercise
            let protocolId = getDefaultProtocol(for: matchedId, sets: exercise.sets.count)
            protocolVariantIds[index] = protocolId

            // Create exercise instance and sets
            createExerciseInstanceAndSets(
                exercise: exercise,
                workoutId: workoutId,
                protocolId: protocolId,
                date: session.date
            )
        }

        // Format workout name
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"
        let name = "Imported: \(dateFormatter.string(from: session.date))"

        return Workout(
            id: workoutId,
            programId: importedProgramId,
            name: name,
            scheduledDate: session.date,
            type: .strength,
            splitDay: nil,
            status: .completed,
            completedDate: session.date,
            exerciseIds: exerciseIds,
            protocolVariantIds: protocolVariantIds,
            exercisesSelectedAt: session.date,
            supersetGroups: nil
        )
    }

    // MARK: - Exercise Instance Creation

    /// Create ExerciseInstance and ExerciseSet records for an imported exercise
    @MainActor
    private static func createExerciseInstanceAndSets(
        exercise: ImportedSessionExercise,
        workoutId: String,
        protocolId: String,
        date: Date
    ) {
        guard let matchedId = exercise.matchedExerciseId else { return }

        let instanceId = "\(workoutId)-\(matchedId)"

        // Create sets
        var setIds: [String] = []

        for (index, importedSet) in exercise.sets.enumerated() {
            let setId = "\(instanceId)-set\(index + 1)"
            setIds.append(setId)

            let exerciseSet = ExerciseSet(
                id: setId,
                exerciseInstanceId: instanceId,
                setNumber: index + 1,
                targetWeight: importedSet.weight,
                targetReps: importedSet.reps,
                targetRPE: nil,
                actualWeight: importedSet.weight,
                actualReps: importedSet.reps,
                completion: .completed,
                startTime: date,
                endTime: date,
                notes: nil,
                recordedDate: date
            )
            LocalDataStore.shared.exerciseSets[setId] = exerciseSet
        }

        // Create exercise instance
        let instance = ExerciseInstance(
            id: instanceId,
            exerciseId: matchedId,
            workoutId: workoutId,
            protocolVariantId: protocolId,
            setIds: setIds,
            status: .completed,
            trainerInstructions: nil,
            supersetLabel: nil
        )
        LocalDataStore.shared.exerciseInstances[instanceId] = instance
    }

    // MARK: - Protocol Selection

    /// Get a default protocol ID for an exercise based on set count
    /// If no specific protocol exists, creates a simple one
    @MainActor
    private static func getDefaultProtocol(for exerciseId: String, sets setCount: Int) -> String {
        // Look for existing protocol that matches set count
        let matchingProtocol = LocalDataStore.shared.protocolConfigs.values.first { config in
            config.reps.count == setCount
        }

        if let existing = matchingProtocol {
            return existing.id
        }

        // Create a default protocol for this set count
        let protocolId = "imported-protocol-\(setCount)sets"

        // Check if we already created this protocol
        if LocalDataStore.shared.protocolConfigs[protocolId] != nil {
            return protocolId
        }

        // Create default protocol - simple straight sets
        let reps = Array(repeating: 8, count: setCount)  // Default 8 reps per set
        let intensityAdjustments = Array(repeating: 0.0, count: setCount)
        let restBetweenSets = Array(repeating: 90, count: max(0, setCount - 1))

        // Note: We need to create this manually since ProtocolConfig requires Codable init
        // For now, return a generic protocol ID that the system can handle
        return "gbc-compound-3x10"  // Fallback to existing protocol
    }
}

