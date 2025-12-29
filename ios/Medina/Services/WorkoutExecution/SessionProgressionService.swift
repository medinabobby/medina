//
// SessionProgressionService.swift
// Medina
//
// v56.0 - Extracted from WorkoutSessionCoordinator (Phase 1 refactor)
// Created: November 2025
//
// Purpose: Pure session progression business logic (no UI, no voice)
// Handles: Set/exercise advancement, skip operations, reset operations
//
// ⚠️ Side Effects: Mutates TestDataManager.shared and DeltaStore.shared directly
// This matches current architecture pattern (not pure functions)
//

import Foundation

/// Service responsible for all workout session progression logic
/// Extracted from WorkoutSessionCoordinator to improve testability and maintainability
@MainActor
class SessionProgressionService {

    // MARK: - Session Progression

    /// Advance session to next set/exercise with rest timer logic
    ///
    /// ⚠️ Side Effects:
    /// - Mutates `DeltaStore.shared` (saves instance deltas for completed exercises)
    ///
    /// - Parameters:
    ///   - session: Current session (immutable input)
    ///   - workout: Workout being executed
    ///   - currentInstance: Instance for current exercise
    ///   - setJustCompleted: Index of set just completed (BEFORE any mutation)
    ///   - didCompleteExercise: Whether this was the last set of the exercise
    ///   - wasSkipped: Whether this exercise was skipped (vs completed normally)
    /// - Returns: Tuple with (updated session, rest duration if rest needed, voice message)
    func advanceSession(
        session: Session,
        workout: Workout,
        currentInstance: ExerciseInstance,
        setJustCompleted: Int,
        didCompleteExercise: Bool,
        wasSkipped: Bool = false
    ) -> (session: Session, restDuration: TimeInterval?, setJustCompletedIndex: Int) {
        var updatedSession = session

        // Mark current exercise instance as complete or skipped if needed
        if didCompleteExercise {
            // v57.0: Check if ANY set was actually completed (not all skipped)
            let allSets = TestDataManager.shared.exerciseSets.values.filter {
                $0.exerciseInstanceId == currentInstance.id
            }
            let hasCompletedSet = allSets.contains { $0.completion == .completed }

            // If all sets were skipped, mark instance as skipped (orange)
            // If at least one set was completed, mark as completed (green)
            let instanceDelta = DeltaStore.InstanceDelta(
                instanceId: currentInstance.id,
                completion: hasCompletedSet ? .completed : .skipped
            )
            DeltaStore.shared.saveInstanceDelta(instanceDelta)
        }

        // Determine rest timer and progression logic
        let inSuperset = workout.isInSuperset(position: updatedSession.currentExerciseIndex)
        var shouldStartRest = false
        var restDuration: TimeInterval = 0

        if inSuperset {
            // Superset progression
            if let group = workout.supersetGroup(for: updatedSession.currentExerciseIndex),
               let nextPos = group.nextPosition(after: updatedSession.currentExerciseIndex, wrapAround: true) {

                // v55.0 Phase 3: If we just completed an exercise (via skip), exit superset immediately
                if didCompleteExercise {
                    // Mark ALL exercises in superset as skipped if they have incomplete sets
                    for pos in group.exercisePositions {
                        let exerciseId = workout.exerciseIds[pos]
                        if let instance = TestDataManager.shared.exerciseInstances.values.first(where: {
                            $0.workoutId == workout.id && $0.exerciseId == exerciseId
                        }) {
                            // Check if this exercise has any incomplete sets
                            let hasIncompleteSets = instance.setIds.contains { setId in
                                guard let set = TestDataManager.shared.exerciseSets[setId] else { return false }
                                return set.completion != .completed && set.completion != .skipped
                            }

                            // If exercise has incomplete sets, mark instance as skipped
                            if hasIncompleteSets {
                                let instanceDelta = DeltaStore.InstanceDelta(
                                    instanceId: instance.id,
                                    completion: .skipped
                                )
                                DeltaStore.shared.saveInstanceDelta(instanceDelta)
                            }
                        }
                    }

                    // Exit superset group (don't rotate to next exercise)
                    shouldStartRest = false
                    if let lastPos = group.exercisePositions.max() {
                        updatedSession.currentExerciseIndex = lastPos + 1
                        updatedSession.currentSetIndex = 0
                    }
                } else if nextPos == group.exercisePositions.first {
                    // Completed a full superset cycle - check ALL exercises for pending sets
                    let nextSetIndex = updatedSession.currentSetIndex + 1

                    if hasAnyPendingSets(in: group, at: nextSetIndex, workout: workout) {
                        // More sets to do - find first exercise with pending set
                        shouldStartRest = true
                        restDuration = 30
                        updatedSession.currentSetIndex = nextSetIndex

                        if let firstPendingPos = findFirstPendingExercise(in: group, at: nextSetIndex, workout: workout) {
                            updatedSession.currentExerciseIndex = firstPendingPos
                        } else {
                            // Fallback (shouldn't happen if hasAnyPendingSets is true)
                            updatedSession.currentExerciseIndex = nextPos
                        }
                    } else {
                        // All exercises complete - exit superset
                        shouldStartRest = false
                        if let lastPos = group.exercisePositions.max() {
                            updatedSession.currentExerciseIndex = lastPos + 1
                            updatedSession.currentSetIndex = 0
                        }
                    }
                } else {
                    // Rotate to next exercise, skipping over any with completed/skipped sets
                    if let pendingPos = findNextPendingExercise(
                        in: group,
                        after: updatedSession.currentExerciseIndex,
                        at: updatedSession.currentSetIndex,
                        workout: workout
                    ) {
                        // Found exercise with pending set at current index
                        shouldStartRest = true
                        restDuration = 30
                        updatedSession.currentExerciseIndex = pendingPos
                        // Keep currentSetIndex the same
                    } else {
                        // All exercises at current index are done - advance to next set
                        let nextSetIndex = updatedSession.currentSetIndex + 1

                        if hasAnyPendingSets(in: group, at: nextSetIndex, workout: workout) {
                            shouldStartRest = true
                            restDuration = 30
                            updatedSession.currentSetIndex = nextSetIndex

                            if let firstPendingPos = findFirstPendingExercise(in: group, at: nextSetIndex, workout: workout) {
                                updatedSession.currentExerciseIndex = firstPendingPos
                            }
                        } else {
                            // Exit superset - no more pending sets in any exercise
                            shouldStartRest = false
                            if let lastPos = group.exercisePositions.max() {
                                updatedSession.currentExerciseIndex = lastPos + 1
                                updatedSession.currentSetIndex = 0
                            }
                        }
                    }
                }
            }
        } else {
            // Standalone exercise progression
            // v57.5: Check didCompleteExercise first (handles skip exercise correctly)
            if didCompleteExercise {
                // Exercise complete (via skip or last set) - move to next exercise
                shouldStartRest = false
                updatedSession.currentExerciseIndex += 1
                updatedSession.currentSetIndex = 0
            } else if updatedSession.currentSetIndex < currentInstance.setIds.count - 1 {
                // More sets in current exercise
                shouldStartRest = true
                restDuration = 90
                updatedSession.currentSetIndex += 1
            } else {
                // Last set just completed - move to next exercise
                shouldStartRest = false
                updatedSession.currentExerciseIndex += 1
                updatedSession.currentSetIndex = 0
            }
        }

        // Return session with optional rest duration
        let finalRestDuration = shouldStartRest ? restDuration : nil
        return (updatedSession, finalRestDuration, setJustCompleted)
    }

    // MARK: - Skip Operations

    /// Skip the current exercise (all remaining sets) and advance to the next exercise
    ///
    /// ⚠️ Side Effects:
    /// - Mutates `TestDataManager.shared.exerciseSets` (marks sets as skipped)
    /// - Mutates `DeltaStore.shared` (saves set deltas)
    ///
    /// - Parameters:
    ///   - session: Current active session
    ///   - workout: Workout being executed
    /// - Returns: Tuple with (updated session, exercise name for voice, rest duration if needed, setJustCompleted index)
    func skipExercise(
        session: Session,
        workout: Workout
    ) -> (session: Session, exerciseName: String, restDuration: TimeInterval?, setJustCompletedIndex: Int)? {
        // Get current instance
        guard let instance = getCurrentInstance(session: session, workout: workout) else {
            Logger.log(.warning, component: "SessionProgressionService", message: "No current exercise to skip")
            return nil
        }

        // Get exercise name for voice announcement
        let exercise = TestDataManager.shared.exercises[instance.exerciseId]
        let exerciseName = exercise?.name ?? "exercise"

        // Skip ALL remaining sets of current exercise
        let currentSetIndex = session.currentSetIndex
        let remainingSetIds = Array(instance.setIds.dropFirst(currentSetIndex))

        for setId in remainingSetIds {
            // Save skip delta for each remaining set
            let setDelta = DeltaStore.SetDelta(
                setId: setId,
                actualWeight: nil,
                actualReps: nil,
                completion: .skipped
            )
            DeltaStore.shared.saveSetDelta(setDelta)

            // Update in-memory set completion status
            if var set = TestDataManager.shared.exerciseSets[setId] {
                set.completion = .skipped
                TestDataManager.shared.exerciseSets[setId] = set
            }
        }

        Logger.log(.info, component: "SessionProgressionService",
                   message: "Skipped exercise: \(instance.exerciseId) (\(remainingSetIds.count) sets)")

        // v57.5: When skipping an exercise, that exercise IS complete (regardless of superset state)
        // The advanceSession() logic will handle whether to exit the superset or continue rotation
        let didCompleteExercise = true

        // Advance to next set/exercise
        let (updatedSession, restDuration, setJustCompleted) = advanceSession(
            session: session,
            workout: workout,
            currentInstance: instance,
            setJustCompleted: session.currentSetIndex,
            didCompleteExercise: didCompleteExercise,
            wasSkipped: true
        )

        return (updatedSession, exerciseName, restDuration, setJustCompleted)
    }

    /// Unskip a previously skipped set
    ///
    /// ⚠️ Side Effects:
    /// - Mutates `TestDataManager.shared.exerciseSets` (clears set data)
    /// - Mutates `DeltaStore.shared` (removes skip delta)
    ///
    /// - Parameter setId: ID of set to unskip
    /// - Returns: true if successful, false if set not found
    func unskipSet(setId: String) -> Bool {
        guard let set = TestDataManager.shared.exerciseSets[setId] else {
            Logger.log(.warning, component: "SessionProgressionService", message: "Set not found for unskip: \(setId)")
            return false
        }

        // Remove skip delta (restores to pending state)
        let setDelta = DeltaStore.SetDelta(
            setId: setId,
            actualWeight: nil,
            actualReps: nil,
            completion: nil  // nil means pending (no delta applied)
        )
        DeltaStore.shared.saveSetDelta(setDelta)

        // Update in-memory set completion status
        var updatedSet = set
        updatedSet.completion = nil  // nil means pending
        updatedSet.actualWeight = nil
        updatedSet.actualReps = nil
        TestDataManager.shared.exerciseSets[setId] = updatedSet

        Logger.log(.info, component: "SessionProgressionService",
                   message: "Unskipped set: \(setId)")

        return true
    }

    // MARK: - Reset Operations

    /// Reset workout - clear all data, delete session
    ///
    /// ⚠️ Side Effects:
    /// - Mutates `TestDataManager.shared.sessions` (deletes session)
    /// - Mutates `TestDataManager.shared.exerciseInstances` (resets status)
    /// - Mutates `TestDataManager.shared.exerciseSets` (clears set data)
    /// - Mutates `TestDataManager.shared.workouts` (resets status)
    /// - Mutates `DeltaStore.shared` (clears all deltas for workout)
    ///
    /// - Parameters:
    ///   - workoutId: ID of workout to reset
    ///   - activeSessionId: ID of currently active session (if any)
    /// - Returns: Session ID that was deleted (if any)
    func resetWorkout(workoutId: String, activeSessionId: String?) -> String? {
        // 1. Find and DELETE active session
        var deletedSessionId: String?
        if let session = TestDataManager.shared.sessions.values.first(where: {
            $0.workoutId == workoutId && $0.status == .active
        }) {
            TestDataManager.shared.sessions.removeValue(forKey: session.id)
            deletedSessionId = session.id
        }

        // 2. Get instances using workoutId field
        let instances = TestDataManager.shared.exerciseInstances.values.filter {
            $0.workoutId == workoutId
        }

        let instanceIds = Set(instances.map { $0.id })
        let setIds = Set(instances.flatMap { $0.setIds })

        // 3. Clear deltas
        clearInstanceDeltas(for: instanceIds)
        clearSetDeltas(for: setIds)

        let workoutDelta = DeltaStore.WorkoutDelta(
            workoutId: workoutId,
            scheduledDate: nil,
            completion: nil
        )
        DeltaStore.shared.saveWorkoutDelta(workoutDelta)

        // 4. Clear in-memory state
        for instance in instances {
            var updated = instance
            updated.status = .scheduled
            TestDataManager.shared.exerciseInstances[instance.id] = updated

            for setId in instance.setIds {
                if var set = TestDataManager.shared.exerciseSets[setId] {
                    set.actualWeight = nil
                    set.actualReps = nil
                    set.completion = nil
                    set.startTime = nil
                    set.endTime = nil
                    set.notes = nil
                    set.recordedDate = nil
                    TestDataManager.shared.exerciseSets[setId] = set
                }
            }
        }

        if var workout = TestDataManager.shared.workouts[workoutId] {
            workout.status = .scheduled
            workout.completedDate = nil
            TestDataManager.shared.workouts[workoutId] = workout
        }

        return deletedSessionId
    }

    /// Reset exercise - clear data
    ///
    /// ⚠️ Side Effects:
    /// - Mutates `TestDataManager.shared.exerciseInstances` (resets status)
    /// - Mutates `TestDataManager.shared.exerciseSets` (clears set data)
    /// - Mutates `DeltaStore.shared` (clears deltas for exercise)
    ///
    /// - Parameter instanceId: ID of exercise instance to reset
    /// - Returns: true if successful, false if instance not found
    func resetExercise(instanceId: String) -> Bool {
        guard let instance = TestDataManager.shared.exerciseInstances[instanceId] else {
            return false
        }

        // Clear deltas
        clearInstanceDeltas(for: [instanceId])
        clearSetDeltas(for: Set(instance.setIds))

        // Clear in-memory state
        var updated = instance
        updated.status = .scheduled
        TestDataManager.shared.exerciseInstances[instanceId] = updated

        for setId in instance.setIds {
            if var set = TestDataManager.shared.exerciseSets[setId] {
                set.actualWeight = nil
                set.actualReps = nil
                set.completion = nil
                set.startTime = nil
                set.endTime = nil
                set.notes = nil
                set.recordedDate = nil
                TestDataManager.shared.exerciseSets[setId] = set
            }
        }

        return true
    }

    // MARK: - Query Helpers

    /// Get current exercise instance from session indices
    /// - Parameters:
    ///   - session: Session with current indices
    ///   - workout: Workout being executed
    /// - Returns: ExerciseInstance if indices are valid, nil otherwise
    func getCurrentInstance(session: Session, workout: Workout) -> ExerciseInstance? {
        guard session.currentExerciseIndex < workout.exerciseIds.count else {
            return nil
        }

        let exerciseId = workout.exerciseIds[session.currentExerciseIndex]

        return TestDataManager.shared.exerciseInstances.values.first {
            $0.workoutId == workout.id && $0.exerciseId == exerciseId
        }
    }

    /// Get current set from session indices
    /// - Parameters:
    ///   - session: Session with current indices
    ///   - workout: Workout being executed
    /// - Returns: Tuple of (set, instance) if indices are valid, nil otherwise
    func getCurrentSet(session: Session, workout: Workout) -> (set: ExerciseSet, instance: ExerciseInstance)? {
        guard let instance = getCurrentInstance(session: session, workout: workout),
              session.currentSetIndex < instance.setIds.count else {
            return nil
        }

        let setId = instance.setIds[session.currentSetIndex]
        guard let set = TestDataManager.shared.exerciseSets[setId] else {
            return nil
        }

        return (set, instance)
    }

    /// Get next set's target weight and reps for voice announcement
    /// - Parameters:
    ///   - session: Current session
    ///   - workout: Current workout
    /// - Returns: Tuple with (setNumber, weight, reps) or nil if no next set
    func getNextSetWithTargets(session: Session, workout: Workout) -> (setNumber: Int, weight: Double, reps: Int)? {
        // Check if we have more exercises
        guard session.currentExerciseIndex < workout.exerciseIds.count else {
            return nil
        }

        // Get current exercise ID
        let exerciseId = workout.exerciseIds[session.currentExerciseIndex]

        // Find the exercise instance for this workout
        guard let instance = TestDataManager.shared.exerciseInstances.values.first(where: {
            $0.workoutId == workout.id && $0.exerciseId == exerciseId
        }) else {
            return nil
        }

        // Check if we have more sets in current exercise
        guard session.currentSetIndex < instance.setIds.count else {
            return nil
        }

        // Get the next set
        let nextSetId = instance.setIds[session.currentSetIndex]
        guard let nextSet = TestDataManager.shared.exerciseSets[nextSetId] else {
            return nil
        }

        // Return next set info
        return (
            setNumber: session.currentSetIndex + 1,  // 1-indexed
            weight: nextSet.targetWeight ?? 0,
            reps: nextSet.targetReps ?? 0
        )
    }

    // MARK: - Superset Skip Helpers (v55.0)

    /// Check if ANY exercise in superset has pending sets at given index
    /// - Parameters:
    ///   - group: Superset group to check
    ///   - setIndex: Set index to check (0-indexed)
    ///   - workout: Current workout
    /// - Returns: true if any exercise has a pending set at this index
    private func hasAnyPendingSets(
        in group: SupersetGroup,
        at setIndex: Int,
        workout: Workout
    ) -> Bool {
        return group.exercisePositions.contains { pos in
            let exerciseId = workout.exerciseIds[pos]
            guard let instance = TestDataManager.shared.exerciseInstances.values.first(where: {
                $0.workoutId == workout.id && $0.exerciseId == exerciseId
            }) else {
                return false
            }

            // Guard: Check bounds before subscripting
            guard setIndex < instance.setIds.count else {
                return false
            }

            let setId = instance.setIds[setIndex]
            guard let set = TestDataManager.shared.exerciseSets[setId] else {
                // Set doesn't exist in memory → treat as pending
                return true
            }

            // Pending = anything NOT completed or skipped
            return set.completion != .completed && set.completion != .skipped
        }
    }

    /// Find first exercise in superset with pending set at given index
    /// - Parameters:
    ///   - group: Superset group to search
    ///   - setIndex: Set index to check (0-indexed)
    ///   - workout: Current workout
    /// - Returns: Position of first exercise with pending set, or nil if none
    private func findFirstPendingExercise(
        in group: SupersetGroup,
        at setIndex: Int,
        workout: Workout
    ) -> Int? {
        return group.exercisePositions.first { pos in
            let exerciseId = workout.exerciseIds[pos]
            guard let instance = TestDataManager.shared.exerciseInstances.values.first(where: {
                $0.workoutId == workout.id && $0.exerciseId == exerciseId
            }) else {
                return false
            }

            // Guard: Check bounds
            guard setIndex < instance.setIds.count else {
                return false
            }

            let setId = instance.setIds[setIndex]
            guard let set = TestDataManager.shared.exerciseSets[setId] else {
                return true
            }

            return set.completion != .completed && set.completion != .skipped
        }
    }

    /// Find next exercise in rotation with pending set at given index
    /// Wraps around to start if needed, stops if no pending sets found
    /// - Parameters:
    ///   - group: Superset group to search
    ///   - position: Current position to start searching after
    ///   - setIndex: Set index to check (0-indexed)
    ///   - workout: Current workout
    /// - Returns: Position of next exercise with pending set, or nil if none
    private func findNextPendingExercise(
        in group: SupersetGroup,
        after position: Int,
        at setIndex: Int,
        workout: Workout
    ) -> Int? {
        var candidatePos = group.nextPosition(after: position, wrapAround: true) ?? position
        let startPos = candidatePos
        var checkedCount = 0
        let maxChecks = group.exercisePositions.count

        // Loop through all exercises, wrapping around once
        while checkedCount < maxChecks {
            let exerciseId = workout.exerciseIds[candidatePos]
            if let instance = TestDataManager.shared.exerciseInstances.values.first(where: {
                $0.workoutId == workout.id && $0.exerciseId == exerciseId
            }), setIndex < instance.setIds.count {
                let setId = instance.setIds[setIndex]
                if let set = TestDataManager.shared.exerciseSets[setId] {
                    if set.completion != .completed && set.completion != .skipped {
                        return candidatePos
                    }
                } else {
                    // Set doesn't exist → treat as pending
                    return candidatePos
                }
            }

            // Try next position
            if let next = group.nextPosition(after: candidatePos, wrapAround: true) {
                candidatePos = next
            }
            checkedCount += 1

            // Prevent infinite loop if we've wrapped all the way around
            if candidatePos == startPos && checkedCount > 0 {
                break
            }
        }

        return nil
    }

    // MARK: - Private Helpers

    /// Helper to clear instance deltas
    private func clearInstanceDeltas(for instanceIds: Set<String>) {
        DeltaStore.shared.clearInstanceDeltas(for: instanceIds)
    }

    /// Helper to clear set deltas
    private func clearSetDeltas(for setIds: Set<String>) {
        DeltaStore.shared.clearSetDeltas(for: setIds)
    }
}
