//
// ToolHandlerUtilities.swift
// Medina
//
// v63.2: Shared utilities for tool handlers
// v72.2: Consolidated streaming into single streamAndHandleEvents() function
// v80.0: Updated for Responses API - simplified tool handling flow
// v141: Added suggestion chips data consumption
// v175.1: Added workoutCreatedData consumption (was missing, causing card not to show)
// v186: Removed class schedule card data (class booking deferred for beta)
// Extracted from ToolCallHandler for reuse across all handlers
//

import SwiftUI

/// Shared utilities for tool handlers
@MainActor
enum ToolHandlerUtilities {

    // MARK: - Unified Streaming (v80.0 - Responses API)

    /// Configuration for streaming behavior
    struct StreamConfig {
        /// Initial message to display (default: empty assistant message)
        var initialMessage: Message = Message(content: "", isUser: false)
        /// Whether to flush pending cards after streaming (default: true)
        var flushCardsOnComplete: Bool = true
        /// Callback invoked after streaming completes
        var onComplete: (() -> Void)? = nil
        /// Component name for logging
        var logComponent: String = "ToolHandlerUtilities"
    }

    /// v80.0: Unified streaming function for Responses API
    /// Handles text deltas, tool calls, and completion events
    ///
    /// - Parameters:
    ///   - stream: The async stream of ResponseEvents from OpenAI Responses API
    ///   - context: Tool call context with message callbacks
    ///   - config: Configuration options for streaming behavior
    private static func streamAndHandleResponseEvents(
        _ stream: AsyncThrowingStream<ResponseStreamProcessor.ResponseEvent, Error>,
        context: ToolCallContext,
        config: StreamConfig = StreamConfig()
    ) async {
        // v108.1: Check for pending analysis card data from batch tool execution
        let analysisCardData = context.pendingAnalysisCardData
        context.pendingAnalysisCardData = nil  // Consume it

        // v186: Removed class schedule card data (class booking deferred for beta)

        // v141: Check for pending suggestion chips from batch tool execution
        let suggestionChipsData = context.pendingSuggestionChipsData
        context.pendingSuggestionChipsData = nil  // Consume it

        // v175.1: Check for pending workout created data (start_workout card)
        let workoutCreatedData = context.pendingWorkoutCreatedData
        context.pendingWorkoutCreatedData = nil  // Consume it

        // v146: Add placeholder message with ALL pending data (cards + chips together)
        // Previously cards and chips were mutually exclusive - now both can appear
        // v186: Removed classScheduleCardData (class booking deferred for beta)
        let initialMessage = Message(
            content: config.initialMessage.content,
            isUser: false,
            workoutCreatedData: workoutCreatedData,
            analysisCardData: analysisCardData,
            suggestionChipsData: suggestionChipsData
        )
        context.addMessage(initialMessage)
        let messageIndex = context.messagesCount() - 1

        var accumulatedText = ""

        do {
            streamLoop: for try await event in stream {
                switch event {
                case .responseCreated:
                    // v80.1: Response ID captured by ResponsesManager for tool continuation
                    break

                case .textDelta(let delta):
                    accumulatedText += delta
                    // v108.1/v141/v175.1/v186: Preserve card data during streaming updates
                    let updatedMessage = Message(
                        content: accumulatedText,
                        isUser: false,
                        workoutCreatedData: workoutCreatedData,
                        analysisCardData: analysisCardData,
                        suggestionChipsData: suggestionChipsData
                    )
                    context.updateMessage(messageIndex, updatedMessage)

                case .textDone:
                    Logger.log(.debug, component: config.logComponent, message: "✅ Text generation complete")

                case .responseCompleted(let responseId):
                    Logger.log(.info, component: config.logComponent, message: "✅ Response completed: \(responseId)")
                    break streamLoop

                case .responseFailed(let error):
                    Logger.log(.error, component: config.logComponent, message: "❌ Response failed: \(error)")
                    break streamLoop

                case .toolCall(let toolCall):
                    Logger.log(.info, component: config.logComponent, message: "🔧 Tool call: \(toolCall.name)")
                    await handleResponseToolCall(toolCall, context: context)

                case .toolCalls(let toolCalls):
                    Logger.log(.info, component: config.logComponent, message: "🔧 Batch tool calls: \(toolCalls.count)")
                    await handleResponseBatchToolCalls(toolCalls: toolCalls, context: context)

                case .error(let error):
                    Logger.log(.error, component: config.logComponent, message: "❌ Stream error: \(error)")
                    break streamLoop

                // v210: Workout card from server handler
                case .workoutCard(let cardData):
                    Logger.log(.info, component: config.logComponent, message: "📋 Workout card: \(cardData.workoutName)")
                    context.addMessage(Message(
                        content: "",
                        isUser: false,
                        workoutCreatedData: WorkoutCreatedData(
                            workoutId: cardData.workoutId,
                            workoutName: cardData.workoutName
                        )
                    ))

                // v210: Plan card from server handler
                case .planCard(let cardData):
                    Logger.log(.info, component: config.logComponent, message: "📋 Plan card: \(cardData.planName)")
                    context.addMessage(Message(
                        content: "",
                        isUser: false,
                        planCreatedData: PlanCreatedData(
                            planId: cardData.planId,
                            planName: cardData.planName,
                            workoutCount: cardData.workoutCount,
                            durationWeeks: cardData.durationWeeks
                        )
                    ))

                // v211: Suggestion chips from server (ignored for now)
                case .suggestionChips:
                    break
                }
            }

            Logger.log(.info, component: config.logComponent,
                      message: "✅ Stream finished, text length: \(accumulatedText.count)")

        } catch {
            Logger.log(.error, component: config.logComponent,
                      message: "❌ Stream failed: \(error)")
        }

        // Post-stream cleanup
        if config.flushCardsOnComplete {
            context.flushPendingCards()
        }
        config.onComplete?()
    }

    // MARK: - v80.0: Responses API Tool Handling

    /// Handle a single tool call from Responses API
    /// Execute tool, store output, then continue conversation
    private static func handleResponseToolCall(
        _ toolCall: ResponseStreamProcessor.ToolCall,
        context: ToolCallContext
    ) async {
        // Parse arguments
        guard let jsonData = toolCall.arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            Logger.log(.error, component: "ToolHandlerUtilities", message: "❌ Failed to parse tool arguments")
            return
        }

        // Execute tool using registry
        let output = await ToolHandlerRouter.executeOnly(
            toolName: toolCall.name,
            args: args,
            context: context
        )

        let status = output.hasPrefix("ERROR:") ? "❌" : "✅"
        Logger.spine("ToolHandler", "\(status) \(toolCall.name) done")

        // Store output and continue conversation
        context.responsesManager.executeToolAndStoreOutput(toolCallId: toolCall.id, output: output)

        // Continue the conversation to get AI's response based on tool output
        let continueStream = context.responsesManager.continueAfterToolExecution()

        var config = StreamConfig()
        config.flushCardsOnComplete = true
        config.logComponent = "ToolContinuation"

        await streamAndHandleResponseEvents(continueStream, context: context, config: config)
    }

    /// Handle multiple parallel tool calls from Responses API
    private static func handleResponseBatchToolCalls(
        toolCalls: [ResponseStreamProcessor.ToolCall],
        context: ToolCallContext
    ) async {
        guard !toolCalls.isEmpty else { return }

        let names = toolCalls.map { $0.name }.joined(separator: ", ")
        Logger.spine("ToolHandler", "Executing batch: \(names)")
        Logger.log(.info, component: "ToolHandlerUtilities",
                  message: "📤 Handling \(toolCalls.count) parallel tool calls")

        // Execute all tools and store outputs
        for toolCall in toolCalls {
            guard let jsonData = toolCall.arguments.data(using: .utf8),
                  let args = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                context.responsesManager.executeToolAndStoreOutput(
                    toolCallId: toolCall.id,
                    output: "ERROR: Failed to parse tool arguments"
                )
                continue
            }

            let output = await ToolHandlerRouter.executeOnly(
                toolName: toolCall.name,
                args: args,
                context: context
            )

            let status = output.hasPrefix("ERROR:") ? "❌" : "✅"
            Logger.spine("ToolHandler", "\(status) \(toolCall.name) done")

            context.responsesManager.executeToolAndStoreOutput(toolCallId: toolCall.id, output: output)
        }

        // Continue conversation with all tool outputs
        Logger.spine("ToolHandler", "Continuing after \(toolCalls.count) tools")

        let continueStream = context.responsesManager.continueAfterToolExecution()

        var config = StreamConfig()
        config.flushCardsOnComplete = true
        config.logComponent = "BatchToolContinuation"

        await streamAndHandleResponseEvents(continueStream, context: context, config: config)
    }

    // MARK: - Public Streaming Helpers (v80.0)

    /// Stream tool response and update message in chat
    /// v80.0: Updated for Responses API - execute tool and continue
    static func streamToolResponse(
        toolCall: StreamProcessor.ToolCall,
        toolOutput: String,
        context: ToolCallContext,
        initialMessage: Message? = nil
    ) async {
        let status = toolOutput.hasPrefix("ERROR:") ? "❌" : "✅"
        Logger.spine("ToolHandler", "\(status) \(toolCall.name) → storing output")
        Logger.log(.info, component: "ToolHandlerUtilities",
                  message: "📤 Storing tool output for \(toolCall.name)")

        // Store the output
        context.responsesManager.executeToolAndStoreOutput(toolCallId: toolCall.id, output: toolOutput)

        // Continue conversation
        let stream = context.responsesManager.continueAfterToolExecution()

        var config = StreamConfig()
        config.initialMessage = initialMessage ?? Message(content: "", isUser: false)
        config.flushCardsOnComplete = true

        await streamAndHandleResponseEvents(stream, context: context, config: config)
    }

    /// Submit tool error and stream AI's error response
    static func submitToolError(
        toolCall: StreamProcessor.ToolCall,
        output: String,
        context: ToolCallContext
    ) async {
        // Store error output
        context.responsesManager.executeToolAndStoreOutput(toolCallId: toolCall.id, output: output)

        // Continue conversation
        let stream = context.responsesManager.continueAfterToolExecution()

        var config = StreamConfig()
        config.flushCardsOnComplete = false

        await streamAndHandleResponseEvents(stream, context: context, config: config)
    }

    /// Stream response with callback on completion
    /// Used for creation tools that add a card after AI response
    static func streamWithCard(
        toolCall: StreamProcessor.ToolCall,
        toolOutput: String,
        context: ToolCallContext,
        onComplete: @escaping () -> Void
    ) async {
        // Store output
        context.responsesManager.executeToolAndStoreOutput(toolCallId: toolCall.id, output: toolOutput)

        // Continue conversation
        let stream = context.responsesManager.continueAfterToolExecution()

        var config = StreamConfig()
        config.flushCardsOnComplete = false
        config.onComplete = onComplete

        await streamAndHandleResponseEvents(stream, context: context, config: config)
    }

    // MARK: - Batch Tool Call Handling (Legacy support)

    /// Execute multiple parallel tool calls
    /// v80.0: Updated to use Responses API flow
    static func handleBatchToolCalls(
        toolCalls: [StreamProcessor.ToolCall],
        context: ToolCallContext
    ) async {
        guard !toolCalls.isEmpty else { return }

        let names = toolCalls.map { $0.name }.joined(separator: ", ")
        Logger.spine("ToolHandler", "Executing batch: \(names)")

        // Execute all tools and store outputs
        for toolCall in toolCalls {
            let output = await executeToolOnly(toolCall: toolCall, context: context)
            context.responsesManager.executeToolAndStoreOutput(toolCallId: toolCall.id, output: output)
            let status = output.hasPrefix("ERROR:") ? "❌" : "✅"
            Logger.spine("ToolHandler", "\(status) \(toolCall.name) done")
        }

        // Continue conversation
        let stream = context.responsesManager.continueAfterToolExecution()

        var config = StreamConfig()
        config.flushCardsOnComplete = true
        config.logComponent = "BatchToolHandler"

        await streamAndHandleResponseEvents(stream, context: context, config: config)
    }

    /// Execute a single tool and return the output string (without continuing)
    private static func executeToolOnly(
        toolCall: StreamProcessor.ToolCall,
        context: ToolCallContext
    ) async -> String {
        guard let jsonData = toolCall.arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return "ERROR: Failed to parse tool arguments"
        }

        return await ToolHandlerRouter.executeOnly(
            toolName: toolCall.name,
            args: args,
            context: context
        )
    }

    // MARK: - Enum Parsing

    /// Parse SplitDay from string
    static func parseSplitDay(_ str: String?) -> SplitDay? {
        guard let str = str else { return nil }
        switch str.lowercased() {
        case "upper": return .upper
        case "lower": return .lower
        case "push": return .push
        case "pull": return .pull
        case "legs": return .legs
        case "fullbody", "full_body": return .fullBody
        case "chest": return .chest
        case "back": return .back
        case "shoulders": return .shoulders
        case "arms": return .arms
        default: return nil
        }
    }

    /// Parse EffortLevel from string
    static func parseEffortLevel(_ str: String?) -> EffortLevel? {
        guard let str = str else { return nil }
        switch str.lowercased() {
        case "recovery": return .recovery
        case "standard": return .standard
        case "push", "pushit", "push_it": return .pushIt
        default: return nil
        }
    }

    /// Parse FitnessGoal from string
    static func parseFitnessGoal(_ str: String?) -> FitnessGoal {
        guard let str = str else { return .generalFitness }
        switch str.lowercased() {
        case "strength": return .strength
        case "musclegain", "hypertrophy": return .muscleGain
        case "fatloss", "weightloss": return .fatLoss
        case "endurance": return .endurance
        case "athleticperformance", "athletic", "sports": return .athleticPerformance  // v66.2
        default: return .generalFitness
        }
    }

    /// Parse DayOfWeek from string
    static func parseDayOfWeek(_ str: String) -> DayOfWeek? {
        switch str.lowercased() {
        case "sunday": return .sunday
        case "monday": return .monday
        case "tuesday": return .tuesday
        case "wednesday": return .wednesday
        case "thursday": return .thursday
        case "friday": return .friday
        case "saturday": return .saturday
        default: return nil
        }
    }

    /// Parse ISO date from string
    static func parseDate(_ str: String?) -> Date? {
        guard let str = str else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: str)
    }

    /// Parse ISO date (date only, no time) from string
    static func parseDateOnly(_ str: String?) -> Date? {
        guard let str = str else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: str)
    }

    // MARK: - v67: Parameter Resolution Helpers

    /// Resolve an Int parameter with priority: AI args → profile → default
    /// Logs the resolution source for debugging
    static func resolveInt(
        key: String,
        args: [String: Any],
        profile: Int?,
        default defaultValue: Int,
        component: String
    ) -> Int {
        if let aiValue = args[key] as? Int {
            Logger.log(.info, component: component, message: "✅ Using AI's \(key): \(aiValue)")
            return aiValue
        } else if let profileValue = profile, profileValue > 0 {
            Logger.log(.info, component: component, message: "✅ Using profile \(key): \(profileValue)")
            return profileValue
        } else {
            Logger.log(.info, component: component, message: "⚠️ Using default \(key): \(defaultValue)")
            return defaultValue
        }
    }

    /// Resolve an enum parameter with priority: AI args → profile → default
    /// Parser converts string to enum type
    static func resolveEnum<T>(
        key: String,
        args: [String: Any],
        parser: (String?) -> T?,
        profile: T?,
        default defaultValue: T,
        component: String
    ) -> T {
        if let aiString = args[key] as? String, let aiValue = parser(aiString) {
            Logger.log(.info, component: component, message: "✅ Using AI's \(key): \(aiString)")
            return aiValue
        } else if let profileValue = profile {
            Logger.log(.info, component: component, message: "✅ Using profile \(key)")
            return profileValue
        } else {
            Logger.log(.info, component: component, message: "⚠️ Using default \(key)")
            return defaultValue
        }
    }

    /// Resolve an optional enum parameter with priority: AI args → profile → nil
    /// Returns nil if neither AI nor profile specify a value
    static func resolveOptionalEnum<T>(
        key: String,
        args: [String: Any],
        parser: (String?) -> T?,
        profile: T?,
        component: String
    ) -> T? {
        if let aiString = args[key] as? String, let aiValue = parser(aiString) {
            Logger.log(.info, component: component, message: "✅ Using AI's \(key): \(aiString)")
            return aiValue
        } else if let profileValue = profile {
            Logger.log(.info, component: component, message: "✅ Using profile \(key)")
            return profileValue
        } else {
            Logger.log(.info, component: component, message: "⚠️ No \(key) specified - will auto-recommend")
            return nil
        }
    }

    /// Resolve a Set<MuscleGroup> parameter with priority: AI args → profile → nil
    static func resolveMuscleGroups(
        key: String,
        args: [String: Any],
        profile: Set<MuscleGroup>?,
        component: String
    ) -> Set<MuscleGroup>? {
        if let aiArray = args[key] as? [String] {
            let groups = Set(aiArray.compactMap { parseMuscleGroup($0) })
            if !groups.isEmpty {
                Logger.log(.info, component: component, message: "✅ Using AI's \(key): \(groups.count) groups")
                return groups
            }
        }
        if let profileValue = profile, !profileValue.isEmpty {
            Logger.log(.info, component: component, message: "✅ Using profile \(key): \(profileValue.count) groups")
            return profileValue
        }
        Logger.log(.info, component: component, message: "⚠️ No \(key) specified")
        return nil
    }

    // MARK: - v67: Additional Enum Parsers

    /// Parse SplitType from string
    static func parseSplitType(_ str: String?) -> SplitType? {
        guard let str = str else { return nil }
        switch str.lowercased() {
        case "fullbody", "full_body": return .fullBody
        case "upperlower", "upper_lower": return .upperLower
        case "pushpull", "push_pull": return .pushPull
        case "pushpulllegs", "push_pull_legs", "ppl": return .pushPullLegs
        case "bodypart", "body_part", "bro_split": return .bodyPart
        default: return nil
        }
    }

    /// Parse TrainingLocation from string
    static func parseTrainingLocation(_ str: String?) -> TrainingLocation? {
        guard let str = str else { return nil }
        switch str.lowercased() {
        case "gym": return .gym
        case "home": return .home
        case "outdoor", "outdoors": return .outdoor
        default: return nil
        }
    }

    /// Parse ExperienceLevel from string
    static func parseExperienceLevel(_ str: String?) -> ExperienceLevel? {
        guard let str = str else { return nil }
        switch str.lowercased() {
        case "beginner": return .beginner
        case "intermediate": return .intermediate
        case "advanced": return .advanced
        case "expert": return .expert
        default: return nil
        }
    }

    /// Parse MuscleGroup from string
    static func parseMuscleGroup(_ str: String) -> MuscleGroup? {
        switch str.lowercased() {
        case "chest", "pecs": return .chest
        case "back": return .back
        case "lats": return .lats
        case "shoulders", "delts": return .shoulders
        case "biceps": return .biceps
        case "triceps": return .triceps
        case "quads", "quadriceps": return .quadriceps
        case "hamstrings", "hams": return .hamstrings
        case "glutes": return .glutes
        case "calves": return .calves
        case "core": return .core
        case "abs": return .abs
        case "forearms": return .forearms
        case "traps", "trapezius": return .traps
        case "fullbody", "full_body": return .fullBody
        default: return nil
        }
    }

    // MARK: - Auto Training Days

    /// Auto-select training days based on count (spread evenly across week)
    static func autoSelectTrainingDays(count: Int) -> Set<DayOfWeek> {
        switch count {
        case 2: return [.monday, .thursday]
        case 3: return [.monday, .wednesday, .friday]
        case 4: return [.monday, .tuesday, .thursday, .friday]
        case 5: return [.monday, .tuesday, .wednesday, .friday, .saturday]
        case 6: return [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        default: return [.monday, .tuesday, .thursday, .friday]
        }
    }
}
