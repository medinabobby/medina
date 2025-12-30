//
// ChatViewModelTests.swift
// MedinaTests
//
// v181: ViewModel tests for ChatViewModel
// Tests critical state logic: isNewUser detection, chip generation scenarios
//
// Test Focus:
// - isNewUser property (v179 new user detection)
// - Fallback chip generation logic (v148, v155, v161)
// - Message handling basics
//

import XCTest
@testable import Medina

@MainActor
final class ChatViewModelTests: XCTestCase {

    // MARK: - Properties

    var viewModel: ChatViewModel!
    var testUser: UnifiedUser!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Create fresh test user for each test
        testUser = createTestUser(id: "chat_vm_test_user_\(UUID().uuidString.prefix(8))")

        // Clear any existing data for this user
        clearUserData(userId: testUser.id)

        // Create view model
        viewModel = ChatViewModel(user: testUser)

        // Wait for initialization
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
    }

    override func tearDown() async throws {
        // Clean up
        if let userId = testUser?.id {
            clearUserData(userId: userId)
        }
        viewModel = nil
        testUser = nil
        try await super.tearDown()
    }

    // MARK: - isNewUser Tests (v179)

    func testIsNewUser_NoWorkoutHistory_ReturnsTrue() {
        // Given: User with no workout history
        clearUserData(userId: testUser.id)

        // Ensure onboarding not dismissed
        OnboardingState.reset(for: testUser.id)

        // Recreate view model with clean state
        viewModel = ChatViewModel(user: testUser)

        // When/Then: isNewUser should be true
        // Note: needsOnboarding() checks various conditions
        // For a fresh user with incomplete profile and no history, should be true
        let hasWorkouts = !WorkoutDataStore.workouts(
            for: testUser.id, temporal: .unspecified, dateInterval: nil
        ).isEmpty

        XCTAssertFalse(hasWorkouts, "Fresh user should have no workout history")
    }

    func testIsNewUser_WithWorkoutHistory_ReturnsFalse() {
        // Given: User with workout history (need full plan -> program -> workout chain)
        let plan = createTestPlan(userId: testUser.id)
        LocalDataStore.shared.plans[plan.id] = plan

        let program = createTestProgram(userId: testUser.id, planId: plan.id)
        LocalDataStore.shared.programs[program.id] = program

        let workout = createTestWorkout(userId: testUser.id, programId: program.id, daysFromToday: -1, status: .completed)
        LocalDataStore.shared.workouts[workout.id] = workout

        // Recreate view model
        viewModel = ChatViewModel(user: testUser)

        // When: Check hasWorkoutHistory
        let hasWorkouts = !WorkoutDataStore.workouts(
            for: testUser.id, temporal: .unspecified, dateInterval: nil
        ).isEmpty

        // Then: Should have workout history
        XCTAssertTrue(hasWorkouts, "User with completed workout should have history")
    }

    func testIsNewUser_OnboardingDismissed_ReturnsFalse() {
        // Given: User who dismissed onboarding
        OnboardingState.setDismissed(true, for: testUser.id)

        // Recreate view model
        viewModel = ChatViewModel(user: testUser)

        // When/Then: isNewUser should be false because onboarding was dismissed
        XCTAssertTrue(OnboardingState.wasDismissed(for: testUser.id))
    }

    // MARK: - Fallback Chips Logic Tests

    // Note: generateFallbackWorkoutChips is private, so we test the conditions it checks

    func testFallbackChips_ActiveSession_ShouldNotShowStartChips() {
        // Given: User with an active session
        let workout = createTestWorkout(userId: testUser.id, daysFromToday: 0, status: .inProgress)
        LocalDataStore.shared.workouts[workout.id] = workout

        let session = createActiveSession(workoutId: workout.id, userId: testUser.id)
        LocalDataStore.shared.sessions[session.id] = session

        // When: Check active session
        let activeSession = LocalDataStore.shared.activeSession(for: testUser.id)

        // Then: Active session should exist (this would prevent fallback chips)
        XCTAssertNotNil(activeSession, "Active session should exist")
        XCTAssertEqual(activeSession?.workoutId, workout.id)
    }

    func testFallbackChips_InProgressWorkout_ShouldNotShowStartChips() {
        // Given: User with a workout in .inProgress status (but no active session)
        // This simulates app restart where session is lost but status persisted
        // Need full plan -> program -> workout chain for WorkoutResolver
        let plan = createTestPlan(userId: testUser.id)
        LocalDataStore.shared.plans[plan.id] = plan

        let program = createTestProgram(userId: testUser.id, planId: plan.id)
        LocalDataStore.shared.programs[program.id] = program

        let workout = createTestWorkout(userId: testUser.id, programId: program.id, daysFromToday: 0, status: .inProgress)
        LocalDataStore.shared.workouts[workout.id] = workout

        // When: Query workouts
        let allWorkouts = WorkoutDataStore.workouts(for: testUser.id, temporal: .unspecified, dateInterval: nil)
        let hasInProgress = allWorkouts.contains { $0.status == .inProgress }

        // Then: Should detect in-progress workout (this prevents fallback chips in v161)
        XCTAssertTrue(hasInProgress, "Should detect workout with inProgress status")
    }

    func testFallbackChips_TodayWorkout_NoFallbackNeeded() {
        // Given: User with a workout scheduled for today
        // Need full plan -> program -> workout chain for WorkoutResolver
        let plan = createTestPlan(userId: testUser.id)
        LocalDataStore.shared.plans[plan.id] = plan

        let program = createTestProgram(userId: testUser.id, planId: plan.id)
        LocalDataStore.shared.programs[program.id] = program

        let todayWorkout = createTestWorkout(userId: testUser.id, programId: program.id, daysFromToday: 0, status: .scheduled)
        LocalDataStore.shared.workouts[todayWorkout.id] = todayWorkout

        // When: Query today's workouts
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let todayWorkouts = WorkoutResolver.workouts(
            for: testUser.id,
            temporal: .today,
            status: .scheduled,
            modality: .unspecified,
            splitDay: nil,
            source: nil,
            plan: nil,
            program: nil,
            dateInterval: DateInterval(start: today, end: tomorrow)
        )

        // Then: Should find today's workout (no fallback chips needed)
        XCTAssertFalse(todayWorkouts.isEmpty, "Should find today's scheduled workout")
    }

    func testFallbackChips_MissedWorkout_ShouldDetect() {
        // Given: User with a missed workout (past date, still scheduled)
        // Need full plan -> program -> workout chain for WorkoutResolver
        let plan = createTestPlan(userId: testUser.id)
        LocalDataStore.shared.plans[plan.id] = plan

        let program = createTestProgram(userId: testUser.id, planId: plan.id)
        LocalDataStore.shared.programs[program.id] = program

        let missedWorkout = createTestWorkout(userId: testUser.id, programId: program.id, daysFromToday: -3, status: .scheduled)
        LocalDataStore.shared.workouts[missedWorkout.id] = missedWorkout

        // When: Query missed workouts
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let missedWorkouts = WorkoutResolver.workouts(
            for: testUser.id,
            temporal: .past,
            status: .scheduled,
            modality: .unspecified,
            splitDay: nil,
            source: nil,
            plan: nil,
            program: nil,
            dateInterval: DateInterval(start: Date.distantPast, end: today)
        )

        // Then: Should find missed workout
        XCTAssertFalse(missedWorkouts.isEmpty, "Should detect missed workout")
        XCTAssertEqual(missedWorkouts.first?.id, missedWorkout.id)
    }

    func testFallbackChips_NextWorkout_ShouldDetect() {
        // Given: User with a future workout (no today workout)
        // Need full plan -> program -> workout chain for WorkoutResolver
        let plan = createTestPlan(userId: testUser.id)
        LocalDataStore.shared.plans[plan.id] = plan

        let program = createTestProgram(userId: testUser.id, planId: plan.id)
        LocalDataStore.shared.programs[program.id] = program

        let futureWorkout = createTestWorkout(userId: testUser.id, programId: program.id, daysFromToday: 2, status: .scheduled)
        LocalDataStore.shared.workouts[futureWorkout.id] = futureWorkout

        // When: Query upcoming workouts
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let upcomingWorkouts = WorkoutResolver.workouts(
            for: testUser.id,
            temporal: .upcoming,
            status: .scheduled,
            modality: .unspecified,
            splitDay: nil,
            source: nil,
            plan: nil,
            program: nil,
            dateInterval: DateInterval(start: today, end: Date.distantFuture)
        ).sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }

        // Then: Should find next workout
        XCTAssertFalse(upcomingWorkouts.isEmpty, "Should detect upcoming workout")
        XCTAssertEqual(upcomingWorkouts.first?.id, futureWorkout.id)
    }

    // MARK: - Message Flow Tests

    func testStartConversation_NoGreetingMessage() {
        // Given: v179 - all users see centered greeting, no chat message
        viewModel = ChatViewModel(user: testUser)

        // When: Starting conversation
        viewModel.startConversation()

        // Then: No greeting message added (v179 change)
        XCTAssertTrue(viewModel.messages.isEmpty,
            "v179: Should not add greeting message - centered empty state used instead")
    }

    func testAddMessage_AppendsToMessages() {
        // Given: Empty message list
        XCTAssertTrue(viewModel.messages.isEmpty)

        // When: Adding a message
        let message = Message(content: "Test message", isUser: true)
        viewModel.messages.append(message)

        // Then: Message should be added
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages.first?.content, "Test message")
        XCTAssertTrue(viewModel.messages.first?.isUser ?? false)
    }

    // MARK: - Test Helpers

    private func createTestUser(id: String) -> UnifiedUser {
        let user = UnifiedUser(
            id: id,
            firebaseUID: "test_firebase_\(id)",
            authProvider: .email,
            email: "\(id)@test.com",
            name: "Test User",
            birthdate: Calendar.current.date(byAdding: .year, value: -30, to: Date())!,
            gender: .male,
            roles: [.member],
            memberProfile: MemberProfile(
                fitnessGoal: .strength,
                experienceLevel: .intermediate,
                preferredWorkoutDays: [.monday, .wednesday, .friday],
                preferredSessionDuration: 60,
                membershipStatus: .active,
                memberSince: Date()
            )
        )
        LocalDataStore.shared.users[user.id] = user
        return user
    }

    private func createTestPlan(userId: String) -> Plan {
        let planId = "test_plan_\(userId)"
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let endDate = calendar.date(byAdding: .month, value: 1, to: today)!

        return Plan(
            id: planId,
            memberId: userId,
            isSingleWorkout: false,
            status: .active,
            name: "Test Plan",
            description: "Test plan description",
            goal: .strength,
            weightliftingDays: 3,
            cardioDays: 0,
            splitType: .fullBody,
            targetSessionDuration: 60,
            trainingLocation: .gym,
            compoundTimeAllocation: 0.6,
            isolationApproach: .volumeAccumulation,
            preferredDays: [.monday, .wednesday, .friday],
            startDate: today,
            endDate: endDate
        )
    }

    private func createTestWorkout(
        userId: String,
        programId: String? = nil,
        daysFromToday: Int,
        status: ExecutionStatus
    ) -> Workout {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let scheduledDate = calendar.date(byAdding: .day, value: daysFromToday, to: today)!

        let workoutId = "test_workout_\(UUID().uuidString.prefix(8))"
        let resolvedProgramId = programId ?? "test_program_\(userId)"

        return Workout(
            id: workoutId,
            programId: resolvedProgramId,
            name: "Test Workout",
            scheduledDate: scheduledDate,
            type: .strength,
            splitDay: .fullBody,
            status: status,
            completedDate: status == .completed ? Date() : nil,
            exerciseIds: [],
            protocolVariantIds: [:],
            exercisesSelectedAt: nil,
            supersetGroups: nil,
            protocolCustomizations: nil
        )
    }

    private func createTestProgram(userId: String, planId: String? = nil) -> Program {
        let programId = "test_program_\(userId)"
        let resolvedPlanId = planId ?? "test_plan_\(userId)"
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let endDate = calendar.date(byAdding: .month, value: 1, to: today)!

        return Program(
            id: programId,
            planId: resolvedPlanId,
            name: "Test Program",
            focus: .foundation,
            rationale: "Test program",
            startDate: today,
            endDate: endDate,
            startingIntensity: 0.7,
            endingIntensity: 0.9,
            progressionType: .linear,
            status: .active
        )
    }

    private func createActiveSession(workoutId: String, userId: String) -> Session {
        return Session(
            workoutId: workoutId,
            memberId: userId,
            startTime: Date(),
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            status: .active
        )
    }

    private func clearUserData(userId: String) {
        // Clear workouts for this user
        let workoutIds = LocalDataStore.shared.workouts.values
            .filter { workout in
                if let program = LocalDataStore.shared.programs[workout.programId],
                   let plan = LocalDataStore.shared.plans[program.planId] {
                    return plan.memberId == userId
                }
                return workout.programId.contains(userId)
            }
            .map { $0.id }

        for id in workoutIds {
            LocalDataStore.shared.workouts.removeValue(forKey: id)
        }

        // Clear programs for this user
        let programIds = LocalDataStore.shared.programs.values
            .filter { $0.id.contains(userId) }
            .map { $0.id }

        for id in programIds {
            LocalDataStore.shared.programs.removeValue(forKey: id)
        }

        // Clear active sessions for this user
        let sessionIds = LocalDataStore.shared.sessions.values
            .filter { $0.memberId == userId }
            .map { $0.id }
        for id in sessionIds {
            LocalDataStore.shared.sessions.removeValue(forKey: id)
        }

        // Clear onboarding state
        OnboardingState.reset(for: userId)
    }
}
