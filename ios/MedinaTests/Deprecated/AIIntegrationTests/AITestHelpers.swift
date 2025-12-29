//
// AITestHelpers.swift
// MedinaTests
//
// Helpers for AI integration tests that call real OpenAI API
// Created: December 4, 2025
//
// These tests validate AI behavior by:
// 1. Sending real messages to OpenAI
// 2. Collecting full response text
// 3. Capturing tool calls made
// 4. Asserting on response content
//

import Foundation
@testable import Medina

// MARK: - AI Test Response

/// Captures the full AI response for test assertions
struct AITestResponse {
    /// Full accumulated response text from AI
    let text: String

    /// Tool calls made during the response (name -> arguments JSON)
    let toolCalls: [CapturedToolCall]

    /// Response ID from OpenAI
    let responseId: String?

    /// Any error that occurred
    let error: Error?

    /// Check if a specific tool was called
    func toolWasCalled(_ toolName: String) -> Bool {
        return toolCalls.contains { $0.name == toolName }
    }

    /// Get arguments for a tool call (returns first match)
    func argumentsFor(_ toolName: String) -> [String: Any]? {
        guard let call = toolCalls.first(where: { $0.name == toolName }) else {
            return nil
        }
        return call.parsedArguments
    }
}

/// Captured tool call with parsed arguments
struct CapturedToolCall {
    let id: String
    let name: String
    let argumentsJSON: String

    var parsedArguments: [String: Any]? {
        guard let data = argumentsJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}

// MARK: - AI Test Runner

/// Runs AI tests by sending messages and collecting responses
@MainActor
class AITestRunner {

    private let responsesManager: ResponsesManager
    private var currentUser: UnifiedUser?

    init() {
        self.responsesManager = ResponsesManager()
    }

    /// Initialize with a test user
    func initialize(for user: UnifiedUser) async throws {
        // Register user in TestDataManager so tool handlers can find them
        TestDataManager.shared.users[user.id] = user
        self.currentUser = user
        try await responsesManager.initialize(for: user)
    }

    /// Send a message and collect the full response
    /// - Parameter message: The user message to send
    /// - Returns: AITestResponse with text, tool calls, and any errors
    func sendMessage(_ message: String) async throws -> AITestResponse {
        var accumulatedText = ""
        var capturedToolCalls: [CapturedToolCall] = []
        var responseId: String?
        var responseError: Error?

        do {
            let stream = responsesManager.sendMessageStreaming(message)

            for try await event in stream {
                switch event {
                case .responseCreated(let id):
                    responseId = id

                case .textDelta(let delta):
                    accumulatedText += delta

                case .textDone:
                    // Text complete, may still have tool calls
                    break

                case .toolCall(let toolCall):
                    capturedToolCalls.append(CapturedToolCall(
                        id: toolCall.id,
                        name: toolCall.name,
                        argumentsJSON: toolCall.arguments
                    ))

                case .toolCalls(let toolCalls):
                    for toolCall in toolCalls {
                        capturedToolCalls.append(CapturedToolCall(
                            id: toolCall.id,
                            name: toolCall.name,
                            argumentsJSON: toolCall.arguments
                        ))
                    }

                case .responseCompleted(let id):
                    responseId = id
                    // Don't execute tool calls - we're just capturing for test validation

                case .responseFailed(let errorMsg):
                    responseError = NSError(
                        domain: "AITest",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: errorMsg]
                    )

                case .error(let error):
                    responseError = error
                }
            }
        } catch {
            responseError = error
        }

        return AITestResponse(
            text: accumulatedText,
            toolCalls: capturedToolCalls,
            responseId: responseId,
            error: responseError
        )
    }

    /// Reset for next test
    func reset() {
        responsesManager.reset()
        currentUser = nil
    }
}

// MARK: - Test User Factories

/// Creates test users for AI integration tests
enum AITestUsers {

    /// User with full profile - AI should NOT ask for info
    static func userWithFullProfile() -> UnifiedUser {
        let user = UnifiedUser(
            id: "ai_test_full_profile",
            firebaseUID: "ai_test_firebase",
            authProvider: .email,
            email: "aitest@medina.app",
            name: "AI Test User",
            birthdate: Calendar.current.date(byAdding: .year, value: -30, to: Date()),
            gender: .male,
            roles: [.member],
            memberProfile: MemberProfile(
                fitnessGoal: .muscleGain,
                experienceLevel: .intermediate,
                preferredWorkoutDays: [.monday, .tuesday, .wednesday, .thursday, .friday],
                preferredSessionDuration: 60,
                membershipStatus: .active,
                memberSince: Date()
            )
        )
        TestDataManager.shared.users[user.id] = user
        return user
    }

    /// User with home equipment configured
    static func userWithHomeEquipment() -> UnifiedUser {
        var user = UnifiedUser(
            id: "ai_test_home_equipment",
            firebaseUID: "ai_test_home_firebase",
            authProvider: .email,
            email: "aitest_home@medina.app",
            name: "AI Test User Home",
            birthdate: Calendar.current.date(byAdding: .year, value: -30, to: Date()),
            gender: .male,
            roles: [.member],
            memberProfile: MemberProfile(
                fitnessGoal: .muscleGain,
                experienceLevel: .intermediate,
                preferredWorkoutDays: [.monday, .tuesday, .wednesday, .thursday, .friday],
                preferredSessionDuration: 60,
                trainingLocation: .home,
                availableEquipment: [.dumbbells, .pullupBar],
                membershipStatus: .active,
                memberSince: Date()
            )
        )
        TestDataManager.shared.users[user.id] = user
        return user
    }

    /// New user with minimal profile - AI should ASK for info
    /// Note: MemberProfile requires fitnessGoal, experienceLevel, preferredSessionDuration
    /// For testing "new user" behavior, we set defaults but test will validate AI behavior
    static func newUserMinimalProfile() -> UnifiedUser {
        let user = UnifiedUser(
            id: "ai_test_new_user",
            firebaseUID: "ai_test_new_firebase",
            authProvider: .email,
            email: "newuser@medina.app",
            name: "New User",
            birthdate: nil,
            gender: .male,  // Required field
            roles: [.member],
            memberProfile: nil  // No member profile = truly new user
        )
        TestDataManager.shared.users[user.id] = user
        return user
    }
}

// MARK: - Assertion Helpers

extension AITestResponse {

    /// Check response doesn't contain phrases that indicate AI is asking for info
    func assertDoesNotAskFor(_ phrases: [String], file: StaticString = #file, line: UInt = #line) -> Bool {
        let lowercaseText = text.lowercased()
        for phrase in phrases {
            if lowercaseText.contains(phrase.lowercased()) {
                return false
            }
        }
        return true
    }

    /// Check response contains expected confirmation phrases
    func assertContains(_ phrases: [String], file: StaticString = #file, line: UInt = #line) -> Bool {
        let lowercaseText = text.lowercased()
        for phrase in phrases {
            if lowercaseText.contains(phrase.lowercased()) {
                return true
            }
        }
        return false
    }

    /// Common phrases that indicate AI is RE-ASKING for profile data
    /// Note: These should be question phrases, not statements
    /// AI saying "based on your intermediate experience" is GOOD (using profile)
    /// AI asking "what's your experience level?" is BAD (re-asking)
    static let profileReaskPhrases = [
        "what days can you",
        "what days do you",
        "how many days per week",
        "what's your experience level",
        "what is your experience level",
        "how experienced are you",
        "are you a beginner",
        "how long per session",
        "how long do you want your workouts",
        "how much time do you have"
    ]

    /// Common phrases that indicate AI is asking about equipment
    static let equipmentAskPhrases = [
        "what equipment do you have",
        "what equipment will you",
        "do you have access to",
        "what equipment is available"
    ]
}
