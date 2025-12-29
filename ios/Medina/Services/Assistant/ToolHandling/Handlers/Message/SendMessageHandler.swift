//
// SendMessageHandler.swift
// Medina
//
// v93.0: Handler for send_message tool
// v93.1: Two-way threaded messaging (trainers and members can send)
// v93.3: Fix empty threadId string treated as existing thread lookup
// v93.4: Draft flow - shows message for user review before sending
//

import Foundation
import SwiftUI

/// Handles send_message tool calls (trainers and members)
/// v93.4: Now creates a draft for user to review/edit before sending
@MainActor
struct SendMessageHandler: ToolHandler {
    static let toolName = "send_message"
    private static let componentName = "SendMessageHandler"

    /// Execute only - returns output string without submitting (for batch calls)
    static func executeOnly(args: [String: Any], context: ToolCallContext) async -> String {
        return await executeLogic(args: args, context: context)
    }

    static func handle(
        toolCall: StreamProcessor.ToolCall,
        args: [String: Any],
        context: ToolCallContext
    ) async {
        let toolOutput = await executeLogic(args: args, context: context)

        // Stream AI response
        await ToolHandlerUtilities.streamToolResponse(
            toolCall: toolCall,
            toolOutput: toolOutput,
            context: context
        )
    }

    /// Shared logic for both single and batch execution
    /// v93.4: Creates draft for user review instead of sending directly
    private static func executeLogic(args: [String: Any], context: ToolCallContext) async -> String {
        Logger.log(.info, component: componentName, message: "Executing send_message tool (draft flow)")
        Logger.log(.debug, component: componentName, message: "Args: \(args)")

        // Parse required parameters
        guard let recipientId = args["recipientId"] as? String else {
            return "ERROR: Missing required parameter 'recipientId'"
        }

        guard let content = args["content"] as? String else {
            return "ERROR: Missing required parameter 'content'"
        }

        // Validate sender can message recipient based on roles
        let validationResult = validateMessagingPermission(
            sender: context.user,
            recipientId: recipientId
        )

        guard validationResult.isValid else {
            return validationResult.errorMessage ?? "ERROR: Cannot send message to this recipient"
        }

        // Get recipient info for response
        let recipientName = TestDataManager.shared.users[recipientId]?.name ?? recipientId

        // Parse optional parameters
        let messageType: TrainerMessage.MessageType
        if let typeStr = args["messageType"] as? String,
           let type = TrainerMessage.MessageType(rawValue: typeStr) {
            messageType = type
        } else {
            messageType = .general
        }

        // Threading parameters
        // v93.3: Handle empty string as nil (AI sometimes passes "" instead of omitting)
        let existingThreadId = (args["threadId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let subject = args["subject"] as? String

        // Determine thread ID and whether this is a new thread
        let threadId: String
        let isNewThread: Bool

        if let existing = existingThreadId {
            // Replying to existing thread
            threadId = existing
            isNewThread = false

            // Validate thread exists and user is participant
            guard let thread = TestDataManager.shared.thread(id: existing),
                  thread.participantIds.contains(context.user.id) else {
                return "ERROR: Thread not found or you are not a participant"
            }
        } else {
            // New thread - generate ID now
            threadId = UUID().uuidString
            isNewThread = true
        }

        // Get the last message ID for replyToId (if replying)
        let replyToId: String?
        if !isNewThread, let thread = TestDataManager.shared.thread(id: threadId) {
            replyToId = thread.lastMessage?.id
        } else {
            replyToId = nil
        }

        // Compute final subject
        let finalSubject = isNewThread ? (subject ?? generateSubject(from: content)) : nil

        // v93.4: Create draft message data for user review
        // Capture values for closure
        let senderId = context.user.id
        let capturedThreadId = threadId
        let capturedReplyToId = replyToId
        let capturedSubject = finalSubject
        let capturedRecipientName = recipientName

        let draftData = DraftMessageData(
            recipientId: recipientId,
            recipientName: recipientName,
            content: content,
            subject: finalSubject,
            messageType: messageType,
            onSend: { finalContent in
                // Actually send the message when user confirms
                let message = TrainerMessage(
                    senderId: senderId,
                    recipientId: recipientId,
                    content: finalContent,  // Use edited content
                    messageType: messageType,
                    threadId: capturedThreadId,
                    subject: capturedSubject,
                    replyToId: capturedReplyToId
                )

                TestDataManager.shared.addMessageToThread(message)

                Logger.log(.info, component: componentName,
                          message: "Message sent to \(capturedRecipientName) (thread: \(capturedThreadId), new: \(isNewThread))")
            },
            onCancel: {
                Logger.log(.info, component: componentName,
                          message: "Message draft cancelled for \(capturedRecipientName)")
            }
        )

        // Add draft card to chat
        let draftMessage = Message(
            content: "",  // Content shown in card
            isUser: false,
            draftMessageData: draftData
        )
        context.addPendingCard(draftMessage)

        Logger.log(.info, component: componentName,
                  message: "Created message draft for \(recipientName)")

        return """
        SUCCESS: Message draft created for \(recipientName).

        The user can now review, edit, and send the message from the draft card.

        INSTRUCTIONS:
        1. Tell the user you've drafted a message for them to review
        2. Mention they can edit it before sending
        3. Keep response brief - "I've drafted a message to \(recipientName.components(separatedBy: " ").first ?? recipientName). Review it below and tap Send when ready."
        """
    }

    // MARK: - Validation

    private struct ValidationResult {
        let isValid: Bool
        let errorMessage: String?
    }

    /// Validate that sender can message recipient based on their relationship
    private static func validateMessagingPermission(
        sender: UnifiedUser,
        recipientId: String
    ) -> ValidationResult {
        // Validate recipient exists
        guard TestDataManager.shared.users[recipientId] != nil else {
            // v93.2: Provide helpful error with available members/trainer
            if sender.hasRole(.trainer) {
                let members = UserDataStore.members(assignedToTrainer: sender.id)
                return ValidationResult(
                    isValid: false,
                    errorMessage: """
                    ERROR: Recipient '\(recipientId)' not found.

                    Your assigned members:
                    \(members.map { "- \($0.name) (ID: \($0.id))" }.joined(separator: "\n"))

                    Use the exact ID from above.
                    """
                )
            } else if sender.hasRole(.member),
                      let trainerId = sender.memberProfile?.trainerId,
                      let trainer = TestDataManager.shared.users[trainerId] {
                return ValidationResult(
                    isValid: false,
                    errorMessage: """
                    ERROR: Recipient '\(recipientId)' not found.

                    Your trainer: \(trainer.name) (ID: \(trainerId))
                    """
                )
            }
            return ValidationResult(isValid: false, errorMessage: "ERROR: Recipient '\(recipientId)' not found")
        }

        if sender.hasRole(.trainer) {
            // Trainer sending to member - validate assigned member
            let members = UserDataStore.members(assignedToTrainer: sender.id)
            if members.contains(where: { $0.id == recipientId }) {
                return ValidationResult(isValid: true, errorMessage: nil)
            } else {
                return ValidationResult(
                    isValid: false,
                    errorMessage: """
                    ERROR: \(recipientId) is not one of your assigned members.
                    You can only send messages to members assigned to you.

                    Your assigned members:
                    \(members.map { "- \($0.name) (ID: \($0.id))" }.joined(separator: "\n"))
                    """
                )
            }
        } else if sender.hasRole(.member) {
            // Member sending to trainer - validate it's their trainer
            guard let memberProfile = sender.memberProfile,
                  let trainerId = memberProfile.trainerId else {
                return ValidationResult(
                    isValid: false,
                    errorMessage: "ERROR: You don't have an assigned trainer to message"
                )
            }

            if recipientId == trainerId {
                return ValidationResult(isValid: true, errorMessage: nil)
            } else {
                let trainerName = TestDataManager.shared.users[trainerId]?.name ?? trainerId
                return ValidationResult(
                    isValid: false,
                    errorMessage: """
                    ERROR: You can only message your assigned trainer.
                    Your trainer is \(trainerName) (ID: \(trainerId)).
                    """
                )
            }
        } else {
            return ValidationResult(
                isValid: false,
                errorMessage: "ERROR: Your account type cannot send messages"
            )
        }
    }

    // MARK: - Helpers

    /// Generate a subject from message content
    private static func generateSubject(from content: String) -> String {
        // Take first sentence or first 50 chars
        let firstSentence = content.components(separatedBy: [".", "!", "?"]).first ?? content
        let trimmed = firstSentence.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.count <= 50 {
            return trimmed
        } else {
            return String(trimmed.prefix(47)) + "..."
        }
    }
}
