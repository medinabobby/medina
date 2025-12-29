//
// SidebarTests.swift
// MedinaTests
//
// v99.9: Tests for sidebar folder display logic
// v142: Added status color consistency tests
// v172: Removed abandoned status - plans are now draft/active/completed only
// Tests plan sorting, status dots, and display limits
//

import XCTest
import SwiftUI
@testable import Medina

@MainActor
class SidebarTests: XCTestCase {

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        TestDataManager.shared.resetAndReload()
    }

    override func tearDown() async throws {
        TestDataManager.shared.reset()
        try await super.tearDown()
    }

    // MARK: - Plan Status Priority Tests

    func testPlanStatusPriorityOrder() throws {
        // Given: Plans with different statuses
        let memberId = "test_member"
        let calendar = Calendar.current

        // Create plans with different statuses
        let activePlan = Plan(
            id: "plan_active",
            memberId: memberId,
            status: .active,
            name: "Active Plan",
            description: "",
            goal: .strength,
            weightliftingDays: 3,
            cardioDays: 0,
            splitType: .fullBody,
            targetSessionDuration: 60,
            trainingLocation: .gym,
            compoundTimeAllocation: 0.6,
            isolationApproach: .volumeAccumulation,
            preferredDays: [.monday, .wednesday, .friday],
            startDate: Date(),
            endDate: calendar.date(byAdding: .month, value: 1, to: Date())!
        )

        let draftPlan = Plan(
            id: "plan_draft",
            memberId: memberId,
            status: .draft,
            name: "Draft Plan",
            description: "",
            goal: .strength,
            weightliftingDays: 3,
            cardioDays: 0,
            splitType: .fullBody,
            targetSessionDuration: 60,
            trainingLocation: .gym,
            compoundTimeAllocation: 0.6,
            isolationApproach: .volumeAccumulation,
            preferredDays: [.monday, .wednesday, .friday],
            startDate: calendar.date(byAdding: .day, value: 7, to: Date())!,
            endDate: calendar.date(byAdding: .month, value: 2, to: Date())!
        )

        let completedPlan = Plan(
            id: "plan_completed",
            memberId: memberId,
            status: .completed,
            name: "Completed Plan",
            description: "",
            goal: .strength,
            weightliftingDays: 3,
            cardioDays: 0,
            splitType: .fullBody,
            targetSessionDuration: 60,
            trainingLocation: .gym,
            compoundTimeAllocation: 0.6,
            isolationApproach: .volumeAccumulation,
            preferredDays: [.monday, .wednesday, .friday],
            startDate: calendar.date(byAdding: .month, value: -3, to: Date())!,
            endDate: calendar.date(byAdding: .month, value: -1, to: Date())!
        )

        // v172: Removed abandoned plan - plans are now draft/active/completed only

        // Store in data manager (in random order)
        TestDataManager.shared.plans[completedPlan.id] = completedPlan
        TestDataManager.shared.plans[activePlan.id] = activePlan
        TestDataManager.shared.plans[draftPlan.id] = draftPlan

        // When: Getting plans via PlanResolver
        let allPlans = PlanResolver.allPlans(for: memberId)

        // Then: Should have all 3 plans
        XCTAssertEqual(allPlans.count, 3, "Should have all 3 plans")

        // And: Can sort by status priority
        let sorted = allPlans.sorted { plan1, plan2 in
            let priority1 = statusPriority(plan1.status)
            let priority2 = statusPriority(plan2.status)
            return priority1 < priority2
        }

        // Then: Active should be first
        XCTAssertEqual(sorted[0].status, .active, "Active should be first")
        // Then: Draft should be second
        XCTAssertEqual(sorted[1].status, .draft, "Draft should be second")
        // Then: Completed should be last
        XCTAssertEqual(sorted[2].status, .completed, "Completed should be last")
    }

    /// Helper function matching SidebarMemberScopedFolders.statusPriority
    /// v172: Removed abandoned - plans are now draft/active/completed only
    private func statusPriority(_ status: PlanStatus) -> Int {
        switch status {
        case .active: return 0
        case .draft: return 1
        case .completed: return 2
        }
    }

    // MARK: - Plan Display Limit Tests

    func testPlanDisplayLimit() throws {
        // Given: 7 plans for a member
        let memberId = "test_member_many_plans"
        let calendar = Calendar.current

        for i in 1...7 {
            let plan = Plan(
                id: "plan_\(i)",
                memberId: memberId,
                status: i == 1 ? .active : .completed,
                name: "Plan \(i)",
                description: "",
                goal: .strength,
                weightliftingDays: 3,
                cardioDays: 0,
                splitType: .fullBody,
                targetSessionDuration: 60,
                trainingLocation: .gym,
                compoundTimeAllocation: 0.6,
                isolationApproach: .volumeAccumulation,
                preferredDays: [.monday, .wednesday, .friday],
                startDate: calendar.date(byAdding: .day, value: -i * 30, to: Date())!,
                endDate: calendar.date(byAdding: .day, value: -i * 30 + 28, to: Date())!
            )
            TestDataManager.shared.plans[plan.id] = plan
        }

        // When: Getting all plans
        let allPlans = PlanResolver.allPlans(for: memberId)

        // Then: Should have 7 plans
        XCTAssertEqual(allPlans.count, 7, "Should have 7 plans")

        // And: Sidebar should display max 5 (based on v99.9 requirement)
        let maxDisplayedPlans = 5
        let displayedPlans = Array(allPlans.prefix(maxDisplayedPlans))
        XCTAssertEqual(displayedPlans.count, 5, "Sidebar should show max 5 plans")
    }

    // MARK: - SplitDay Display Tests

    func testSplitDayNotApplicableDisplay() throws {
        // Given: SplitDay.notApplicable
        let splitDay = SplitDay.notApplicable

        // Then: displayName should be "N/A"
        XCTAssertEqual(splitDay.displayName, "N/A", "notApplicable should display as N/A")
    }

    func testSplitDayDisplayNames() throws {
        // Test all split day display names
        let testCases: [(SplitDay, String)] = [
            (.upper, "Upper Body"),
            (.lower, "Lower Body"),
            (.push, "Push"),
            (.pull, "Pull"),
            (.legs, "Legs"),
            (.fullBody, "Full Body"),
            (.chest, "Chest"),
            (.back, "Back"),
            (.shoulders, "Shoulders"),
            (.arms, "Arms"),
            (.notApplicable, "N/A")
        ]

        for (splitDay, expectedName) in testCases {
            XCTAssertEqual(splitDay.displayName, expectedName,
                          "\(splitDay) should display as '\(expectedName)'")
        }
    }

    // MARK: - Session Type Display Tests

    func testSessionTypeShortDisplayNames() throws {
        // Test short display names used in workout chips
        let testCases: [(SessionType, String)] = [
            (.strength, "Lifting"),
            (.cardio, "Cardio"),
            (.class, "Class"),
            (.hybrid, "Hybrid"),
            (.mobility, "Mobility")
        ]

        for (sessionType, expectedName) in testCases {
            XCTAssertEqual(sessionType.shortDisplayName, expectedName,
                          "\(sessionType) shortDisplayName should be '\(expectedName)'")
        }
    }

    // MARK: - StatusDot Tests

    func testStatusDotForPlanStatuses() throws {
        // Test that StatusDot can be created for each plan status
        // v172: Removed abandoned - plans are now draft/active/completed only
        let statuses: [PlanStatus] = [.active, .draft, .completed]

        for status in statuses {
            // Should not crash when creating StatusDot
            let statusDot = StatusDot(planStatus: status)
            XCTAssertNotNil(statusDot, "Should create StatusDot for \(status)")
        }
    }

    func testStatusDotForWorkoutStatuses() throws {
        // Test that StatusDot can be created for workout execution statuses
        let statuses: [ExecutionStatus] = [.scheduled, .inProgress, .completed, .skipped]

        for status in statuses {
            // Should not crash when creating StatusDot
            let statusDot = StatusDot(executionStatus: status)
            XCTAssertNotNil(statusDot, "Should create StatusDot for \(status)")
        }
    }

    // MARK: - Library Tests

    func testEmptyExerciseLibrary() throws {
        // Given: A user with no exercises in library
        let userId = "test_empty_library_user"
        var library = UserLibrary(userId: userId)
        library.exercises = []
        TestDataManager.shared.libraries[userId] = library

        // When: Getting user's library exercises
        let userLibrary = TestDataManager.shared.libraries[userId]

        // Then: Should have empty exercises
        XCTAssertEqual(userLibrary?.exercises.count, 0, "Should have empty exercise library")
    }

    func testEmptyProtocolLibrary() throws {
        // Given: A user with no protocols in library
        let userId = "test_empty_protocol_user"
        var library = UserLibrary(userId: userId)
        library.protocols = []
        TestDataManager.shared.libraries[userId] = library

        // When: Getting user's library protocols
        let userLibrary = TestDataManager.shared.libraries[userId]

        // Then: Should have empty protocols
        XCTAssertEqual(userLibrary?.protocols.count, 0, "Should have empty protocol library")
    }

    // MARK: - v142: Status Color Consistency Tests

    /// REGRESSION TEST (v142): Plan status colors must match between EntityListFormatters and StatusHelpers
    ///
    /// Bug: EntityListFormatters had hardcoded colors that didn't match StatusHelpers canonical scheme:
    ///   - Draft was orange (should be grey/SecondaryText)
    ///   - Active was green (should be blue/accentColor)
    ///
    /// This test ensures both sources return the same colors.
    /// v172: Removed abandoned - plans are now draft/active/completed only
    func testPlanStatusColorsConsistency() throws {
        // Test all plan statuses
        let statuses: [PlanStatus] = [.draft, .active, .completed]

        for status in statuses {
            // Get canonical color from StatusHelpers
            let (_, canonicalColor) = status.statusInfo()

            // Create a plan with this status to test EntityListFormatters
            let testPlan = Plan(
                id: "test_plan_\(status.rawValue)",
                memberId: "test_member",
                isSingleWorkout: false,
                status: status,
                name: "Test \(status.rawValue) Plan",
                description: "Test",
                goal: .strength,
                weightliftingDays: 3,
                cardioDays: 0,
                splitType: .fullBody,
                targetSessionDuration: 60,
                trainingLocation: .gym,
                compoundTimeAllocation: 0.6,
                isolationApproach: .volumeAccumulation,
                preferredDays: [.monday, .wednesday, .friday],
                startDate: Date(),
                endDate: Calendar.current.date(byAdding: .month, value: 1, to: Date())!
            )

            // Get color from EntityListFormatters
            let config = EntityListFormatters.formatPlan(testPlan)
            let formatterColor = config.statusColor

            // Colors should match
            XCTAssertEqual(formatterColor, canonicalColor,
                "EntityListFormatters color for '\(status)' should match StatusHelpers. " +
                "Expected: \(canonicalColor), Got: \(formatterColor)")
        }
    }

    /// Test canonical status color scheme for documentation
    /// v172: Removed abandoned - plans are now draft/active/completed only
    func testPlanStatusColorScheme() throws {
        // Document the expected color scheme:
        // - draft: grey (SecondaryText) - not yet started
        // - active: blue (accentColor) - currently running
        // - completed: green - successfully finished

        let (_, draftColor) = PlanStatus.draft.statusInfo()
        let (_, activeColor) = PlanStatus.active.statusInfo()
        let (_, completedColor) = PlanStatus.completed.statusInfo()

        // Draft should be grey (SecondaryText)
        XCTAssertEqual(draftColor, Color("SecondaryText"),
            "Draft status should be grey (SecondaryText)")

        // Active should be accent color (blue)
        XCTAssertEqual(activeColor, Color.accentColor,
            "Active status should be accent color (blue)")

        // Completed should be green
        XCTAssertEqual(completedColor, Color.green,
            "Completed status should be green")
    }
}
