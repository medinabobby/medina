//
//  ResponsesManager.swift
//  Medina
//
//  v80.0: Manages OpenAI Responses API integration
//  v80.1: Fixed tool continuation - use function_call_output format
//  v85.1: Fixed stale user data bug - fetch fresh user before building prompt
//  v197: Phase 7 - Added Firebase backend option (useFirebaseBackend flag)
//  Replaces AssistantManager with simpler architecture:
//  - No assistant caching (instructions sent fresh every request)
//  - No thread management (conversation via previous_response_id)
//  - Tool outputs sent as function_call_output items (not fake assistant messages)
//

import Foundation
import UIKit  // v87.6: For UIImage vision support

/// Manages OpenAI Responses API integration
/// Simpler than AssistantManager - no caching, no threads, no tool output submission
@MainActor
class ResponsesManager: ObservableObject {

    // MARK: - Constants

    private static let component = "ResponsesManager"

    // MARK: - Feature Flags

    /// v197: When true, uses Firebase Functions backend instead of direct OpenAI
    /// Server handles: auth, user context, system prompt, OpenAI call
    /// Client handles: SSE parsing, tool execution (passthrough mode)
    static var useFirebaseBackend: Bool = true

    // MARK: - Properties

    private var currentUser: UnifiedUser?
    private let apiClient = ResponsesAPIClient()
    private let firebaseChatClient = FirebaseChatClient()

    /// v80.1: Last response ID for conversation continuity
    /// The Responses API maintains context via previous_response_id - no manual history needed
    private var lastResponseId: String?

    /// Pending tool calls that need execution
    private var pendingToolCalls: [ResponseStreamProcessor.ToolCall] = []

    /// Tool outputs from executed tools (to include in next request)
    private var pendingToolOutputs: [(callId: String, output: String)] = []

    /// v91.0: Selected member ID for trainer context
    var selectedMemberId: String?

    @Published var isInitialized = false

    // MARK: - Errors

    enum ResponsesError: LocalizedError {
        case notInitialized
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .notInitialized:
                return "ResponsesManager not initialized. Call initialize() first."
            case .apiError(let message):
                return message
            }
        }
    }

    // MARK: - Public API

    /// Initialize the manager for a user
    /// v80.1: Much simpler than AssistantManager - no assistant creation/caching
    func initialize(for user: UnifiedUser) async throws {
        Logger.log(.info, component: Self.component, message: "Initializing for user: \(user.name)")

        self.currentUser = user
        self.lastResponseId = nil  // Fresh conversation
        self.pendingToolCalls = []
        self.pendingToolOutputs = []

        isInitialized = true
        Logger.log(.info, component: Self.component, message: "✅ Initialized (no API calls needed)")
    }

    /// Send a message with streaming response
    /// v80.1: Uses previous_response_id for context - only sends new message
    /// v197: Supports Firebase backend (useFirebaseBackend flag)
    func sendMessageStreaming(_ text: String) -> AsyncThrowingStream<ResponseStreamProcessor.ResponseEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                guard let user = self.currentUser else {
                    Logger.log(.error, component: Self.component, message: "Not initialized - no current user")
                    continuation.finish(throwing: ResponsesError.notInitialized)
                    return
                }

                Logger.spine(Self.component, "📤 User: \(text.prefix(50))...")

                do {
                    let asyncBytes: URLSession.AsyncBytes
                    let httpResponse: HTTPURLResponse

                    // v197: Route to Firebase or direct OpenAI based on feature flag
                    if Self.useFirebaseBackend {
                        // Firebase backend: server handles instructions, tools, user context
                        Logger.log(.info, component: Self.component, message: "🔥 Using Firebase backend")
                        let message = FirebaseChatClient.ChatMessage(role: "user", content: text)
                        (asyncBytes, httpResponse) = try await self.firebaseChatClient.sendMessage(
                            messages: [message],
                            previousResponseId: self.lastResponseId
                        )
                    } else {
                        // Direct OpenAI: build instructions and send tools locally
                        // v96.0: Pass message for tier detection
                        let instructions = self.buildInstructions(for: user, message: text)
                        let inputMessages = [ResponsesAPIClient.ConversationMessage(role: "user", content: text)]

                        (asyncBytes, httpResponse) = try await self.apiClient.createStreamingResponse(
                            input: inputMessages,
                            instructions: instructions,
                            tools: AIToolDefinitions.allTools,
                            previousResponseId: self.lastResponseId
                        )
                    }

                    if httpResponse.statusCode != 200 {
                        // Try to read error body
                        var errorBody = ""
                        for try await byte in asyncBytes {
                            errorBody.append(Character(UnicodeScalar(byte)))
                            if errorBody.count > 1000 { break }
                        }
                        let endpoint = Self.useFirebaseBackend ? "firebase/chat" : "responses"
                        Logger.apiError(endpoint: endpoint, statusCode: httpResponse.statusCode, body: errorBody)
                        continuation.finish(throwing: ResponsesError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)"))
                        return
                    }

                    Logger.log(.info, component: Self.component, message: "✅ Stream started")

                    // Process stream events (same SSE format for both backends)
                    try await self.processStreamEvents(
                        asyncBytes,
                        continuation: continuation
                    )

                    continuation.finish()
                    Logger.log(.info, component: Self.component, message: "✅ Stream completed")

                } catch {
                    Logger.log(.error, component: Self.component, message: "Stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// v174: Generate a quick one-off response without affecting conversation history
    /// Used for natural text generation from instruction blocks (e.g., [AI_GENERATE_RESPONSE])
    /// Does NOT update lastResponseId, so the main conversation is unaffected
    func generateQuickResponse(_ instruction: String) async throws -> String {
        guard let user = currentUser else {
            throw ResponsesError.notInitialized
        }

        Logger.log(.info, component: Self.component, message: "🤖 Quick response generation...")

        // Build minimal system instruction for text generation
        // v182: Default Medina personality (balanced, encouraging)
        let systemInstruction = """
        You are Medina, a balanced fitness assistant. Be friendly and encouraging.
        Generate ONLY the response text - no explanations, no meta-commentary.
        Keep it brief (2-3 sentences).
        """

        // Make one-off API call without touching conversation state
        do {
            let inputMessages = [ResponsesAPIClient.ConversationMessage(role: "user", content: instruction)]
            let (asyncBytes, _) = try await apiClient.createStreamingResponse(
                model: "gpt-4o-mini",
                input: inputMessages,
                instructions: systemInstruction,
                tools: [],  // No tools for quick generation
                previousResponseId: nil  // Don't chain to conversation
            )

            // Collect response text
            var accumulatedText = ""
            let eventStream = ResponseStreamProcessor.processStream(from: asyncBytes)

            for try await event in eventStream {
                switch event {
                case .textDelta(let delta):
                    accumulatedText += delta
                default:
                    break
                }
            }

            let result = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            Logger.log(.info, component: Self.component, message: "✅ Quick response: \(result.prefix(50))...")
            return result.isEmpty ? "Let's get started! Tap the card below to begin." : result

        } catch {
            Logger.log(.error, component: Self.component, message: "❌ Quick response failed: \(error)")
            throw error
        }
    }

    /// v106.3: Non-streaming message for voice mode
    /// Collects full response text, ignores tool calls (simplified for voice)
    func sendMessage(_ text: String) async throws -> String {
        var accumulatedText = ""

        let stream = sendMessageStreaming(text)

        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                accumulatedText += delta
            case .textDone:
                // Text complete - accumulatedText already has full text from deltas
                break
            default:
                // Ignore tool calls, response created, done events for voice
                break
            }
        }

        return accumulatedText.isEmpty ? "I'm not sure how to respond to that." : accumulatedText
    }

    /// v87.6: Send message with images for vision analysis (Claude-style attachments)
    /// Uses gpt-4o (not gpt-4o-mini) for vision capability
    func sendMessageWithImagesStreaming(_ text: String, images: [UIImage]) -> AsyncThrowingStream<ResponseStreamProcessor.ResponseEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                guard let user = self.currentUser else {
                    Logger.log(.error, component: Self.component, message: "Not initialized - no current user")
                    continuation.finish(throwing: ResponsesError.notInitialized)
                    return
                }

                Logger.spine(Self.component, "📤 User (with \(images.count) image(s)): \(text.prefix(50))...")

                do {
                    // Build full instructions
                    // v96.0: Pass message for tier detection (full tier for images)
                    let instructions = self.buildInstructions(for: user, message: text)

                    // Prepare images (resize, compress, base64)
                    let base64Images = images.compactMap { self.prepareImageForAPI($0) }

                    // Build multipart message with text + images
                    let multipartMessage = ResponsesAPIClient.MultipartMessage.withImages(
                        text: text.isEmpty ? "What's in this image?" : text,
                        base64Images: base64Images,
                        detail: "high"
                    )

                    // v87.6: Use gpt-4o for vision (gpt-4o-mini has poor vision)
                    let (asyncBytes, httpResponse) = try await self.apiClient.createStreamingResponseWithMultipart(
                        model: "gpt-4o",
                        input: multipartMessage,
                        instructions: instructions,
                        tools: AIToolDefinitions.allTools,
                        previousResponseId: self.lastResponseId
                    )

                    if httpResponse.statusCode != 200 {
                        var errorBody = ""
                        for try await byte in asyncBytes {
                            errorBody.append(Character(UnicodeScalar(byte)))
                            if errorBody.count > 1000 { break }
                        }
                        Logger.apiError(endpoint: "responses (vision)", statusCode: httpResponse.statusCode, body: errorBody)
                        continuation.finish(throwing: ResponsesError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)"))
                        return
                    }

                    Logger.log(.info, component: Self.component, message: "✅ Vision stream started")

                    // Process stream events
                    try await self.processStreamEvents(
                        asyncBytes,
                        continuation: continuation
                    )

                    continuation.finish()
                    Logger.log(.info, component: Self.component, message: "✅ Vision stream completed")

                } catch {
                    Logger.log(.error, component: Self.component, message: "Vision stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// v87.6: Prepare image for API (resize if needed, compress, base64 encode)
    /// - Max dimension: 2048px (OpenAI limit)
    /// - Format: JPEG at 80% quality
    /// - Returns: Base64 encoded string
    private func prepareImageForAPI(_ image: UIImage) -> String? {
        // Resize if needed (max 2048px on longest side)
        let maxDimension: CGFloat = 2048
        var targetImage = image

        if image.size.width > maxDimension || image.size.height > maxDimension {
            let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            targetImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()

            Logger.log(.debug, component: Self.component, message: "Resized image: \(Int(image.size.width))x\(Int(image.size.height)) → \(Int(newSize.width))x\(Int(newSize.height))")
        }

        // Compress to JPEG and base64 encode
        guard let jpegData = targetImage.jpegData(compressionQuality: 0.8) else {
            Logger.log(.error, component: Self.component, message: "Failed to convert image to JPEG")
            return nil
        }

        let base64 = jpegData.base64EncodedString()
        Logger.log(.debug, component: Self.component, message: "Image prepared: \(jpegData.count / 1024)KB → \(base64.count / 1024)KB base64")

        return base64
    }

    /// Execute a tool and store the output for the next request
    /// In Responses API, tool outputs are included in the next message, not submitted separately
    func executeToolAndStoreOutput(toolCallId: String, output: String) {
        pendingToolOutputs.append((callId: toolCallId, output: output))
        Logger.log(.debug, component: Self.component, message: "Stored tool output, pending: \(pendingToolOutputs.count)")
    }

    /// Continue conversation after tool execution
    /// v80.1: Uses function_call_output items with previous_response_id for context
    /// v197: Supports Firebase backend (useFirebaseBackend flag)
    func continueAfterToolExecution() -> AsyncThrowingStream<ResponseStreamProcessor.ResponseEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                guard let user = self.currentUser else {
                    continuation.finish(throwing: ResponsesError.notInitialized)
                    return
                }

                guard !self.pendingToolOutputs.isEmpty else {
                    Logger.log(.warning, component: Self.component, message: "No pending tool outputs to submit")
                    continuation.finish()
                    return
                }

                guard let previousResponseId = self.lastResponseId else {
                    Logger.log(.error, component: Self.component, message: "No previous response ID for tool continuation")
                    continuation.finish(throwing: ResponsesError.apiError("Missing previous_response_id for tool continuation"))
                    return
                }

                Logger.spine(Self.component, "📤 Continuing with \(self.pendingToolOutputs.count) tool output(s)")

                do {
                    let asyncBytes: URLSession.AsyncBytes
                    let httpResponse: HTTPURLResponse

                    // v197: Route to Firebase or direct OpenAI based on feature flag
                    if Self.useFirebaseBackend {
                        // Firebase backend: send tool outputs to server
                        Logger.log(.info, component: Self.component, message: "🔥 Tool continuation via Firebase")
                        let toolOutputs = self.pendingToolOutputs.map { output in
                            FirebaseChatClient.ToolOutput(callId: output.callId, output: output.output)
                        }
                        self.pendingToolOutputs.removeAll()

                        (asyncBytes, httpResponse) = try await self.firebaseChatClient.continueWithToolOutputs(
                            toolOutputs: toolOutputs,
                            previousResponseId: previousResponseId
                        )
                    } else {
                        // Direct OpenAI: convert to proper function_call_output format
                        let toolOutputs = self.pendingToolOutputs.map { output in
                            ResponsesAPIClient.ToolOutput(callId: output.callId, output: output.output)
                        }
                        self.pendingToolOutputs.removeAll()

                        let instructions = self.buildInstructions(for: user)

                        (asyncBytes, httpResponse) = try await self.apiClient.continueWithToolOutputs(
                            toolOutputs: toolOutputs,
                            instructions: instructions,
                            tools: AIToolDefinitions.allTools,
                            previousResponseId: previousResponseId
                        )
                    }

                    if httpResponse.statusCode != 200 {
                        // Read error body for debugging
                        var errorBody = ""
                        for try await byte in asyncBytes {
                            errorBody.append(Character(UnicodeScalar(byte)))
                            if errorBody.count > 1000 { break }
                        }
                        let endpoint = Self.useFirebaseBackend ? "firebase/chat (continue)" : "responses (continue)"
                        Logger.apiError(endpoint: endpoint, statusCode: httpResponse.statusCode, body: errorBody)
                        continuation.finish(throwing: ResponsesError.apiError("Continue failed: HTTP \(httpResponse.statusCode)"))
                        return
                    }

                    try await self.processStreamEvents(asyncBytes, continuation: continuation)
                    continuation.finish()

                } catch {
                    Logger.log(.error, component: Self.component, message: "Continue error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Reset the conversation (start fresh)
    /// v80.1: Only need to clear lastResponseId - no manual history
    func reset() {
        lastResponseId = nil
        pendingToolCalls.removeAll()
        pendingToolOutputs.removeAll()
        isInitialized = false
        Logger.log(.warning, component: Self.component, message: "Conversation reset")
    }

    /// v86.0: Build system prompt for Realtime API voice sessions
    /// Exposes the same instructions used by text chat for voice consistency
    func buildSystemPromptForVoice(user: UnifiedUser) -> String {
        return buildInstructions(for: user)
    }

    // MARK: - Private Helpers

    /// Build full instructions including system prompt and dynamic context
    /// This is sent fresh every request - no caching issues!
    /// v96.0: Added message parameter for prompt tier detection
    private func buildInstructions(for user: UnifiedUser, message: String? = nil) -> String {
        // v85.1: CRITICAL - Get fresh user data in case settings changed
        // Settings views (VoiceCoachingView, etc.) update TestDataManager directly,
        // but ResponsesManager.currentUser is captured at init time and may be stale.
        // This ensures voiceSettings and other profile changes take effect immediately.
        let freshUser: UnifiedUser
        if let cachedUser = TestDataManager.shared.users[user.id] {
            freshUser = cachedUser
            let verbosity = cachedUser.memberProfile?.voiceSettings?.verbosityLevel ?? 0
            Logger.log(.debug, component: Self.component,
                      message: "v85.1 Fresh user from cache: verbosity=\(verbosity)")
        } else {
            // User not in TestDataManager - this shouldn't happen but use stale copy
            freshUser = user
            Logger.log(.warning, component: Self.component,
                      message: "v85.1 User \(user.id) not in TestDataManager, using stale copy")
        }

        // v96.0: Detect tier and log for debugging
        let tier = message.map { TierDetector.detect(message: $0, user: freshUser) } ?? .full
        Logger.log(.debug, component: Self.component,
                  message: "v96.0 Prompt tier: \(tier.rawValue) (~\(tier.approximateTokens) tokens)")

        // Base system prompt - now uses fresh data with tier detection
        var instructions = SystemPrompts.fitnessAssistant(for: freshUser, message: message)

        // v91.0: Add selected member context for trainers
        let selectedMemberContext = TrainerContextBuilder.buildSelectedMemberContext(
            memberId: selectedMemberId,
            for: freshUser
        )
        if !selectedMemberContext.isEmpty {
            instructions += "\n\n" + selectedMemberContext
        }

        // Add dynamic context (active plan, schedule analysis, etc.)
        let dynamicContext = UserContextBuilder.buildActivePlanContext(for: freshUser)
        if !dynamicContext.contains("No active training plan") || true {
            // Always include dynamic context (even "no plan" is useful info)
            instructions += "\n\n" + dynamicContext
        }

        return instructions
    }

    /// Process streaming events and yield to continuation
    /// v80.1: Only tracks lastResponseId - conversation context handled by API
    private func processStreamEvents(
        _ asyncBytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<ResponseStreamProcessor.ResponseEvent, Error>.Continuation
    ) async throws {
        let eventStream = ResponseStreamProcessor.processStream(from: asyncBytes)

        for try await event in eventStream {
            // v211: Debug log ALL events to trace what's received
            Logger.log(.debug, component: Self.component, message: "📨 Event received: \(event)")
            continuation.yield(event)

            switch event {
            case .responseCreated(let responseId):
                // v80.1: Store responseId EARLY so it's available for tool continuation
                self.lastResponseId = responseId
                Logger.spine(Self.component, "📝 Stored responseId early: \(responseId.prefix(20))...")

            case .responseCompleted(let responseId):
                // Also store on completion (should be same ID)
                self.lastResponseId = responseId
                Logger.spine(Self.component, "✅ Response completed: \(responseId.prefix(20))...")
                // v211: Don't return - continue reading workout_card, plan_card, suggestion_chips
                continue

            case .responseFailed:
                // v211: Don't return - continue reading any remaining events
                continue

            case .toolCall(let toolCall):
                // Store pending tool call
                self.pendingToolCalls.append(toolCall)
                // Don't return - let the caller handle tool execution

            default:
                continue
            }
        }
    }
}
