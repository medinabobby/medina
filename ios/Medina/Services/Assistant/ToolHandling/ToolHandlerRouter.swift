//
// ToolHandlerRouter.swift
// Medina
//
// v63.2: Central router for tool handlers
// v69.4: Added ReschedulePlanHandler
// v72.1: Added UpdateExerciseTargetHandler
// v72.2: Added executeOnly for unified batch execution (removes duplicate switch)
// v209: Removed Phase 0+1 handlers (migrated to server - show_schedule, update_profile,
//       skip_workout, suggest_options, create_workout, create_plan, start_workout,
//       end_workout, reset_workout, activate_plan, abandon_plan, delete_plan)
// Dispatches tool calls to appropriate handlers based on tool name
//

import Foundation

/// Routes tool calls to their appropriate handlers
/// NOTE: Phase 0+1 handlers removed - now run on Firebase Functions server
@MainActor
enum ToolHandlerRouter {

    /// Registry of all tool handlers (Phase 2-4 only - server handles Phase 0+1)
    /// Key: tool name (e.g., "modify_workout")
    /// Value: handler type conforming to ToolHandler protocol
    private static let handlers: [String: ToolHandler.Type] = [
        // Phase 2-4: Still on iOS (pending server migration)
        ModifyWorkoutHandler.toolName: ModifyWorkoutHandler.self,
        ChangeProtocolHandler.toolName: ChangeProtocolHandler.self,
        GetSubstitutionHandler.toolName: GetSubstitutionHandler.self,
        GetSummaryHandler.toolName: GetSummaryHandler.self,
        UpdateExerciseTargetHandler.toolName: UpdateExerciseTargetHandler.self,
        ReschedulePlanHandler.toolName: ReschedulePlanHandler.self,
        SendMessageHandler.toolName: SendMessageHandler.self,
        AnalyzeTrainingDataHandler.toolName: AnalyzeTrainingDataHandler.self,
        AddToLibraryHandler.toolName: AddToLibraryHandler.self,
        RemoveFromLibraryHandler.toolName: RemoveFromLibraryHandler.self,
    ]

    /// Main entry point for handling tool calls (streams response)
    /// - Parameters:
    ///   - toolCall: The tool call from StreamProcessor
    ///   - context: Shared context with user, assistant manager, and callbacks
    static func handle(
        _ toolCall: StreamProcessor.ToolCall,
        context: ToolCallContext
    ) async {
        Logger.log(.info, component: "ToolHandlerRouter", message: "🔧 Handling tool call: \(toolCall.name)")

        // Parse tool arguments
        guard let argsData = toolCall.arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else {
            Logger.log(.error, component: "ToolHandlerRouter", message: "❌ Failed to parse tool arguments")
            return
        }

        // Dispatch to appropriate handler
        guard let handler = handlers[toolCall.name] else {
            Logger.log(.warning, component: "ToolHandlerRouter", message: "⚠️ Unknown tool: \(toolCall.name)")
            return
        }

        await handler.handle(toolCall: toolCall, args: args, context: context)
    }

    /// v72.2: Execute tool and return output string (for batch calls)
    /// Uses single registry - no duplicate switch statement needed
    /// - Parameters:
    ///   - toolName: Name of the tool to execute
    ///   - args: Parsed JSON arguments
    ///   - context: Shared context with user, assistant manager, and callbacks
    /// - Returns: Tool output string
    static func executeOnly(
        toolName: String,
        args: [String: Any],
        context: ToolCallContext
    ) async -> String {
        guard let handler = handlers[toolName] else {
            Logger.log(.warning, component: "ToolHandlerRouter", message: "⚠️ Unknown tool: \(toolName)")
            return "ERROR: Unknown tool: \(toolName)"
        }

        return await handler.executeOnly(args: args, context: context)
    }
}
