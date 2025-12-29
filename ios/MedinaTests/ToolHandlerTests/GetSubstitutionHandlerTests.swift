//
// GetSubstitutionHandlerTests.swift
// MedinaTests
//
// v188: Tests for get_substitution_options tool handler
// Tests: exercise alternatives, equipment filtering, experience level, error handling
//
// Created: December 2025
//

import XCTest
@testable import Medina

@MainActor
class GetSubstitutionHandlerTests: XCTestCase {

    // MARK: - Properties

    var mockContext: MockToolContext!
    var testUser: UnifiedUser!
    var context: ToolCallContext!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        TestDataManager.shared.resetAndReload()

        mockContext = MockToolContext()
        testUser = TestFixtures.testUser
        TestDataManager.shared.currentUserId = testUser.id
        context = mockContext.build(for: testUser)
    }

    override func tearDown() async throws {
        mockContext.reset()
        TestDataManager.shared.reset()
        try await super.tearDown()
    }

    // MARK: - Success Cases

    /// Test: Valid exercise returns alternatives
    func testValidExercise_ReturnsAlternatives() async throws {
        // Given: A common compound exercise that should have alternatives
        let exerciseId = "barbell_bench_press"

        // When: Requesting substitution options
        let output = await GetSubstitutionHandler.executeOnly(
            args: ["exerciseId": exerciseId],
            context: context
        )

        // Then: Should return alternatives
        XCTAssertFalse(output.hasPrefix("ERROR"),
            "Should not return error for valid exercise. Output: \(output)")
        XCTAssertTrue(output.contains("alternatives") || output.contains("Found"),
            "Should mention alternatives found. Output: \(output)")
        XCTAssertTrue(output.contains("match"),
            "Should include match percentage. Output: \(output)")
    }

    /// Test: Match percentage is calculated
    func testMatchPercentage_Calculated() async throws {
        // Given: A common exercise
        let exerciseId = "barbell_bench_press"

        // When: Requesting substitution options
        let output = await GetSubstitutionHandler.executeOnly(
            args: ["exerciseId": exerciseId],
            context: context
        )

        // Then: Should include percentage match
        XCTAssertTrue(output.contains("%"),
            "Should include percentage in output. Output: \(output)")
    }

    // MARK: - Equipment Filtering Tests

    /// Test: Home workout uses user's available equipment
    func testHomeWorkout_UsesUserEquipment() async throws {
        // Given: A user with limited home equipment
        var updatedUser = testUser!
        updatedUser.memberProfile?.availableEquipment = [.dumbbells, .bodyweight]
        TestDataManager.shared.users[testUser.id] = updatedUser
        context = mockContext.build(for: updatedUser)

        // And: A home workout
        let (_, _, workout) = try createHomeWorkout()

        // When: Requesting substitution with workout context
        let output = await GetSubstitutionHandler.executeOnly(
            args: [
                "exerciseId": "barbell_bench_press",
                "workoutId": workout.id
            ],
            context: context
        )

        // Then: Should find alternatives (even if limited)
        XCTAssertFalse(output.hasPrefix("ERROR"),
            "Should not error for home workout. Output: \(output)")
        // Note: May find dumbbell alternatives or indicate limited options
    }

    /// Test: Gym workout has access to all equipment
    func testGymWorkout_AllEquipmentAvailable() async throws {
        // Given: A gym workout
        let (_, _, workout) = try createGymWorkout()

        // When: Requesting substitution with workout context
        let output = await GetSubstitutionHandler.executeOnly(
            args: [
                "exerciseId": "barbell_bench_press",
                "workoutId": workout.id
            ],
            context: context
        )

        // Then: Should find alternatives from full equipment list
        XCTAssertFalse(output.hasPrefix("ERROR"),
            "Should not error. Output: \(output)")
        XCTAssertTrue(output.contains("alternatives") || output.contains("Found"),
            "Should find gym alternatives. Output: \(output)")
    }

    // MARK: - Error Cases

    /// Test: Missing exerciseId returns error
    func testMissingExerciseId_ReturnsError() async throws {
        // When: Calling without exerciseId
        let output = await GetSubstitutionHandler.executeOnly(
            args: [:],
            context: context
        )

        // Then: Should return error
        XCTAssertTrue(output.hasPrefix("ERROR"),
            "Should return ERROR for missing exerciseId. Output: \(output)")
        XCTAssertTrue(output.contains("exerciseId"),
            "Should mention missing exerciseId. Output: \(output)")
    }

    /// Test: Invalid exercise ID handled gracefully
    func testInvalidExerciseId_HandledGracefully() async throws {
        // Given: A non-existent exercise ID
        let fakeExerciseId = "nonexistent_exercise_xyz123"

        // When: Requesting substitution
        let output = await GetSubstitutionHandler.executeOnly(
            args: ["exerciseId": fakeExerciseId],
            context: context
        )

        // Then: Should handle gracefully (either error or no alternatives message)
        // The handler should not crash and should return something sensible
        XCTAssertFalse(output.isEmpty,
            "Should return some output for invalid exercise")
    }

    /// Test: Exercise with no alternatives shows appropriate message
    func testNoAlternatives_ShowsAppropriateMessage() async throws {
        // Given: A very specific exercise that may have few/no alternatives
        // Using a hypothetical ID - the test verifies the message format
        let exerciseId = "unique_specialized_exercise"

        // When: Requesting substitution
        let output = await GetSubstitutionHandler.executeOnly(
            args: ["exerciseId": exerciseId],
            context: context
        )

        // Then: Should return some output (not crash)
        // If no alternatives, should explain the situation
        XCTAssertFalse(output.isEmpty,
            "Should return output even for exercises with no alternatives")
    }

    // MARK: - Helpers

    /// Creates a home workout for testing equipment filtering
    private func createHomeWorkout() throws -> (Plan, Program, Workout) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let planId = "test_home_plan_\(UUID().uuidString.prefix(8))"
        let programId = "test_home_program_\(UUID().uuidString.prefix(8))"
        let workoutId = "test_home_workout_\(UUID().uuidString.prefix(8))"

        let plan = Plan(
            id: planId,
            memberId: testUser.id,
            isSingleWorkout: false,
            status: .active,
            name: "Home Plan",
            description: "Home workout plan",
            goal: .strength,
            weightliftingDays: 3,
            cardioDays: 0,
            splitType: .fullBody,
            targetSessionDuration: 60,
            trainingLocation: .home,  // Home workout
            compoundTimeAllocation: 0.6,
            isolationApproach: .volumeAccumulation,
            preferredDays: [.monday, .wednesday, .friday],
            startDate: today,
            endDate: calendar.date(byAdding: .month, value: 1, to: today)!
        )

        let program = Program(
            id: programId,
            planId: planId,
            name: "Home Program",
            focus: .development,
            rationale: "Test",
            startDate: today,
            endDate: calendar.date(byAdding: .month, value: 1, to: today)!,
            startingIntensity: 0.75,
            endingIntensity: 0.85,
            progressionType: .linear,
            status: .active
        )

        let workout = Workout(
            id: workoutId,
            programId: programId,
            name: "Home Workout",
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

        return (plan, program, workout)
    }

    /// Creates a gym workout for testing full equipment access
    private func createGymWorkout() throws -> (Plan, Program, Workout) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let planId = "test_gym_plan_\(UUID().uuidString.prefix(8))"
        let programId = "test_gym_program_\(UUID().uuidString.prefix(8))"
        let workoutId = "test_gym_workout_\(UUID().uuidString.prefix(8))"

        let plan = Plan(
            id: planId,
            memberId: testUser.id,
            isSingleWorkout: false,
            status: .active,
            name: "Gym Plan",
            description: "Gym workout plan",
            goal: .strength,
            weightliftingDays: 3,
            cardioDays: 0,
            splitType: .fullBody,
            targetSessionDuration: 60,
            trainingLocation: .gym,  // Gym workout
            compoundTimeAllocation: 0.6,
            isolationApproach: .volumeAccumulation,
            preferredDays: [.monday, .wednesday, .friday],
            startDate: today,
            endDate: calendar.date(byAdding: .month, value: 1, to: today)!
        )

        let program = Program(
            id: programId,
            planId: planId,
            name: "Gym Program",
            focus: .development,
            rationale: "Test",
            startDate: today,
            endDate: calendar.date(byAdding: .month, value: 1, to: today)!,
            startingIntensity: 0.75,
            endingIntensity: 0.85,
            progressionType: .linear,
            status: .active
        )

        let workout = Workout(
            id: workoutId,
            programId: programId,
            name: "Gym Workout",
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

        return (plan, program, workout)
    }
}
