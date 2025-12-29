//
// ToolHandlerRouter.swift
// Medina
//
// v63.2: Central router for tool handlers
// v212: ALL HANDLERS MIGRATED TO SERVER
// iOS is now a pure passthrough - all tool execution happens on Firebase Functions
// This file retained for backwards compatibility but router is empty
//

import Foundation

/// Routes tool calls to their appropriate handlers
/// NOTE: v212 - ALL handlers migrated to server. iOS is 100% passthrough.
/// This router is now empty - all tool execution happens on Firebase Functions.
@MainActor
enum ToolHandlerRouter {

    /// Registry of all tool handlers
    /// v212: EMPTY - all handlers now run on Firebase Functions server
    /// iOS receives tool results via SSE stream, no local execution needed
    // v212: All 22 handlers now on server:
    // Phase 0: show_schedule, update_profile, suggest_options, skip_workout, delete_plan
    // Phase 1: reset_workout, activate_plan, abandon_plan, start_workout, end_workout, create_workout, create_plan
    // Phase 2: add_to_library, remove_from_library, update_exercise_target, get_substitution_options, get_summary, send_message, reschedule_plan
    // Phase 3: modify_workout, change_protocol, analyze_training_data
    private static let handlers: [String: ToolHandler.Type] = [:]

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
