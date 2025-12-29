//
//  OpenAIAPIClient.swift
//  Medina
//
//  v67.1: Extracted from AssistantManager.swift
//  v79.6: Added additional_instructions support for dynamic context per-run
//  Handles all HTTP communication with OpenAI Assistants API
//

import Foundation

/// Low-level HTTP client for OpenAI Assistants API
/// Extracted for testability and to centralize HTTP boilerplate
actor OpenAIAPIClient {

    // MARK: - Properties

    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"

    // MARK: - Errors

    enum APIError: LocalizedError {
        case invalidResponse
        case httpError(Int, String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
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

    init(apiKey: String = Config.openAIKey) {
        self.apiKey = apiKey
    }

    // MARK: - Assistant Operations

    /// Create a new assistant with given instructions and tools
    func createAssistant(
        instructions: String,
        tools: [[String: Any]],
        model: String = "gpt-4o-mini",
        name: String = "Medina Fitness Coach",
        description: String = "Personal fitness coach and workout companion"
    ) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "name": name,
            "description": description,
            "instructions": instructions,
            "tools": tools
        ]

        let data = try await post(endpoint: "assistants", body: body)
        return try extractID(from: data, field: "id", errorContext: "assistant ID")
    }

    // MARK: - Thread Operations

    /// Create a new conversation thread
    func createThread() async throws -> String {
        let data = try await post(endpoint: "threads", body: [:])
        return try extractID(from: data, field: "id", errorContext: "thread ID")
    }

    /// Add a user message to a thread
    func addMessage(threadId: String, content: String) async throws {
        let body: [String: Any] = [
            "role": "user",
            "content": content
        ]
        _ = try await post(endpoint: "threads/\(threadId)/messages", body: body)
    }

    // MARK: - Run Operations (Streaming)

    /// Create a streaming run and return raw bytes for processing
    /// - Parameters:
    ///   - threadId: The thread to run on
    ///   - assistantId: The assistant to use
    ///   - additionalInstructions: Optional dynamic context to append to assistant instructions for this run only
    func createStreamingRun(
        threadId: String,
        assistantId: String,
        additionalInstructions: String? = nil
    ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        var body: [String: Any] = [
            "assistant_id": assistantId,
            "stream": true
        ]

        // v79.6: Add dynamic context per-run (plan status, schedule analysis, etc.)
        if let additionalInstructions = additionalInstructions, !additionalInstructions.isEmpty {
            body["additional_instructions"] = additionalInstructions
        }

        return try await postStreaming(endpoint: "threads/\(threadId)/runs", body: body)
    }

    /// Submit tool outputs and return streaming response
    func submitToolOutputs(
        threadId: String,
        runId: String,
        outputs: [(toolCallId: String, output: String)]
    ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let toolOutputs = outputs.map { output in
            ["tool_call_id": output.toolCallId, "output": output.output]
        }

        let body: [String: Any] = [
            "tool_outputs": toolOutputs,
            "stream": true
        ]

        return try await postStreaming(
            endpoint: "threads/\(threadId)/runs/\(runId)/submit_tool_outputs",
            body: body
        )
    }

    // MARK: - Run Operations (Batch/Polling)

    /// Create a non-streaming run and return run ID
    func createRun(threadId: String, assistantId: String) async throws -> String {
        let body: [String: Any] = [
            "assistant_id": assistantId
        ]
        let data = try await post(endpoint: "threads/\(threadId)/runs", body: body)
        return try extractID(from: data, field: "id", errorContext: "run ID")
    }

    /// Get current status of a run
    func getRunStatus(threadId: String, runId: String) async throws -> String {
        let data = try await get(endpoint: "threads/\(threadId)/runs/\(runId)")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else {
            throw APIError.parseError("Could not extract run status")
        }

        return status
    }

    // MARK: - Message Operations

    /// Get the latest assistant message from a thread
    func getLatestAssistantMessage(threadId: String) async throws -> String {
        let data = try await get(endpoint: "threads/\(threadId)/messages?limit=1")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["data"] as? [[String: Any]],
              let firstMessage = messages.first,
              let role = firstMessage["role"] as? String,
              role == "assistant",
              let content = firstMessage["content"] as? [[String: Any]],
              let textContent = content.first,
              let text = textContent["text"] as? [String: Any],
              let value = text["value"] as? String else {
            throw APIError.parseError("Could not extract assistant message")
        }

        return value
    }

    // MARK: - Private HTTP Helpers

    /// Build a request with common headers
    private func makeRequest(endpoint: String, method: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)/\(endpoint)")!)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
        return request
    }

    /// POST request returning data
    private func post(endpoint: String, body: [String: Any]) async throws -> Data {
        var request = makeRequest(endpoint: endpoint, method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(httpResponse.statusCode, errorBody)
        }

        return data
    }

    /// POST request returning streaming bytes
    private func postStreaming(endpoint: String, body: [String: Any]) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        var request = makeRequest(endpoint: endpoint, method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Note: For streaming, we return even non-200 responses
        // The caller handles error reading from the stream
        return (asyncBytes, httpResponse)
    }

    /// GET request returning data
    private func get(endpoint: String) async throws -> Data {
        let request = makeRequest(endpoint: endpoint, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(httpResponse.statusCode, errorBody)
        }

        return data
    }

    /// Extract ID field from JSON response
    private func extractID(from data: Data, field: String, errorContext: String) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json[field] as? String else {
            throw APIError.parseError("Could not extract \(errorContext)")
        }
        return id
    }
}
