//
// AIIntegrationTests.swift
// MedinaTests
//
// AI Integration Tests - calls real OpenAI API to validate AI behavior
// Created: December 4, 2025
// v106.4: Added class filter inference regression test
//
// These tests validate:
// - Profile-aware behavior (AI uses profile data, doesn't re-ask)
// - New user handling (AI asks for required info when missing)
// - Tool execution (correct tools called with correct params)
// - Class listing does NOT infer filters from profile (v106.4 regression)
//
// Cost: ~$0.01-0.05 per test run (uses gpt-4o-mini)
// Note: Tests may be flaky due to AI response variability
//

import XCTest
@testable import Medina

@MainActor
class AIIntegrationTests: XCTestCase {

    // MARK: - Properties

    var testRunner: AITestRunner!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        TestDataManager.shared.resetAndReload()
        testRunner = AITestRunner()
    }

    override func tearDown() async throws {
        testRunner.reset()
        TestDataManager.shared.reset()
        try await super.tearDown()
    }

    // MARK: - Test 0: API Connection Diagnostic

    /// Simple test to verify API connection works and log raw response
    func test0_APIConnectionDiagnostic() async throws {
        // Given: User with full profile
        let user = AITestUsers.userWithFullProfile()
        try await testRunner.initialize(for: user)

        // When: Sending simple message
        let response = try await testRunner.sendMessage("Hello, what can you help me with?")

        // Then: Should get a response (any response)
        XCTAssertNil(response.error, "Should not have error: \(response.error?.localizedDescription ?? "none")")
        XCTAssertFalse(response.text.isEmpty, "Should have response text. Got empty response.")

        // Log for manual inspection
        print("=== AI DIAGNOSTIC RESPONSE ===")
        print("Text length: \(response.text.count)")
        print("Text preview: \(response.text.prefix(300))")
        print("Tool calls: \(response.toolCalls.map { $0.name })")
        print("Response ID: \(response.responseId ?? "nil")")
        print("==============================")
    }

    // MARK: - Test 1: Profile-Aware Plan Creation

    /// AI should use profile data and NOT ask for experience level, schedule, duration
    /// Note: AI may ask follow-up questions about goals/preferences (that's fine)
    /// Key behavior: AI should NOT re-ask for data that's already in profile
    func testProfileAwarePlanCreation() async throws {
        // Given: User with full profile (intermediate, Mon-Fri, 60 min)
        let user = AITestUsers.userWithFullProfile()
        try await testRunner.initialize(for: user)

        // When: Asking to create a plan with specific goal
        let response = try await testRunner.sendMessage("Create a muscle gain plan for me. Start immediately.")

        // Check for errors first
        if let error = response.error {
            XCTFail("API Error: \(error.localizedDescription)")
            return
        }

        // Log for debugging (visible in Xcode console when running tests)
        Logger.log(.info, component: "AIIntegrationTests",
            message: """
            📝 AI Response: \(response.text.prefix(500))...
            🔧 Tool calls: \(response.toolCalls.map { $0.name })
            """)

        // Then: AI should NOT ask for profile information (schedule, experience, duration)
        // These are the things that ARE in the profile already
        let doesNotReask = response.assertDoesNotAskFor(AITestResponse.profileReaskPhrases)
        XCTAssertTrue(doesNotReask,
            "AI should NOT ask for profile data (schedule/experience/duration). Response: \(response.text.prefix(200))")

        // Note: We don't require create_plan to be called immediately - AI may:
        // - Call create_plan (ideal)
        // - Ask about goal specifics (acceptable)
        // - Confirm understanding (acceptable)
        // The key test is that it doesn't re-ask for profile data it already has
        if response.toolWasCalled("create_plan") {
            print("✅ AI called create_plan tool")
        } else {
            print("ℹ️ AI didn't call create_plan yet (may need follow-up). Tools: \(response.toolCalls.map { $0.name })")
        }
    }

    // MARK: - Test 2: New User Needs Experience Level

    /// AI should ASK for experience level when not set (required for plan creation)
    func testNewUserNeedsExperienceLevel() async throws {
        // Given: New user with no experience level set
        let user = AITestUsers.newUserMinimalProfile()
        try await testRunner.initialize(for: user)

        // When: Asking to create a plan
        let response = try await testRunner.sendMessage("Create a workout plan for me")

        // Log response for debugging
        print("📝 AI Response:\n\(response.text)")
        print("🔧 Tool calls: \(response.toolCalls.map { $0.name })")

        // Then: AI should ASK for experience level (it's required)
        let asksForExperience = response.assertContains([
            "experience",
            "beginner",
            "intermediate",
            "advanced",
            "how long have you been"
        ])

        // Either asks for experience OR creates plan with clarifying question
        // (AI may choose to ask vs assume)
        let createdPlan = response.toolWasCalled("create_plan")

        XCTAssertTrue(asksForExperience || !createdPlan,
            "AI should ask for experience level OR not create plan yet. Response: \(response.text)")
    }

    // MARK: - Test 3: Home Equipment Awareness

    /// AI should use configured home equipment, not ask again
    func testHomeEquipmentAwareness() async throws {
        // Given: User with home equipment configured (dumbbells, pull-up bar)
        let user = AITestUsers.userWithHomeEquipment()
        try await testRunner.initialize(for: user)

        // When: Asking for a home workout
        let response = try await testRunner.sendMessage("Create a home workout for tomorrow")

        // Log response for debugging
        print("📝 AI Response:\n\(response.text)")
        print("🔧 Tool calls: \(response.toolCalls.map { $0.name })")

        // Then: AI should NOT ask about equipment
        let doesNotAskEquipment = response.assertDoesNotAskFor(AITestResponse.equipmentAskPhrases)
        XCTAssertTrue(doesNotAskEquipment,
            "AI should NOT ask about equipment (it's configured). Response: \(response.text)")

        // And: AI should call create_workout tool
        XCTAssertTrue(response.toolWasCalled("create_workout"),
            "AI should call create_workout tool. Tools called: \(response.toolCalls.map { $0.name })")
    }

    // MARK: - Test 4: Workout Creation with Date Parsing

    /// AI should parse relative date and call create_workout with correct date
    func testWorkoutCreationWithDateParsing() async throws {
        // Given: User with full profile
        let user = AITestUsers.userWithFullProfile()
        try await testRunner.initialize(for: user)

        // When: Asking to create workout for "tomorrow"
        let response = try await testRunner.sendMessage("Create an upper body workout for tomorrow")

        // Log response for debugging
        print("📝 AI Response:\n\(response.text)")
        print("🔧 Tool calls: \(response.toolCalls.map { $0.name })")

        // Then: AI should call create_workout
        XCTAssertTrue(response.toolWasCalled("create_workout"),
            "AI should call create_workout tool")

        // And: Arguments should have correct date (tomorrow)
        if let args = response.argumentsFor("create_workout"),
           let scheduledDate = args["scheduledDate"] as? String {

            // Calculate expected tomorrow date
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            let expectedDate = String(formatter.string(from: tomorrow).prefix(10))

            XCTAssertEqual(scheduledDate, expectedDate,
                "Scheduled date should be tomorrow (\(expectedDate)), got: \(scheduledDate)")
        }

        // And: Should have upper split day
        if let args = response.argumentsFor("create_workout"),
           let splitDay = args["splitDay"] as? String {
            XCTAssertEqual(splitDay, "upper",
                "Split day should be 'upper', got: \(splitDay)")
        }
    }

    // MARK: - Test 5: Profile Confirmation in Response

    /// AI should show awareness of profile data in its response
    /// This is a SOFT test - validates good coach behavior but not critical
    func testProfileConfirmationInResponse() async throws {
        // Given: User with full profile
        let user = AITestUsers.userWithFullProfile()
        try await testRunner.initialize(for: user)

        // When: Asking to create a plan with explicit instruction
        let response = try await testRunner.sendMessage("Create a strength training plan based on my profile")

        // Log response for debugging
        print("📝 AI Response:\n\(response.text)")
        print("🔧 Tool calls: \(response.toolCalls.map { $0.name })")

        // Check for errors first
        if let error = response.error {
            XCTFail("API Error: \(error.localizedDescription)")
            return
        }

        // Then: Response should mention using profile data (good coach behavior)
        let confirmsProfile = response.assertContains([
            "your schedule",
            "your profile",
            "monday",
            "tuesday",
            "wednesday",
            "60 minute",
            "intermediate",
            "5 days",
            "five days",
            "profile"
        ])

        // This is a soft check - AI should ideally confirm but it's not critical
        if confirmsProfile {
            print("✅ AI confirmed profile data")
        } else {
            print("ℹ️ AI didn't explicitly confirm profile data (acceptable)")
        }

        // Check tool was called OR AI is ready to proceed
        // AI may ask for goal clarification even with full profile
        let calledTool = response.toolWasCalled("create_plan")
        let isReady = response.assertContains(["creating", "created", "plan", "ready", "sure", "will"])

        XCTAssertTrue(calledTool || isReady,
            "AI should either call create_plan OR indicate readiness. Response: \(response.text.prefix(200))")
    }

    // v186: Removed class booking tests (class booking deferred for beta)
    // - testClassListingDoesNotInferFiltersFromProfile
    // - testBookAClassChipDoesNotInferFilters
}
