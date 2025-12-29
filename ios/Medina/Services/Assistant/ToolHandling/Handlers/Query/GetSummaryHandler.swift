//
// GetSummaryHandler.swift
// Medina
//
// v63.2: Handler for get_summary tool
// Returns summary of workout, program, or plan progress
//

import Foundation

/// Handles get_summary tool calls
@MainActor
struct GetSummaryHandler: ToolHandler {
    static let toolName = "get_summary"

    /// v66.4: Execute only - returns output string without submitting (for batch calls)
    static func executeOnly(args: [String: Any], context: ToolCallContext) async -> String {
        let (toolOutput, _, _) = executeLogic(args: args, context: context)
        return toolOutput
    }

    static func handle(
        toolCall: StreamProcessor.ToolCall,
        args: [String: Any],
        context: ToolCallContext
    ) async {
        let (toolOutput, summaryCardData, workoutSummary) = executeLogic(args: args, context: context)

        if toolOutput.hasPrefix("ERROR:") {
            await ToolHandlerUtilities.submitToolError(
                toolCall: toolCall,
                output: toolOutput,
                context: context
            )
            return
        }

        Logger.log(.debug, component: "GetSummaryHandler", message: "Submitting summary")

        // Stream with summary card
        let postToolPlaceholder = Message(content: "", isUser: false, summaryCardData: summaryCardData)
        context.addMessage(postToolPlaceholder)
        let postToolIndex = context.messagesCount() - 1

        var postToolText = ""

        do {
            let continueStream = context.assistantManager.submitToolOutput(
                toolCallId: toolCall.id,
                runId: toolCall.runId,
                output: toolOutput
            )

            for try await event in continueStream {
                switch event {
                case .textDelta(let delta):
                    postToolText += delta
                    context.updateMessage(postToolIndex, Message(content: postToolText, isUser: false, summaryCardData: summaryCardData))
                case .textDone, .runCompleted:
                    break
                case .runFailed(let error):
                    Logger.log(.error, component: "GetSummaryHandler", message: "Run failed: \(error)")
                case .toolCall:
                    Logger.log(.warning, component: "GetSummaryHandler", message: "Nested tool call not supported")
                case .toolCalls:
                    Logger.log(.warning, component: "GetSummaryHandler", message: "Nested batch tool calls not supported")
                case .error(let error):
                    Logger.log(.error, component: "GetSummaryHandler", message: "Error: \(error)")
                }
            }
        } catch {
            Logger.log(.error, component: "GetSummaryHandler", message: "Failed to submit summary: \(error)")
        }

        // Fallback text if AI didn't generate any
        let trimmedText = postToolText.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.log(.debug, component: "GetSummaryHandler", message: "Post-tool text length: \(trimmedText.count)")

        if trimmedText.isEmpty, let summary = workoutSummary {
            let fallbackText = generateFallbackSummaryText(summary)
            Logger.log(.info, component: "GetSummaryHandler", message: "Using fallback summary text")
            context.updateMessage(postToolIndex, Message(content: fallbackText, isUser: false, summaryCardData: summaryCardData))
        }
    }

    /// v66.4: Shared logic - returns (output, cardData, workoutSummary)
    private static func executeLogic(args: [String: Any], context: ToolCallContext) -> (String, SummaryCardData?, CompletedWorkoutSummary?) {
        Logger.log(.info, component: "GetSummaryHandler", message: "🔧 Executing get_summary")

        guard let scope = args["scope"] as? String,
              let id = args["id"] as? String else {
            return ("ERROR: Missing required parameters. Please specify 'scope' and 'id'.", nil, nil)
        }

        var toolOutput: String = ""
        var summaryCardData: SummaryCardData?
        var workoutSummary: CompletedWorkoutSummary?

        switch scope {
        case "workout":
            if let summary = WorkoutSummaryService.generateSummary(for: id, memberId: context.user.id) {
                workoutSummary = summary
                toolOutput = formatWorkoutSummary(summary)

                let workout = TestDataManager.shared.workouts[id]
                let workoutStatus = workout?.status
                let cardTitle = workout?.displayName ?? summary.workoutName

                let durationText: String
                if summary.duration.actual > 0 {
                    durationText = "\(Int(summary.duration.actual / 60)) min"
                } else if summary.duration.estimated > 0 {
                    durationText = "~\(Int(summary.duration.estimated / 60)) min"
                } else {
                    durationText = ""
                }

                let subtitle = "\(summary.exercises.completed) of \(summary.exercises.total) exercises\(durationText.isEmpty ? "" : " • \(durationText)")"

                summaryCardData = SummaryCardData(
                    scope: .workout,
                    id: id,
                    title: cardTitle,
                    subtitle: subtitle,
                    workoutStatus: workoutStatus
                )
            } else {
                toolOutput = "ERROR: Workout not found with ID: \(id)"
            }

        case "program":
            if let program = TestDataManager.shared.programs[id] {
                let metrics = MetricsCalculator.programProgress(for: program, memberId: context.user.id)
                toolOutput = formatProgramSummary(program: program, metrics: metrics)
                summaryCardData = SummaryCardData(
                    scope: .program,
                    id: id,
                    title: program.name,
                    subtitle: "\(metrics.sessions.completed) of \(metrics.sessions.total) workouts"
                )
            } else {
                toolOutput = "ERROR: Program not found with ID: \(id)"
            }

        case "plan":
            if let plan = TestDataManager.shared.plans[id] {
                let metrics = MetricsCalculator.planPerformance(for: plan, memberId: context.user.id)
                toolOutput = formatPlanSummary(plan: plan, metrics: metrics)
                summaryCardData = SummaryCardData(
                    scope: .plan,
                    id: id,
                    title: plan.name,
                    subtitle: "\(metrics.sessions.completed) of \(metrics.sessions.total) workouts"
                )
            } else {
                toolOutput = "ERROR: Plan not found with ID: \(id)"
            }

        default:
            toolOutput = "ERROR: Invalid scope '\(scope)'. Use 'workout', 'program', or 'plan'."
        }

        return (toolOutput, summaryCardData, workoutSummary)
    }

    // MARK: - Formatting

    private static func formatWorkoutSummary(_ summary: CompletedWorkoutSummary) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        var output = """
        WORKOUT SUMMARY: "\(summary.workoutName)"
        Date: \(dateFormatter.string(from: summary.scheduledDate))
        Status: Completed
        Duration: \(Int(summary.duration.actual / 60)) minutes (estimated: \(Int(summary.duration.estimated / 60)) min)
        Exercises: \(summary.exercises.completed) of \(summary.exercises.total) completed
        Sets: \(summary.sets.completed) of \(summary.sets.total) completed
        Reps: \(summary.reps.completed) of \(summary.reps.total) completed
        Volume: \(Int(summary.volume.actual)) lbs lifted

        EXERCISE BREAKDOWN:
        """

        for detail in summary.exerciseDetails {
            let label = detail.supersetLabel ?? ""
            let labelPrefix = label.isEmpty ? "" : "\(label). "
            let statusText = detail.status == .skipped ? "SKIPPED" : "\(detail.setsCompleted)/\(detail.setsTotal) sets, \(detail.totalReps) reps"
            output += "\n\(labelPrefix)\(detail.exerciseName) - \(statusText)"
        }

        output += """


        REQUIRED: You MUST respond with a conversational text summary (2-3 sentences).
        DO NOT just show the card - you must write text that can be read aloud.
        """

        return output
    }

    private static func formatProgramSummary(program: Program, metrics: CardProgressMetrics) -> String {
        """
        PROGRAM SUMMARY: "\(program.name)"
        Workouts: \(metrics.sessions.completed) of \(metrics.sessions.total) completed
        Exercises: \(metrics.exercises.completed) of \(metrics.exercises.total) completed
        Sets: \(metrics.sets.completed) of \(metrics.sets.total) completed
        Reps: \(metrics.reps.completed) of \(metrics.reps.total) completed

        INSTRUCTIONS: Summarize program progress conversationally.
        """
    }

    /// v72.2: Enhanced to include exercise names for AI context
    private static func formatPlanSummary(plan: Plan, metrics: CardProgressMetrics) -> String {
        // Get all programs in this plan
        let programIds = TestDataManager.shared.programs.values
            .filter { $0.planId == plan.id }
            .map { $0.id }

        // Get all workouts from these programs
        let workouts = TestDataManager.shared.workouts.values
            .filter { programIds.contains($0.programId ?? "") }

        // Collect unique exercise IDs from all workouts
        let allExerciseIds = Set(workouts.flatMap { $0.exerciseIds })

        // Get exercise names
        let exerciseNames = allExerciseIds.compactMap { id in
            TestDataManager.shared.exercises[id]?.name
        }.sorted()

        let exerciseList = exerciseNames.isEmpty
            ? "No exercises found"
            : exerciseNames.map { "- \($0)" }.joined(separator: "\n")

        return """
        PLAN SUMMARY: "\(plan.name)"
        Status: \(plan.status.rawValue)
        Total Workouts: \(metrics.sessions.completed) of \(metrics.sessions.total) completed
        Total Exercises: \(metrics.exercises.completed) of \(metrics.exercises.total) completed

        EXERCISES IN THIS PLAN (\(exerciseNames.count)):
        \(exerciseList)

        INSTRUCTIONS: Summarize the plan progress and list the key exercises featured in this plan.
        """
    }

    private static func generateFallbackSummaryText(_ summary: CompletedWorkoutSummary) -> String {
        let workout = TestDataManager.shared.workouts.values.first { $0.name == summary.workoutName }
        let dayName = workout?.displayName ?? summary.workoutName

        let durationText: String
        if summary.duration.actual > 0 {
            durationText = "\(Int(summary.duration.actual / 60)) minutes"
        } else if summary.duration.estimated > 0 {
            durationText = "about \(Int(summary.duration.estimated / 60)) minutes"
        } else {
            durationText = ""
        }

        var text = "Here's your \(dayName) workout summary! "
        text += "You completed \(summary.exercises.completed) of \(summary.exercises.total) exercises"

        if !durationText.isEmpty {
            text += " in \(durationText)"
        }

        if summary.volume.actual > 0 {
            let volumeK = Int(summary.volume.actual / 1000)
            if volumeK > 0 {
                text += ", moving \(volumeK),\(Int(summary.volume.actual.truncatingRemainder(dividingBy: 1000) / 100))00 lbs total"
            } else {
                text += ", totaling \(Int(summary.volume.actual)) lbs"
            }
        }

        text += ". Tap below for the full breakdown."

        return text
    }
}
