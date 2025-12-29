//
// ChipResolutionTests.swift
// MedinaTests
//
// v145: Initial chip resolution tests
// v146: Removed ContextChipsProvider fallback tests (fallback deleted - showing nothing
//       is better than showing irrelevant chips). Chips now exclusively come from handlers.
//
// Tests the chip resolution logic: handlers set chips via pendingSuggestionChipsData,
// which flows through ToolHandlerUtilities into Message.suggestionChipsData.
//
// Created: December 2025
//

import XCTest
@testable import Medina

@MainActor
class ChipResolutionTests: XCTestCase {

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        TestDataManager.shared.resetAndReload()
        DeltaStore.shared.clearAllDeltas()
    }

    override func tearDown() async throws {
        DeltaStore.shared.clearAllDeltas()
        TestDataManager.shared.reset()
        try await super.tearDown()
    }

    // MARK: - Message Chip Tests

    /// Test: AI-provided chips are stored correctly on Message
    func testMessage_AIChipsStoredCorrectly() throws {
        // Given: A message with AI-provided chips
        let aiChips = [
            SuggestionChip("Book Yoga", command: "Book Yoga class"),
            SuggestionChip("Book HIIT", command: "Book HIIT class")
        ]
        let message = Message(
            content: "Here are today's classes",
            isUser: false,
            suggestionChipsData: aiChips
        )

        // Then: AI chips should be stored
        XCTAssertNotNil(message.suggestionChipsData)
        XCTAssertEqual(message.suggestionChipsData?.count, 2)
        XCTAssertEqual(message.suggestionChipsData?.first?.title, "Book Yoga")
        XCTAssertEqual(message.suggestionChipsData?.first?.command, "Book Yoga class")
    }

    /// Test: Message can hold both cards and chips (v146 fix)
    /// v186: Updated to use workoutCreatedData instead of classScheduleCardData (class booking deferred)
    func testMessage_CardsAndChipsTogether() throws {
        // Given: A message with both card and chips
        let chips = [
            SuggestionChip("Start workout", command: "Start the workout"),
            SuggestionChip("View details", command: "Show workout details")
        ]
        // Create a minimal workout card data for testing
        let workoutCard = WorkoutCreatedData(workoutId: "test-workout", workoutName: "Test Workout")
        let message = Message(
            content: "Here's your workout",
            isUser: false,
            workoutCreatedData: workoutCard,
            suggestionChipsData: chips
        )

        // Then: Both should be present (v146 fix - previously mutually exclusive)
        XCTAssertNotNil(message.workoutCreatedData, "Card data should be present")
        XCTAssertNotNil(message.suggestionChipsData, "Chips should be present even with card")
        XCTAssertEqual(message.suggestionChipsData?.count, 2)
    }

    /// Test: Empty chips array results in no chips (no fallback)
    func testMessage_EmptyChips_NoFallback() throws {
        // Given: A message with empty chips array
        let message = Message(
            content: "Here are today's classes",
            isUser: false,
            suggestionChipsData: []
        )

        // Then: v146: No fallback - empty means empty
        XCTAssertTrue(message.suggestionChipsData?.isEmpty ?? true,
            "Empty chips should remain empty - no fallback in v146")
    }

    /// Test: Nil chips results in no chips (no fallback)
    func testMessage_NilChips_NoFallback() throws {
        // Given: A message with nil chips
        let message = Message(
            content: "Response without chips",
            isUser: false,
            suggestionChipsData: nil
        )

        // Then: v146: No fallback - nil means nil
        XCTAssertNil(message.suggestionChipsData,
            "Nil chips should remain nil - no fallback in v146")
    }

    // MARK: - SuggestionChip Model Tests

    /// Test: SuggestionChip stores title and command correctly
    func testSuggestionChip_Properties() throws {
        let chip = SuggestionChip("Start Workout", command: "Start my next workout")

        XCTAssertEqual(chip.title, "Start Workout")
        XCTAssertEqual(chip.command, "Start my next workout")
    }

    /// Test: SuggestionChip title truncation for display
    func testSuggestionChip_LongTitle() throws {
        // Given: Chip with long title
        let chip = SuggestionChip("Book Red Light DISTRICT Class", command: "Book Red Light DISTRICT")

        // Then: Title is stored as-is (truncation is UI responsibility)
        XCTAssertEqual(chip.title, "Book Red Light DISTRICT Class")
    }
}
