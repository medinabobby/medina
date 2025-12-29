//
// GetSubstitutionHandler.swift
// Medina
//
// v63.2: Handler for get_substitution_options tool
// Finds alternative exercises for a given exercise
//

import Foundation

/// Handles get_substitution_options tool calls
@MainActor
struct GetSubstitutionHandler: ToolHandler {
    static let toolName = "get_substitution_options"

    /// v66.4: Execute only - returns output string without submitting (for batch calls)
    static func executeOnly(args: [String: Any], context: ToolCallContext) async -> String {
        return executeLogic(args: args, context: context)
    }

    static func handle(
        toolCall: StreamProcessor.ToolCall,
        args: [String: Any],
        context: ToolCallContext
    ) async {
        let toolOutput = executeLogic(args: args, context: context)

        if toolOutput.hasPrefix("ERROR:") {
            await ToolHandlerUtilities.submitToolError(
                toolCall: toolCall,
                output: toolOutput,
                context: context
            )
        } else {
            await ToolHandlerUtilities.streamToolResponse(
                toolCall: toolCall,
                toolOutput: toolOutput,
                context: context
            )
        }
    }

    /// v66.4: Shared logic for both single and batch execution
    private static func executeLogic(args: [String: Any], context: ToolCallContext) -> String {
        Logger.log(.info, component: "GetSubstitutionHandler", message: "🔧 Executing get_substitution_options")

        guard let exerciseId = args["exerciseId"] as? String else {
            return "ERROR: Missing exerciseId parameter."
        }

        let workoutId = args["workoutId"] as? String

        // Determine available equipment
        let availableEquipment: Set<Equipment>
        if let wId = workoutId,
           let workout = TestDataManager.shared.workouts[wId],
           let program = TestDataManager.shared.programs[workout.programId],
           let plan = TestDataManager.shared.plans[program.planId],
           plan.trainingLocation == .home {
            availableEquipment = context.user.memberProfile?.availableEquipment ?? [.bodyweight]
        } else {
            availableEquipment = Set(Equipment.allCases)
        }

        let userExperienceLevel = context.user.memberProfile?.experienceLevel ?? .intermediate

        let candidates = ExerciseSubstitutionService.findAlternatives(
            for: exerciseId,
            availableEquipment: availableEquipment,
            userLibrary: TestDataManager.shared.libraries[context.user.id],
            userExperienceLevel: userExperienceLevel
        )

        Logger.log(.info, component: "GetSubstitutionHandler", message: "📤 Submitting substitution options: \(candidates.count) alternatives found")

        return formatSubstitutionOptions(candidates, originalExerciseId: exerciseId)
    }

    // MARK: - Formatting

    private static func formatSubstitutionOptions(
        _ candidates: [SubstitutionCandidate],
        originalExerciseId: String
    ) -> String {
        let originalName = TestDataManager.shared.exercises[originalExerciseId]?.name ?? originalExerciseId

        if candidates.isEmpty {
            return """
            No alternative exercises found for \(originalName).
            The user may need to adjust their equipment availability or try a different exercise.
            """
        }

        var output = "Found \(candidates.count) alternatives for \(originalName):\n\n"

        for (index, candidate) in candidates.prefix(5).enumerated() {
            let name = candidate.exercise.name
            let score = candidate.scorePercentage
            output += "\(index + 1). \(name) (\(score)% match)\n"
        }

        output += "\nGenerate a conversational response listing these alternatives."

        return output
    }
}
