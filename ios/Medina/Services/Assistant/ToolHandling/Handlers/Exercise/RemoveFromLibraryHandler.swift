//
// RemoveFromLibraryHandler.swift
// Medina
//
// v184: Handler for remove_from_library tool
// Allows users to remove exercises from their favorites via natural language
//

import Foundation

/// Handles remove_from_library tool calls
@MainActor
struct RemoveFromLibraryHandler: ToolHandler {
    static let toolName = "remove_from_library"

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
            Logger.log(.error, component: "RemoveFromLibraryHandler", message: "❌ Missing required parameter: exerciseId")
            return "ERROR: Missing required parameter 'exerciseId'. Please specify which exercise to remove."
        }

        Logger.log(.info, component: "RemoveFromLibraryHandler", message: "🔧 Executing remove_from_library for exerciseId: \(exerciseId)")

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
            Logger.log(.info, component: "RemoveFromLibraryHandler", message: "✓ Fuzzy matched '\(exerciseId)' → '\(matched.id)'")
        }

        guard let foundExercise = exercise else {
            Logger.log(.error, component: "RemoveFromLibraryHandler", message: "❌ Exercise not found: \(exerciseId)")
            return "ERROR: Exercise '\(exerciseId)' not found. Please check the exercise name or ID."
        }

        let userId = context.user.id

        // Check if in library
        if let library = TestDataManager.shared.libraries[userId],
           !library.exercises.contains(resolvedId) {
            Logger.log(.info, component: "RemoveFromLibraryHandler", message: "⚠️ Exercise not in library")
            return "'\(foundExercise.name)' is not in your library."
        }

        // Remove from library
        do {
            try LibraryPersistenceService.removeExercise(resolvedId, userId: userId)

            Logger.log(.info, component: "RemoveFromLibraryHandler", message: "✅ Removed '\(foundExercise.name)' from library")

            // Suggestion chips
            context.pendingSuggestionChipsData = [
                SuggestionChip("Show my library", command: "Show my exercise library"),
                SuggestionChip("Add exercise", command: "Add an exercise to my library")
            ]

            return """
            Removed '\(foundExercise.name)' from your library.

            [VOICE_READY: Confirm the exercise was removed from their favorites.]
            """

        } catch {
            Logger.log(.error, component: "RemoveFromLibraryHandler", message: "❌ Failed to remove exercise: \(error)")
            return "ERROR: Failed to remove exercise from library: \(error.localizedDescription)"
        }
    }
}
