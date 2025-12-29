//
//  ResponsesAPIClient.swift
//  Medina
//
//  v80.0: OpenAI Responses API client (replaces Assistants API)
//  v80.1: Fixed tool output format - use function_call_output items
//  v87.6: Added multipart content support for vision (text + images)
//  Simpler architecture: single endpoint, inline tool handling, no thread management
//

import Foundation

/// Low-level HTTP client for OpenAI Responses API
/// Replaces OpenAIAPIClient with simpler Responses API architecture
actor ResponsesAPIClient {

    // MARK: - Constants

    private static let component = "ResponsesAPIClient"

    // MARK: - Properties

    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"

    // MARK: - Types

    /// Message in conversation history
    struct ConversationMessage: Sendable {
        let role: String  // "user", "assistant", "system"
        let content: String

        func toDictionary() -> [String: Any] {
            return ["role": role, "content": content]
        }
    }

    /// v87.6: Multipart content for vision (text + images)
    /// Used when sending images to gpt-4o via Responses API
    /// Note: Responses API uses "input_text" and "input_image" types (not "text"/"image_url")
    struct MultipartMessage: Sendable {
        let role: String
        let content: [[String: Any]]  // Array of content parts (input_text, input_image)

        /// Create a multipart message with text and base64 images
        /// Responses API format: https://platform.openai.com/docs/api-reference/responses
        static func withImages(text: String, base64Images: [String], detail: String = "high") -> MultipartMessage {
            var contentParts: [[String: Any]] = []

            // Add text content first (Responses API uses "input_text" type)
            if !text.isEmpty {
                contentParts.append(["type": "input_text", "text": text])
            }

            // Add each image (Responses API uses "input_image" type with direct URL)
            for base64 in base64Images {
                contentParts.append([
                    "type": "input_image",
                    "image_url": "data:image/jpeg;base64,\(base64)",
                    "detail": detail
                ])
            }

            return MultipartMessage(role: "user", content: contentParts)
        }

        func toDictionary() -> [String: Any] {
            return ["role": role, "content": content]
        }
    }

    /// Tool output for function_call_output items
    struct ToolOutput: Sendable {
        let callId: String
        let output: String

        func toDictionary() -> [String: Any] {
            return [
                "type": "function_call_output",
                "call_id": callId,
                "output": output
            ]
        }
    }

    /// Tool definition for Responses API
    struct ToolDefinition: Sendable {
        let type: String = "function"
        let name: String
        let description: String
        let parameters: [String: Any]

        func toDictionary() -> [String: Any] {
            return [
                "type": type,
                "name": name,
                "description": description,
                "parameters": parameters
            ]
        }
    }

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

    // MARK: - Response Creation

    /// Create a streaming response with the Responses API
    /// - Parameters:
    ///   - model: The model to use (default: gpt-4o-mini)
    ///   - input: Conversation history as messages
    ///   - instructions: System instructions (sent fresh every request)
    ///   - tools: Tool definitions for function calling (Assistants API format, will be converted)
    ///   - previousResponseId: Optional ID for conversation continuity
    /// - Returns: Async stream of bytes and HTTP response
    func createStreamingResponse(
        model: String = "gpt-4o-mini",
        input: [ConversationMessage],
        instructions: String,
        tools: [[String: Any]],
        previousResponseId: String? = nil
    ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        // Convert tools from Assistants API format to Responses API format
        let responsesTools = convertToolsToResponsesFormat(tools)

        var body: [String: Any] = [
            "model": model,
            "input": input.map { $0.toDictionary() },
            "instructions": instructions,
            "tools": responsesTools,
            "stream": true
        ]

        // Add conversation continuity if provided
        if let previousResponseId = previousResponseId {
            body["previous_response_id"] = previousResponseId
        }

        return try await postStreaming(endpoint: "responses", body: body)
    }

    /// v87.6: Create streaming response with multipart content (text + images)
    /// Used for vision analysis with gpt-4o
    func createStreamingResponseWithMultipart(
        model: String = "gpt-4o",
        input: MultipartMessage,
        instructions: String,
        tools: [[String: Any]],
        previousResponseId: String? = nil
    ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let responsesTools = convertToolsToResponsesFormat(tools)

        var body: [String: Any] = [
            "model": model,
            "input": [input.toDictionary()],  // Single multipart message in array
            "instructions": instructions,
            "tools": responsesTools,
            "stream": true
        ]

        if let previousResponseId = previousResponseId {
            body["previous_response_id"] = previousResponseId
        }

        Logger.spine(Self.component, "📤 Vision request: \(model), \(input.content.count) content parts")

        return try await postStreaming(endpoint: "responses", body: body)
    }

    /// Create a non-streaming response (for simple queries)
    func createResponse(
        model: String = "gpt-4o-mini",
        input: [ConversationMessage],
        instructions: String,
        tools: [[String: Any]],
        previousResponseId: String? = nil
    ) async throws -> Data {
        var body: [String: Any] = [
            "model": model,
            "input": input.map { $0.toDictionary() },
            "instructions": instructions,
            "tools": tools
        ]

        if let previousResponseId = previousResponseId {
            body["previous_response_id"] = previousResponseId
        }

        return try await post(endpoint: "responses", body: body)
    }

    /// v80.1: Continue conversation with tool outputs
    /// Uses previous_response_id for context + function_call_output items for tool results
    func continueWithToolOutputs(
        model: String = "gpt-4o-mini",
        toolOutputs: [ToolOutput],
        instructions: String,
        tools: [[String: Any]],
        previousResponseId: String
    ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let responsesTools = convertToolsToResponsesFormat(tools)

        // Input is ONLY the tool outputs - previous_response_id provides conversation context
        let body: [String: Any] = [
            "model": model,
            "input": toolOutputs.map { $0.toDictionary() },
            "instructions": instructions,
            "tools": responsesTools,
            "stream": true,
            "previous_response_id": previousResponseId
        ]

        Logger.spine(Self.component, "📤 Tool outputs: \(toolOutputs.count), prev: \(previousResponseId.prefix(20))...")

        return try await postStreaming(endpoint: "responses", body: body)
    }

    // MARK: - Private HTTP Helpers

    /// Build a request with common headers
    private func makeRequest(endpoint: String, method: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)/\(endpoint)")!)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Note: No OpenAI-Beta header needed for Responses API
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
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = jsonData

        Logger.log(.debug, component: Self.component, message: "POST /\(endpoint) (\(jsonData.count) bytes)")

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            Logger.log(.error, component: Self.component, message: "HTTP \(httpResponse.statusCode)")
        }

        // Return even non-200 responses - caller handles error reading from stream
        return (asyncBytes, httpResponse)
    }

    // MARK: - Tool Format Conversion

    /// Convert tools from Assistants API format to Responses API format
    /// Assistants API: {"type": "function", "function": {"name": "...", "description": "...", "parameters": ...}}
    /// Responses API: {"type": "function", "name": "...", "description": "...", "parameters": ...}
    private func convertToolsToResponsesFormat(_ tools: [[String: Any]]) -> [[String: Any]] {
        return tools.map { tool in
            // Check if this is the nested Assistants API format
            if let functionDef = tool["function"] as? [String: Any] {
                // Flatten: extract name, description, parameters to top level
                var responseTool: [String: Any] = [
                    "type": "function"
                ]

                if let name = functionDef["name"] {
                    responseTool["name"] = name
                }
                if let description = functionDef["description"] {
                    responseTool["description"] = description
                }
                if let parameters = functionDef["parameters"] {
                    responseTool["parameters"] = parameters
                }
                // Include strict if present
                if let strict = functionDef["strict"] {
                    responseTool["strict"] = strict
                }

                return responseTool
            }

            // Already in flat format, return as-is
            return tool
        }
    }
}
