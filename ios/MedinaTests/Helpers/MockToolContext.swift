//
// MockToolContext.swift
// MedinaTests
//
// Test infrastructure for tool handler testing
// Created: December 4, 2025
// Updated: December 9, 2025 - v99.9: Added pendingCards tracking
//
// Provides mock ToolCallContext for unit testing tool handlers
// without making network calls or requiring full UI context.
//

import Foundation
@testable import Medina

/// Builder for creating test-friendly ToolCallContext instances
/// Captures messages and state for test assertions
@MainActor
class MockToolContext {

    // MARK: - Captured State (for test assertions)

    /// Messages added during tool execution
    private(set) var capturedMessages: [Message] = []

    /// Last stored workout ID
    private(set) var lastWorkoutId: String?

    /// v99.9: Track the last built context to access pending cards
    private(set) var lastBuiltContext: ToolCallContext?

    /// v193.1: Last user message for server-side intent detection tests
    private var _lastUserMessage: String?

    /// Mock ResponsesManager (won't make network calls)
    private let responsesManager: ResponsesManager

    // MARK: - Initialization

    init() {
        self.responsesManager = ResponsesManager()
    }

    /// v193.1: Set the last user message for intent detection tests
    func setLastUserMessage(_ message: String?) {
        _lastUserMessage = message
    }

    // MARK: - Build Context

    /// Build a ToolCallContext for testing
    /// - Parameter user: The test user
    /// - Returns: Configured ToolCallContext with mock closures
    func build(for user: UnifiedUser) -> ToolCallContext {
        let context = ToolCallContext(
            user: user,
            responsesManager: responsesManager,
            addMessage: { [weak self] message in
                self?.capturedMessages.append(message)
            },
            updateMessage: { [weak self] index, message in
                guard let self = self, index < self.capturedMessages.count else { return }
                self.capturedMessages[index] = message
            },
            messagesCount: { [weak self] in
                return self?.capturedMessages.count ?? 0
            },
            getLastCreatedWorkoutId: { [weak self] in
                return self?.lastWorkoutId
            },
            setLastCreatedWorkoutId: { [weak self] id in
                self?.lastWorkoutId = id
            },
            lastUserMessage: _lastUserMessage  // v193.1: Pass last user message for intent detection
        )
        lastBuiltContext = context
        return context
    }

    // MARK: - Test Helpers

    /// Reset captured state between tests
    func reset() {
        capturedMessages.removeAll()
        lastWorkoutId = nil
        _lastUserMessage = nil  // v193.1: Reset last user message
        lastBuiltContext?.pendingCards.removeAll()
        lastBuiltContext = nil
    }

    /// Check if any message contains workout created data
    var hasWorkoutCard: Bool {
        // Check both captured messages and pending cards
        let hasCaptured = capturedMessages.contains { $0.workoutCreatedData != nil }
        let hasPending = lastBuiltContext?.pendingCards.contains { $0.workoutCreatedData != nil } ?? false
        return hasCaptured || hasPending
    }

    /// Get the first workout card's data
    var workoutCardData: WorkoutCreatedData? {
        // Check captured messages first, then pending cards
        if let data = capturedMessages.first(where: { $0.workoutCreatedData != nil })?.workoutCreatedData {
            return data
        }
        return lastBuiltContext?.pendingCards.first { $0.workoutCreatedData != nil }?.workoutCreatedData
    }

    /// Check if any message contains plan created data
    var hasPlanCard: Bool {
        // Check both captured messages and pending cards
        let hasCaptured = capturedMessages.contains { $0.planCreatedData != nil }
        let hasPending = lastBuiltContext?.pendingCards.contains { $0.planCreatedData != nil } ?? false
        return hasCaptured || hasPending
    }

    /// Get the first plan card's data
    var planCardData: PlanCreatedData? {
        // Check captured messages first, then pending cards
        if let data = capturedMessages.first(where: { $0.planCreatedData != nil })?.planCreatedData {
            return data
        }
        return lastBuiltContext?.pendingCards.first { $0.planCreatedData != nil }?.planCreatedData
    }
}
