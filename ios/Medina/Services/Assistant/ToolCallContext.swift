//
// ToolCallContext.swift
// Medina
//
// v236: Extracted from deleted ToolHandler.swift
// Shared context for tool call handling - still needed by ChatViewModel
//

import Foundation

/// Shared context for tool call handling
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
