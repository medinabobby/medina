//
// ModifyWorkoutHandler.swift
// Medina
//
// v63.2: Handler for modify_workout tool
// v83.2: Added protocolCustomizations support, preserves exercises/supersets
// Modifies an existing workout's parameters
//

import Foundation

/// Handles modify_workout tool calls
@MainActor
struct ModifyWorkoutHandler: ToolHandler {
    static let toolName = "modify_workout"

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

    /// v66.4: Shared logic for both single and batch execution
    private static func executeLogic(args: [String: Any], context: ToolCallContext) async -> String {
        Logger.log(.info, component: "ModifyWorkoutHandler", message: "🔧 Executing modify_workout")

        // Get workout ID from args or use last created
        guard let workoutId = args["workoutId"] as? String ?? context.getLastCreatedWorkoutId() else {
            return "ERROR: No workout ID provided and no recent workout to modify."
        }

        // Parse optional modification parameters
        let newDuration = args["newDuration"] as? Int
        let newSplitDayStr = args["newSplitDay"] as? String
        let newEffortLevelStr = args["newEffortLevel"] as? String
        let newName = args["newName"] as? String
        let newScheduledDateStr = args["newScheduledDate"] as? String
        // v101.1: Parse session type change
        let newSessionTypeStr = args["newSessionType"] as? String
        // v129: Parse training location change
        let newTrainingLocationStr = args["newTrainingLocation"] as? String

        // Convert string values to enums using utilities
        let newSplitDay = ToolHandlerUtilities.parseSplitDay(newSplitDayStr)
        let newEffortLevel = ToolHandlerUtilities.parseEffortLevel(newEffortLevelStr)
        let newScheduledDate = ToolHandlerUtilities.parseDate(newScheduledDateStr)
        // v101.1: Parse session type
        let newSessionType: SessionType? = newSessionTypeStr.flatMap { SessionType(rawValue: $0) }
        // v129: Parse training location
        let newTrainingLocation: TrainingLocation? = newTrainingLocationStr.flatMap { TrainingLocation(rawValue: $0) }

        // v83.2: Parse protocol customizations
        let protocolCustomizations = parseProtocolCustomizations(args["protocolCustomizations"])

        Logger.log(.info, component: "ModifyWorkoutHandler",
                  message: "Parsed params: duration=\(newDuration.map { String($0) } ?? "nil"), split=\(newSplitDayStr ?? "nil"), sessionType=\(newSessionTypeStr ?? "nil"), location=\(newTrainingLocationStr ?? "nil"), customizations=\(protocolCustomizations?.count ?? 0)")

        // v83.5: When customizations are provided, IGNORE duration/split to force exercise preservation
        // This prevents AI from accidentally triggering structural changes during protocol-only modifications
        let effectiveDuration: Int?
        let effectiveSplitDay: SplitDay?

        if protocolCustomizations != nil {
            // Protocol customization mode - null out structural params
            effectiveDuration = nil
            effectiveSplitDay = nil
            if newDuration != nil || newSplitDay != nil {
                Logger.log(.info, component: "ModifyWorkoutHandler",
                          message: "v83.5: Ignoring duration/splitDay params because protocolCustomizations provided - preserving exercises")
            }
        } else {
            // Structural change mode - use provided params
            effectiveDuration = newDuration
            effectiveSplitDay = newSplitDay
        }

        // Build modification data
        // v83.5: When customizations provided, duration/split are nil to guarantee exercise preservation
        // v101.1: Session type change is a structural change that replaces exercises
        // v129: Training location change is also a structural change
        let modification = WorkoutModificationData(
            workoutId: workoutId,
            newDuration: effectiveDuration,
            newSplitDay: effectiveSplitDay,
            newEffortLevel: newEffortLevel,
            newName: newName,
            newScheduledDate: newScheduledDate,
            newSessionType: newSessionType,  // v101.1: Pass session type change
            newTrainingLocation: newTrainingLocation,  // v129: Pass training location change
            protocolCustomizations: protocolCustomizations,
            preserveExercises: newSessionType == nil && newTrainingLocation == nil  // v129: Don't preserve when changing location
        )

        do {
            let (newWorkoutId, newPlan) = try await WorkoutModificationService.modifyWorkout(
                modification,
                userId: context.user.id
            )

            context.setLastCreatedWorkoutId(newWorkoutId)

            // Add workout card
            context.addMessage(Message(
                content: "",
                isUser: false,
                workoutCreatedData: WorkoutCreatedData(
                    workoutId: newWorkoutId,
                    workoutName: newPlan.name
                )
            ))

            return formatModificationSuccess(plan: newPlan, workoutId: newWorkoutId)

        } catch let error as WorkoutModificationError {
            return "ERROR: \(error.userMessage)"
        } catch {
            return "ERROR: \(error.localizedDescription)"
        }
    }

    // MARK: - Formatting

    private static func formatModificationSuccess(plan: Plan, workoutId: String) -> String {
        guard let workout = TestDataManager.shared.workouts[workoutId] else {
            return "Workout modified successfully."
        }

        let exerciseNames = workout.exerciseIds.compactMap { id in
            TestDataManager.shared.exercises[id]?.name
        }

        // v83.2: Include superset info in response if present
        var supersetInfo = ""
        if let groups = workout.supersetGroups, !groups.isEmpty {
            supersetInfo = "\nSupersets: \(groups.count) group(s) preserved"
        }

        return """
        SUCCESS: Workout modified.

        NEW_WORKOUT_ID: \(workout.id)
        Name: \(plan.name)
        Exercise count: \(workout.exerciseIds.count)
        Exercises: \(exerciseNames.joined(separator: ", "))\(supersetInfo)

        INSTRUCTIONS:
        1. Confirm the modification was successful
        2. Briefly describe what changed
        3. Tell them the updated workout link is below
        """
    }

    // MARK: - v83.2: Protocol Customization Parsing

    /// Parse protocolCustomizations array from tool args
    /// Expected format: [{ "exercisePosition": 0, "repsAdjustment": 2, "tempoOverride": "3010", "rationale": "..." }]
    private static func parseProtocolCustomizations(_ arg: Any?) -> [Int: ProtocolCustomization]? {
        guard let customizationsArray = arg as? [[String: Any]], !customizationsArray.isEmpty else {
            return nil
        }

        var result: [Int: ProtocolCustomization] = [:]

        for customDict in customizationsArray {
            guard let position = customDict["exercisePosition"] as? Int else {
                Logger.log(.warning, component: "ModifyWorkoutHandler",
                          message: "Skipping customization: missing exercisePosition")
                continue
            }

            // Parse adjustment values (default to 0 if not provided)
            let repsAdjustment = customDict["repsAdjustment"] as? Int ?? 0
            let restAdjustment = customDict["restAdjustment"] as? Int ?? 0
            let setsAdjustment = customDict["setsAdjustment"] as? Int ?? 0
            let tempoOverride = customDict["tempoOverride"] as? String
            let rpeOverride = customDict["rpeOverride"] as? Double  // v83.4
            let rationale = customDict["rationale"] as? String

            // We need a baseProtocolId - we'll use a placeholder since we're modifying
            // The actual base protocol will be resolved when applying customizations
            let customization = ProtocolCustomization(
                baseProtocolId: "pending_resolution",  // Will be resolved in WorkoutCreationService
                setsAdjustment: setsAdjustment,
                repsAdjustment: repsAdjustment,
                restAdjustment: restAdjustment,
                tempoOverride: tempoOverride,
                rpeOverride: rpeOverride,  // v83.4
                rationale: rationale
            )

            result[position] = customization

            Logger.log(.info, component: "ModifyWorkoutHandler",
                      message: "Parsed customization for position \(position): reps=\(repsAdjustment), rest=\(restAdjustment), tempo=\(tempoOverride ?? "nil"), rpe=\(rpeOverride.map { String($0) } ?? "nil")")
        }

        return result.isEmpty ? nil : result
    }
}
