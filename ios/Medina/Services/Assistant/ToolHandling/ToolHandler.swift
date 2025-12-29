//
// ToolHandler.swift
// Medina
//
// v63.2: Protocol for tool handlers (refactored from monolithic ToolCallHandler)
// v72.2: Added executeOnly to protocol for unified batch execution
// v80.0: Updated for Responses API - simplified tool call handling
// v109.3: Added pendingClassScheduleCardData for calendar-style class listings
// v141: Added pendingSuggestionChipsData for response suggestion chips
// v174: Added pendingWorkoutCreatedData for card-below-text pattern
// Each tool handler implements this protocol and handles a specific AI tool call
//

import Foundation

/// v80.0: Unified ToolCall type for both APIs (transition support)
/// Eventually only ResponseStreamProcessor.ToolCall will be used
struct UnifiedToolCall {
    let id: String
    let name: String
    let arguments: String

    // v80.0: Create from ResponseStreamProcessor.ToolCall
    init(from responseToolCall: ResponseStreamProcessor.ToolCall) {
        self.id = responseToolCall.id
        self.name = responseToolCall.name
        self.arguments = responseToolCall.arguments
    }

    // Legacy: Create from StreamProcessor.ToolCall (deprecated)
    init(from assistantToolCall: StreamProcessor.ToolCall) {
        self.id = assistantToolCall.id
        self.name = assistantToolCall.name
        self.arguments = assistantToolCall.arguments
    }

    // Direct initialization
    init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// Protocol for all tool handlers
/// Each handler is responsible for a single tool (e.g., create_workout, show_schedule)
protocol ToolHandler {
    /// The tool name this handler responds to (e.g., "create_workout", "show_schedule")
    static var toolName: String { get }

    /// Handle the tool call (streams response to user)
    /// v80.0: Now uses UnifiedToolCall instead of StreamProcessor.ToolCall
    /// - Parameters:
    ///   - toolCall: The tool call with id, name, arguments
    ///   - args: Parsed JSON arguments as dictionary
    ///   - context: Shared context with user, responses manager, and message callbacks
    static func handle(
        toolCall: StreamProcessor.ToolCall,
        args: [String: Any],
        context: ToolCallContext
    ) async

    /// v72.2: Execute tool and return output string (for batch calls)
    /// Returns the tool output without submitting to OpenAI - caller handles submission
    /// - Parameters:
    ///   - args: Parsed JSON arguments as dictionary
    ///   - context: Shared context with user, responses manager, and message callbacks
    /// - Returns: Tool output string to be submitted to OpenAI
    static func executeOnly(args: [String: Any], context: ToolCallContext) async -> String
}

/// Shared context for all tool handlers
/// Contains dependencies and callbacks needed to process tool calls
/// v80.0: Updated to use ResponsesManager instead of AssistantManager
/// v126: Added lastUserMessage for server-side intent detection
class ToolCallContext {
    /// The current user
    let user: UnifiedUser

    /// v80.0: The responses manager for continuing conversation after tool execution
    let responsesManager: ResponsesManager

    /// v126: The last user message text (for server-side intent detection when AI misses parameters)
    let lastUserMessage: String?

    /// Legacy: The assistant manager (deprecated, kept for transition)
    @available(*, deprecated, message: "Use responsesManager instead")
    var assistantManager: AssistantManager {
        // This will crash if called - forcing migration to responsesManager
        fatalError("assistantManager is deprecated. Use responsesManager instead.")
    }

    /// Add a new message to the chat
    let addMessage: (Message) -> Void

    /// Update an existing message by index
    let updateMessage: (Int, Message) -> Void

    /// Get the current message count
    let messagesCount: () -> Int

    /// Get the ID of the last created workout (for modify_workout)
    let getLastCreatedWorkoutId: () -> String?

    /// Store the ID of a created workout (for modify_workout)
    let setLastCreatedWorkoutId: (String?) -> Void

    /// v71.0: Pending cards to add after AI text streams (for batch tool calls)
    /// Cards are added in order after the AI response completes
    var pendingCards: [Message] = []

    /// v108.1: Pending analysis card data to attach to streamed message
    /// Set by AnalyzeTrainingDataHandler during executeOnly (batch path)
    /// Consumed by streamAndHandleResponseEvents when creating message
    var pendingAnalysisCardData: AnalysisCardData?

    // v186: Removed pendingClassScheduleCardData (class booking deferred for beta)

    /// v141: Pending suggestion chips to attach to streamed message
    /// Set by handlers (SkipWorkoutHandler, SuggestOptionsHandler) during executeOnly
    /// Consumed by streamAndHandleResponseEvents when creating message
    var pendingSuggestionChipsData: [SuggestionChip]?

    /// v174: Pending workout created data to attach to message
    /// Set by StartWorkoutHandler during executeOnly (card below text)
    /// Consumed by ChatViewModel.handleDirectToolCommand when creating response message
    var pendingWorkoutCreatedData: WorkoutCreatedData?

    /// v80.0: Updated initializer using ResponsesManager
    /// v126: Added lastUserMessage for server-side intent detection
    init(
        user: UnifiedUser,
        responsesManager: ResponsesManager,
        addMessage: @escaping (Message) -> Void,
        updateMessage: @escaping (Int, Message) -> Void,
        messagesCount: @escaping () -> Int,
        getLastCreatedWorkoutId: @escaping () -> String?,
        setLastCreatedWorkoutId: @escaping (String?) -> Void,
        lastUserMessage: String? = nil
    ) {
        self.user = user
        self.responsesManager = responsesManager
        self.addMessage = addMessage
        self.updateMessage = updateMessage
        self.messagesCount = messagesCount
        self.getLastCreatedWorkoutId = getLastCreatedWorkoutId
        self.setLastCreatedWorkoutId = setLastCreatedWorkoutId
        self.lastUserMessage = lastUserMessage
    }

    /// v71.0: Add a card to be shown after AI text streams
    /// Use this instead of addMessage for cards created during batch tool execution
    func addPendingCard(_ message: Message) {
        pendingCards.append(message)
    }

    /// v71.0: Flush all pending cards to chat (call after AI text streaming completes)
    func flushPendingCards() {
        for card in pendingCards {
            addMessage(card)
        }
        pendingCards.removeAll()
    }
}
