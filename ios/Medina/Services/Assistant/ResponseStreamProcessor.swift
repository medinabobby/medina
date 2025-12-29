//
//  ResponseStreamProcessor.swift
//  Medina
//
//  v80.0: Stream processor for OpenAI Responses API
//  Simpler than Assistants API - no requires_action handling, tool results inline
//

import Foundation

/// Processes Server-Sent Events (SSE) from OpenAI Responses API
/// Simpler than StreamProcessor - unified event handling
class ResponseStreamProcessor {

    // MARK: - Constants

    private static let component = "ResponseStreamProcessor"

    // MARK: - State for Tool Call Parsing

    /// Track pending tool calls by item_id (name comes in output_item.added, args come in arguments.done)
    private static var pendingToolCalls: [String: (name: String, callId: String)] = [:]

    // MARK: - Stream Events

    /// Events emitted during streaming
    enum ResponseEvent: Sendable {
        case responseCreated(responseId: String)            // v80.1: Response started - ID available for tool continuations
        case textDelta(String)                              // New text chunk
        case textDone                                       // Text generation complete
        case toolCall(ToolCall)                             // Single tool call (execute and include result in next request)
        case toolCalls([ToolCall])                          // Multiple parallel tool calls
        case responseCompleted(responseId: String)          // Response finished, includes ID for chaining
        case responseFailed(String)                         // Response failed with error
        case error(Error)                                   // Processing error
        case workoutCard(WorkoutCardData)                   // v210: Workout card from server handler
        case planCard(PlanCardData)                         // v210: Plan card from server handler
        case suggestionChips([[String: String]])            // v211: Suggestion chips from server
    }

    /// v210: Workout card data from server handler
    struct WorkoutCardData: Sendable {
        let workoutId: String
        let workoutName: String
    }

    /// v210: Plan card data from server handler
    struct PlanCardData: Sendable {
        let planId: String
        let planName: String
        let workoutCount: Int
        let durationWeeks: Int
    }

    /// Tool call information from Responses API
    struct ToolCall: Sendable {
        let id: String           // Tool call ID
        let name: String         // Tool name (e.g., "show_schedule")
        let arguments: String    // JSON arguments

        // Note: No runId needed - Responses API doesn't have the submit_tool_outputs flow
    }

    // MARK: - Async Stream Processing

    /// Process SSE stream from URLSession data stream
    static func processStream(
        from dataStream: URLSession.AsyncBytes
    ) -> AsyncThrowingStream<ResponseEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                var byteBuffer: [UInt8] = []
                var currentEvent: String?

                do {
                    for try await byte in dataStream {
                        if byte == 0x0A {  // newline byte
                            let line = String(decoding: byteBuffer, as: UTF8.self)
                                .trimmingCharacters(in: .whitespaces)

                            if line.hasPrefix("event:") {
                                currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                            } else if line.hasPrefix("data:") {
                                let jsonString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)

                                if jsonString == "[DONE]" {
                                    // Stream complete - we should have already received response.completed
                                    Logger.log(.debug, component: "ResponseStreamProcessor", message: "Stream [DONE] marker received")
                                } else if let event = parseEventData(jsonString, eventType: currentEvent) {
                                    continuation.yield(event)
                                }

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
                            if jsonString != "[DONE]", let event = parseEventData(jsonString, eventType: currentEvent) {
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

    /// Parse event data JSON based on event type
    /// v80.0.1: Fixed to match actual Responses API format from curl testing
    private static func parseEventData(_ jsonString: String, eventType: String?) -> ResponseEvent? {
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        // Responses API event types (verified via curl testing)
        switch eventType {

        // v80.1: Response created - capture ID early for tool continuation
        case "response.created":
            if let response = json["response"] as? [String: Any],
               let responseId = response["id"] as? String {
                Logger.spine(component, "📝 Response created: \(responseId.prefix(20))...")
                return .responseCreated(responseId: responseId)
            }

        // Text content delta
        case "response.output_text.delta":
            if let delta = json["delta"] as? String {
                return .textDelta(delta)
            }

        // Content part delta (alternative text format)
        case "response.content_part.delta":
            if let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                return .textDelta(text)
            }

        // v178: Content part added - may contain initial text
        case "response.content_part.added":
            if let part = json["part"] as? [String: Any],
               let text = part["text"] as? String,
               !text.isEmpty {
                return .textDelta(text)
            }

        // Text output complete
        case "response.output_text.done", "response.content_part.done":
            return .textDone

        // Response completed successfully
        case "response.completed":
            if let response = json["response"] as? [String: Any],
               let responseId = response["id"] as? String {
                Logger.spine(component, "✅ Response completed: \(responseId)")
                return .responseCompleted(responseId: responseId)
            }

        // Response failed
        case "response.failed":
            if let response = json["response"] as? [String: Any],
               let error = response["error"] as? [String: Any],
               let message = error["message"] as? String {
                return .responseFailed(message)
            }
            // Fallback: check top-level error
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return .responseFailed(message)
            }
            return .responseFailed("Unknown error")

        // Function/tool call added - capture tool name and ID, store for later
        case "response.output_item.added":
            if let item = json["item"] as? [String: Any],
               let type = item["type"] as? String,
               type == "function_call",
               let callId = item["call_id"] as? String,
               let name = item["name"] as? String,
               let itemId = item["id"] as? String {
                // Store name and callId by itemId - we'll need them when arguments.done fires
                pendingToolCalls[itemId] = (name: name, callId: callId)
                Logger.log(.debug, component: component, message: "Tool call started: \(name)")
            }

        // Function call arguments (streamed separately)
        case "response.function_call_arguments.delta":
            // Arguments are streamed - accumulating happens at higher level
            break

        // Function call complete with full arguments - THIS is when we emit
        case "response.function_call_arguments.done":
            let itemId = json["item_id"] as? String ?? ""
            let arguments = json["arguments"] as? String ?? "{}"

            // Look up the name and callId from the earlier output_item.added event
            if let pending = pendingToolCalls[itemId] {
                let name = pending.name
                let callId = pending.callId
                pendingToolCalls.removeValue(forKey: itemId)  // Clean up

                Logger.spine(component, "🔧 Tool call: \(name)")
                return .toolCall(ToolCall(id: callId, name: name, arguments: arguments))
            } else {
                Logger.log(.warning, component: component, message: "No pending tool call found for itemId: \(itemId)")
            }

        // Output item done (could be message or function_call)
        case "response.output_item.done":
            if let item = json["item"] as? [String: Any],
               let type = item["type"] as? String {
                if type == "message" {
                    return .textDone
                }
                // function_call done is handled by arguments.done
            }

        // v210: Workout card from server handler (custom event)
        case "workout_card":
            if let cards = json["cards"] as? [[String: Any]], let firstCard = cards.first,
               let workoutId = firstCard["workoutId"] as? String,
               let workoutName = firstCard["workoutName"] as? String {
                Logger.spine(component, "📋 Workout card: \(workoutName)")
                return .workoutCard(WorkoutCardData(workoutId: workoutId, workoutName: workoutName))
            }

        // v210: Plan card from server handler (custom event)
        case "plan_card":
            if let cards = json["cards"] as? [[String: Any]], let firstCard = cards.first,
               let planId = firstCard["planId"] as? String,
               let planName = firstCard["planName"] as? String,
               let workoutCount = firstCard["workoutCount"] as? Int,
               let durationWeeks = firstCard["durationWeeks"] as? Int {
                Logger.spine(component, "📋 Plan card: \(planName)")
                return .planCard(PlanCardData(planId: planId, planName: planName, workoutCount: workoutCount, durationWeeks: durationWeeks))
            }

        // v211: Suggestion chips from server
        case "suggestion_chips":
            if let chips = json["chips"] as? [[String: String]] {
                Logger.spine(component, "💡 Suggestion chips: \(chips.count)")
                return .suggestionChips(chips)
            }

        default:
            // Log unhandled events for debugging
            if let eventType = eventType, !eventType.isEmpty {
                Logger.log(.debug, component: "ResponseStreamProcessor",
                          message: "Unhandled event type: \(eventType)")
            }
        }

        return nil
    }
}
