//
// ThreadRow.swift
// Medina
//
// v93.1: Two-Way Threaded Messaging
// v171: Removed blue dot indicators (bold text + badge on folder is sufficient)
// Sidebar row component for displaying message threads
//

import SwiftUI

/// Row component for displaying a message thread in the sidebar
struct ThreadRow: View {
    let thread: MessageThread
    let currentUserId: String
    let onTap: () -> Void

    private var unreadCount: Int {
        thread.unreadCount(for: currentUserId)
    }

    private var hasUnread: Bool {
        unreadCount > 0
    }

    private var otherParticipantName: String {
        guard let otherId = thread.otherParticipant(currentUserId: currentUserId),
              let user = LocalDataStore.shared.users[otherId] else {
            return "Unknown"
        }
        return user.name
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // v171: Removed blue dot - bold text + badge on folder label is sufficient
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(thread.subject)
                            .font(.subheadline)
                            .fontWeight(hasUnread ? .semibold : .regular)
                            .foregroundColor(Color("PrimaryText"))
                            .lineLimit(1)

                        Spacer()

                        Text(thread.timeAgo)
                            .font(.caption2)
                            .foregroundColor(Color("SecondaryText"))
                    }

                    HStack {
                        Text(otherParticipantName)
                            .font(.caption)
                            .foregroundColor(Color("SecondaryText"))

                        Text("·")
                            .font(.caption)
                            .foregroundColor(Color("SecondaryText"))

                        Text(thread.previewText)
                            .font(.caption)
                            .foregroundColor(Color("SecondaryText"))
                            .lineLimit(1)
                    }
                }

                // Message count badge for threads with multiple messages
                if thread.messages.count > 1 {
                    Text("\(thread.messages.count)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(hasUnread ? Color.accentColor : Color.gray.opacity(0.5))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Compact thread row for sidebar folder display
struct CompactThreadRow: View {
    let thread: MessageThread
    let currentUserId: String
    let onTap: () -> Void

    private var unreadCount: Int {
        thread.unreadCount(for: currentUserId)
    }

    private var hasUnread: Bool {
        unreadCount > 0
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // v171: Removed blue dot - bold text + badge on folder label is sufficient
                VStack(alignment: .leading, spacing: 1) {
                    Text(thread.subject)
                        .font(.caption)
                        .fontWeight(hasUnread ? .semibold : .regular)
                        .foregroundColor(Color("PrimaryText"))
                        .lineLimit(1)

                    Text(thread.previewText)
                        .font(.caption2)
                        .foregroundColor(Color("SecondaryText"))
                        .lineLimit(1)
                }

                Spacer()

                Text(thread.timeAgo)
                    .font(.caption2)
                    .foregroundColor(Color("SecondaryText"))
            }
            .padding(.leading, 56)  // v171: Aligned with plan rows (no dot)
            .padding(.trailing, 20)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let sampleMessages = [
        TrainerMessage(
            id: "msg_001",
            senderId: "nick_vargas",
            recipientId: "bobby",
            content: "I put a new 8 week bike plan in your folder for the spring race.",
            messageType: .planUpdate,
            threadId: "thread_001",
            subject: "8 Week Bike Training Plan"
        ),
        TrainerMessage(
            id: "msg_002",
            senderId: "bobby",
            recipientId: "nick_vargas",
            content: "Thanks Nick! Actually my race is 12 weeks out.",
            messageType: .general,
            threadId: "thread_001",
            replyToId: "msg_001"
        )
    ]

    let sampleThread = MessageThread(
        id: "thread_001",
        participantIds: ["bobby", "nick_vargas"],
        subject: "8 Week Bike Training Plan",
        messages: sampleMessages
    )

    return VStack(spacing: 0) {
        ThreadRow(
            thread: sampleThread,
            currentUserId: "bobby",
            onTap: {}
        )

        Divider()

        CompactThreadRow(
            thread: sampleThread,
            currentUserId: "bobby",
            onTap: {}
        )
    }
    .background(Color("ChatBackground"))
}
