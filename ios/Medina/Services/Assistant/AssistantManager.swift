//
//  AssistantManager.swift
//  Medina
//
//  Created by Bobby Tulsiani on 2025-11-24.
//  v59.1 - AssistantManager Foundation
//  v67.1 - Refactored to use OpenAIAPIClient for HTTP layer
//  v69.3 - Consolidated logging (print → Logger)
//  v74.7 - Bumped cache key for intensityStart/intensityEnd tool params
//  v79.6 - Dynamic per-run context via additional_instructions (plan awareness)
//

import Foundation

/// Manages OpenAI Assistants API integration
/// Orchestrates assistant lifecycle, thread management, and streaming
/// HTTP communication delegated to OpenAIAPIClient
@MainActor
class AssistantManager: ObservableObject {

    // MARK: - Properties

    private var assistantId: String?
    private var threadId: String?
    private var currentUser: UnifiedUser?  // v79.6: Store user for dynamic context
    private let apiClient = OpenAIAPIClient()

    /// v74.11: Old cache keys to clean up on initialization
    private static let legacyCacheKeys = [
        "openai_assistant_id",
        "openai_assistant_id_v670",
        "openai_assistant_id_v691",
        "openai_assistant_id_v692",
        "openai_assistant_id_v693",
        "openai_assistant_id_v723",  // v72.4: Plan naming/timeline transparency
        "openai_assistant_id_v724",  // v74.7: Pre-intensity params
        "openai_assistant_id_v747",  // v74.7: intensityStart/intensityEnd
        "openai_assistant_id_v7410"  // v74.10: MUST ask experience level first
    ]
    private static let currentCacheKey = "openai_assistant_id_v7411"  // v74.11: Combined question (experience + optional extras)

    @Published var isInitialized = false

    // MARK: - Errors

    enum AssistantError: LocalizedError {
        case notInitialized
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .notInitialized:
                return "AssistantManager not initialized. Call initialize() first."
            case .apiError(let message):
                return message
            }
        }
    }

    // MARK: - Initialization

    init() {
        // v69.3: Clean up old cache keys on init
        Self.cleanupLegacyCacheKeys()
    }

    /// v72.3: Remove orphaned assistant ID keys from previous versions
    private static func cleanupLegacyCacheKeys() {
        for key in legacyCacheKeys {
            if UserDefaults.standard.object(forKey: key) != nil {
                UserDefaults.standard.removeObject(forKey: key)
                Logger.log(.info, component: "AssistantManager", message: "🧹 Cleaned up legacy cache key: \(key)")
            }
        }
    }

    // MARK: - Public API

    /// Initialize the assistant for a user
    func initialize(for user: UnifiedUser) async throws {
        Logger.log(.info, component: "AssistantManager", message: "🤖 Initializing...")

        // v79.6: Store user for dynamic per-run context
        self.currentUser = user

        // Check if assistant already exists (persisted in UserDefaults)
        if let existingId = UserDefaults.standard.string(forKey: Self.currentCacheKey) {
            assistantId = existingId
            Logger.log(.info, component: "AssistantManager", message: "✅ Using existing assistant: \(existingId)")
        } else {
            // Create new assistant
            let instructions = SystemPrompts.fitnessAssistant(for: user)
            assistantId = try await apiClient.createAssistant(
                instructions: instructions,
                tools: AIToolDefinitions.allTools
            )
            UserDefaults.standard.set(assistantId, forKey: Self.currentCacheKey)
            Logger.log(.info, component: "AssistantManager", message: "✅ Created new assistant: \(assistantId ?? "")")
        }

        // Create new thread (fresh thread each session)
        threadId = try await apiClient.createThread()
        Logger.log(.info, component: "AssistantManager", message: "✅ Created thread: \(threadId ?? "")")

        isInitialized = true
        Logger.log(.info, component: "AssistantManager", message: "✅ Initialization complete")
    }

    /// Send a message with streaming response
    func sendMessageStreaming(_ text: String) -> AsyncThrowingStream<StreamProcessor.StreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                guard let threadId = self.threadId, let assistantId = self.assistantId else {
                    continuation.finish(throwing: AssistantError.notInitialized)
                    return
                }

                Logger.log(.info, component: "AssistantManager", message: "💬 Sending message (streaming): \(text.prefix(50))...")

                do {
                    // Step 1: Add message to thread
                    try await self.apiClient.addMessage(threadId: threadId, content: text)
                    Logger.log(.info, component: "AssistantManager", message: "✅ Message added to thread")

                    // v79.6: Build dynamic context for this run (plan status, schedule analysis)
                    let dynamicContext = self.buildDynamicContext()

                    // Step 2: Create streaming run with dynamic context
                    let (asyncBytes, httpResponse) = try await self.apiClient.createStreamingRun(
                        threadId: threadId,
                        assistantId: assistantId,
                        additionalInstructions: dynamicContext
                    )

                    if httpResponse.statusCode != 200 {
                        continuation.finish(throwing: AssistantError.apiError("Stream request failed with status \(httpResponse.statusCode)"))
                        return
                    }

                    Logger.log(.info, component: "AssistantManager", message: "✅ Stream started")

                    // Step 3: Process stream events
                    try await self.processStreamEvents(
                        asyncBytes,
                        continuation: continuation,
                        breakOnToolCall: true
                    )

                    continuation.finish()
                    Logger.log(.info, component: "AssistantManager", message: "✅ Stream completed")

                } catch {
                    Logger.log(.error, component: "AssistantManager", message: "❌ Stream error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Send a message and get batch response (non-streaming)
    func sendMessage(_ text: String) async throws -> String {
        guard let threadId = threadId, let assistantId = assistantId else {
            throw AssistantError.notInitialized
        }

        Logger.log(.info, component: "AssistantManager", message: "💬 Sending message: \(text.prefix(50))...")

        // Step 1: Add message to thread
        try await apiClient.addMessage(threadId: threadId, content: text)
        Logger.log(.info, component: "AssistantManager", message: "✅ Message added to thread")

        // Step 2: Create run (batch mode)
        let runId = try await apiClient.createRun(threadId: threadId, assistantId: assistantId)
        Logger.log(.info, component: "AssistantManager", message: "✅ Run created: \(runId)")

        // Step 3: Poll until run completes
        try await waitForRunCompletion(threadId: threadId, runId: runId)
        Logger.log(.info, component: "AssistantManager", message: "✅ Run completed")

        // Step 4: Retrieve messages
        let response = try await apiClient.getLatestAssistantMessage(threadId: threadId)
        Logger.log(.info, component: "AssistantManager", message: "✅ Received response: \(response.prefix(100))...")

        return response
    }

    /// Submit single tool output and continue streaming
    func submitToolOutput(toolCallId: String, runId: String, output: String) -> AsyncThrowingStream<StreamProcessor.StreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                guard let threadId = self.threadId else {
                    continuation.finish(throwing: AssistantError.notInitialized)
                    return
                }

                Logger.log(.info, component: "AssistantManager",
                          message: "📤 Submitting tool output for call \(toolCallId), runId: \(runId)")

                do {
                    let (asyncBytes, httpResponse) = try await self.apiClient.submitToolOutputs(
                        threadId: threadId,
                        runId: runId,
                        outputs: [(toolCallId: toolCallId, output: output)]
                    )

                    if httpResponse.statusCode != 200 {
                        // Read error body from stream
                        var errorBody = ""
                        for try await line in asyncBytes.lines {
                            errorBody += line
                        }
                        Logger.apiError(
                            endpoint: "submit_tool_outputs",
                            statusCode: httpResponse.statusCode,
                            body: errorBody
                        )
                        continuation.finish(throwing: AssistantError.apiError(errorBody.isEmpty ? "Submit tool output failed" : errorBody))
                        return
                    }

                    Logger.log(.info, component: "AssistantManager",
                              message: "✅ Tool output submitted, continuing stream")

                    // Process stream events
                    try await self.processStreamEvents(
                        asyncBytes,
                        continuation: continuation,
                        breakOnToolCall: false
                    )

                    continuation.finish()
                    Logger.log(.info, component: "AssistantManager",
                              message: "✅ Stream completed after tool output")

                } catch {
                    Logger.log(.error, component: "AssistantManager",
                              message: "❌ Submit tool output error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Submit multiple tool outputs at once (for parallel tool calls)
    func submitToolOutputs(outputs: [(toolCallId: String, output: String)], runId: String) -> AsyncThrowingStream<StreamProcessor.StreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                guard let threadId = self.threadId else {
                    continuation.finish(throwing: AssistantError.notInitialized)
                    return
                }

                Logger.log(.info, component: "AssistantManager",
                          message: "📤 Submitting \(outputs.count) tool outputs for run \(runId)")

                do {
                    let (asyncBytes, httpResponse) = try await self.apiClient.submitToolOutputs(
                        threadId: threadId,
                        runId: runId,
                        outputs: outputs
                    )

                    if httpResponse.statusCode != 200 {
                        var errorBody = ""
                        for try await line in asyncBytes.lines {
                            errorBody += line
                        }
                        Logger.apiError(
                            endpoint: "submit_tool_outputs (batch)",
                            statusCode: httpResponse.statusCode,
                            body: errorBody
                        )
                        continuation.finish(throwing: AssistantError.apiError(errorBody.isEmpty ? "Submit tool outputs failed" : errorBody))
                        return
                    }

                    Logger.log(.info, component: "AssistantManager",
                              message: "✅ \(outputs.count) tool outputs submitted, continuing stream")

                    try await self.processStreamEvents(
                        asyncBytes,
                        continuation: continuation,
                        breakOnToolCall: false
                    )

                    continuation.finish()
                    Logger.log(.info, component: "AssistantManager",
                              message: "✅ Stream completed after submitting \(outputs.count) tool outputs")

                } catch {
                    Logger.log(.error, component: "AssistantManager",
                              message: "❌ Submit tool outputs error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Reset the assistant (for testing/debugging)
    func reset() {
        UserDefaults.standard.removeObject(forKey: Self.currentCacheKey)
        assistantId = nil
        threadId = nil
        isInitialized = false
        Logger.log(.warning, component: "AssistantManager", message: "⚠️ Assistant reset")
    }

    // MARK: - Private Helpers

    /// v79.6: Build dynamic context for each run
    /// Includes active plan status, schedule analysis, and other session-specific context
    /// This is appended to the base system prompt via additional_instructions
    private func buildDynamicContext() -> String? {
        guard let user = currentUser else { return nil }

        // Build active plan context (includes schedule analysis)
        let planContext = UserContextBuilder.buildActivePlanContext(for: user)

        // Only return if there's meaningful content
        if planContext.contains("No active training plan") {
            // Still useful to tell AI there's no plan
            return planContext
        }

        return planContext
    }

    /// Process streaming events and yield to continuation
    /// - Parameters:
    ///   - asyncBytes: Raw bytes from streaming response
    ///   - continuation: Stream continuation to yield events to
    ///   - breakOnToolCall: Whether to break when a tool call is received
    private func processStreamEvents(
        _ asyncBytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<StreamProcessor.StreamEvent, Error>.Continuation,
        breakOnToolCall: Bool
    ) async throws {
        let eventStream = StreamProcessor.processStream(from: asyncBytes)

        for try await event in eventStream {
            continuation.yield(event)

            // Stop on completion, error, or (optionally) tool call
            switch event {
            case .runCompleted, .runFailed:
                return
            case .toolCall where breakOnToolCall:
                // Let tool handler manage conversation flow
                return
            default:
                continue
            }
        }
    }

    /// Poll until run completes (for batch mode)
    private func waitForRunCompletion(threadId: String, runId: String) async throws {
        var attempts = 0
        let maxAttempts = 60 // 60 seconds max

        while attempts < maxAttempts {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            attempts += 1

            let status = try await apiClient.getRunStatus(threadId: threadId, runId: runId)
            Logger.log(.info, component: "AssistantManager", message: "⏳ Run status: \(status) (attempt \(attempts))")

            if status == "completed" {
                return
            } else if status == "failed" || status == "cancelled" || status == "expired" {
                throw AssistantError.apiError("Run ended with status: \(status)")
            }
        }

        throw AssistantError.apiError("Run polling timeout after 60 seconds")
    }
}
