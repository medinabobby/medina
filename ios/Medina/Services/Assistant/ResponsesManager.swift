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

    // MARK: - Properties

    private var currentUser: UnifiedUser?
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
                guard self.currentUser != nil else {
                    Logger.log(.error, component: Self.component, message: "Not initialized - no current user")
                    continuation.finish(throwing: ResponsesError.notInitialized)
                    return
                }

                Logger.spine(Self.component, "📤 User: \(text.prefix(50))...")

                do {
                    // Firebase backend: server handles instructions, tools, user context
                    let message = FirebaseChatClient.ChatMessage(role: "user", content: text)
                    let (asyncBytes, httpResponse) = try await self.firebaseChatClient.sendMessage(
                        messages: [message],
                        previousResponseId: self.lastResponseId
                    )

                    if httpResponse.statusCode != 200 {
                        // Try to read error body
                        var errorBody = ""
                        for try await byte in asyncBytes {
                            errorBody.append(Character(UnicodeScalar(byte)))
                            if errorBody.count > 1000 { break }
                        }
                        Logger.apiError(endpoint: "firebase/chat", statusCode: httpResponse.statusCode, body: errorBody)
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
    /// Returns a default encouraging message (quick generation now handled server-side)
    func generateQuickResponse(_ instruction: String) async throws -> String {
        guard currentUser != nil else {
            throw ResponsesError.notInitialized
        }

        Logger.log(.info, component: Self.component, message: "🤖 Quick response (default)")
        // Server handles AI responses - return default for local quick generation
        return "Let's get started! Tap the card below to begin."
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

    /// v87.6: Send message with images for vision analysis
    /// TODO: Implement Firebase vision endpoint
    func sendMessageWithImagesStreaming(_ text: String, images: [UIImage]) -> AsyncThrowingStream<ResponseStreamProcessor.ResponseEvent, Error> {
        return AsyncThrowingStream { continuation in
            // Vision through Firebase not yet implemented - send text only
            Logger.log(.warning, component: Self.component, message: "Vision not yet supported via Firebase, sending text only")
            Task { @MainActor in
                // Fall back to text-only message
                let textStream = self.sendMessageStreaming(text.isEmpty ? "I tried to share an image but vision isn't supported yet." : text)
                for try await event in textStream {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }

    /// Execute a tool and store the output for the next request
    /// In Responses API, tool outputs are included in the next message, not submitted separately
    func executeToolAndStoreOutput(toolCallId: String, output: String) {
        pendingToolOutputs.append((callId: toolCallId, output: output))
        Logger.log(.debug, component: Self.component, message: "Stored tool output, pending: \(pendingToolOutputs.count)")
    }

    /// Continue conversation after tool execution
    /// Sends tool outputs to Firebase backend for AI to process results
    func continueAfterToolExecution() -> AsyncThrowingStream<ResponseStreamProcessor.ResponseEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                guard self.currentUser != nil else {
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
                    // Send tool outputs to Firebase backend
                    let toolOutputs = self.pendingToolOutputs.map { output in
                        FirebaseChatClient.ToolOutput(callId: output.callId, output: output.output)
                    }
                    self.pendingToolOutputs.removeAll()

                    let (asyncBytes, httpResponse) = try await self.firebaseChatClient.continueWithToolOutputs(
                        toolOutputs: toolOutputs,
                        previousResponseId: previousResponseId
                    )

                    if httpResponse.statusCode != 200 {
                        var errorBody = ""
                        for try await byte in asyncBytes {
                            errorBody.append(Character(UnicodeScalar(byte)))
                            if errorBody.count > 1000 { break }
                        }
                        Logger.apiError(endpoint: "firebase/chat (continue)", statusCode: httpResponse.statusCode, body: errorBody)
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
    /// Returns minimal voice-focused prompt (full prompts built server-side)
    func buildSystemPromptForVoice(user: UnifiedUser) -> String {
        let name = user.name
        let goal = user.memberProfile?.fitnessGoal.rawValue ?? "fitness"
        let experience = user.memberProfile?.experienceLevel.rawValue ?? "intermediate"

        return """
        You are Medina, a personal fitness coach and training companion.

        User: \(name)
        Goal: \(goal)
        Experience: \(experience)

        Communication Style:
        - Be conversational, friendly, and encouraging
        - Keep responses brief for voice (1-2 sentences when possible)
        - Use clear, simple language
        - When creating workouts, be specific about exercises, sets, reps

        Important:
        - Safety first - never recommend dangerous exercises
        - Respect the user's experience level
        - Focus on actionable advice
        """
    }

    // MARK: - Private Helpers

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
