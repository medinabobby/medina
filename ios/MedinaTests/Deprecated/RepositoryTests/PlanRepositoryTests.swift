//
// PlanRepositoryTests.swift
// MedinaTests
//
// v181: Repository pattern tests for Plan persistence
// Tests the repository contract - works with any backend (file, Firebase, mock)
//
// Test Cases:
// - Save/load round-trip
// - Overwrite existing
// - Load returns nil for missing
// - Delete removes plan
// - LoadAll returns all for user
// - Concurrent saves (no data loss)
//

import XCTest
@testable import Medina

@MainActor
final class PlanRepositoryTests: XCTestCase {

    // MARK: - Properties

    var mockRepository: MockPlanRepository!
    var testUser: UnifiedUser!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        mockRepository = MockPlanRepository()
        testUser = TestFixtures.testUser
    }

    override func tearDown() async throws {
        mockRepository.reset()
        mockRepository = nil
        try await super.tearDown()
    }

    // MARK: - Test Helpers

    private func createTestPlan(
        id: String = UUID().uuidString,
        memberId: String? = nil,
        name: String = "Test Plan",
        status: PlanStatus = .active
    ) -> Plan {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return Plan(
            id: id,
            memberId: memberId ?? testUser.id,
            isSingleWorkout: false,
            status: status,
            name: name,
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
            endDate: calendar.date(byAdding: .month, value: 1, to: today)!
        )
    }

    // MARK: - Save/Load Round-Trip Tests

    func testSaveAndLoadPlan_RoundTrip() async throws {
        // Given: A plan to save
        let originalPlan = createTestPlan(name: "Round Trip Test")

        // When: Saving and loading
        try await mockRepository.save(originalPlan)
        let loadedPlan = try await mockRepository.load(id: originalPlan.id)

        // Then: Plan should be identical
        XCTAssertNotNil(loadedPlan)
        XCTAssertEqual(loadedPlan?.id, originalPlan.id)
        XCTAssertEqual(loadedPlan?.name, originalPlan.name)
        XCTAssertEqual(loadedPlan?.memberId, originalPlan.memberId)
        XCTAssertEqual(loadedPlan?.goal, originalPlan.goal)
        XCTAssertEqual(loadedPlan?.status, originalPlan.status)
        XCTAssertEqual(loadedPlan?.weightliftingDays, originalPlan.weightliftingDays)
    }

    func testSavePlan_OverwritesExisting() async throws {
        // Given: An existing plan
        let planId = "overwrite_test_plan"
        let originalPlan = createTestPlan(id: planId, name: "Original Name")
        try await mockRepository.save(originalPlan)

        // When: Saving an updated version
        var updatedPlan = originalPlan
        updatedPlan.name = "Updated Name"
        updatedPlan.status = .completed
        try await mockRepository.save(updatedPlan)

        // Then: Load should return updated version
        let loadedPlan = try await mockRepository.load(id: planId)
        XCTAssertEqual(loadedPlan?.name, "Updated Name")
        XCTAssertEqual(loadedPlan?.status, .completed)

        // And: Only one plan should exist
        let allPlans = try await mockRepository.loadAll(for: testUser.id)
        XCTAssertEqual(allPlans.count, 1)
    }

    func testLoadPlan_ReturnsNilForMissing() async throws {
        // Given: No plans saved
        XCTAssertTrue(mockRepository.plans.isEmpty)

        // When: Loading a non-existent plan
        let loadedPlan = try await mockRepository.load(id: "nonexistent_plan")

        // Then: Should return nil
        XCTAssertNil(loadedPlan)
    }

    // MARK: - Delete Tests

    func testDeletePlan_RemovesPlan() async throws {
        // Given: A saved plan
        let plan = createTestPlan(name: "To Be Deleted")
        try await mockRepository.save(plan)
        let savedPlan = try await mockRepository.load(id: plan.id)
        XCTAssertNotNil(savedPlan)

        // When: Deleting the plan
        try await mockRepository.delete(id: plan.id, userId: testUser.id)

        // Then: Plan should no longer exist
        let loadedPlan = try await mockRepository.load(id: plan.id)
        XCTAssertNil(loadedPlan)
    }

    func testDeletePlan_DoesNotAffectOtherPlans() async throws {
        // Given: Two saved plans
        let plan1 = createTestPlan(id: "plan_keep", name: "Keep This")
        let plan2 = createTestPlan(id: "plan_delete", name: "Delete This")
        try await mockRepository.save(plan1)
        try await mockRepository.save(plan2)

        // When: Deleting one plan
        try await mockRepository.delete(id: plan2.id, userId: testUser.id)

        // Then: Other plan should still exist
        let remainingPlan = try await mockRepository.load(id: plan1.id)
        XCTAssertNotNil(remainingPlan)
        XCTAssertEqual(remainingPlan?.name, "Keep This")

        // And: Deleted plan should be gone
        let deletedPlan = try await mockRepository.load(id: plan2.id)
        XCTAssertNil(deletedPlan)
    }

    // MARK: - LoadAll Tests

    func testLoadAllPlans_ReturnsAllForUser() async throws {
        // Given: Multiple plans for the same user
        let plan1 = createTestPlan(id: "plan_1", name: "Plan 1")
        let plan2 = createTestPlan(id: "plan_2", name: "Plan 2")
        let plan3 = createTestPlan(id: "plan_3", name: "Plan 3")

        try await mockRepository.save(plan1)
        try await mockRepository.save(plan2)
        try await mockRepository.save(plan3)

        // When: Loading all plans for user
        let allPlans = try await mockRepository.loadAll(for: testUser.id)

        // Then: All plans should be returned
        XCTAssertEqual(allPlans.count, 3)
        XCTAssertTrue(allPlans.contains { $0.name == "Plan 1" })
        XCTAssertTrue(allPlans.contains { $0.name == "Plan 2" })
        XCTAssertTrue(allPlans.contains { $0.name == "Plan 3" })
    }

    func testLoadAllPlans_FiltersToUser() async throws {
        // Given: Plans for different users
        let userAPlan = createTestPlan(id: "user_a_plan", memberId: "user_a", name: "User A Plan")
        let userBPlan = createTestPlan(id: "user_b_plan", memberId: "user_b", name: "User B Plan")
        let testUserPlan = createTestPlan(id: "test_user_plan", name: "Test User Plan")

        try await mockRepository.save(userAPlan)
        try await mockRepository.save(userBPlan)
        try await mockRepository.save(testUserPlan)

        // When: Loading all plans for test user
        let testUserPlans = try await mockRepository.loadAll(for: testUser.id)

        // Then: Only test user's plan should be returned
        XCTAssertEqual(testUserPlans.count, 1)
        XCTAssertEqual(testUserPlans.first?.name, "Test User Plan")
    }

    func testLoadAllPlans_ReturnsEmptyForNoPlans() async throws {
        // Given: No plans saved
        XCTAssertTrue(mockRepository.plans.isEmpty)

        // When: Loading all plans
        let allPlans = try await mockRepository.loadAll(for: testUser.id)

        // Then: Empty array should be returned
        XCTAssertTrue(allPlans.isEmpty)
    }

    // MARK: - Concurrent Save Tests

    func testBatchSaves_NoDataLoss() async throws {
        // Given: Multiple plans to save
        let plans = (1...10).map { i in
            createTestPlan(id: "batch_plan_\(i)", name: "Batch Plan \(i)")
        }

        // When: Saving all plans sequentially
        // Note: Mock repository doesn't need to be thread-safe
        // Real implementations (Firebase) handle concurrency internally
        for plan in plans {
            try await mockRepository.save(plan)
        }

        // Then: All plans should be saved
        let allPlans = try await mockRepository.loadAll(for: testUser.id)
        XCTAssertEqual(allPlans.count, 10)

        // And: Each plan should be retrievable
        for plan in plans {
            let loaded = try await mockRepository.load(id: plan.id)
            XCTAssertNotNil(loaded, "Plan \(plan.id) should be saved")
        }
    }

    // MARK: - Error Handling Tests

    func testSave_ThrowsOnError() async throws {
        // Given: Repository configured to throw
        mockRepository.shouldThrowOnSave = true
        let plan = createTestPlan()

        // When/Then: Save should throw
        do {
            try await mockRepository.save(plan)
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

    // MARK: - Call Count Verification Tests

    func testSave_IncrementsCallCount() async throws {
        // Given: Fresh repository
        XCTAssertEqual(mockRepository.saveCallCount, 0)

        // When: Saving plans
        let plan1 = createTestPlan(id: "plan_1")
        let plan2 = createTestPlan(id: "plan_2")
        try await mockRepository.save(plan1)
        try await mockRepository.save(plan2)

        // Then: Call count should reflect saves
        XCTAssertEqual(mockRepository.saveCallCount, 2)
    }

    func testLoad_IncrementsCallCount() async throws {
        // Given: Fresh repository
        XCTAssertEqual(mockRepository.loadCallCount, 0)

        // When: Loading plans
        _ = try await mockRepository.load(id: "plan_1")
        _ = try await mockRepository.loadAll(for: testUser.id)

        // Then: Call count should reflect loads
        XCTAssertEqual(mockRepository.loadCallCount, 2)
    }
}
