//
// HandlerResponseBuilder.swift
// Medina
//
// v69.5: Standardized response formatting for tool handlers
// Provides consistent structure for AI-parseable responses
//

import Foundation

/// Builds standardized responses for tool handlers
/// Ensures consistent formatting across all handlers for AI parsing
enum HandlerResponseBuilder {

    // MARK: - Success Responses

    /// Builds a success response with data fields and AI guidance
    /// - Parameters:
    ///   - action: What was accomplished (e.g., "Workout created", "Plan rescheduled")
    ///   - data: Key-value pairs of relevant data
    ///   - guidance: Instructions for AI on how to respond to user
    /// - Returns: Formatted response string
    static func success(
        action: String,
        data: [(key: String, value: String)] = [],
        guidance: [String] = []
    ) -> String {
        var response = "SUCCESS: \(action)"

        // Add data fields
        if !data.isEmpty {
            response += "\n"
            for field in data {
                response += "\n\(field.key): \(field.value)"
            }
        }

        // Add guidance section
        if !guidance.isEmpty {
            response += "\n\nRESPONSE_GUIDANCE:"
            for (index, point) in guidance.enumerated() {
                response += "\n\(index + 1). \(point)"
            }
        }

        return response
    }

    // MARK: - Error Responses

    /// Builds an error response
    /// - Parameter message: The error message
    /// - Returns: Formatted error string with ERROR: prefix
    static func error(_ message: String) -> String {
        return "ERROR: \(message)"
    }

    /// Builds an error for missing required parameter
    /// - Parameter parameter: Name of the missing parameter
    /// - Returns: Formatted error string
    static func missingParameter(_ parameter: String) -> String {
        return "ERROR: Missing required parameter '\(parameter)'."
    }

    /// Builds an error for entity not found
    /// - Parameters:
    ///   - entityType: Type of entity (e.g., "Workout", "Plan")
    ///   - id: The ID that wasn't found
    /// - Returns: Formatted error string
    static func notFound(entityType: String, id: String) -> String {
        return "ERROR: \(entityType) not found with ID '\(id)'."
    }

    // MARK: - Informational Responses

    /// Builds an informational response (not success, not error - just data)
    /// - Parameters:
    ///   - summary: Brief summary headline
    ///   - data: Key-value pairs of data
    ///   - instruction: Single instruction for AI
    /// - Returns: Formatted response string
    static func info(
        summary: String,
        data: [(key: String, value: String)] = [],
        instruction: String? = nil
    ) -> String {
        var response = summary

        if !data.isEmpty {
            response += "\n"
            for field in data {
                response += "\n\(field.key): \(field.value)"
            }
        }

        if let instruction = instruction {
            response += "\n\nINSTRUCTIONS: \(instruction)"
        }

        return response
    }

    // MARK: - Voice-Ready Responses

    /// Builds a response that requires voice-friendly AI output
    /// - Parameters:
    ///   - content: The main content
    ///   - voiceGuidance: Guidance for generating voice-ready response
    /// - Returns: Formatted response string
    static func voiceReady(
        content: String,
        voiceGuidance: String
    ) -> String {
        return """
        \(content)

        [VOICE_READY: \(voiceGuidance)]
        """
    }

    // MARK: - Follow-up Responses

    /// Builds a response that requires user follow-up action
    /// - Parameters:
    ///   - message: Message to user
    ///   - instruction: Instruction for AI on what to do if user confirms
    /// - Returns: Formatted response string
    static func requiresFollowUp(
        message: String,
        instruction: String
    ) -> String {
        return """
        \(message)

        [INSTRUCTION: \(instruction)]
        """
    }
}
