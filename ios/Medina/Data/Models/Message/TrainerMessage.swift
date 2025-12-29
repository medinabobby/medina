//
// TrainerMessage.swift
// Medina
//
// v93.0: Trainer-Member Messaging
// v93.1: Two-way threaded messaging (email model)
//

import Foundation

/// Message in a conversation thread between trainer and member
/// Both trainers AND members can send messages
struct TrainerMessage: Identifiable, Codable, Equatable {
    let id: String
    let senderId: String       // Trainer OR Member's user ID
    let recipientId: String    // Member OR Trainer's user ID
    let content: String        // Message text
    let timestamp: Date
    var isRead: Bool           // For unread badge
    let messageType: MessageType

    // MARK: - Threading (v93.1)
    let threadId: String       // Groups messages in same conversation
    let subject: String?       // Thread subject (first message sets, replies inherit)
    let replyToId: String?     // Message this replies to (nil = thread starter)

    /// Category of message for potential filtering/styling
    enum MessageType: String, Codable, CaseIterable {
        case encouragement    // "Great job!"
        case planUpdate       // "Your new plan is ready"
        case checkIn          // "How are you feeling?"
        case reminder         // "Don't forget leg day"
        case general          // Default

        var displayName: String {
            switch self {
            case .encouragement: return "Encouragement"
            case .planUpdate: return "Plan Update"
            case .checkIn: return "Check-in"
            case .reminder: return "Reminder"
            case .general: return "Message"
            }
        }

        var icon: String {
            switch self {
            case .encouragement: return "star.fill"
            case .planUpdate: return "doc.text.fill"
            case .checkIn: return "hand.wave.fill"
            case .reminder: return "bell.fill"
            case .general: return "bubble.right.fill"
            }
        }
    }

    init(
        id: String = UUID().uuidString,
        senderId: String,
        recipientId: String,
        content: String,
        timestamp: Date = Date(),
        isRead: Bool = false,
        messageType: MessageType = .general,
        threadId: String? = nil,
        subject: String? = nil,
        replyToId: String? = nil
    ) {
        self.id = id
        self.senderId = senderId
        self.recipientId = recipientId
        self.content = content
        self.timestamp = timestamp
        self.isRead = isRead
        self.messageType = messageType
        self.threadId = threadId ?? id  // Default: message ID is thread ID (single-message thread)
        self.subject = subject
        self.replyToId = replyToId
    }
}

// MARK: - Convenience Extensions

extension TrainerMessage {
    /// Time since message was sent, formatted for display
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    /// Preview text for list display (truncated)
    var previewText: String {
        if content.count > 50 {
            return String(content.prefix(47)) + "..."
        }
        return content
    }
}
