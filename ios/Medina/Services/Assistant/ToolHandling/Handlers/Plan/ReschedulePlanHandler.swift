//
// ReschedulePlanHandler.swift
// Medina
//
// v69.4: Handler for reschedule_plan tool
// v69.7: Improved error messages with plan type suggestions
// v74.10: Show plan card after reschedule (user shouldn't scroll to find plan)
// Changes schedule of existing plans without losing completed workout progress
//

import Foundation

/// Handles reschedule_plan tool calls
@MainActor
struct ReschedulePlanHandler: ToolHandler {
    static let toolName = "reschedule_plan"

    /// v69.4: Execute only - returns output string without submitting (for batch calls)
    static func executeOnly(args: [String: Any], context: ToolCallContext) async -> String {
        return await executeLogic(args: args, context: context)
    }

    static func handle(
        toolCall: StreamProcessor.ToolCall,
        args: [String: Any],
        context: ToolCallContext
    ) async {
        let toolOutput = await executeLogic(args: args, context: context)

        if !toolOutput.hasPrefix("ERROR:") {
            await ToolHandlerUtilities.streamToolResponse(
                toolCall: toolCall,
                toolOutput: toolOutput,
                context: context
            )
        } else {
            await ToolHandlerUtilities.submitToolError(
                toolCall: toolCall,
                output: toolOutput,
                context: context
            )
        }
    }

    /// v69.4: Shared logic for both single and batch execution
    private static func executeLogic(args: [String: Any], context: ToolCallContext) async -> String {
        Logger.log(.info, component: "ReschedulePlanHandler", message: "🔧 Executing reschedule_plan tool")

        // Parse planId - supports "current", "draft", or specific ID
        guard let planIdArg = args["planId"] as? String else {
            Logger.log(.error, component: "ReschedulePlanHandler", message: "❌ Missing required parameter: planId")
            return "ERROR: Missing required parameter 'planId'. Use 'current' for active plan, 'draft' for draft, or specific plan ID."
        }

        // Parse new preferred days
        guard let newDaysArray = args["newPreferredDays"] as? [String], !newDaysArray.isEmpty else {
            Logger.log(.error, component: "ReschedulePlanHandler", message: "❌ Missing required parameter: newPreferredDays")
            return "ERROR: Missing required parameter 'newPreferredDays'. Provide array like ['monday', 'wednesday', 'friday']."
        }

        let newPreferredDays = Set(newDaysArray.compactMap { ToolHandlerUtilities.parseDayOfWeek($0) })
        if newPreferredDays.isEmpty {
            Logger.log(.error, component: "ReschedulePlanHandler", message: "❌ Could not parse any valid days from: \(newDaysArray)")
            return "ERROR: Could not parse training days. Use lowercase day names like 'monday', 'wednesday', 'friday'."
        }

        // Resolve the plan
        let userId = context.user.id
        let plan: Plan?

        // v69.7: Check what plans exist for better error messages
        let activePlan = PlanResolver.activePlan(for: userId)
        let draftPlan = PlanResolver.draftPlans(for: userId).first

        switch planIdArg.lowercased() {
        case "current":
            plan = activePlan
            if plan == nil {
                Logger.log(.warning, component: "ReschedulePlanHandler", message: "⚠️ No active plan found")
                if draftPlan != nil {
                    // User has a draft but tried "current" - suggest using "draft"
                    return "ERROR: No active plan found, but there IS a draft plan. Use planId: \"draft\" to reschedule the draft, or use create_plan to replace it."
                }
                return "ERROR: No active plan found. Create a new plan with create_plan instead."
            }
        case "draft":
            plan = draftPlan
            if plan == nil {
                Logger.log(.warning, component: "ReschedulePlanHandler", message: "⚠️ No draft plan found")
                if activePlan != nil {
                    // User has active plan but tried "draft" - suggest using "current"
                    return "ERROR: No draft plan found, but there IS an active plan. Use planId: \"current\" to reschedule the active plan."
                }
                return "ERROR: No draft plan found. Create a new plan with create_plan instead."
            }
        default:
            plan = TestDataManager.shared.plans[planIdArg]
            if plan == nil {
                Logger.log(.warning, component: "ReschedulePlanHandler", message: "⚠️ Plan not found: \(planIdArg)")
                // Suggest available options
                var suggestion = "ERROR: Plan not found with ID '\(planIdArg)'."
                if activePlan != nil {
                    suggestion += " Use planId: \"current\" for the active plan."
                }
                if draftPlan != nil {
                    suggestion += " Use planId: \"draft\" for the draft plan."
                }
                return suggestion
            }
        }

        guard let targetPlan = plan else {
            return "ERROR: Could not resolve plan."
        }

        // Parse optional parameters
        let newDaysPerWeek = args["newDaysPerWeek"] as? Int ?? newPreferredDays.count
        let newCardioDays = args["newCardioDays"] as? Int

        // Parse AI's day assignments
        var dayAssignments: [DayOfWeek: SessionType]? = nil
        if let assignments = args["workoutDayAssignments"] as? [String: String] {
            dayAssignments = [:]
            for (dayStr, typeStr) in assignments {
                if let day = ToolHandlerUtilities.parseDayOfWeek(dayStr) {
                    dayAssignments?[day] = typeStr.lowercased() == "cardio" ? .cardio : .strength
                }
            }
        }

        Logger.log(.info, component: "ReschedulePlanHandler",
                  message: "📅 Rescheduling plan '\(targetPlan.name)' to \(newPreferredDays.map { $0.displayName }.sorted())")

        do {
            let result = try await PlanRescheduleService.reschedule(
                plan: targetPlan,
                newPreferredDays: newPreferredDays,
                newDaysPerWeek: newDaysPerWeek,
                newCardioDays: newCardioDays,
                dayAssignments: dayAssignments,
                userId: userId
            )

            Logger.log(.info, component: "ReschedulePlanHandler",
                      message: "✅ Rescheduled plan: \(result.rescheduledCount) workouts regenerated, \(result.preservedCount) preserved")

            // v74.10: Queue plan card to appear after AI text streams
            let workoutCount = result.rescheduledCount + result.preservedCount
            let durationWeeks = calculateDurationWeeks(for: result.plan)
            context.addPendingCard(Message(
                content: "",
                isUser: false,
                planCreatedData: PlanCreatedData(
                    planId: result.plan.id,
                    planName: result.plan.name,
                    workoutCount: workoutCount,
                    durationWeeks: durationWeeks
                )
            ))

            return formatSuccess(result: result, newDays: newPreferredDays)

        } catch {
            Logger.log(.error, component: "ReschedulePlanHandler", message: "❌ Reschedule failed: \(error)")
            return "ERROR: Failed to reschedule plan: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    /// v74.10: Calculate plan duration in weeks
    private static func calculateDurationWeeks(for plan: Plan) -> Int {
        let days = Calendar.current.dateComponents([.day], from: plan.startDate, to: plan.endDate).day ?? 0
        return max(1, (days + 6) / 7)  // Round up to nearest week
    }

    // MARK: - Formatting

    private static func formatSuccess(result: PlanRescheduleService.RescheduleResult, newDays: Set<DayOfWeek>) -> String {
        let sortedDays = newDays.sorted { $0.rawValue < $1.rawValue }.map { $0.displayName }.joined(separator: ", ")

        var response = """
        SUCCESS: Plan rescheduled.

        PLAN: \(result.plan.name)
        NEW_SCHEDULE: \(sortedDays)
        WORKOUTS_REGENERATED: \(result.rescheduledCount)
        """

        if result.preservedCount > 0 {
            response += "\nCOMPLETED_PRESERVED: \(result.preservedCount)"
        }

        response += """

        INSTRUCTIONS FOR RESPONSE:
        1. Confirm the new schedule (mention the days)
        2. State how many workouts were rescheduled
        """

        if result.preservedCount > 0 {
            response += "\n3. Mention that \(result.preservedCount) completed workout(s) were preserved"
        }

        response += "\n4. Keep response brief and conversational"

        return response
    }
}
