//
// DraftMessageCard.swift
// Medina
//
// v93.4: Inline card for reviewing/editing message before sending
// User can edit content, send, or cancel
//

import SwiftUI

/// Card shown in chat when AI drafts a message for user to review before sending
struct DraftMessageCard: View {
    let data: DraftMessageData

    @State private var editedContent: String
    @State private var isEditing: Bool = false
    @State private var isSent: Bool = false
    @FocusState private var isFocused: Bool

    init(data: DraftMessageData) {
        self.data = data
        self._editedContent = State(initialValue: data.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.accentColor)

                Text("Draft Message")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color("PrimaryText"))

                Spacer()

                if isSent {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text("Sent")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color("BackgroundSecondary"))

            Divider()

            // Recipient info
            HStack(spacing: 8) {
                Text("To:")
                    .font(.system(size: 13))
                    .foregroundColor(Color("SecondaryText"))

                Text(data.recipientName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color("PrimaryText"))

                Spacer()

                // Message type badge
                HStack(spacing: 4) {
                    Image(systemName: data.messageType.icon)
                        .font(.system(size: 10))
                    Text(data.messageType.displayName)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(data.messageType.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(data.messageType.color.opacity(0.15))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Subject (if present)
            if let subject = data.subject, !subject.isEmpty {
                HStack(spacing: 8) {
                    Text("Subject:")
                        .font(.system(size: 13))
                        .foregroundColor(Color("SecondaryText"))

                    Text(subject)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color("PrimaryText"))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Divider()

            // Message content (editable)
            if isSent {
                // Show sent state
                Text(editedContent)
                    .font(.system(size: 15))
                    .foregroundColor(Color("SecondaryText"))
                    .padding(16)
            } else if isEditing {
                // Editing mode
                TextEditor(text: $editedContent)
                    .font(.system(size: 15))
                    .foregroundColor(Color("PrimaryText"))
                    .scrollContentBackground(.hidden)
                    .background(Color("BackgroundSecondary").opacity(0.5))
                    .frame(minHeight: 80, maxHeight: 200)
                    .padding(12)
                    .focused($isFocused)
            } else {
                // Read mode - tap to edit
                Text(editedContent)
                    .font(.system(size: 15))
                    .foregroundColor(Color("PrimaryText"))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isEditing = true
                        isFocused = true
                    }
            }

            if !isSent {
                Divider()

                // Action buttons
                HStack(spacing: 12) {
                    // Cancel button
                    Button {
                        data.onCancel()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color("SecondaryText"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color("BackgroundSecondary"))
                            .cornerRadius(8)
                    }

                    // Edit/Done toggle
                    if isEditing {
                        Button {
                            isEditing = false
                            isFocused = false
                        } label: {
                            Text("Done")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(8)
                        }
                    } else {
                        Button {
                            isEditing = true
                            isFocused = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12))
                                Text("Edit")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(8)
                        }
                    }

                    // Send button
                    Button {
                        withAnimation {
                            isSent = true
                        }
                        data.onSend(editedContent)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12))
                            Text("Send")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                    }
                    .disabled(editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)
            }
        }
        .background(Color("Background"))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color("SecondaryText").opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Message Type Colors

extension TrainerMessage.MessageType {
    var color: Color {
        switch self {
        case .general: return .accentColor
        case .encouragement: return .green
        case .reminder: return .orange
        case .planUpdate: return .purple
        case .checkIn: return .blue
        }
    }
}

// MARK: - Preview

#Preview("Draft Message") {
    VStack {
        DraftMessageCard(data: DraftMessageData(
            recipientId: "bobby",
            recipientName: "Bobby Tulsiani",
            content: "Great work on your squat session today! Your form looked solid and you hit all your targets. Keep pushing!",
            subject: "Nice Squat Session!",
            messageType: .encouragement,
            onSend: { content in print("Send: \(content)") },
            onCancel: { print("Cancelled") }
        ))
        .padding()
    }
    .background(Color("BackgroundPrimary"))
}

#Preview("Long Draft") {
    VStack {
        DraftMessageCard(data: DraftMessageData(
            recipientId: "bobby",
            recipientName: "Bobby Tulsiani",
            content: "I noticed you've been consistent with your workouts this week - that's awesome! A few notes:\n\n1. Your bench press is progressing well\n2. Consider adding more mobility work before squats\n3. Rest days are important too - don't skip them\n\nLet me know if you have any questions!",
            subject: "Weekly Check-in",
            messageType: .checkIn,
            onSend: { content in print("Send: \(content)") },
            onCancel: { print("Cancelled") }
        ))
        .padding()
    }
    .background(Color("BackgroundPrimary"))
}
