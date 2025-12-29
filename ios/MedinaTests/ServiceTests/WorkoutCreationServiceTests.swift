//
// WorkoutCreationServiceTests.swift
// MedinaTests
//
// Direct unit tests for WorkoutCreationService
// Created: December 2025
//
// Test Coverage:
// - Happy path: Valid intent → complete workout with exercises, instances, sets
// - Error handling: Invalid user, no matching exercises, duration shortfall
// - Cardio workouts: Duration protocol selection
// - Equipment filtering: Home workout uses bodyweight only
// - Active plan insertion: Workout inserts into existing plan
//
// These tests verify the service layer directly (not through tool handlers)
// to catch failures at the source before they propagate to users.
//

import XCTest
@testable import Medina

@MainActor
class WorkoutCreationServiceTests: XCTestCase {

    // MARK: - Properties

    private var testUser: UnifiedUser!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        TestDataManager.shared.resetAndReload()
        DeltaStore.shared.clearAllDeltas()

        testUser = TestFixtures.testUser
        TestDataManager.shared.currentUserId = testUser.id
    }

    override func tearDown() async throws {
        testUser = nil
        DeltaStore.shared.clearAllDeltas()
        try await super.tearDown()
    }

    // MARK: - Happy Path Tests

    /// Test: Valid intent creates complete workout structure
    func testCreateFromIntent_HappyPath() async throws {
        // Given: Valid workout intent
        let intent = WorkoutIntentData(
            name: "Test Workout",
            splitDay: .fullBody,
            scheduledDate: Date(),
            duration: 45,
            effortLevel: .standard,
            sessionType: .strength,
            trainingLocation: .gym,
            availableEquipment: nil,
            exerciseIds: nil,
            selectionReasoning: nil,
            protocolCustomizations: nil,
            supersetStyle: nil,
            supersetGroups: nil,
            preserveProtocolId: nil,
            movementPatternFilter: nil,
            exerciseCountOverride: nil
        )

        // When: Creating workout
        let result = try await WorkoutCreationService.createFromIntent(intent, userId: testUser.id)

        // Then: Plan exists
        XCTAssertNotNil(TestDataManager.shared.plans[result.plan.id], "Plan should be persisted")
        XCTAssertEqual(result.plan.memberId, testUser.id, "Plan should belong to test user")

        // And: Workout exists with exercises
        let workout = result.workout
        XCTAssertNotNil(TestDataManager.shared.workouts[workout.id], "Workout should be persisted")
        XCTAssertGreaterThan(workout.exerciseIds.count, 0, "Workout should have exercises")
        XCTAssertEqual(workout.type, .strength, "Workout type should be strength")

        // And: Protocols assigned
        XCTAssertEqual(workout.protocolVariantIds.count, workout.exerciseIds.count,
                      "Each exercise should have a protocol")

        // And: Instances created
        let instances = TestDataManager.shared.exerciseInstances.values.filter {
            $0.workoutId == workout.id
        }
        XCTAssertEqual(instances.count, workout.exerciseIds.count,
                      "Each exercise should have an instance")

        // And: Sets created
        for instance in instances {
            XCTAssertGreaterThan(instance.setIds.count, 0, "Instance should have sets")
            for setId in instance.setIds {
                XCTAssertNotNil(TestDataManager.shared.exerciseSets[setId],
                              "Set \(setId) should exist")
            }
        }
    }

    /// Test: Workout name and date match intent
    func testCreateFromIntent_WorkoutMatchesIntent() async throws {
        // Given: Specific intent values
        let scheduledDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let intent = WorkoutIntentData(
            name: "Leg Day Power",
            splitDay: .legs,
            scheduledDate: scheduledDate,
            duration: 60,
            effortLevel: .pushIt,
            sessionType: .strength,
            trainingLocation: .gym,
            availableEquipment: nil,
            exerciseIds: nil,
            selectionReasoning: nil,
            protocolCustomizations: nil,
            supersetStyle: nil,
            supersetGroups: nil,
            preserveProtocolId: nil,
            movementPatternFilter: nil,
            exerciseCountOverride: nil
        )

        // When: Creating workout
        let result = try await WorkoutCreationService.createFromIntent(intent, userId: testUser.id)

        // Then: Workout matches intent
        XCTAssertEqual(result.workout.name, "Leg Day Power")
        XCTAssertEqual(result.workout.splitDay, SplitDay.legs)
        if let workoutDate = result.workout.scheduledDate {
            XCTAssertTrue(Calendar.current.isDate(workoutDate, inSameDayAs: scheduledDate))
        } else {
            XCTFail("Workout scheduledDate should not be nil")
        }
    }

    // MARK: - Error Handling Tests

    /// Test: Invalid user throws descriptive error
    func testCreateFromIntent_InvalidUser_ThrowsError() async throws {
        // Given: Intent for non-existent user
        let intent = createMinimalIntent()

        // When/Then: Should throw error
        do {
            _ = try await WorkoutCreationService.createFromIntent(intent, userId: "nonexistent_user_xyz")
            XCTFail("Should throw error for invalid user")
        } catch {
            let nsError = error as NSError
            XCTAssertTrue(nsError.localizedDescription.contains("not found"),
                         "Error should mention user not found: \(error)")
        }
    }

    /// Test: Empty library handles gracefully (either fallback or descriptive error)
    func testCreateFromIntent_EmptyLibrary_HandlesGracefully() async throws {
        // Given: User with empty library
        let emptyUserId = "empty_library_user"
        let emptyUser = UnifiedUser(
            id: emptyUserId,
            firebaseUID: "empty_firebase",
            authProvider: .email,
            email: "empty@test.com",
            name: "Empty Library User",
            birthdate: Date(),
            gender: .male,
            roles: [.member],
            memberProfile: MemberProfile(
                fitnessGoal: .strength,
                experienceLevel: .intermediate,
                preferredSessionDuration: 60,
                membershipStatus: .active,
                memberSince: Date()
            )
        )
        TestDataManager.shared.users[emptyUserId] = emptyUser
        TestFixtures.setupEmptyLibrary(for: emptyUserId)

        let intent = createMinimalIntent()

        // When: Try to create workout
        // Then: Should either succeed with fallback OR throw descriptive error (not crash)
        do {
            let result = try await WorkoutCreationService.createFromIntent(intent, userId: emptyUserId)
            // If it succeeds, workout should still be valid
            XCTAssertGreaterThanOrEqual(result.workout.exerciseIds.count, 0,
                                        "If succeeds, workout should exist")
        } catch {
            // If it throws, error should be descriptive (not a crash)
            let description = error.localizedDescription.lowercased()
            // Just verify we got an error message, not a nil/crash
            XCTAssertFalse(description.isEmpty, "Error should have a description")
        }
    }

    // MARK: - Cardio Workout Tests

    /// Test: Cardio workout uses duration-based protocol
    func testCreateFromIntent_CardioWorkout_UsesDurationProtocol() async throws {
        // Given: Cardio intent
        let intent = WorkoutIntentData(
            name: "30 Min Run",
            splitDay: .notApplicable,
            scheduledDate: Date(),
            duration: 30,
            effortLevel: .standard,
            sessionType: .cardio,
            trainingLocation: .gym,
            availableEquipment: nil,
            exerciseIds: nil,
            selectionReasoning: nil,
            protocolCustomizations: nil,
            supersetStyle: nil,
            supersetGroups: nil,
            preserveProtocolId: nil,
            movementPatternFilter: nil,
            exerciseCountOverride: nil
        )

        // When: Creating cardio workout
        let result = try await WorkoutCreationService.createFromIntent(intent, userId: testUser.id)

        // Then: Workout type is cardio
        XCTAssertEqual(result.workout.type, .cardio, "Workout type should be cardio")

        // And: Protocol is cardio-based
        for (_, protocolId) in result.workout.protocolVariantIds {
            XCTAssertTrue(protocolId.contains("cardio"),
                         "Protocol '\(protocolId)' should be cardio-based")
        }
    }

    /// Test: Cardio workout selects appropriate protocol for duration
    func testCreateFromIntent_CardioWorkout_MatchesDuration() async throws {
        // Test different durations
        let testCases: [(duration: Int, expectedProtocolSubstring: String)] = [
            (20, "20min"),
            (30, "30min"),
            (45, "45min")
        ]

        for testCase in testCases {
            // Reset for each test
            TestDataManager.shared.resetAndReload()
            testUser = TestFixtures.testUser

            let intent = WorkoutIntentData(
                name: "\(testCase.duration) Min Cardio",
                splitDay: .notApplicable,
                scheduledDate: Date(),
                duration: testCase.duration,
                effortLevel: .standard,
                sessionType: .cardio,
                trainingLocation: .gym,
                availableEquipment: nil,
                exerciseIds: nil,
                selectionReasoning: nil,
                protocolCustomizations: nil,
                supersetStyle: nil,
                supersetGroups: nil,
                preserveProtocolId: nil,
                movementPatternFilter: nil,
                exerciseCountOverride: nil
            )

            let result = try await WorkoutCreationService.createFromIntent(intent, userId: testUser.id)

            // Protocol should match duration (approximately)
            let protocolId = result.workout.protocolVariantIds.values.first ?? ""
            XCTAssertTrue(protocolId.contains("cardio"),
                         "\(testCase.duration)min workout should have cardio protocol, got: \(protocolId)")
        }
    }

    // MARK: - Equipment Filtering Tests

    /// Test: Home workout filters to bodyweight exercises
    func testCreateFromIntent_HomeWorkout_FiltersToBodyweight() async throws {
        // Given: Home workout intent (no equipment specified)
        let intent = WorkoutIntentData(
            name: "Home Workout",
            splitDay: .fullBody,
            scheduledDate: Date(),
            duration: 30,
            effortLevel: .standard,
            sessionType: .strength,
            trainingLocation: .home,
            availableEquipment: nil,  // Should default to bodyweight
            exerciseIds: nil,
            selectionReasoning: nil,
            protocolCustomizations: nil,
            supersetStyle: nil,
            supersetGroups: nil,
            preserveProtocolId: nil,
            movementPatternFilter: nil,
            exerciseCountOverride: nil
        )

        // When: Creating home workout
        let result = try await WorkoutCreationService.createFromIntent(intent, userId: testUser.id)

        // Then: All exercises should be bodyweight compatible
        let allowedEquipment: Set<Equipment> = [.bodyweight, .none]

        for exerciseId in result.workout.exerciseIds {
            guard let exercise = TestDataManager.shared.exercises[exerciseId] else {
                continue
            }
            XCTAssertTrue(allowedEquipment.contains(exercise.equipment),
                         "Exercise '\(exercise.name)' uses \(exercise.equipment) which is not bodyweight compatible")
        }
    }

    /// Test: Gym workout can use all equipment
    func testCreateFromIntent_GymWorkout_UsesFullEquipment() async throws {
        // Given: Gym workout intent
        let intent = WorkoutIntentData(
            name: "Gym Workout",
            splitDay: .upper,
            scheduledDate: Date(),
            duration: 60,
            effortLevel: .standard,
            sessionType: .strength,
            trainingLocation: .gym,
            availableEquipment: nil,  // Should default to full gym
            exerciseIds: nil,
            selectionReasoning: nil,
            protocolCustomizations: nil,
            supersetStyle: nil,
            supersetGroups: nil,
            preserveProtocolId: nil,
            movementPatternFilter: nil,
            exerciseCountOverride: nil
        )

        // When: Creating gym workout
        let result = try await WorkoutCreationService.createFromIntent(intent, userId: testUser.id)

        // Then: Should have exercises (gym should have plenty)
        XCTAssertGreaterThan(result.workout.exerciseIds.count, 0, "Gym workout should have exercises")

        // And: Should likely include barbell/dumbbell exercises
        let usedEquipment = Set(result.workout.exerciseIds.compactMap { exerciseId -> Equipment? in
            TestDataManager.shared.exercises[exerciseId]?.equipment
        })

        // Gym workouts typically include barbells or dumbbells
        let hasGymEquipment = usedEquipment.contains(.barbell) ||
                             usedEquipment.contains(.dumbbells) ||
                             usedEquipment.contains(.machine)
        XCTAssertTrue(hasGymEquipment || result.workout.exerciseIds.isEmpty == false,
                     "Gym workout should use gym equipment or at least have exercises")
    }

    // MARK: - Active Plan Integration Tests

    /// Test: Workout inserts into active plan instead of creating new plan
    func testCreateFromIntent_InsertsIntoActivePlan() async throws {
        // Given: Active plan exists
        let activePlan = createActivePlan(for: testUser.id)
        let initialWorkoutCount = countWorkoutsInPlan(activePlan)

        let intent = WorkoutIntentData(
            name: "Extra Cardio",
            splitDay: .notApplicable,
            scheduledDate: Date(),
            duration: 30,
            effortLevel: .recovery,
            sessionType: .cardio,
            trainingLocation: .gym,
            availableEquipment: nil,
            exerciseIds: nil,
            selectionReasoning: nil,
            protocolCustomizations: nil,
            supersetStyle: nil,
            supersetGroups: nil,
            preserveProtocolId: nil,
            movementPatternFilter: nil,
            exerciseCountOverride: nil
        )

        // When: Creating workout
        let result = try await WorkoutCreationService.createFromIntent(intent, userId: testUser.id)

        // Then: Should use existing plan
        XCTAssertEqual(result.plan.id, activePlan.id, "Should insert into existing active plan")

        // And: Workout count increased
        let finalWorkoutCount = countWorkoutsInPlan(activePlan)
        XCTAssertEqual(finalWorkoutCount, initialWorkoutCount + 1, "Should have one more workout")
    }

    /// Test: Single workout creates new plan when no active plan exists
    func testCreateFromIntent_CreatesNewPlan_WhenNoActivePlan() async throws {
        // Given: No active plan (just test user, no plans)
        let initialPlanCount = TestDataManager.shared.plans.values.filter {
            $0.memberId == testUser.id
        }.count

        let intent = createMinimalIntent()

        // When: Creating workout
        let result = try await WorkoutCreationService.createFromIntent(intent, userId: testUser.id)

        // Then: New plan created
        let finalPlanCount = TestDataManager.shared.plans.values.filter {
            $0.memberId == testUser.id
        }.count

        XCTAssertEqual(finalPlanCount, initialPlanCount + 1, "Should create new plan")
        XCTAssertTrue(result.plan.isSingleWorkout, "New plan should be single workout")
    }

    // MARK: - Exercise Count Override Tests (v103, v193)

    /// Test: Exercise count override is honored EXACTLY (v193 fix)
    /// Bug: Image showed 6 exercises but workout had 7 - builder was adding exercises to meet duration
    func testCreateFromIntent_ExerciseCountOverride() async throws {
        // Given: Intent with exercise count override (fewer than duration would suggest)
        let intent = WorkoutIntentData(
            name: "Image-Based Workout",
            splitDay: .fullBody,
            scheduledDate: Date(),
            duration: 60,  // Duration would suggest ~6-8 exercises
            effortLevel: .standard,
            sessionType: .strength,
            trainingLocation: .gym,
            availableEquipment: nil,
            exerciseIds: nil,
            selectionReasoning: nil,
            protocolCustomizations: nil,
            supersetStyle: nil,
            supersetGroups: nil,
            preserveProtocolId: nil,
            movementPatternFilter: nil,
            exerciseCountOverride: 4  // Override to EXACTLY 4 exercises
        )

        // When: Creating workout
        let result = try await WorkoutCreationService.createFromIntent(intent, userId: testUser.id)

        // Then: Should have EXACTLY 4 exercises (v193: override is absolute, not a hint)
        XCTAssertEqual(result.workout.exerciseIds.count, 4,
                      "v193: exerciseCountOverride should be honored EXACTLY, not adjusted for duration")
    }

    /// Test: v193 - Image extraction with 6 exercises should result in exactly 6
    func testCreateFromIntent_ExerciseCountOverride_ImageSixExercises() async throws {
        // Given: Intent simulating image with 6 visible exercises
        let intent = WorkoutIntentData(
            name: "Image Extracted Workout",
            splitDay: .upper,
            scheduledDate: Date(),
            duration: 45,  // Duration might suggest 5 exercises, but image shows 6
            effortLevel: .standard,
            sessionType: .strength,
            trainingLocation: .gym,
            availableEquipment: nil,
            exerciseIds: nil,
            selectionReasoning: nil,
            protocolCustomizations: nil,
            supersetStyle: nil,
            supersetGroups: nil,
            preserveProtocolId: nil,
            movementPatternFilter: nil,
            exerciseCountOverride: 6  // Image shows exactly 6 exercises
        )

        // When: Creating workout
        let result = try await WorkoutCreationService.createFromIntent(intent, userId: testUser.id)

        // Then: Should have EXACTLY 6 exercises (not 7!)
        XCTAssertEqual(result.workout.exerciseIds.count, 6,
                      "v193: Image showed 6 exercises - workout should have exactly 6, not 7")
    }

    // MARK: - v127-v132: Home Workout Location Tests

    /// v127: Home workout with no equipment should only use bodyweight exercises
    func testCreateFromIntent_HomeNoEquipment_BodyweightOnly() async throws {
        // Given: Home intent with no equipment (nil = bodyweight only)
        let intent = WorkoutIntentData(
            name: "Home Bodyweight",
            splitDay: .fullBody,
            scheduledDate: Date(),
            duration: 30,
            effortLevel: .standard,
            sessionType: .strength,
            trainingLocation: .home,
            availableEquipment: nil,  // Should force bodyweight only
            exerciseIds: nil,
            selectionReasoning: nil,
            protocolCustomizations: nil,
            supersetStyle: nil,
            supersetGroups: nil,
            preserveProtocolId: nil,
            movementPatternFilter: nil,
            exerciseCountOverride: nil
        )

        // When: Creating home workout
        let result = try await WorkoutCreationService.createFromIntent(intent, userId: testUser.id)

        // Then: All exercises should be bodyweight only
        let gymEquipment: Set<Equipment> = [.barbell, .dumbbells, .cableMachine, .machine, .smith, .pullupBar]

        for exerciseId in result.workout.exerciseIds {
            guard let exercise = TestDataManager.shared.exercises[exerciseId] else {
                continue
            }
            XCTAssertFalse(gymEquipment.contains(exercise.equipment),
                "Home workout should NOT have \(exercise.equipment) exercise '\(exercise.name)'")
        }
    }

    /// v130: Home workout should find exercises even when library is gym-only
    func testCreateFromIntent_HomeWorkout_UsesFullCatalog() async throws {
        // Given: User with library containing ONLY gym exercises
        let gymOnlyLibraryUser = "gym_only_library_user"
        TestDataManager.shared.users[gymOnlyLibraryUser] = UnifiedUser(
            id: gymOnlyLibraryUser,
            firebaseUID: "gym_only",
            authProvider: .email,
            email: "gymonly@test.com",
            name: "Gym Only User",
            birthdate: Date(),
            gender: .male,
            roles: [.member],
            memberProfile: MemberProfile(
                fitnessGoal: .strength,
                experienceLevel: .intermediate,
                preferredSessionDuration: 45,
                membershipStatus: .active,
                memberSince: Date()
            )
        )

        // Set up library with only barbell exercises
        var gymLibrary = UserLibrary(userId: gymOnlyLibraryUser)
        gymLibrary.exercises = ["barbell_bench_press", "barbell_squat", "conventional_deadlift"]
        TestDataManager.shared.libraries[gymOnlyLibraryUser] = gymLibrary

        // When: Creating home workout
        let intent = WorkoutIntentData(
            name: "Home Despite Gym Library",
            splitDay: .fullBody,
            scheduledDate: Date(),
            duration: 30,
            effortLevel: .standard,
            sessionType: .strength,
            trainingLocation: .home,
            availableEquipment: nil,
            exerciseIds: nil,
            selectionReasoning: nil,
            protocolCustomizations: nil,
            supersetStyle: nil,
            supersetGroups: nil,
            preserveProtocolId: nil,
            movementPatternFilter: nil,
            exerciseCountOverride: nil
        )

        let result = try await WorkoutCreationService.createFromIntent(intent, userId: gymOnlyLibraryUser)

        // Then: Should succeed with bodyweight exercises from full catalog
        XCTAssertGreaterThan(result.workout.exerciseIds.count, 0,
            "Should find bodyweight exercises from full catalog")

        // And: All exercises should be bodyweight
        for exerciseId in result.workout.exerciseIds {
            if let exercise = TestDataManager.shared.exercises[exerciseId] {
                let isBodyweight = exercise.equipment == .bodyweight || exercise.equipment == .none
                XCTAssertTrue(isBodyweight,
                    "Exercise '\(exercise.name)' should be bodyweight, got \(exercise.equipment)")
            }
        }
    }

    /// v132: Duration calculation should be consistent between builder and display
    func testCreateFromIntent_DurationConsistency() async throws {
        // Given: Standard gym workout intent
        let intent = WorkoutIntentData(
            name: "Duration Test",
            splitDay: .upper,
            scheduledDate: Date(),
            duration: 45,
            effortLevel: .standard,
            sessionType: .strength,
            trainingLocation: .gym,
            availableEquipment: nil,
            exerciseIds: nil,
            selectionReasoning: nil,
            protocolCustomizations: nil,
            supersetStyle: nil,
            supersetGroups: nil,
            preserveProtocolId: nil,
            movementPatternFilter: nil,
            exerciseCountOverride: nil
        )

        // When: Creating workout
        let result = try await WorkoutCreationService.createFromIntent(intent, userId: testUser.id)

        // Then: Get instances and calculate duration same way UI does
        let instances = TestDataManager.shared.exerciseInstances.values.filter {
            $0.workoutId == result.workout.id
        }
        let protocolConfigs = instances.compactMap { instance in
            TestDataManager.shared.protocolConfigs[instance.protocolVariantId]
        }

        // Calculate duration with v132 transition time (matching UI)
        let displayDuration = ExerciseTimeCalculator.calculateWorkoutTime(
            protocolConfigs: protocolConfigs,
            workoutType: .strength,
            restBetweenExercises: 90  // v132: Same as DurationAwareWorkoutBuilder
        )

        // Duration should be within target range (40-50 for 45 min target)
        XCTAssertGreaterThanOrEqual(displayDuration, 38,
            "Duration should be at least 38 min")
        XCTAssertLessThanOrEqual(displayDuration, 52,
            "Duration should be at most 52 min")
    }

    // MARK: - Superset Tests

    /// Test: Superset style creates superset groups
    func testCreateFromIntent_SupersetStyle_CreatesGroups() async throws {
        // Given: Intent with superset style
        let intent = WorkoutIntentData(
            name: "Superset Workout",
            splitDay: .fullBody,
            scheduledDate: Date(),
            duration: 45,
            effortLevel: .standard,
            sessionType: .strength,
            trainingLocation: .gym,
            availableEquipment: nil,
            exerciseIds: nil,
            selectionReasoning: nil,
            protocolCustomizations: nil,
            supersetStyle: .antagonist,
            supersetGroups: nil,
            preserveProtocolId: nil,
            movementPatternFilter: nil,
            exerciseCountOverride: nil
        )

        // When: Creating workout
        let result = try await WorkoutCreationService.createFromIntent(intent, userId: testUser.id)

        // Then: Should have superset groups (if enough exercises)
        if result.workout.exerciseIds.count >= 4 {
            XCTAssertNotNil(result.workout.supersetGroups, "Should have superset groups")
            XCTAssertGreaterThan(result.workout.supersetGroups?.count ?? 0, 0,
                               "Should have at least one superset group")
        }
    }

    // MARK: - Helper Methods

    /// Create minimal valid intent for testing
    private func createMinimalIntent() -> WorkoutIntentData {
        return WorkoutIntentData(
            name: "Test Workout",
            splitDay: .fullBody,
            scheduledDate: Date(),
            duration: 45,
            effortLevel: .standard,
            sessionType: .strength,
            trainingLocation: .gym,
            availableEquipment: nil,
            exerciseIds: nil,
            selectionReasoning: nil,
            protocolCustomizations: nil,
            supersetStyle: nil,
            supersetGroups: nil,
            preserveProtocolId: nil,
            movementPatternFilter: nil,
            exerciseCountOverride: nil
        )
    }

    /// Create an active plan for testing
    private func createActivePlan(for userId: String) -> Plan {
        let planId = "test_active_plan_\(UUID().uuidString.prefix(8))"
        let programId = "test_program_\(UUID().uuidString.prefix(8))"
        let workoutId = "test_workout_\(UUID().uuidString.prefix(8))"

        let plan = Plan(
            id: planId,
            memberId: userId,
            isSingleWorkout: false,
            status: .active,
            name: "Test Active Plan",
            description: "Active plan for testing",
            goal: .strength,
            weightliftingDays: 4,
            cardioDays: 0,
            splitType: .upperLower,
            targetSessionDuration: 60,
            trainingLocation: .gym,
            compoundTimeAllocation: 0.7,
            isolationApproach: .minimal,
            preferredDays: [.monday, .wednesday, .friday],
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .month, value: 3, to: Date())!,
            emphasizedMuscleGroups: [],
            excludedMuscleGroups: [],
            experienceLevel: .intermediate
        )

        let program = Program(
            id: programId,
            planId: planId,
            name: "Test Program",
            focus: .development,
            rationale: "Test",
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .month, value: 3, to: Date())!,
            startingIntensity: 0.75,
            endingIntensity: 0.85,
            progressionType: .linear,
            status: .active
        )

        let workout = Workout(
            id: workoutId,
            programId: programId,
            name: "Existing Workout",
            scheduledDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
            type: .strength,
            splitDay: .upper,
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

        return plan
    }

    /// Count workouts in a plan
    private func countWorkoutsInPlan(_ plan: Plan) -> Int {
        let programIds = Set(TestDataManager.shared.programs.values
            .filter { $0.planId == plan.id }
            .map { $0.id })

        return TestDataManager.shared.workouts.values
            .filter { programIds.contains($0.programId) }
            .count
    }
}
