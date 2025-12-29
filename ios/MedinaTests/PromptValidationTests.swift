//
// PromptValidationTests.swift
// MedinaTests
//
// v148: Tests that verify critical instructions exist in AI prompts
// These catch accidental deletions or modifications to prompts that could cause regressions
//
// Philosophy: Test USER-FACING BEHAVIOR requirements, not implementation details
//

import XCTest
@testable import Medina

class PromptValidationTests: XCTestCase {

    // MARK: - Workout Flow Instructions

    /// v148: Workout choices must use chips, not text questions
    func testStartWorkoutInstructions_RequiresChipsForChoices() {
        let instructions = ToolInstructions.build()

        // Must prohibit text-based questions for choices
        XCTAssertTrue(
            instructions.contains("NEVER ask \"Would you like to...\" as text"),
            "start_workout must prohibit text questions for choices"
        )

        // Must require suggest_options for workout choices
        XCTAssertTrue(
            instructions.contains("THEN IMMEDIATELY call suggest_options") ||
            instructions.contains("call suggest_options"),
            "start_workout must require suggest_options for choices"
        )
    }

    /// v148: Instructions must cover all workout scenarios
    func testStartWorkoutInstructions_CoversAllScenarios() {
        let instructions = ToolInstructions.build()

        // Today's workout scenario
        XCTAssertTrue(
            instructions.contains("Today's Workout") &&
            instructions.contains("IMMEDIATELY call start_workout"),
            "Must have instructions for today's workout"
        )

        // No today workout + next scheduled
        XCTAssertTrue(
            instructions.contains("Next Scheduled Workout"),
            "Must have instructions for next scheduled workout"
        )

        // Missed workouts scenario
        XCTAssertTrue(
            instructions.contains("Missed Workout"),
            "Must have instructions for missed workouts"
        )
    }

    /// Workout IDs must never be fabricated
    func testStartWorkoutInstructions_ProhibitsFabricatedIds() {
        let instructions = ToolInstructions.build()

        XCTAssertTrue(
            instructions.contains("NEVER FABRICATE") ||
            instructions.contains("NEVER guess") ||
            instructions.contains("NEVER construct"),
            "Must prohibit fabricating workout IDs"
        )
    }

    // v186: Removed Class Booking Instructions tests (class booking deferred for beta)

    // MARK: - Suggestion Chips Instructions

    /// v141+: Chips must be used for action choices
    func testSuggestOptionsInstructions_RequiredForChoices() {
        let instructions = ToolInstructions.build()

        // Must prohibit numbered lists for choices
        XCTAssertTrue(
            instructions.contains("Numbered lists") ||
            instructions.contains("numbered list"),
            "suggest_options must prohibit numbered lists"
        )

        // Must prohibit bullet points for choices
        XCTAssertTrue(
            instructions.contains("Bullet points") ||
            instructions.contains("bullet point"),
            "suggest_options must prohibit bullet points for choices"
        )
    }

    /// suggest_options must list allowed commands
    func testSuggestOptionsInstructions_HasAllowedCommands() {
        let instructions = ToolInstructions.build()

        XCTAssertTrue(
            instructions.contains("ALLOWED COMMANDS") ||
            instructions.contains("allowed commands"),
            "suggest_options must list allowed commands"
        )
    }

    /// suggest_options must prohibit non-existent features
    func testSuggestOptionsInstructions_ProhibitsNonExistentFeatures() {
        let instructions = ToolInstructions.build()

        XCTAssertTrue(
            instructions.contains("DO NOT suggest non-existent") ||
            instructions.contains("calorie") ||
            instructions.contains("nutrition"),
            "suggest_options must prohibit suggesting non-existent features"
        )
    }

    // MARK: - Plan Creation Instructions

    /// Plan creation must confirm before creating
    func testCreatePlanInstructions_RequiresConfirmation() {
        let instructions = ToolInstructions.build()

        XCTAssertTrue(
            instructions.contains("CONFIRM BEFORE CREATING") ||
            instructions.contains("confirm") && instructions.contains("before"),
            "create_plan must require confirmation before creating"
        )
    }

    /// Plan creation must ask for experience level
    func testCreatePlanInstructions_RequiresExperienceLevel() {
        let instructions = ToolInstructions.build()

        XCTAssertTrue(
            instructions.contains("experience level") ||
            instructions.contains("EXPERIENCE LEVEL"),
            "create_plan must require experience level"
        )
    }

    // MARK: - General Safety Instructions

    /// Must have instructions to never fabricate IDs
    func testInstructions_GeneralIdSafety() {
        let instructions = ToolInstructions.build()

        // Count mentions of ID safety
        let neverFabricate = instructions.components(separatedBy: "NEVER").count - 1
        XCTAssertGreaterThanOrEqual(neverFabricate, 3,
            "Should have multiple NEVER warnings about fabricating IDs")
    }

    // MARK: - Tool Definitions Validation

    /// All critical tools must be defined
    func testToolDefinitions_CriticalToolsExist() {
        let allTools = AIToolDefinitions.allTools

        let toolNames = allTools.compactMap { tool -> String? in
            guard let function = tool["function"] as? [String: Any],
                  let name = function["name"] as? String else {
                return nil
            }
            return name
        }

        // Critical tools that must exist
        // v186: Removed list_classes, book_class (class booking deferred for beta)
        let criticalTools = [
            "start_workout",
            "skip_workout",
            "create_workout",
            "suggest_options",
            "show_schedule",
            "create_plan"
        ]

        for tool in criticalTools {
            XCTAssertTrue(toolNames.contains(tool),
                "Critical tool '\(tool)' must be defined in AIToolDefinitions")
        }
    }

    // v186: Removed testToolDefinitions_BuyClassCreditExists (class booking deferred for beta)

    // MARK: - Regression Prevention

    /// v148: This test documents the chip regression and ensures the fix stays in place
    func testWorkoutChoiceChips_RegressionPrevention() {
        let instructions = ToolInstructions.build()

        // The v148 fix added explicit chip requirements for workout choices
        // This test ensures those instructions aren't accidentally removed

        let hasChipRequirement =
            instructions.contains("suggest_options") &&
            (instructions.contains("workout") || instructions.contains("Workout"))

        XCTAssertTrue(hasChipRequirement,
            "v148 REGRESSION: Workout choice instructions must require suggest_options. " +
            "See v148 fix for context - removing this causes chips to not appear.")
    }

    // v186: Removed testClassBookingCreditFirst_RegressionPrevention (class booking deferred for beta)
}
