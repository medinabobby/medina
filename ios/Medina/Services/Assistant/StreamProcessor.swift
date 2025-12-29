//
//  StreamProcessor.swift
//  Medina
//
//  Created by Bobby Tulsiani on 2025-11-24.
//  v59.2 - Stream Processing for OpenAI Assistants API
//

import Foundation

/// Processes Server-Sent Events (SSE) from OpenAI Assistants API
/// v59.2: Basic text streaming only (no tool calls yet)
class StreamProcessor {

    // MARK: - Stream Events

    /// Events emitted during streaming
    enum StreamEvent {
        case textDelta(String)           // New text chunk
        case textDone                    // Text generation complete
        case toolCall(ToolCall)          // v59.3: Single tool call (legacy)
        case toolCalls([ToolCall])       // v66.4: Multiple parallel tool calls
        case runCompleted                // Run finished successfully
        case runFailed(String)           // Run failed with error
        case error(Error)                // Processing error
    }

    /// v59.3: Tool call information
    struct ToolCall {
        let id: String                   // Tool call ID (for submitting output)
        let runId: String                // Run ID that requires action
        let name: String                 // Tool name (e.g., "show_schedule")
        let arguments: String            // JSON arguments
    }

    // MARK: - Async Stream Processing

    /// Process SSE stream from URLSession data stream
    static func processStream(
        from dataStream: URLSession.AsyncBytes
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                // v68.0: Buffer raw bytes to handle multi-byte UTF-8 characters correctly
                var byteBuffer: [UInt8] = []
                var currentEvent: String?  // Track the event type

                do {
                    for try await byte in dataStream {
                        if byte == 0x0A {  // newline byte
                            // Convert byte buffer to string using proper UTF-8 decoding
                            let line = String(decoding: byteBuffer, as: UTF8.self)
                                .trimmingCharacters(in: .whitespaces)

                            if line.hasPrefix("event:") {
                                // Extract event type
                                currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                                print("📡 [StreamProcessor] Event: \(currentEvent ?? "nil")")
                            } else if line.hasPrefix("data:") {
                                // Extract JSON data
                                let jsonString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)

                                // Skip [DONE] marker
                                if jsonString == "[DONE]" {
                                    continuation.yield(.runCompleted)
                                } else if let event = parseEventData(jsonString, eventType: currentEvent) {
                                    continuation.yield(event)
                                }

                                // Reset event after processing data
                                currentEvent = nil
                            }

                            byteBuffer = []
                        } else {
                            byteBuffer.append(byte)
                        }
                    }

                    // Process any remaining buffer
                    if !byteBuffer.isEmpty {
                        let line = String(decoding: byteBuffer, as: UTF8.self)
                            .trimmingCharacters(in: .whitespaces)
                        if line.hasPrefix("data:") {
                            let jsonString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            if jsonString == "[DONE]" {
                                continuation.yield(.runCompleted)
                            } else if let event = parseEventData(jsonString, eventType: currentEvent) {
                                continuation.yield(event)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Event Parsing

    /// Parse event data JSON with known event type
    private static func parseEventData(_ jsonString: String, eventType: String?) -> StreamEvent? {
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        // Handle based on event type
        switch eventType {
        case "thread.message.delta":
            // Extract text delta from message delta event
            if let delta = json["delta"] as? [String: Any],
               let content = delta["content"] as? [[String: Any]],
               let firstContent = content.first,
               let text = firstContent["text"] as? [String: Any],
               let value = text["value"] as? String {
                print("📝 [StreamProcessor] Text delta: \(value)")
                return .textDelta(value)
            }

        case "thread.message.completed":
            return .textDone

        case "thread.run.completed":
            return .runCompleted

        case "thread.run.failed":
            if let lastError = json["last_error"] as? [String: Any],
               let message = lastError["message"] as? String {
                return .runFailed(message)
            }
            return .runFailed("Unknown error")

        case "thread.run.requires_action":
            // v66.4: Extract ALL tool calls (OpenAI can request multiple in parallel)
            if let runId = json["id"] as? String,
               let requiredAction = json["required_action"] as? [String: Any],
               let submitToolOutputs = requiredAction["submit_tool_outputs"] as? [String: Any],
               let toolCallsJson = submitToolOutputs["tool_calls"] as? [[String: Any]] {

                var parsedToolCalls: [ToolCall] = []
                for toolCallJson in toolCallsJson {
                    if let toolCallId = toolCallJson["id"] as? String,
                       let function = toolCallJson["function"] as? [String: Any],
                       let name = function["name"] as? String,
                       let arguments = function["arguments"] as? String {
                        print("🔧 [StreamProcessor] Tool call: \(name) with args: \(arguments)")
                        parsedToolCalls.append(ToolCall(id: toolCallId, runId: runId, name: name, arguments: arguments))
                    }
                }

                if parsedToolCalls.count == 1 {
                    // Single tool call - use legacy event for backwards compatibility
                    Logger.spine("StreamProcessor", "Tool call: \(parsedToolCalls[0].name)")
                    return .toolCall(parsedToolCalls[0])
                } else if parsedToolCalls.count > 1 {
                    // Multiple parallel tool calls
                    let names = parsedToolCalls.map { $0.name }.joined(separator: ", ")
                    Logger.spine("StreamProcessor", "Parallel tool calls (\(parsedToolCalls.count)): \(names)")
                    return .toolCalls(parsedToolCalls)
                }
            }

        default:
            break
        }

        return nil
    }
}
