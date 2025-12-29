//
// MessageThread.swift
// Medina
//
// v93.1: Two-Way Threaded Messaging
// Container model grouping messages in a conversation
//

import Foundation

/// A conversation thread between a trainer and member
/// Groups related messages together (like email threads)
struct MessageThread: Identifiable, Codable, Equatable {
    let id: String                    // Thread ID (same as first message's threadId)
    let participantIds: [String]      // [trainer, member] in consistent order
    let subject: String               // Thread subject from first message
    let createdAt: Date               // When thread started
    var messages: [TrainerMessage]    // All messages in thread, chronological
    var lastMessageAt: Date           // For sorting (updated when messages added)

    // MARK: - Computed Properties

    /// Most recent message in thread
    var lastMessage: TrainerMessage? {
        messages.max(by: { $0.timestamp < $1.timestamp })
    }

    /// Count of unread messages for a specific user
    func unreadCount(for userId: String) -> Int {
        messages.filter { $0.recipientId == userId && !$0.isRead }.count
    }

    /// Preview text for list display (from last message)
    var previewText: String {
        lastMessage?.previewText ?? ""
    }

    /// Time since last activity
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastMessageAt, relativeTo: Date())
    }

    /// Get the other participant (not the current user)
    func otherParticipant(currentUserId: String) -> String? {
        participantIds.first(where: { $0 != currentUserId })
    }

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        participantIds: [String],
        subject: String,
        createdAt: Date = Date(),
        messages: [TrainerMessage] = [],
        lastMessageAt: Date? = nil
    ) {
        self.id = id
        self.participantIds = participantIds.sorted() // Consistent ordering
        self.subject = subject
        self.createdAt = createdAt
        self.messages = messages
        self.lastMessageAt = lastMessageAt ?? messages.last?.timestamp ?? createdAt
    }

    /// Create a new thread from an initial message
    static func create(from message: TrainerMessage) -> MessageThread {
        MessageThread(
            id: message.threadId,
            participantIds: [message.senderId, message.recipientId],
            subject: message.subject ?? "New Message",
            createdAt: message.timestamp,
            messages: [message],
            lastMessageAt: message.timestamp
        )
    }

    // MARK: - Mutations

    /// Add a reply to this thread
    mutating func addMessage(_ message: TrainerMessage) {
        messages.append(message)
        lastMessageAt = message.timestamp
    }

    /// Mark all messages as read for a specific recipient
    mutating func markAllAsRead(for userId: String) {
        for index in messages.indices {
            if messages[index].recipientId == userId {
                messages[index].isRead = true
            }
        }
    }
}

// MARK: - Comparable (for sorting)

extension MessageThread: Comparable {
    static func < (lhs: MessageThread, rhs: MessageThread) -> Bool {
        lhs.lastMessageAt > rhs.lastMessageAt // Most recent first
    }
}
