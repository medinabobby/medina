//
// ChangeProtocolHandler.swift
// Medina
//
// v84.0: Clean protocol change handler
// Created: December 5, 2025
//
// Simple tool for changing workout protocols.
// Uses in-place modification - no delete/recreate.
//

import Foundation

/// Handles change_protocol tool calls
@MainActor
struct ChangeProtocolHandler: ToolHandler {
    static let toolName = "change_protocol"

    /// v66.4: Execute only - returns output string without submitting (for batch calls)
    static func executeOnly(args: [String: Any], context: ToolCallContext) async -> String {
        return await executeLogic(args: args, context: context)
    }

    static func handle(
        toolCall: StreamProcessor.ToolCall,
        args: [String: Any],
        context: ToolCallContext
    ) async {
        let toolOutput = await executeLogic(args: args, context: context)

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

    /// Shared logic for both single and batch execution
    private static func executeLogic(args: [String: Any], context: ToolCallContext) async -> String {
        Logger.log(.info, component: "ChangeProtocolHandler", message: "🔧 Executing change_protocol")

        // Get workout ID from args or use last created
        guard let workoutId = args["workoutId"] as? String ?? context.getLastCreatedWorkoutId() else {
            return "ERROR: No workout ID provided and no recent workout to modify."
        }

        // Parse named protocol (preferred) or custom values
        let namedProtocolStr = args["namedProtocol"] as? String
        let targetReps = args["targetReps"] as? Int
        let targetSets = args["targetSets"] as? Int
        let restBetweenSets = args["restBetweenSets"] as? Int
        let tempo = args["tempo"] as? String
        let targetRPE = args["targetRPE"] as? Double

        Logger.log(.info, component: "ChangeProtocolHandler",
                  message: "Params: namedProtocol=\(namedProtocolStr ?? "nil"), reps=\(targetReps.map { String($0) } ?? "nil"), sets=\(targetSets.map { String($0) } ?? "nil")")

        do {
            let result: ProtocolChangeResult
            let hasCustomValues = targetReps != nil || targetSets != nil || restBetweenSets != nil || tempo != nil || targetRPE != nil

            if let protoStr = namedProtocolStr {
                // v84.1: Use ProtocolResolver for data-driven lookup
                // Supports aliases ("gbc", "drop sets") and direct IDs ("machine_drop_set")
                result = try ProtocolChangeService.changeProtocol(
                    workoutId: workoutId,
                    to: protoStr,
                    repsOverride: targetReps,
                    setsOverride: targetSets,
                    restOverride: restBetweenSets,
                    tempoOverride: tempo,
                    rpeOverride: targetRPE,
                    userId: context.user.id
                )

                if hasCustomValues {
                    Logger.log(.info, component: "ChangeProtocolHandler",
                              message: "✅ Applied '\(protoStr)' with overrides: reps=\(targetReps.map { String($0) } ?? "default"), rest=\(restBetweenSets.map { String($0) } ?? "default"), rpe=\(targetRPE.map { String($0) } ?? "default")")
                } else {
                    Logger.log(.info, component: "ChangeProtocolHandler",
                              message: "✅ Applied '\(protoStr)' to workout")
                }

            } else if hasCustomValues {
                // Use custom values only (no named protocol)
                result = try ProtocolChangeService.changeProtocol(
                    workoutId: workoutId,
                    targetReps: targetReps,
                    targetSets: targetSets,
                    restBetweenSets: restBetweenSets,
                    tempo: tempo,
                    targetRPE: targetRPE,
                    userId: context.user.id
                )

                Logger.log(.info, component: "ChangeProtocolHandler",
                          message: "✅ Applied custom protocol: \(targetReps ?? 0) reps, \(targetSets ?? 0) sets")

            } else {
                return "ERROR: Must provide either namedProtocol (e.g., 'gbc', 'drop sets', 'waves', 'myo') or custom values (targetReps, targetSets, etc.)"
            }

            // Update context with workout ID
            context.setLastCreatedWorkoutId(result.workoutId)

            // Add workout card so user can tap to see changes
            context.addMessage(Message(
                content: "",
                isUser: false,
                workoutCreatedData: WorkoutCreatedData(
                    workoutId: result.workoutId,
                    workoutName: result.workoutName
                )
            ))

            return formatSuccess(result: result)

        } catch let error as ProtocolChangeError {
            return "ERROR: \(error.userMessage)"
        } catch {
            return "ERROR: \(error.localizedDescription)"
        }
    }

    // MARK: - Formatting

    private static func formatSuccess(result: ProtocolChangeResult) -> String {
        let protocolDisplayName = result.protocolName ?? "Custom Protocol"

        return """
        SUCCESS: Protocol changed to \(protocolDisplayName).

        WORKOUT_ID: \(result.workoutId)
        Name: \(result.workoutName)
        Exercises: \(result.exerciseCount)
        Sets updated: \(result.setsUpdated)

        NEW PROTOCOL VALUES:
        - Reps: \(result.newReps) per set
        - Rest: \(result.newRest) seconds
        - Tempo: \(result.newTempo)
        - RPE: \(result.newRPE)

        INSTRUCTIONS:
        1. Confirm the protocol was changed successfully
        2. Briefly explain what changed (e.g., "Now using GBC protocol with 12 reps, 30s rest for metabolic stress")
        3. Tell them to tap the link below to see the updated workout
        """
    }
}
