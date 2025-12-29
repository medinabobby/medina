//
// UserContextBuilderTests.swift
// MedinaTests
//
// v137: Regression test for active vs draft plan workout selection
// v142: Added test for missed workouts only from active plan
// v157: Added tests for active session context and "no workout in progress" handling
// Tests that buildTodayContext only includes workouts from active plans
//
// Created: December 2025
//

import XCTest
@testable import Medina

@MainActor
class UserContextBuilderTests: XCTestCase {

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

    // MARK: - v137 Regression Test

    /// REGRESSION TEST (v137): AI was picking workouts from draft plans instead of active plans
    ///
    /// Bug: User with both active plan and draft plan having workouts today would get:
    ///   "Today's Workout: [draft plan workout] (ID: draft_workout_id)"
    /// Expected: Only workouts from active plan should appear in context
    ///
    /// Root cause: UserContextBuilder.buildTodayContext() didn't filter by plan status
    func testBuildCurrentContext_OnlyIncludesActiveWorkouts() throws {
        // Given: User with both active and draft plans having workouts TODAY
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Create ACTIVE plan with workout today
        let activePlanId = "test_active_plan"
        let activeProgramId = "test_active_program"
        let activeWorkoutId = "test_active_workout"

        let activePlan = Plan(
            id: activePlanId,
            memberId: testUser.id,
            isSingleWorkout: false,
            status: .active,
            name: "Active Plan",
            description: "Active plan for testing",
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

        let activeProgram = Program(
            id: activeProgramId,
            planId: activePlanId,
            name: "Active Program",
            focus: .development,
            rationale: "Test",
            startDate: calendar.date(byAdding: .day, value: -7, to: today)!,
            endDate: calendar.date(byAdding: .month, value: 1, to: today)!,
            startingIntensity: 0.75,
            endingIntensity: 0.85,
            progressionType: .linear,
            status: .active
        )

        let activeWorkout = Workout(
            id: activeWorkoutId,
            programId: activeProgramId,
            name: "Active Workout",
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

        // Create DRAFT plan with workout today
        let draftPlanId = "test_draft_plan"
        let draftProgramId = "test_draft_program"
        let draftWorkoutId = "test_draft_workout"

        let draftPlan = Plan(
            id: draftPlanId,
            memberId: testUser.id,
            isSingleWorkout: false,
            status: .draft,
            name: "Draft Plan",
            description: "Draft plan for testing",
            goal: .muscleGain,
            weightliftingDays: 4,
            cardioDays: 0,
            splitType: .upperLower,
            targetSessionDuration: 60,
            trainingLocation: .gym,
            compoundTimeAllocation: 0.6,
            isolationApproach: .volumeAccumulation,
            preferredDays: [.monday, .tuesday, .thursday, .friday],
            startDate: today,
            endDate: calendar.date(byAdding: .month, value: 2, to: today)!
        )

        let draftProgram = Program(
            id: draftProgramId,
            planId: draftPlanId,
            name: "Draft Program",
            focus: .development,
            rationale: "Test",
            startDate: today,
            endDate: calendar.date(byAdding: .month, value: 2, to: today)!,
            startingIntensity: 0.70,
            endingIntensity: 0.80,
            progressionType: .linear,
            status: .active  // Program status doesn't matter, plan status does
        )

        let draftWorkout = Workout(
            id: draftWorkoutId,
            programId: draftProgramId,
            name: "Draft Workout",
            scheduledDate: today,
            type: .strength,
            splitDay: .upper,
            status: .scheduled,
            completedDate: nil,
            exerciseIds: ["barbell_overhead_press"],
            protocolVariantIds: [0: "strength_3x5_moderate"],
            exercisesSelectedAt: Date(),
            supersetGroups: nil,
            protocolCustomizations: nil
        )

        // Register in TestDataManager
        TestDataManager.shared.plans[activePlanId] = activePlan
        TestDataManager.shared.plans[draftPlanId] = draftPlan
        TestDataManager.shared.programs[activeProgramId] = activeProgram
        TestDataManager.shared.programs[draftProgramId] = draftProgram
        TestDataManager.shared.workouts[activeWorkoutId] = activeWorkout
        TestDataManager.shared.workouts[draftWorkoutId] = draftWorkout

        // When: Building current context
        let context = UserContextBuilder.buildCurrentContext(for: testUser)

        // Then: "Today's Workout" line should include ACTIVE workout ID
        // The key check is that the AI directive uses the active workout, not draft
        let todaysWorkoutLine = context.components(separatedBy: "\n")
            .first { $0.contains("Today's Workout:") }

        XCTAssertNotNil(todaysWorkoutLine, "Should have a 'Today's Workout' line")
        XCTAssertTrue(todaysWorkoutLine?.contains(activeWorkoutId) == true,
            "Today's Workout should reference active workout ID '\(activeWorkoutId)'. Line: \(todaysWorkoutLine ?? "nil")")
        XCTAssertFalse(todaysWorkoutLine?.contains(draftWorkoutId) == true,
            "Today's Workout should NOT reference draft workout ID '\(draftWorkoutId)'. Line: \(todaysWorkoutLine ?? "nil")")

        // And: The AI directive should use the active workout ID
        let directiveLine = context.components(separatedBy: "\n")
            .first { $0.contains("start_workout(workoutId:") }

        XCTAssertNotNil(directiveLine, "Should have a start_workout directive")
        XCTAssertTrue(directiveLine?.contains(activeWorkoutId) == true,
            "AI directive should use active workout ID. Line: \(directiveLine ?? "nil")")
    }

    /// Test: When no active plan exists, no "Today's Workout" should appear
    func testBuildCurrentContext_NoTodayWorkout_WhenOnlyDraftPlan() throws {
        // Given: User with ONLY a draft plan having workout today
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let draftPlanId = "test_draft_only_plan"
        let draftProgramId = "test_draft_only_program"
        let draftWorkoutId = "test_draft_only_workout"

        let draftPlan = Plan(
            id: draftPlanId,
            memberId: testUser.id,
            isSingleWorkout: false,
            status: .draft,
            name: "Draft Only Plan",
            description: "Draft plan for testing",
            goal: .muscleGain,
            weightliftingDays: 4,
            cardioDays: 0,
            splitType: .upperLower,
            targetSessionDuration: 60,
            trainingLocation: .gym,
            compoundTimeAllocation: 0.6,
            isolationApproach: .volumeAccumulation,
            preferredDays: [.monday, .tuesday, .thursday, .friday],
            startDate: today,
            endDate: calendar.date(byAdding: .month, value: 2, to: today)!
        )

        let draftProgram = Program(
            id: draftProgramId,
            planId: draftPlanId,
            name: "Draft Program",
            focus: .development,
            rationale: "Test",
            startDate: today,
            endDate: calendar.date(byAdding: .month, value: 2, to: today)!,
            startingIntensity: 0.70,
            endingIntensity: 0.80,
            progressionType: .linear,
            status: .active
        )

        let draftWorkout = Workout(
            id: draftWorkoutId,
            programId: draftProgramId,
            name: "Draft Only Workout",
            scheduledDate: today,
            type: .strength,
            splitDay: .upper,
            status: .scheduled,
            completedDate: nil,
            exerciseIds: ["barbell_overhead_press"],
            protocolVariantIds: [0: "strength_3x5_moderate"],
            exercisesSelectedAt: Date(),
            supersetGroups: nil,
            protocolCustomizations: nil
        )

        // Register in TestDataManager
        TestDataManager.shared.plans[draftPlanId] = draftPlan
        TestDataManager.shared.programs[draftProgramId] = draftProgram
        TestDataManager.shared.workouts[draftWorkoutId] = draftWorkout

        // When: Building current context
        let context = UserContextBuilder.buildCurrentContext(for: testUser)

        // Then: Context should NOT include "Today's Workout" line (since no active plan)
        let todaysWorkoutLine = context.components(separatedBy: "\n")
            .first { $0.contains("Today's Workout:") }

        XCTAssertNil(todaysWorkoutLine,
            "Context should NOT include 'Today's Workout' when only draft plans exist. Found: \(todaysWorkoutLine ?? "nil")")

        // And: There should be no start_workout directive
        let directiveLine = context.components(separatedBy: "\n")
            .first { $0.contains("start_workout(workoutId:") }

        XCTAssertNil(directiveLine,
            "Context should NOT include start_workout directive for draft workouts. Found: \(directiveLine ?? "nil")")
    }

    // MARK: - v142 Regression Test: Missed Workouts

    /// REGRESSION TEST (v142): AI was picking missed workouts from draft plans
    ///
    /// Bug: User with active plan and draft plan both having missed workouts would get
    ///   "Missed Workouts: [draft plan workout] - ID: draft_workout_id"
    /// Expected: Only missed workouts from active plan should appear in context
    ///
    /// Root cause: UserContextBuilder.buildMissedWorkoutsContext() didn't filter by plan status
    func testBuildCurrentContext_MissedWorkouts_OnlyFromActivePlan() throws {
        // Given: User with both active and draft plans having MISSED workouts (past scheduled)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!

        // Create ACTIVE plan with missed workout
        let activePlanId = "test_active_plan_missed"
        let activeProgramId = "test_active_program_missed"
        let activeMissedWorkoutId = "test_active_missed_workout"

        let activePlan = Plan(
            id: activePlanId,
            memberId: testUser.id,
            isSingleWorkout: false,
            status: .active,
            name: "Active Plan With Missed",
            description: "Active plan for testing missed workouts",
            goal: .strength,
            weightliftingDays: 3,
            cardioDays: 0,
            splitType: .fullBody,
            targetSessionDuration: 60,
            trainingLocation: .gym,
            compoundTimeAllocation: 0.6,
            isolationApproach: .volumeAccumulation,
            preferredDays: [.monday, .wednesday, .friday],
            startDate: calendar.date(byAdding: .day, value: -14, to: today)!,
            endDate: calendar.date(byAdding: .month, value: 1, to: today)!
        )

        let activeProgram = Program(
            id: activeProgramId,
            planId: activePlanId,
            name: "Active Program",
            focus: .development,
            rationale: "Test",
            startDate: calendar.date(byAdding: .day, value: -14, to: today)!,
            endDate: calendar.date(byAdding: .month, value: 1, to: today)!,
            startingIntensity: 0.75,
            endingIntensity: 0.85,
            progressionType: .linear,
            status: .active
        )

        // Missed workout from ACTIVE plan (scheduled 2 days ago, not completed)
        let activeMissedWorkout = Workout(
            id: activeMissedWorkoutId,
            programId: activeProgramId,
            name: "Active Missed Workout",
            scheduledDate: twoDaysAgo,
            type: .strength,
            splitDay: .fullBody,
            status: .scheduled,  // Still scheduled = missed
            completedDate: nil,
            exerciseIds: ["barbell_bench_press"],
            protocolVariantIds: [0: "strength_3x5_moderate"],
            exercisesSelectedAt: Date(),
            supersetGroups: nil,
            protocolCustomizations: nil
        )

        // Create DRAFT plan with missed workout
        let draftPlanId = "test_draft_plan_missed"
        let draftProgramId = "test_draft_program_missed"
        let draftMissedWorkoutId = "test_draft_missed_workout"

        let draftPlan = Plan(
            id: draftPlanId,
            memberId: testUser.id,
            isSingleWorkout: false,
            status: .draft,
            name: "Draft Plan With Missed",
            description: "Draft plan for testing",
            goal: .muscleGain,
            weightliftingDays: 4,
            cardioDays: 0,
            splitType: .upperLower,
            targetSessionDuration: 60,
            trainingLocation: .gym,
            compoundTimeAllocation: 0.6,
            isolationApproach: .volumeAccumulation,
            preferredDays: [.monday, .tuesday, .thursday, .friday],
            startDate: calendar.date(byAdding: .day, value: -7, to: today)!,
            endDate: calendar.date(byAdding: .month, value: 2, to: today)!
        )

        let draftProgram = Program(
            id: draftProgramId,
            planId: draftPlanId,
            name: "Draft Program",
            focus: .development,
            rationale: "Test",
            startDate: calendar.date(byAdding: .day, value: -7, to: today)!,
            endDate: calendar.date(byAdding: .month, value: 2, to: today)!,
            startingIntensity: 0.70,
            endingIntensity: 0.80,
            progressionType: .linear,
            status: .active
        )

        // Missed workout from DRAFT plan (scheduled 2 days ago, not completed)
        let draftMissedWorkout = Workout(
            id: draftMissedWorkoutId,
            programId: draftProgramId,
            name: "Draft Missed Workout",
            scheduledDate: twoDaysAgo,
            type: .strength,
            splitDay: .upper,
            status: .scheduled,  // Still scheduled = missed
            completedDate: nil,
            exerciseIds: ["barbell_overhead_press"],
            protocolVariantIds: [0: "strength_3x5_moderate"],
            exercisesSelectedAt: Date(),
            supersetGroups: nil,
            protocolCustomizations: nil
        )

        // Register in TestDataManager
        TestDataManager.shared.plans[activePlanId] = activePlan
        TestDataManager.shared.plans[draftPlanId] = draftPlan
        TestDataManager.shared.programs[activeProgramId] = activeProgram
        TestDataManager.shared.programs[draftProgramId] = draftProgram
        TestDataManager.shared.workouts[activeMissedWorkoutId] = activeMissedWorkout
        TestDataManager.shared.workouts[draftMissedWorkoutId] = draftMissedWorkout

        // When: Building current context
        let context = UserContextBuilder.buildCurrentContext(for: testUser)

        // Then: "Missed Workouts" section should include ACTIVE workout ID
        XCTAssertTrue(context.contains(activeMissedWorkoutId),
            "Context should include active plan's missed workout ID '\(activeMissedWorkoutId)'")

        // And: Should NOT include draft workout ID
        XCTAssertFalse(context.contains(draftMissedWorkoutId),
            "Context should NOT include draft plan's missed workout ID '\(draftMissedWorkoutId)'")
    }

    /// Test: When no active plan exists, no "Missed Workouts" should appear
    func testBuildCurrentContext_NoMissedWorkouts_WhenOnlyDraftPlan() throws {
        // Given: User with ONLY a draft plan having missed workouts
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!

        let draftPlanId = "test_draft_only_missed_plan"
        let draftProgramId = "test_draft_only_missed_program"
        let draftMissedWorkoutId = "test_draft_only_missed_workout"

        let draftPlan = Plan(
            id: draftPlanId,
            memberId: testUser.id,
            isSingleWorkout: false,
            status: .draft,
            name: "Draft Only Plan",
            description: "Draft plan for testing",
            goal: .muscleGain,
            weightliftingDays: 4,
            cardioDays: 0,
            splitType: .upperLower,
            targetSessionDuration: 60,
            trainingLocation: .gym,
            compoundTimeAllocation: 0.6,
            isolationApproach: .volumeAccumulation,
            preferredDays: [.monday, .tuesday, .thursday, .friday],
            startDate: calendar.date(byAdding: .day, value: -7, to: today)!,
            endDate: calendar.date(byAdding: .month, value: 2, to: today)!
        )

        let draftProgram = Program(
            id: draftProgramId,
            planId: draftPlanId,
            name: "Draft Program",
            focus: .development,
            rationale: "Test",
            startDate: calendar.date(byAdding: .day, value: -7, to: today)!,
            endDate: calendar.date(byAdding: .month, value: 2, to: today)!,
            startingIntensity: 0.70,
            endingIntensity: 0.80,
            progressionType: .linear,
            status: .active
        )

        let draftMissedWorkout = Workout(
            id: draftMissedWorkoutId,
            programId: draftProgramId,
            name: "Draft Only Missed Workout",
            scheduledDate: twoDaysAgo,
            type: .strength,
            splitDay: .upper,
            status: .scheduled,
            completedDate: nil,
            exerciseIds: ["barbell_overhead_press"],
            protocolVariantIds: [0: "strength_3x5_moderate"],
            exercisesSelectedAt: Date(),
            supersetGroups: nil,
            protocolCustomizations: nil
        )

        // Register in TestDataManager
        TestDataManager.shared.plans[draftPlanId] = draftPlan
        TestDataManager.shared.programs[draftProgramId] = draftProgram
        TestDataManager.shared.workouts[draftMissedWorkoutId] = draftMissedWorkout

        // When: Building current context
        let context = UserContextBuilder.buildCurrentContext(for: testUser)

        // Then: Context should NOT include "Missed Workouts" section
        XCTAssertFalse(context.contains("Missed Workouts"),
            "Context should NOT include 'Missed Workouts' when only draft plans exist")
        XCTAssertFalse(context.contains(draftMissedWorkoutId),
            "Context should NOT include draft plan's missed workout ID '\(draftMissedWorkoutId)'")
    }

    // MARK: - v157: Active Session Context Tests

    /// v157: When there's an active session, context should include it with workout ID
    /// This allows AI to respond to "continue workout" with the correct workout ID
    func testBuildCurrentContext_WithActiveSession_IncludesSessionInfo() throws {
        // Given: User with an active session
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Create active plan and workout
        let planId = "test_session_plan"
        let programId = "test_session_program"
        let workoutId = "test_session_workout"

        let plan = Plan(
            id: planId,
            memberId: testUser.id,
            isSingleWorkout: false,
            status: .active,
            name: "Session Test Plan",
            description: "Plan for testing session context",
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
            name: "Session Test Program",
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
            name: "Active Session Workout",
            scheduledDate: today,
            type: .strength,
            splitDay: .fullBody,
            status: .inProgress,
            completedDate: nil,
            exerciseIds: ["barbell_bench_press", "barbell_back_squat"],
            protocolVariantIds: [0: "strength_3x5_moderate", 1: "strength_3x5_moderate"],
            exercisesSelectedAt: Date(),
            supersetGroups: nil,
            protocolCustomizations: nil
        )

        // Create active session
        let session = Session(
            id: "test_session_id",
            workoutId: workoutId,
            memberId: testUser.id,
            startTime: Date(),
            status: .active
        )

        // Register in TestDataManager
        TestDataManager.shared.plans[planId] = plan
        TestDataManager.shared.programs[programId] = program
        TestDataManager.shared.workouts[workoutId] = workout
        TestDataManager.shared.sessions[session.id] = session

        // When: Building current context
        let context = UserContextBuilder.buildCurrentContext(for: testUser)

        // Then: Context should include ACTIVE SESSION info
        XCTAssertTrue(context.contains("ACTIVE SESSION"),
            "Context should include 'ACTIVE SESSION' when there's an active session")
        XCTAssertTrue(context.contains(workoutId),
            "Context should include the workout ID '\(workoutId)'")
        XCTAssertTrue(context.contains("Active Session Workout"),
            "Context should include the workout name")

        // And: Should have directive to use start_workout with correct ID
        XCTAssertTrue(context.contains("start_workout(workoutId: \"\(workoutId)\")"),
            "Context should include start_workout directive with correct workout ID")

        // Cleanup
        TestDataManager.shared.sessions.removeValue(forKey: session.id)
    }

    /// v157: When there's NO active session or in-progress workout, context should say so
    /// This prevents AI from guessing workout IDs when user says "continue workout"
    func testBuildCurrentContext_NoActiveSession_ExplicitlyStatesNoWorkoutInProgress() throws {
        // Given: User with NO active session and NO in-progress workout
        // (testUser starts fresh with no sessions)

        // When: Building current context
        let context = UserContextBuilder.buildCurrentContext(for: testUser)

        // Then: Context should explicitly state there's no workout in progress
        XCTAssertTrue(context.contains("NO WORKOUT IN PROGRESS"),
            "Context should include 'NO WORKOUT IN PROGRESS' when no session exists. Context: \(context)")

        // And: Should have directive to NOT call start_workout with guessed ID
        XCTAssertTrue(context.contains("DO NOT call start_workout with a guessed ID"),
            "Context should warn AI not to guess workout IDs")
    }

    /// v157: Regression test - AI was calling start_workout with fabricated ID when user said "continue"
    /// Bug: User says "Continue workout" → AI calls start_workout(workoutId: "bobby_20251215_fullbody")
    ///      which doesn't exist, leading to "no workout scheduled" response
    /// Expected: AI should see "NO WORKOUT IN PROGRESS" and respond with text, not a tool call
    func testBuildCurrentContext_NoActiveSession_PreventsFabricatedWorkoutId() throws {
        // Given: User with NO active session
        // When: Building current context
        let context = UserContextBuilder.buildCurrentContext(for: testUser)

        // Then: Context should have explicit instruction about "continue workout"
        XCTAssertTrue(context.contains("continue workout") || context.contains("continue\""),
            "Context should mention 'continue' scenario. Context: \(context)")

        // And: Should tell AI to respond with text, not a tool call
        XCTAssertTrue(context.contains("respond with text") || context.contains("explain there's nothing to continue"),
            "Context should tell AI to respond with text explanation")
    }
}
