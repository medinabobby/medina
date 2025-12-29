//
// DeltaStoreTests.swift
// MedinaTests
//
// v181: Tests for DeltaStore delta merge logic
// Tests validate the delta application logic critical for Firebase conflict resolution
//
// Test Cases:
// - Save/load workout deltas
// - Save/load set deltas
// - Apply deltas to workout correctly
// - Clear deltas removes all for version
// - Last write wins (multiple deltas for same entity)
//

import XCTest
@testable import Medina

final class DeltaStoreTests: XCTestCase {

    // MARK: - Properties

    var deltaStore: DeltaStore!
    var testUser: UnifiedUser!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        deltaStore = DeltaStore.shared
        testUser = await MainActor.run { TestFixtures.testUser }

        // Clear any existing deltas before each test
        deltaStore.clearAllDeltas()
    }

    override func tearDown() async throws {
        // Clean up after tests
        deltaStore.clearAllDeltas()
        deltaStore = nil
        try await super.tearDown()
    }

    // MARK: - Workout Delta Tests

    func testSaveWorkoutDelta_PersistsToUserDefaults() {
        // Given: A workout delta
        let delta = DeltaStore.WorkoutDelta(
            workoutId: "test_workout_1",
            completion: .completed
        )

        // When: Saving the delta
        deltaStore.saveWorkoutDelta(delta)

        // Then: Delta should be loadable
        let loadedDeltas = deltaStore.loadWorkoutDeltas()
        XCTAssertEqual(loadedDeltas.count, 1)
        XCTAssertEqual(loadedDeltas.first?.workoutId, "test_workout_1")
        XCTAssertEqual(loadedDeltas.first?.completion, .completed)
    }

    func testLoadWorkoutDeltas_ReturnsAllForWorkout() {
        // Given: Multiple deltas for different workouts
        let delta1 = DeltaStore.WorkoutDelta(workoutId: "workout_a", completion: .completed)
        let delta2 = DeltaStore.WorkoutDelta(workoutId: "workout_b", completion: .skipped)
        let delta3 = DeltaStore.WorkoutDelta(workoutId: "workout_a", completion: .inProgress)

        deltaStore.saveWorkoutDelta(delta1)
        deltaStore.saveWorkoutDelta(delta2)
        deltaStore.saveWorkoutDelta(delta3)

        // When: Loading all deltas
        let loadedDeltas = deltaStore.loadWorkoutDeltas()

        // Then: All deltas should be returned
        XCTAssertEqual(loadedDeltas.count, 3)
    }

    func testApplyDeltas_UpdatesWorkoutCorrectly() {
        // Given: A workout and a delta
        let workoutId = "apply_test_workout"
        var workout = createTestWorkout(id: workoutId, status: .scheduled)
        var workouts: [String: Workout] = [workoutId: workout]

        let delta = DeltaStore.WorkoutDelta(
            workoutId: workoutId,
            completion: .completed
        )
        deltaStore.saveWorkoutDelta(delta)

        // When: Applying deltas
        let updatedWorkouts = deltaStore.applyWorkoutDeltas(to: workouts)

        // Then: Workout status should be updated
        XCTAssertEqual(updatedWorkouts[workoutId]?.status, .completed)
    }

    func testApplyDeltas_UpdatesScheduledDate() {
        // Given: A workout and a delta with new date
        let workoutId = "date_test_workout"
        let originalDate = Date()
        let newDate = Calendar.current.date(byAdding: .day, value: 1, to: originalDate)!

        var workout = createTestWorkout(id: workoutId, status: .scheduled, scheduledDate: originalDate)
        var workouts: [String: Workout] = [workoutId: workout]

        let delta = DeltaStore.WorkoutDelta(
            workoutId: workoutId,
            scheduledDate: newDate
        )
        deltaStore.saveWorkoutDelta(delta)

        // When: Applying deltas
        let updatedWorkouts = deltaStore.applyWorkoutDeltas(to: workouts)

        // Then: Workout date should be updated
        let updatedWorkout = updatedWorkouts[workoutId]
        XCTAssertNotNil(updatedWorkout)
        if let workout = updatedWorkout, let updatedDate = workout.scheduledDate {
            XCTAssertEqual(
                Calendar.current.startOfDay(for: updatedDate),
                Calendar.current.startOfDay(for: newDate)
            )
        } else {
            XCTFail("Workout or scheduledDate should not be nil")
        }
    }

    func testClearDeltas_RemovesAllForVersion() {
        // Given: Multiple saved deltas
        deltaStore.saveWorkoutDelta(DeltaStore.WorkoutDelta(workoutId: "w1", completion: .completed))
        deltaStore.saveWorkoutDelta(DeltaStore.WorkoutDelta(workoutId: "w2", completion: .skipped))
        XCTAssertEqual(deltaStore.loadWorkoutDeltas().count, 2)

        // When: Clearing deltas
        deltaStore.clearWorkoutDeltas()

        // Then: No deltas should remain
        XCTAssertEqual(deltaStore.loadWorkoutDeltas().count, 0)
    }

    func testDeltaConflict_LastWriteWins() {
        // Given: Multiple deltas for the same workout with different values
        let workoutId = "conflict_test_workout"
        var workout = createTestWorkout(id: workoutId, status: .scheduled)
        var workouts: [String: Workout] = [workoutId: workout]

        // Save first delta
        let delta1 = DeltaStore.WorkoutDelta(
            workoutId: workoutId,
            completion: .inProgress,
            timestamp: Date().addingTimeInterval(-60) // 1 minute ago
        )
        deltaStore.saveWorkoutDelta(delta1)

        // Save second delta (later timestamp)
        let delta2 = DeltaStore.WorkoutDelta(
            workoutId: workoutId,
            completion: .completed,
            timestamp: Date() // Now
        )
        deltaStore.saveWorkoutDelta(delta2)

        // When: Applying deltas
        let updatedWorkouts = deltaStore.applyWorkoutDeltas(to: workouts)

        // Then: Last write (completed) should win
        XCTAssertEqual(updatedWorkouts[workoutId]?.status, .completed)
    }

    // MARK: - Set Delta Tests

    func testSaveSetDelta_PersistsToUserDefaults() {
        // Given: A set delta
        let delta = DeltaStore.SetDelta(
            setId: "test_set_1",
            actualWeight: 135.0,
            actualReps: 8,
            completion: .completed
        )

        // When: Saving the delta
        deltaStore.saveSetDelta(delta)

        // Then: Delta should be loadable
        let loadedDeltas = deltaStore.loadSetDeltas()
        XCTAssertEqual(loadedDeltas.count, 1)
        XCTAssertEqual(loadedDeltas.first?.setId, "test_set_1")
        XCTAssertEqual(loadedDeltas.first?.actualWeight, 135.0)
        XCTAssertEqual(loadedDeltas.first?.actualReps, 8)
    }

    func testApplySetDeltas_UpdatesSetCorrectly() {
        // Given: A set and a delta
        let setId = "apply_set_test"
        var set = createTestSet(id: setId)
        var sets: [String: ExerciseSet] = [setId: set]

        let delta = DeltaStore.SetDelta(
            setId: setId,
            actualWeight: 185.0,
            actualReps: 5,
            completion: .completed
        )
        deltaStore.saveSetDelta(delta)

        // When: Applying deltas
        let updatedSets = deltaStore.applySetDeltas(to: sets)

        // Then: Set should be updated
        let updatedSet = updatedSets[setId]
        XCTAssertEqual(updatedSet?.actualWeight, 185.0)
        XCTAssertEqual(updatedSet?.actualReps, 5)
        XCTAssertEqual(updatedSet?.completion, .completed)
    }

    func testClearSetDeltas_ForSpecificSets() {
        // Given: Multiple set deltas
        deltaStore.saveSetDelta(DeltaStore.SetDelta(setId: "set_keep", actualWeight: 100))
        deltaStore.saveSetDelta(DeltaStore.SetDelta(setId: "set_clear", actualWeight: 200))
        XCTAssertEqual(deltaStore.loadSetDeltas().count, 2)

        // When: Clearing specific sets
        deltaStore.clearSetDeltas(for: Set(["set_clear"]))

        // Then: Only specified set delta should be removed
        let remaining = deltaStore.loadSetDeltas()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.setId, "set_keep")
    }

    // MARK: - Instance Delta Tests

    func testSaveInstanceDelta_PersistsToUserDefaults() {
        // Given: An instance delta
        let delta = DeltaStore.InstanceDelta(
            instanceId: "test_instance_1",
            completion: .completed
        )

        // When: Saving the delta
        deltaStore.saveInstanceDelta(delta)

        // Then: Delta should be loadable
        let loadedDeltas = deltaStore.loadInstanceDeltas()
        XCTAssertEqual(loadedDeltas.count, 1)
        XCTAssertEqual(loadedDeltas.first?.instanceId, "test_instance_1")
        XCTAssertEqual(loadedDeltas.first?.completion, .completed)
    }

    // MARK: - Has Deltas Test

    func testHasWorkoutDeltas_ReturnsTrueWhenExists() {
        // Given: A delta exists for a workout
        let workoutId = "has_delta_workout"
        deltaStore.saveWorkoutDelta(DeltaStore.WorkoutDelta(workoutId: workoutId, completion: .completed))

        // When/Then: hasWorkoutDeltas should return true
        XCTAssertTrue(deltaStore.hasWorkoutDeltas(workoutId))
        XCTAssertFalse(deltaStore.hasWorkoutDeltas("nonexistent_workout"))
    }

    // MARK: - Delta Summary Test

    func testGetDeltaSummary_ReturnsCorrectCounts() {
        // Given: Various deltas
        deltaStore.saveWorkoutDelta(DeltaStore.WorkoutDelta(workoutId: "w1", completion: .completed))
        deltaStore.saveWorkoutDelta(DeltaStore.WorkoutDelta(workoutId: "w2", completion: .skipped))
        deltaStore.saveSetDelta(DeltaStore.SetDelta(setId: "s1", actualWeight: 100))
        deltaStore.saveInstanceDelta(DeltaStore.InstanceDelta(instanceId: "i1", completion: .completed))

        // When: Getting summary
        let summary = deltaStore.getDeltaSummary()

        // Then: Summary should contain counts
        XCTAssertTrue(summary.contains("Workout deltas: 2"))
        XCTAssertTrue(summary.contains("Set deltas: 1"))
        XCTAssertTrue(summary.contains("Instance deltas: 1"))
    }

    // MARK: - Test Helpers

    private func createTestWorkout(
        id: String,
        status: ExecutionStatus = .scheduled,
        scheduledDate: Date = Date()
    ) -> Workout {
        return Workout(
            id: id,
            programId: "test_program",
            name: "Test Workout",
            scheduledDate: scheduledDate,
            type: .strength,
            splitDay: .fullBody,
            status: status,
            completedDate: nil,
            exerciseIds: [],
            protocolVariantIds: [:],
            exercisesSelectedAt: nil,
            supersetGroups: nil,
            protocolCustomizations: nil
        )
    }

    private func createTestSet(id: String) -> ExerciseSet {
        return ExerciseSet(
            id: id,
            exerciseInstanceId: "test_instance",
            setNumber: 1,
            targetWeight: 135.0,
            targetReps: 8
        )
    }
}
