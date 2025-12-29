//
// WorkoutRepositoryTests.swift
// MedinaTests
//
// v181: Repository pattern tests for Workout persistence
// Tests the repository contract - works with any backend (file, Firebase, mock)
//
// Test Cases:
// - Save/load round-trip (preserves exercises and sets)
// - Load workout restores full hierarchy
// - Delete workout removes from storage
// - Delete for program cascades correctly
// - Update status persists change
// - SaveAll batch operation
//

import XCTest
@testable import Medina

@MainActor
final class WorkoutRepositoryTests: XCTestCase {

    // MARK: - Properties

    var mockRepository: MockWorkoutRepository!
    var testUser: UnifiedUser!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        mockRepository = MockWorkoutRepository()
        testUser = TestFixtures.testUser
    }

    override func tearDown() async throws {
        mockRepository.reset()
        mockRepository = nil
        try await super.tearDown()
    }

    // MARK: - Test Helpers

    private func createTestWorkout(
        id: String = UUID().uuidString,
        programId: String = "test_program",
        name: String = "Test Workout",
        status: ExecutionStatus = .scheduled,
        daysFromToday: Int = 0
    ) -> Workout {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let scheduledDate = calendar.date(byAdding: .day, value: daysFromToday, to: today)!

        return Workout(
            id: id,
            programId: programId,
            name: name,
            scheduledDate: scheduledDate,
            type: .strength,
            splitDay: .fullBody,
            status: status,
            completedDate: nil,
            exerciseIds: ["barbell_bench_press", "barbell_back_squat"],
            protocolVariantIds: [0: "strength_3x5_moderate", 1: "strength_3x5_moderate"],
            exercisesSelectedAt: Date(),
            supersetGroups: nil,
            protocolCustomizations: nil
        )
    }

    // MARK: - Save/Load Round-Trip Tests

    func testSaveAndLoadWorkout_RoundTrip() async throws {
        // Given: A workout to save
        let originalWorkout = createTestWorkout(name: "Round Trip Test")

        // When: Saving and loading
        try await mockRepository.save(originalWorkout, userId: testUser.id)
        let loadedWorkout = try await mockRepository.load(id: originalWorkout.id)

        // Then: Workout should be identical
        XCTAssertNotNil(loadedWorkout)
        XCTAssertEqual(loadedWorkout?.id, originalWorkout.id)
        XCTAssertEqual(loadedWorkout?.name, originalWorkout.name)
        XCTAssertEqual(loadedWorkout?.programId, originalWorkout.programId)
        XCTAssertEqual(loadedWorkout?.status, originalWorkout.status)
        XCTAssertEqual(loadedWorkout?.splitDay, originalWorkout.splitDay)
    }

    func testSaveWorkout_PersistsExercisesAndSets() async throws {
        // Given: A workout with exercises and protocol variants
        let workout = createTestWorkout()
        XCTAssertEqual(workout.exerciseIds.count, 2)
        XCTAssertEqual(workout.protocolVariantIds.count, 2)

        // When: Saving and loading
        try await mockRepository.save(workout, userId: testUser.id)
        let loadedWorkout = try await mockRepository.load(id: workout.id)

        // Then: Exercises and protocols should be preserved
        XCTAssertEqual(loadedWorkout?.exerciseIds.count, 2)
        XCTAssertEqual(loadedWorkout?.protocolVariantIds.count, 2)
        XCTAssertTrue(loadedWorkout?.exerciseIds.contains("barbell_bench_press") ?? false)
        XCTAssertTrue(loadedWorkout?.exerciseIds.contains("barbell_back_squat") ?? false)
    }

    func testLoadWorkout_RestoresFullHierarchy() async throws {
        // Given: A workout with all fields populated
        var workout = createTestWorkout()
        workout.supersetGroups = [SupersetGroup.pair(groupNumber: 1, position1: 0, position2: 1, restBetweenSets: 60)]
        workout.protocolCustomizations = [
            0: ProtocolCustomization(baseProtocolId: "strength_3x5_moderate", restAdjustment: 30)
        ]

        // When: Saving and loading
        try await mockRepository.save(workout, userId: testUser.id)
        let loadedWorkout = try await mockRepository.load(id: workout.id)

        // Then: All hierarchy should be restored
        XCTAssertNotNil(loadedWorkout?.supersetGroups)
        XCTAssertEqual(loadedWorkout?.supersetGroups?.first?.exercisePositions, [0, 1])
        XCTAssertNotNil(loadedWorkout?.protocolCustomizations?[0])
        XCTAssertEqual(loadedWorkout?.protocolCustomizations?[0]?.restAdjustment, 30)
    }

    // MARK: - Delete Tests

    func testDeleteWorkout_RemovesFromStorage() async throws {
        // Given: A saved workout
        let workout = createTestWorkout(name: "To Be Deleted")
        try await mockRepository.save(workout, userId: testUser.id)
        let savedWorkout = try await mockRepository.load(id: workout.id)
        XCTAssertNotNil(savedWorkout)

        // When: Deleting the workout
        try await mockRepository.delete(id: workout.id, userId: testUser.id)

        // Then: Workout should no longer exist
        let loadedWorkout = try await mockRepository.load(id: workout.id)
        XCTAssertNil(loadedWorkout)
    }

    func testDeleteForProgram_CascadesToWorkouts() async throws {
        // Given: Multiple workouts for a program
        let programId = "test_program_cascade"
        let workout1 = createTestWorkout(id: "workout_1", programId: programId, name: "Workout 1")
        let workout2 = createTestWorkout(id: "workout_2", programId: programId, name: "Workout 2")
        let otherWorkout = createTestWorkout(id: "other_workout", programId: "other_program", name: "Other Workout")

        try await mockRepository.save(workout1, userId: testUser.id)
        try await mockRepository.save(workout2, userId: testUser.id)
        try await mockRepository.save(otherWorkout, userId: testUser.id)

        // When: Deleting all workouts for program
        try await mockRepository.deleteForProgram(programId: programId, userId: testUser.id)

        // Then: Program workouts should be deleted
        let deleted1 = try await mockRepository.load(id: workout1.id)
        let deleted2 = try await mockRepository.load(id: workout2.id)
        XCTAssertNil(deleted1)
        XCTAssertNil(deleted2)

        // And: Other program's workout should remain
        let remaining = try await mockRepository.load(id: otherWorkout.id)
        XCTAssertNotNil(remaining)
    }

    // MARK: - Update Status Tests

    func testUpdateWorkoutStatus_PersistsChange() async throws {
        // Given: A scheduled workout
        let workout = createTestWorkout(status: .scheduled)
        try await mockRepository.save(workout, userId: testUser.id)
        let savedWorkout = try await mockRepository.load(id: workout.id)
        XCTAssertEqual(savedWorkout?.status, .scheduled)

        // When: Updating status to inProgress
        try await mockRepository.updateStatus(id: workout.id, status: .inProgress, userId: testUser.id)

        // Then: Status should be updated
        let updatedWorkout = try await mockRepository.load(id: workout.id)
        XCTAssertEqual(updatedWorkout?.status, .inProgress)
    }

    func testUpdateWorkoutStatus_ToCompleted() async throws {
        // Given: An in-progress workout
        let workout = createTestWorkout(status: .inProgress)
        try await mockRepository.save(workout, userId: testUser.id)

        // When: Updating status to completed
        try await mockRepository.updateStatus(id: workout.id, status: .completed, userId: testUser.id)

        // Then: Status should be completed
        let updatedWorkout = try await mockRepository.load(id: workout.id)
        XCTAssertEqual(updatedWorkout?.status, .completed)
    }

    func testUpdateWorkoutStatus_ToSkipped() async throws {
        // Given: A scheduled workout
        let workout = createTestWorkout(status: .scheduled)
        try await mockRepository.save(workout, userId: testUser.id)

        // When: Updating status to skipped
        try await mockRepository.updateStatus(id: workout.id, status: .skipped, userId: testUser.id)

        // Then: Status should be skipped
        let updatedWorkout = try await mockRepository.load(id: workout.id)
        XCTAssertEqual(updatedWorkout?.status, .skipped)
    }

    func testUpdateWorkoutStatus_ThrowsForMissing() async throws {
        // Given: No workout with the ID exists

        // When/Then: Update should throw notFound error
        do {
            try await mockRepository.updateStatus(id: "nonexistent", status: .completed, userId: testUser.id)
            XCTFail("Should have thrown error")
        } catch let error as RepositoryError {
            if case .notFound = error {
                // Expected
            } else {
                XCTFail("Expected notFound error, got: \(error)")
            }
        }
    }

    // MARK: - Batch Save Tests

    func testSaveAll_BatchOperation() async throws {
        // Given: Multiple workouts to save
        let workouts = (1...5).map { i in
            createTestWorkout(id: "batch_workout_\(i)", name: "Batch Workout \(i)")
        }

        // When: Saving all at once
        try await mockRepository.saveAll(workouts, userId: testUser.id)

        // Then: All workouts should be saved
        let allWorkouts = try await mockRepository.loadAll(for: testUser.id)
        XCTAssertEqual(allWorkouts.count, 5)

        for workout in workouts {
            let loaded = try await mockRepository.load(id: workout.id)
            XCTAssertNotNil(loaded, "Workout \(workout.id) should be saved")
        }
    }

    func testSaveAll_UpdatesExisting() async throws {
        // Given: An existing workout
        let existingWorkout = createTestWorkout(id: "existing_workout", name: "Original Name")
        try await mockRepository.save(existingWorkout, userId: testUser.id)

        // When: Saving batch that includes updated version
        var updatedWorkout = existingWorkout
        updatedWorkout.name = "Updated Name"
        let newWorkout = createTestWorkout(id: "new_workout", name: "New Workout")

        try await mockRepository.saveAll([updatedWorkout, newWorkout], userId: testUser.id)

        // Then: Existing should be updated, new should be added
        let loadedExisting = try await mockRepository.load(id: existingWorkout.id)
        XCTAssertEqual(loadedExisting?.name, "Updated Name")

        let loadedNew = try await mockRepository.load(id: newWorkout.id)
        XCTAssertNotNil(loadedNew)
    }

    // MARK: - LoadForProgram Tests

    func testLoadForProgram_ReturnsOnlyProgramWorkouts() async throws {
        // Given: Workouts for different programs
        let programA = "program_a"
        let programB = "program_b"

        let workoutA1 = createTestWorkout(id: "workout_a1", programId: programA, name: "A1")
        let workoutA2 = createTestWorkout(id: "workout_a2", programId: programA, name: "A2")
        let workoutB1 = createTestWorkout(id: "workout_b1", programId: programB, name: "B1")

        try await mockRepository.save(workoutA1, userId: testUser.id)
        try await mockRepository.save(workoutA2, userId: testUser.id)
        try await mockRepository.save(workoutB1, userId: testUser.id)

        // When: Loading workouts for program A
        let programAWorkouts = try await mockRepository.loadForProgram(programId: programA, userId: testUser.id)

        // Then: Only program A workouts should be returned
        XCTAssertEqual(programAWorkouts.count, 2)
        XCTAssertTrue(programAWorkouts.allSatisfy { $0.programId == programA })
    }

    // MARK: - Error Handling Tests

    func testSave_ThrowsOnError() async throws {
        // Given: Repository configured to throw
        mockRepository.shouldThrowOnSave = true
        let workout = createTestWorkout()

        // When/Then: Save should throw
        do {
            try await mockRepository.save(workout, userId: testUser.id)
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is RepositoryError)
        }
    }

    func testLoad_ThrowsOnError() async throws {
        // Given: Repository configured to throw
        mockRepository.shouldThrowOnLoad = true

        // When/Then: Load should throw
        do {
            _ = try await mockRepository.load(id: "any_id")
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is RepositoryError)
        }
    }
}
