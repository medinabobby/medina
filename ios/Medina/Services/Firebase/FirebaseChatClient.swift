//
//  FirebaseChatClient.swift
//  Medina
//
//  v197: Phase 7 - Firebase Functions chat client
//  Calls /api/chat endpoint instead of OpenAI directly
//  Server handles: auth, user context, system prompt, OpenAI call
//  Client handles: SSE parsing, tool execution (passthrough mode)
//

import Foundation

/// HTTP client for Firebase Functions /api/chat endpoint
/// Replaces direct OpenAI calls with server-mediated chat
actor FirebaseChatClient {

    // MARK: - Constants

    private static let component = "FirebaseChatClient"

    /// Production endpoint (deployed Firebase Function)
    private static let productionURL = "https://chat-dpkc2km3oa-uc.a.run.app"

    /// Local emulator URL (for development)
    private static let emulatorURL = "http://localhost:5001/medinaintelligence/us-central1/chat"

    // MARK: - Properties

    private let baseURL: String
    private let authService: FirebaseAuthService

    // MARK: - Types

    /// Message in conversation
    struct ChatMessage: Sendable, Codable {
        let role: String  // "user", "assistant"
        let content: String
    }

    /// Request body for /api/chat
    struct ChatRequest: Codable {
        let messages: [ChatMessage]
        let previousResponseId: String?

        init(messages: [ChatMessage], previousResponseId: String? = nil) {
            self.messages = messages
            self.previousResponseId = previousResponseId
        }
    }

    /// Tool output for continuing after tool execution
    struct ToolOutput: Sendable, Codable {
        let type: String = "function_call_output"
        let callId: String
        let output: String

        enum CodingKeys: String, CodingKey {
            case type
            case callId = "call_id"
            case output
        }
    }

    // MARK: - Errors

    enum ChatError: LocalizedError {
        case notAuthenticated
        case invalidResponse
        case httpError(Int, String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Not authenticated - please sign in"
            case .invalidResponse:
                return "Invalid response from server"
            case .httpError(let code, let message):
                return "HTTP \(code): \(message)"
            case .parseError(let message):
                return "Parse error: \(message)"
            }
        }
    }

    // MARK: - Initialization

    /// Initialize with optional emulator mode for development
    init(useEmulator: Bool = false, authService: FirebaseAuthService = .shared) {
        self.baseURL = useEmulator ? Self.emulatorURL : Self.productionURL
        self.authService = authService
    }

    // MARK: - Chat API

    /// Send chat message and receive streaming response
    /// - Parameters:
    ///   - messages: Conversation history
    ///   - previousResponseId: Optional ID for conversation continuity
    /// - Returns: Async stream of SSE bytes and HTTP response
    func sendMessage(
        messages: [ChatMessage],
        previousResponseId: String? = nil
    ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        // Get Firebase ID token (uses existing throwing method)
        let idToken: String
        do {
            idToken = try await authService.getIDToken()
        } catch {
            throw ChatError.notAuthenticated
        }

        let request = ChatRequest(messages: messages, previousResponseId: previousResponseId)
        return try await postStreaming(body: request, idToken: idToken)
    }

    /// Continue conversation after tool execution (passthrough mode)
    /// In Phase 7, tools execute on iOS and results are sent back to server
    /// - Parameters:
    ///   - toolOutputs: Results from tool execution
    ///   - previousResponseId: Response ID from the tool call response
    /// - Returns: Async stream of SSE bytes and HTTP response
    func continueWithToolOutputs(
        toolOutputs: [ToolOutput],
        previousResponseId: String
    ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        // Get Firebase ID token (uses existing throwing method)
        let idToken: String
        do {
            idToken = try await authService.getIDToken()
        } catch {
            throw ChatError.notAuthenticated
        }

        // For tool continuation, we send tool outputs with the previous response ID
        // The server will forward these to OpenAI to continue the conversation
        let body: [String: Any] = [
            "toolOutputs": toolOutputs.map { output in
                [
                    "type": output.type,
                    "call_id": output.callId,
                    "output": output.output
                ]
            },
            "previousResponseId": previousResponseId
        ]

        return try await postStreamingRaw(body: body, idToken: idToken)
    }

    // MARK: - Private HTTP Helpers

    /// POST request with Codable body, returning streaming response
    private func postStreaming<T: Codable>(body: T, idToken: String) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        Logger.log(.debug, component: Self.component, message: "POST \(baseURL) (auth: Bearer ...)")

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            Logger.log(.error, component: Self.component, message: "HTTP \(httpResponse.statusCode)")
        }

        return (asyncBytes, httpResponse)
    }

    /// POST request with raw dictionary body, returning streaming response
    private func postStreamingRaw(body: [String: Any], idToken: String) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Logger.log(.debug, component: Self.component, message: "POST \(baseURL) (tool outputs)")

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatError.invalidResponse
        }

        return (asyncBytes, httpResponse)
    }
}
