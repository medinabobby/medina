//
// AddToLibraryHandler.swift
// Medina
//
// v184: Handler for add_to_library tool
// Allows users to add exercises to their favorites via natural language
//

import Foundation

/// Handles add_to_library tool calls
@MainActor
struct AddToLibraryHandler: ToolHandler {
    static let toolName = "add_to_library"

    /// Execute only - returns output string without submitting (for batch calls)
    static func executeOnly(args: [String: Any], context: ToolCallContext) async -> String {
        return await executeLogic(args: args, context: context)
    }

    static func handle(
        toolCall: StreamProcessor.ToolCall,
        args: [String: Any],
        context: ToolCallContext
    ) async {
        let toolOutput = await executeLogic(args: args, context: context)
        await ToolHandlerUtilities.streamToolResponse(
            toolCall: toolCall,
            toolOutput: toolOutput,
            context: context
        )
    }

    /// Shared logic for both single and batch execution
    private static func executeLogic(args: [String: Any], context: ToolCallContext) async -> String {
        guard let exerciseId = args["exerciseId"] as? String else {
            Logger.log(.error, component: "AddToLibraryHandler", message: "❌ Missing required parameter: exerciseId")
            return "ERROR: Missing required parameter 'exerciseId'. Please specify which exercise to add."
        }

        Logger.log(.info, component: "AddToLibraryHandler", message: "🔧 Executing add_to_library for exerciseId: \(exerciseId)")

        // Try to find the exercise (supports fuzzy matching)
        var exercise: Exercise?
        var resolvedId = exerciseId

        // First try exact match
        if let found = TestDataManager.shared.exercises[exerciseId] {
            exercise = found
        }
        // Try fuzzy matching (handles AI hallucinated IDs)
        else if let matched = ExerciseFuzzyMatcher.match(exerciseId) {
            exercise = matched
            resolvedId = matched.id
            Logger.log(.info, component: "AddToLibraryHandler", message: "✓ Fuzzy matched '\(exerciseId)' → '\(matched.id)'")
        }

        guard let foundExercise = exercise else {
            Logger.log(.error, component: "AddToLibraryHandler", message: "❌ Exercise not found: \(exerciseId)")
            return "ERROR: Exercise '\(exerciseId)' not found. Please check the exercise name or ID."
        }

        let userId = context.user.id

        // Check if already in library
        if let library = TestDataManager.shared.libraries[userId],
           library.exercises.contains(resolvedId) {
            Logger.log(.info, component: "AddToLibraryHandler", message: "⚠️ Exercise already in library")
            return "'\(foundExercise.name)' is already in your library."
        }

        // Add to library
        do {
            try LibraryPersistenceService.addExercise(resolvedId, userId: userId)

            Logger.log(.info, component: "AddToLibraryHandler", message: "✅ Added '\(foundExercise.name)' to library")

            // Suggestion chips
            context.pendingSuggestionChipsData = [
                SuggestionChip("Create workout", command: "Create a workout with \(foundExercise.name)"),
                SuggestionChip("Add another", command: "Add more exercises to my library")
            ]

            return """
            ✅ Added '\(foundExercise.name)' to your library!

            This exercise will now be prioritized when creating workouts.

            [VOICE_READY: Confirm the exercise was added to their favorites.]
            """

        } catch {
            Logger.log(.error, component: "AddToLibraryHandler", message: "❌ Failed to add exercise: \(error)")
            return "ERROR: Failed to add exercise to library: \(error.localizedDescription)"
        }
    }
}
