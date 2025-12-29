//
// ChatInputView.swift
// Medina
//
// v99.9: Added suggestion chips above input (Grok/ChatGPT style)
// v74.8: Added speech-to-text microphone button
// v74.9: Claude-style file attachment UX - show attached file, let user add message
// v86.0: Added Realtime API voice button (ChatGPT-style unified voice chat)
// Last reviewed: December 2025
//

import SwiftUI

/// Data for an attached file pending send
/// v75.0: Now stores file data directly to avoid security-scoped URL access issues
struct FileAttachment: Equatable {
    let fileName: String
    let data: Data

    /// Initialize from a URL - reads file data immediately
    /// This is important because document picker URLs may become inaccessible after dismiss
    init?(url: URL) {
        self.fileName = url.lastPathComponent

        // Start security-scoped access (required for files from document picker)
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Read file data immediately
        do {
            self.data = try Data(contentsOf: url)
        } catch {
            Logger.log(.error, component: "FileAttachment",
                       message: "Failed to read file data: \(error)")
            return nil
        }
    }

    /// Initialize with pre-loaded data (for testing or when data is already available)
    init(fileName: String, data: Data) {
        self.fileName = fileName
        self.data = data
    }
}

/// v99.9: Suggestion chip data for empty state
struct SuggestionChip: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let command: String

    init(_ title: String, subtitle: String? = nil, command: String) {
        self.title = title
        self.subtitle = subtitle
        self.command = command
    }
}

struct ChatInputView: View {
    @Binding var text: String
    let placeholder: String  // v67: Dynamic placeholder (e.g., "Connecting..." while initializing)
    let isDisabled: Bool     // v67: Combined disabled state (typing OR not initialized)
    let onSend: () -> Void
    let onPlusButtonTap: () -> Void  // v51.0: New plan creation action

    // v87.6: Multiple file attachments (Claude-style)
    @Binding var attachments: [FileAttachment]
    let onSendWithAttachments: (([FileAttachment], String) -> Void)?

    // v86.0: Voice session state (Realtime API)
    @Binding var isVoiceSessionActive: Bool
    let onVoiceButtonTap: () -> Void
    let onEndVoiceSession: () -> Void
    let isVoiceEnabled: Bool  // From user's VoiceSettings.chatVoiceEnabled

    // v99.9: Suggestion chips for empty state (Grok/ChatGPT style)
    // v144: Changed to pass whole chip so caller can show title but send command
    let suggestions: [SuggestionChip]
    let onSuggestionTap: ((SuggestionChip) -> Void)?

    // v74.8: Speech recognition
    @StateObject private var speechService = SpeechRecognitionService()

    // v87.6: Computed property for whether we can send
    private var canSend: Bool {
        !text.isEmpty || !attachments.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // v99.9: Suggestion chips (Grok/ChatGPT style - above input)
            if !suggestions.isEmpty {
                suggestionChipsView
            }

            // v87.6: Attachment previews (Claude-style chips above input)
            if !attachments.isEmpty {
                attachmentPreviews()
            }

            mainInputRow
        }
        .background(Color.backgroundPrimary)
        // v74.8: Update text when transcription changes
        .onChange(of: speechService.transcribedText) { newValue in
            if !newValue.isEmpty {
                text = newValue
            }
        }
    }

    // MARK: - Suggestion Chips

    /// v99.9: Grok/ChatGPT style suggestion chips above input
    /// v141: Single-line chips for consistent UX - subtitles not rendered
    private var suggestionChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(suggestions) { chip in
                    Button(action: { onSuggestionTap?(chip) }) {
                        Text(chip.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Main Input Row

    private var mainInputRow: some View {
        HStack(spacing: 12) {
            // v51.0: Plus button (OpenAI-style)
            Button(action: onPlusButtonTap) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel("Preferences")

            // Text input field with mic button
            HStack(spacing: 8) {
                // v74.8: Show recording indicator OR text field
                if speechService.isRecording {
                    // Recording state - show recording dot and live text
                    HStack(spacing: 8) {
                        // Recording indicator (pulsing red dot)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)

                        // Live transcription or "Listening..."
                        Text(speechService.transcribedText.isEmpty ? "Listening..." : speechService.transcribedText)
                            .font(.body)
                            .foregroundColor(speechService.transcribedText.isEmpty ? .secondary : .primary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    // Normal text field
                    TextField(placeholder, text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .disabled(isDisabled)
                        .onSubmit {
                            if !text.isEmpty {
                                onSend()
                            }
                        }

                    // Microphone button (only when empty and not in voice session)
                    // v89: Use canRequestAuthorization to allow tapping when permission not yet asked
                    if text.isEmpty && !isVoiceSessionActive {
                        Button(action: {
                            speechService.startRecording()
                        }) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 20))
                                .foregroundColor(speechService.canRequestAuthorization ? .secondary : .secondary.opacity(0.5))
                        }
                        .disabled(!speechService.canRequestAuthorization || isDisabled)
                        .accessibilityLabel("Start voice input")

                        // v86.0: Voice chat button (next to mic)
                        if isVoiceEnabled {
                            Button(action: onVoiceButtonTap) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 18))
                                    .foregroundColor(.secondary)
                            }
                            .disabled(isDisabled)
                            .accessibilityLabel("Start voice conversation")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.backgroundSecondary)
            .cornerRadius(24)

            // v86.0: End voice session button (ChatGPT-style)
            if isVoiceSessionActive {
                Button(action: onEndVoiceSession) {
                    Text("End")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red)
                        .cornerRadius(16)
                }
                .accessibilityLabel("End voice session")
            }
            // v74.8: Stop recording button (replaces send when recording)
            else if speechService.isRecording {
                Button(action: {
                    speechService.stopRecording()
                }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.red)
                }
                .accessibilityLabel("Stop recording")
            }
            // v74.9: Send button (show when text OR attachment is present)
            else if canSend {
                Button(action: handleSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(isDisabled ? .secondary : .accentBlue)
                }
                .disabled(isDisabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Attachment Previews

    /// v87.6: Claude-style attachment chips shown above input field (supports multiple)
    @ViewBuilder
    private func attachmentPreviews() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments.indices, id: \.self) { index in
                    attachmentChip(attachments[index], index: index)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 12)
    }

    /// Single attachment chip with remove button
    @ViewBuilder
    private func attachmentChip(_ attachment: FileAttachment, index: Int) -> some View {
        let isImage = isImageFile(attachment.fileName)

        HStack(spacing: 6) {
            // File/image icon
            Image(systemName: isImage ? "photo.fill" : "doc.fill")
                .font(.system(size: 12))
                .foregroundColor(isImage ? .blue : .orange)

            // File name (truncated)
            Text(attachment.fileName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: 120)

            // Remove button
            Button(action: {
                attachments.remove(at: index)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.backgroundSecondary)
        .cornerRadius(16)
    }

    /// Check if file is an image based on extension
    private func isImageFile(_ fileName: String) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp"].contains(ext)
    }

    // MARK: - Actions

    /// v87.6: Handle send - either with attachments or plain text
    private func handleSend() {
        if !attachments.isEmpty {
            // Send with attachments
            onSendWithAttachments?(attachments, text)
            attachments.removeAll()
            text = ""
        } else {
            // Plain text send
            onSend()
        }
    }
}
