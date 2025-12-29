//
// UpdateExerciseTargetHandler.swift
// Medina
//
// v72.1: Handler for update_exercise_target tool
// Saves user's 1RM or working weight from natural language chat
// v74.7: Updated to use OneRMCalculationService (Epley formula)
//

import Foundation

/// Handles update_exercise_target tool calls
/// Allows users to say "my 1RM for bench is 225" or "I use 45lb dumbbells for curls"
@MainActor
struct UpdateExerciseTargetHandler: ToolHandler {
    static let toolName = "update_exercise_target"

    /// v72.1: Execute only - returns output string without submitting (for batch calls)
    static func executeOnly(args: [String: Any], context: ToolCallContext) async -> String {
        return await executeLogic(args: args, context: context)
    }

    static func handle(
        toolCall: StreamProcessor.ToolCall,
        args: [String: Any],
        context: ToolCallContext
    ) async {
        let toolOutput = await executeLogic(args: args, context: context)

        // Stream AI response
        await ToolHandlerUtilities.streamToolResponse(
            toolCall: toolCall,
            toolOutput: toolOutput,
            context: context
        )
    }

    /// Shared logic for both single and batch execution
    private static func executeLogic(args: [String: Any], context: ToolCallContext) async -> String {
        Logger.log(.info, component: "UpdateExerciseTargetHandler", message: "🔧 Executing update_exercise_target tool")
        Logger.log(.debug, component: "UpdateExerciseTargetHandler", message: "🔧 Args: \(args)")

        // Parse required arguments
        guard let exerciseId = args["exercise_id"] as? String else {
            return "ERROR: Missing exercise_id parameter"
        }

        guard let weightLbs = (args["weight_lbs"] as? Double) ?? (args["weight_lbs"] as? Int).map({ Double($0) }) else {
            return "ERROR: Missing or invalid weight_lbs parameter"
        }

        guard let weightType = args["weight_type"] as? String else {
            return "ERROR: Missing weight_type parameter (must be '1rm' or 'working')"
        }

        // Validate exercise exists
        guard let exercise = TestDataManager.shared.exercises[exerciseId] else {
            // Try fuzzy matching
            if let match = findExerciseMatch(for: exerciseId) {
                return """
                ERROR: Exercise '\(exerciseId)' not found.
                Did you mean '\(match.name)' (id: '\(match.id)')?
                Please try again with the correct exercise ID.
                """
            }
            return "ERROR: Exercise '\(exerciseId)' not found in database"
        }

        let userId = context.user.id
        let targetId = "\(userId)-\(exerciseId)"

        // Calculate effective 1RM
        var effectiveMax = weightLbs
        var repsUsed: Int? = nil

        if weightType == "working" {
            // Parse reps for working weight
            if let reps = (args["reps"] as? Int) ?? (args["reps"] as? Double).map({ Int($0) }) {
                if reps > 0 && reps <= 20 {
                    // v74.7: Use Epley formula via OneRMCalculationService
                    if let calculated1RM = OneRMCalculationService.calculate(weight: weightLbs, reps: reps) {
                        effectiveMax = calculated1RM
                        repsUsed = reps
                        Logger.log(.info, component: "UpdateExerciseTargetHandler",
                                  message: "📊 Calculated 1RM: \(Int(effectiveMax)) lbs from \(Int(weightLbs))x\(reps)")
                    } else {
                        return "ERROR: Could not calculate 1RM from provided weight and reps"
                    }
                } else {
                    return "ERROR: Reps must be between 1 and 20 for 1RM calculation"
                }
            } else {
                return "ERROR: 'reps' is required when weight_type is 'working'"
            }
        }

        // Update or create target
        var target = TestDataManager.shared.targets[targetId] ?? ExerciseTarget(
            id: targetId,
            exerciseId: exerciseId,
            memberId: userId,
            targetType: .max,
            currentTarget: nil,
            lastCalibrated: nil,
            targetHistory: []
        )

        let previousMax = target.currentTarget
        target.currentTarget = effectiveMax
        target.lastCalibrated = Date()

        // Add to history
        target.targetHistory.append(ExerciseTarget.TargetEntry(
            date: Date(),
            target: effectiveMax,
            calibrationSource: "chat_input"
        ))

        // Save to TestDataManager
        TestDataManager.shared.targets[targetId] = target

        // v206: Removed legacy disk persistence - Firestore is source of truth
        // TODO: Add Firestore target sync when ready

        // Add exercise to library if not already there
        do {
            try LibraryPersistenceService.addExercises([exerciseId], userId: userId)
            Logger.log(.info, component: "UpdateExerciseTargetHandler",
                      message: "✅ Added \(exerciseId) to library")
        } catch {
            Logger.log(.warning, component: "UpdateExerciseTargetHandler",
                      message: "⚠️ Could not add to library: \(error)")
        }

        Logger.log(.info, component: "UpdateExerciseTargetHandler",
                  message: "✅ Saved 1RM for \(exercise.name): \(Int(effectiveMax)) lbs")

        // Format success output for AI
        var response = """
        SUCCESS: Exercise target updated.
        Exercise: \(exercise.name)
        1RM: \(Int(effectiveMax)) lbs
        """

        if let reps = repsUsed {
            response += "\nCalculated from: \(Int(weightLbs)) lbs x \(reps) reps (Epley formula)"
        }

        if let previous = previousMax {
            let change = effectiveMax - previous
            let changeStr = change >= 0 ? "+\(Int(change))" : "\(Int(change))"
            response += "\nPrevious 1RM: \(Int(previous)) lbs (\(changeStr) lbs)"
        }

        response += """

        INSTRUCTIONS:
        1. Acknowledge that you saved their \(exercise.name) data
        2. If they gave you a 1RM, confirm the value
        3. If they gave you a working weight, explain you calculated their 1RM from it
        4. Offer to save more exercises or continue with workout planning
        5. Keep response brief and conversational
        """

        return response
    }

    // MARK: - Helpers

    /// Try to find a matching exercise by name (fuzzy match)
    private static func findExerciseMatch(for query: String) -> Exercise? {
        let lowercaseQuery = query.lowercased().replacingOccurrences(of: "_", with: " ")

        // Try exact name match first
        if let exactMatch = TestDataManager.shared.exercises.values.first(where: {
            $0.name.lowercased() == lowercaseQuery
        }) {
            return exactMatch
        }

        // Try contains match
        if let containsMatch = TestDataManager.shared.exercises.values.first(where: {
            $0.name.lowercased().contains(lowercaseQuery) || lowercaseQuery.contains($0.name.lowercased())
        }) {
            return containsMatch
        }

        return nil
    }
}
