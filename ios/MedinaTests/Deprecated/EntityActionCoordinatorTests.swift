//
// EntityActionCoordinatorTests.swift
// MedinaTests
//
// v169: Tests for EntityActionCoordinator workout skip functionality
// Tests: DeltaStore persistence, notification posting
//
// Created: December 2025
//

import XCTest
@testable import Medina

@MainActor
class EntityActionCoordinatorTests: XCTestCase {

    // MARK: - Properties

    private var coordinator: EntityActionCoordinator!
    private var testUser: UnifiedUser!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        TestDataManager.shared.resetAndReload()
        DeltaStore.shared.clearAllDeltas()

        coordinator = EntityActionCoordinator()
        testUser = TestFixtures.testUser
        TestDataManager.shared.currentUserId = testUser.id
    }

    override func tearDown() async throws {
        coordinator = nil
        testUser = nil
        DeltaStore.shared.clearAllDeltas()
        TestDataManager.shared.reset()
        try await super.tearDown()
    }

    // MARK: - Workout Skip Tests (v169)

    /// v169: executeWorkoutSkip should save to DeltaStore
    func testExecuteWorkoutSkip_SavesDeltaStore() async throws {
        // Given: A scheduled workout in an active plan
        let (_, workout) = try createActivePlanWithWorkout()

        // Clear deltas before test
        DeltaStore.shared.clearAllDeltas()

        // When: Executing skip action via coordinator
        let descriptor = EntityDescriptor(
            entityType: .workout,
            entityId: workout.id,
            status: "Scheduled",
            userRole: .member
        )
        let result = await coordinator.execute(
            actionType: .skipWorkout,
            descriptor: descriptor,
            context: .detailView
        )

        // Then: Action should succeed
        if case .failure(let error) = result {
            XCTFail("Skip should succeed, got error: \(error)")
            return
        }

        // And: Delta should be saved
        let deltas = DeltaStore.shared.loadWorkoutDeltas()
        let matchingDelta = deltas.first { $0.workoutId == workout.id }

        XCTAssertNotNil(matchingDelta, "DeltaStore should contain a delta for the skipped workout")
        XCTAssertEqual(matchingDelta?.completion, .skipped,
            "Delta should have .skipped completion status")
    }

    /// v169: executeWorkoutSkip should post notification for UI refresh
    func testExecuteWorkoutSkip_PostsNotification() async throws {
        // Given: A scheduled workout in an active plan
        let (_, workout) = try createActivePlanWithWorkout()

        // Set up notification expectation
        let expectation = XCTNSNotificationExpectation(
            name: .workoutStatusDidChange,
            object: nil
        )

        // When: Executing skip action via coordinator
        let descriptor = EntityDescriptor(
            entityType: .workout,
            entityId: workout.id,
            status: "Scheduled",
            userRole: .member
        )
        _ = await coordinator.execute(
            actionType: .skipWorkout,
            descriptor: descriptor,
            context: .detailView
        )

        // Then: Notification should be posted
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    /// v169: executeWorkoutSkip should update workout status to .skipped
    func testExecuteWorkoutSkip_UpdatesWorkoutStatus() async throws {
        // Given: A scheduled workout in an active plan
        let (_, workout) = try createActivePlanWithWorkout()

        // Verify initial status
        XCTAssertEqual(TestDataManager.shared.workouts[workout.id]?.status, .scheduled)

        // When: Executing skip action via coordinator
        let descriptor = EntityDescriptor(
            entityType: .workout,
            entityId: workout.id,
            status: "Scheduled",
            userRole: .member
        )
        _ = await coordinator.execute(
            actionType: .skipWorkout,
            descriptor: descriptor,
            context: .detailView
        )

        // Then: Workout status should be .skipped
        XCTAssertEqual(TestDataManager.shared.workouts[workout.id]?.status, .skipped,
            "Workout status should be .skipped after coordinator skip")
    }

    /// v169: executeWorkoutSkip with nonexistent workout should fail
    func testExecuteWorkoutSkip_NonexistentWorkout_Fails() async throws {
        // Given: A non-existent workout ID
        let fakeWorkoutId = "nonexistent_workout_12345"

        // When: Executing skip action for fake workout
        let descriptor = EntityDescriptor(
            entityType: .workout,
            entityId: fakeWorkoutId,
            status: "Scheduled",
            userRole: .member
        )
        let result = await coordinator.execute(
            actionType: .skipWorkout,
            descriptor: descriptor,
            context: .detailView
        )

        // Then: Should fail with appropriate error
        if case .success = result {
            XCTFail("Skip should fail for non-existent workout")
        }
    }

    // MARK: - Helpers

    /// Creates an active plan with a scheduled workout for today
    private func createActivePlanWithWorkout() throws -> (Plan, Workout) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let planId = "test_coord_plan_\(UUID().uuidString.prefix(8))"
        let programId = "test_coord_program_\(UUID().uuidString.prefix(8))"
        let workoutId = "test_coord_workout_\(UUID().uuidString.prefix(8))"

        let plan = Plan(
            id: planId,
            memberId: testUser.id,
            isSingleWorkout: false,
            status: .active,
            name: "Test Plan for Coordinator",
            description: "Plan for testing coordinator",
            goal: .strength,
            weightliftingDays: 3,
            cardioDays: 0,
            splitType: .fullBody,
            targetSessionDuration: 60,
            trainingLocation: .gym,
            compoundTimeAllocation: 0.6,
            isolationApproach: .volumeAccumulation,
            preferredDays: [.monday, .wednesday, .friday],
            startDate: calendar.date(byAdding: .day, value: -7, to: today)!,
            endDate: calendar.date(byAdding: .month, value: 1, to: today)!
        )

        let program = Program(
            id: programId,
            planId: planId,
            name: "Test Program",
            focus: .development,
            rationale: "Test",
            startDate: calendar.date(byAdding: .day, value: -7, to: today)!,
            endDate: calendar.date(byAdding: .month, value: 1, to: today)!,
            startingIntensity: 0.75,
            endingIntensity: 0.85,
            progressionType: .linear,
            status: .active
        )

        let workout = Workout(
            id: workoutId,
            programId: programId,
            name: "Test Coordinator Workout",
            scheduledDate: today,
            type: .strength,
            splitDay: .fullBody,
            status: .scheduled,
            completedDate: nil,
            exerciseIds: ["barbell_bench_press"],
            protocolVariantIds: [0: "strength_3x5_moderate"],
            exercisesSelectedAt: Date(),
            supersetGroups: nil,
            protocolCustomizations: nil
        )

        TestDataManager.shared.plans[planId] = plan
        TestDataManager.shared.programs[programId] = program
        TestDataManager.shared.workouts[workoutId] = workout

        return (plan, workout)
    }
}
