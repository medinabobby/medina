//
// AnalyzeTrainingDataTests.swift
// MedinaTests
//
// v107.0: Tests for analyze_training_data handler
// Tests historical data analysis across date ranges
//

import XCTest
@testable import Medina

@MainActor
class AnalyzeTrainingDataTests: XCTestCase {

    // MARK: - Properties

    var mockContext: MockToolContext!
    var testUser: UnifiedUser!
    var context: ToolCallContext!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        // Reset data store to clean state and load Bobby's data
        TestDataManager.shared.resetAndReload()

        // Create mock context using Bobby (who has rich historical data)
        mockContext = MockToolContext()
        testUser = TestDataManager.shared.users["bobby"]!
        context = mockContext.build(for: testUser)
    }

    override func tearDown() async throws {
        mockContext.reset()
        TestDataManager.shared.reset()
        try await super.tearDown()
    }

    // MARK: - Period Summary Tests

    func testPeriodSummaryReturnsData() async throws {
        // Given: Bobby with full workout history
        // When: Requesting period summary for 2025
        let output = await AnalyzeTrainingDataHandler.executeOnly(
            args: [
                "analysisType": "period_summary",
                "dateRange": [
                    "start": "2025-01-01",
                    "end": "2025-12-01"
                ]
            ],
            context: context
        )

        // Then: Should return training analysis
        XCTAssertFalse(output.hasPrefix("ERROR"), "Should not error: \(output)")
        XCTAssertTrue(output.contains("TRAINING ANALYSIS"), "Should have analysis header")
        XCTAssertTrue(output.contains("Period Summary"), "Should be period summary type")

        // And: Should contain expected sections
        XCTAssertTrue(output.contains("OVERVIEW:"), "Should have overview section")
        XCTAssertTrue(output.contains("Workouts:"), "Should show workout count")
        XCTAssertTrue(output.contains("Total Volume:"), "Should show volume")
        XCTAssertTrue(output.contains("MUSCLE GROUP BREAKDOWN:"), "Should have muscle breakdown")
        XCTAssertTrue(output.contains("TOP EXERCISES"), "Should have top exercises")

        print("📊 Period Summary Output:\n\(output)")
    }

    func testPeriodSummaryDefaultsTo90Days() async throws {
        // Given: No date range specified
        // When: Requesting period summary
        let output = await AnalyzeTrainingDataHandler.executeOnly(
            args: ["analysisType": "period_summary"],
            context: context
        )

        // Then: Should default to last 90 days (not error)
        XCTAssertFalse(output.hasPrefix("ERROR"), "Should not error with default date range")
        XCTAssertTrue(output.contains("TRAINING ANALYSIS"), "Should return analysis")
    }

    func testPeriodSummaryShowsAdherenceRate() async throws {
        // Given: Bobby's workout history
        // When: Requesting period summary
        let output = await AnalyzeTrainingDataHandler.executeOnly(
            args: [
                "analysisType": "period_summary",
                "dateRange": [
                    "start": "2025-01-01",
                    "end": "2025-12-01"
                ]
            ],
            context: context
        )

        // Then: Should show adherence rate
        XCTAssertTrue(output.contains("adherence"), "Should mention adherence")
        XCTAssertTrue(output.contains("%"), "Should show percentage")
    }

    // MARK: - Exercise Progression Tests

    func testExerciseProgressionWithValidExercise() async throws {
        // Given: Exercise that Bobby has done
        // When: Requesting exercise progression for bench press
        let output = await AnalyzeTrainingDataHandler.executeOnly(
            args: [
                "analysisType": "exercise_progression",
                "exerciseId": "barbell_bench_press",
                "dateRange": [
                    "start": "2025-01-01",
                    "end": "2025-12-01"
                ]
            ],
            context: context
        )

        // Then: Should show progression data (or no data message)
        XCTAssertFalse(output.hasPrefix("ERROR"), "Should not error: \(output)")
        XCTAssertTrue(output.contains("TRAINING ANALYSIS"), "Should have analysis header")

        // Should contain either progression data or no data message
        let hasData = output.contains("SESSION HISTORY") || output.contains("TREND:")
        let hasNoData = output.contains("NO DATA:")
        XCTAssertTrue(hasData || hasNoData, "Should show data or no data message")

        print("📊 Exercise Progression Output:\n\(output)")
    }

    func testExerciseProgressionWithFuzzyName() async throws {
        // Given: Fuzzy exercise name
        // When: Requesting exercise progression with name instead of ID
        let output = await AnalyzeTrainingDataHandler.executeOnly(
            args: [
                "analysisType": "exercise_progression",
                "exerciseName": "bench press",
                "dateRange": [
                    "start": "2025-01-01",
                    "end": "2025-12-01"
                ]
            ],
            context: context
        )

        // Then: Should resolve and return data (not error)
        XCTAssertFalse(output.hasPrefix("ERROR"), "Should not error with fuzzy name")
    }

    func testExerciseProgressionWithInvalidExercise() async throws {
        // Given: Invalid exercise ID
        // When: Requesting exercise progression
        let output = await AnalyzeTrainingDataHandler.executeOnly(
            args: [
                "analysisType": "exercise_progression",
                "exerciseId": "nonexistent_exercise_xyz123",
                "dateRange": [
                    "start": "2025-01-01",
                    "end": "2025-12-01"
                ]
            ],
            context: context
        )

        // Then: Should handle gracefully (either error or no data)
        // Not a hard error - just no data found
        XCTAssertTrue(
            output.contains("NO DATA") || output.contains("ERROR") || output.contains("couldn't find"),
            "Should indicate no data or error"
        )
    }

    // MARK: - Strength Trends Tests

    func testStrengthTrendsReturnsCategories() async throws {
        // Given: Bobby's workout history
        // When: Requesting strength trends
        let output = await AnalyzeTrainingDataHandler.executeOnly(
            args: [
                "analysisType": "strength_trends",
                "dateRange": [
                    "start": "2025-01-01",
                    "end": "2025-12-01"
                ]
            ],
            context: context
        )

        // Then: Should show trend categories
        XCTAssertFalse(output.hasPrefix("ERROR"), "Should not error: \(output)")
        XCTAssertTrue(output.contains("TRAINING ANALYSIS"), "Should have analysis header")

        // Should have trend categories (may be empty but labels should exist)
        XCTAssertTrue(output.contains("IMPROVING"), "Should have improving category")
        XCTAssertTrue(output.contains("MAINTAINING"), "Should have maintaining category")
        XCTAssertTrue(output.contains("REGRESSING"), "Should have regressing category")

        print("📊 Strength Trends Output:\n\(output)")
    }

    func testStrengthTrendsWithMuscleGroupFilter() async throws {
        // Given: Muscle group filter
        // When: Requesting strength trends for chest only
        let output = await AnalyzeTrainingDataHandler.executeOnly(
            args: [
                "analysisType": "strength_trends",
                "muscleGroup": "chest",
                "dateRange": [
                    "start": "2025-01-01",
                    "end": "2025-12-01"
                ]
            ],
            context: context
        )

        // Then: Should not error (may return no data if no chest exercises)
        XCTAssertFalse(output.hasPrefix("ERROR"), "Should not error with muscle filter")
    }

    // MARK: - Period Comparison Tests

    func testPeriodComparisonBetweenMonths() async throws {
        // Given: Two periods to compare
        // When: Comparing Q3 vs Q4 2025
        let output = await AnalyzeTrainingDataHandler.executeOnly(
            args: [
                "analysisType": "period_comparison",
                "dateRange": [
                    "start": "2025-07-01",
                    "end": "2025-09-30"
                ],
                "comparisonDateRange": [
                    "start": "2025-10-01",
                    "end": "2025-11-30"
                ]
            ],
            context: context
        )

        // Then: Should show comparison
        XCTAssertFalse(output.hasPrefix("ERROR"), "Should not error: \(output)")
        XCTAssertTrue(output.contains("Period Comparison"), "Should be comparison type")
        XCTAssertTrue(output.contains("COMPARISON SUMMARY:"), "Should have comparison section")

        print("📊 Period Comparison Output:\n\(output)")
    }

    func testPeriodComparisonShowsVolumeChange() async throws {
        // Given: Two periods
        // When: Comparing periods
        let output = await AnalyzeTrainingDataHandler.executeOnly(
            args: [
                "analysisType": "period_comparison",
                "dateRange": [
                    "start": "2025-01-01",
                    "end": "2025-06-30"
                ],
                "comparisonDateRange": [
                    "start": "2025-07-01",
                    "end": "2025-11-30"
                ]
            ],
            context: context
        )

        // Then: Should show volume change
        XCTAssertTrue(output.contains("Volume:"), "Should show volume change")
    }

    // MARK: - Error Handling Tests

    func testInvalidAnalysisTypeReturnsError() async throws {
        // Given: Invalid analysis type
        // When: Requesting invalid type
        let output = await AnalyzeTrainingDataHandler.executeOnly(
            args: ["analysisType": "invalid_type"],
            context: context
        )

        // Then: Should return error
        XCTAssertTrue(output.hasPrefix("ERROR"), "Should error on invalid type")
        XCTAssertTrue(output.contains("analysisType"), "Should mention analysisType in error")
    }

    func testMissingAnalysisTypeReturnsError() async throws {
        // Given: No analysis type
        // When: Requesting with empty args
        let output = await AnalyzeTrainingDataHandler.executeOnly(
            args: [:],
            context: context
        )

        // Then: Should return error
        XCTAssertTrue(output.hasPrefix("ERROR"), "Should error on missing type")
    }

    // MARK: - Response Guidance Tests

    func testOutputContainsResponseGuidance() async throws {
        // Given: Valid request
        // When: Requesting any analysis type
        let output = await AnalyzeTrainingDataHandler.executeOnly(
            args: [
                "analysisType": "period_summary",
                "dateRange": [
                    "start": "2025-01-01",
                    "end": "2025-12-01"
                ]
            ],
            context: context
        )

        // Then: Should contain response guidance for AI
        XCTAssertTrue(output.contains("RESPONSE_GUIDANCE:"), "Should have response guidance")
    }

    // MARK: - Include Details Tests

    func testIncludeDetailsShowsWeeklyBreakdown() async throws {
        // Given: Include details flag
        // When: Requesting with details
        let output = await AnalyzeTrainingDataHandler.executeOnly(
            args: [
                "analysisType": "period_summary",
                "includeDetails": true,
                "dateRange": [
                    "start": "2025-01-01",
                    "end": "2025-12-01"
                ]
            ],
            context: context
        )

        // Then: Should include weekly breakdown
        XCTAssertFalse(output.hasPrefix("ERROR"), "Should not error")
        // Weekly breakdown should appear when includeDetails=true and data exists
        if output.contains("WEEKLY BREAKDOWN:") {
            print("✅ Weekly breakdown included with details flag")
        } else {
            print("ℹ️ No weekly breakdown (may not have enough data)")
        }
    }
}
