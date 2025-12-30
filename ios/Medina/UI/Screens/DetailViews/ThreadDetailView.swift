//
// ThreadDetailView.swift
// Medina
//
// v93.1: Two-Way Threaded Messaging
// v93.2: Inline reply composer and delete button
// Full conversation thread view - shows all messages in thread
//

import SwiftUI

struct ThreadDetailView: View {
    let threadId: String
    @EnvironmentObject private var navigationModel: NavigationModel

    @State private var thread: MessageThread?
    @State private var replyText: String = ""
    @State private var showDeleteConfirmation: Bool = false
    @FocusState private var isReplyFocused: Bool
    private let currentUserId: String

    init(threadId: String) {
        self.threadId = threadId
        self.currentUserId = LocalDataStore.shared.currentUserId ?? "unknown"
    }

    var body: some View {
        Group {
            if let thread = thread {
                VStack(spacing: 0) {
                    // Breadcrumb navigation
                    BreadcrumbBar(items: [
                        BreadcrumbItem(label: "Messages", action: { navigationModel.pop() }),
                        BreadcrumbItem(label: truncatedSubject(thread.subject), action: nil)
                    ])

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                // Thread header
                                threadHeader(for: thread)

                                Divider()

                                // Messages
                                ForEach(thread.messages) { message in
                                    ThreadMessageBubble(
                                        message: message,
                                        isFromCurrentUser: message.senderId == currentUserId
                                    )
                                    .id(message.id)
                                }

                                Spacer(minLength: 100)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 24)
                        }
                        .onAppear {
                            scrollToBottom(proxy: proxy)
                        }
                        .onChange(of: thread.messages.count) { _ in
                            scrollToBottom(proxy: proxy)
                        }
                    }

                    // MARK: - Inline Reply Composer
                    VStack(spacing: 12) {
                        Divider()

                        HStack(spacing: 12) {
                            TextField("Reply...", text: $replyText, axis: .vertical)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color("SecondaryBackground"))
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .focused($isReplyFocused)
                                .lineLimit(1...4)

                            Button {
                                sendReply()
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color("SecondaryText") : .accentColor)
                            }
                            .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.horizontal, 16)

                        // Delete button
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.caption)
                                Text("Delete Thread")
                                    .font(.caption)
                            }
                            .foregroundColor(.red.opacity(0.8))
                        }
                        .padding(.bottom, 8)
                    }
                    .background(Color("Background"))
                }
                .onAppear {
                    markThreadAsRead()
                }
                .alert("Delete Thread?", isPresented: $showDeleteConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        deleteThread()
                    }
                } message: {
                    Text("This will permanently delete this conversation and all messages.")
                }
            } else {
                EmptyStateView(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "Thread Not Found",
                    message: "The requested conversation could not be found."
                )
            }
        }
        .navigationTitle("Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadThread()
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastId = thread?.messages.last?.id {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Thread Header

    private func threadHeader(for thread: MessageThread) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Subject
            Text(thread.subject)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(Color("PrimaryText"))

            // Participants
            HStack(spacing: 8) {
                ForEach(thread.participantIds, id: \.self) { participantId in
                    participantBadge(for: participantId)
                }
            }

            // Thread metadata
            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(Color("SecondaryText"))

                Text("Started \(formattedDate(thread.createdAt))")
                    .font(.caption)
                    .foregroundColor(Color("SecondaryText"))

                Text("·")
                    .foregroundColor(Color("SecondaryText"))

                Text("\(thread.messages.count) message\(thread.messages.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(Color("SecondaryText"))
            }
        }
    }

    private func participantBadge(for userId: String) -> some View {
        let user = LocalDataStore.shared.users[userId]
        let name = user?.name ?? userId
        let isTrainer = user?.hasRole(.trainer) ?? false

        return HStack(spacing: 4) {
            Image(systemName: isTrainer ? "person.badge.key" : "person")
                .font(.caption2)
            Text(name.components(separatedBy: " ").first ?? name)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(isTrainer ? .orange : .accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isTrainer ? Color.orange.opacity(0.15) : Color.accentColor.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    private func loadThread() {
        thread = LocalDataStore.shared.thread(id: threadId)
    }

    private func truncatedSubject(_ subject: String) -> String {
        if subject.count > 25 {
            return String(subject.prefix(22)) + "..."
        }
        return subject
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func markThreadAsRead() {
        LocalDataStore.shared.markThreadAsRead(threadId, for: currentUserId)
        Logger.log(.info, component: "ThreadDetailView",
                  message: "Marked thread \(threadId) as read for \(currentUserId)")
    }

    private func sendReply() {
        let content = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let thread = thread else { return }

        // Determine recipient (the other participant)
        let recipientId = thread.participantIds.first { $0 != currentUserId } ?? thread.participantIds.first ?? ""

        // Create the reply message
        let message = TrainerMessage(
            senderId: currentUserId,
            recipientId: recipientId,
            content: content,
            messageType: .general,
            threadId: threadId,
            replyToId: thread.messages.last?.id
        )

        // Add to thread
        LocalDataStore.shared.addMessageToThread(message)

        // Refresh local thread state
        self.thread = LocalDataStore.shared.thread(id: threadId)

        // Clear text field
        replyText = ""

        Logger.log(.info, component: "ThreadDetailView",
                  message: "Sent reply to thread \(threadId)")
    }

    private func deleteThread() {
        LocalDataStore.shared.deleteThread(threadId)
        navigationModel.pop()
        Logger.log(.info, component: "ThreadDetailView",
                  message: "Deleted thread \(threadId)")
    }
}

// MARK: - Thread Message Bubble

private struct ThreadMessageBubble: View {
    let message: TrainerMessage
    let isFromCurrentUser: Bool

    private var senderName: String {
        LocalDataStore.shared.users[message.senderId]?.name ?? message.senderId
    }

    var body: some View {
        HStack {
            if isFromCurrentUser { Spacer(minLength: 50) }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Sender name and time
                HStack(spacing: 4) {
                    if !isFromCurrentUser {
                        Text(senderName.components(separatedBy: " ").first ?? senderName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                    }

                    Text(message.timeAgo)
                        .font(.caption2)
                        .foregroundColor(Color("SecondaryText"))
                }

                // Message bubble
                Text(message.content)
                    .font(.body)
                    .foregroundColor(isFromCurrentUser ? .white : Color("PrimaryText"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        isFromCurrentUser
                            ? Color.accentColor
                            : Color("SecondaryBackground")
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                // Message type badge for non-general messages
                if message.messageType != .general {
                    HStack(spacing: 2) {
                        Image(systemName: message.messageType.icon)
                            .font(.caption2)
                        Text(message.messageType.displayName)
                            .font(.caption2)
                    }
                    .foregroundColor(Color("SecondaryText"))
                }
            }

            if !isFromCurrentUser { Spacer(minLength: 50) }
        }
    }
}

#Preview {
    let sampleMessages = [
        TrainerMessage(
            id: "msg_001",
            senderId: "nick_vargas",
            recipientId: "bobby",
            content: "I put a new 8 week bike plan in your folder for the spring race. Let me know your thoughts!",
            messageType: .planUpdate,
            threadId: "thread_preview",
            subject: "8 Week Bike Training Plan"
        ),
        TrainerMessage(
            id: "msg_002",
            senderId: "bobby",
            recipientId: "nick_vargas",
            content: "Thanks Nick! Actually my race is 12 weeks out, not 8. Can we extend it? Also want to keep some upper body work.",
            messageType: .general,
            threadId: "thread_preview",
            replyToId: "msg_001"
        ),
        TrainerMessage(
            id: "msg_003",
            senderId: "nick_vargas",
            recipientId: "bobby",
            content: "Good call! Updated to 12 weeks with 2 upper body days per week. Check your Plans folder.",
            messageType: .planUpdate,
            threadId: "thread_preview",
            replyToId: "msg_002"
        )
    ]

    let thread = MessageThread(
        id: "thread_preview",
        participantIds: ["bobby", "nick_vargas"],
        subject: "8 Week Bike Training Plan",
        messages: sampleMessages
    )

    LocalDataStore.shared.messageThreads["thread_preview"] = thread
    LocalDataStore.shared.currentUserId = "bobby"

    return NavigationStack {
        ThreadDetailView(threadId: "thread_preview")
    }
    .environmentObject(NavigationModel())
}
