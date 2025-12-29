//
// WorkoutStatus.swift
// Medina
//
// Created: October 2025 (v16.6 parsing refactor)
//

import Foundation

/// Workout-specific status vocabulary
///
/// Replaces the old shared StatusSlot enum with workout-specific semantics.
/// Each status has clear meaning in the workout context.
///
/// Status Lifecycle:
/// .scheduled → .inProgress → .completed
///                          ↘ .skipped
enum WorkoutStatus: String, CaseIterable, Codable {
    case scheduled   // Workout is planned but not started
    case inProgress  // Workout has been started but not finished
    case completed   // Workout finished successfully
    case skipped     // User skipped this workout

    var displayName: String {
        switch self {
        case .scheduled:
            return "Scheduled"
        case .inProgress:
            return "In Progress"
        case .completed:
            return "Completed"
        case .skipped:
            return "Skipped"
        }
    }

    var icon: String {
        switch self {
        case .scheduled:
            return "calendar"
        case .inProgress:
            return "figure.run"
        case .completed:
            return "checkmark.circle.fill"
        case .skipped:
            return "xmark.circle"
        }
    }

    // MARK: - Parsing

    /// Parse workout status from user query
    ///
    /// Handles various phrasings:
    /// - "skipped workout" → .skipped
    /// - "completed workout" → .completed
    /// - "in progress" → .inProgress
    /// - "upcoming workout" → .scheduled
    ///
    /// Returns nil if no status keywords found
    static func detect(tokens: Set<String>, normalized: String) -> WorkoutStatus? {
        // Skipped detection
        if tokens.contains("skipped") || tokens.contains("missed") {
            return .skipped
        }

        // Completed detection
        // v21.3: Use token-based matching only - prevents entity names from triggering status
        if tokens.contains("completed") || tokens.contains("complete") ||
           tokens.contains("finished") || tokens.contains("done") {
            return .completed
        }

        // In Progress detection
        if normalized.contains("in progress") || normalized.contains("started") ||
           normalized.contains("ongoing") || tokens.contains("active") {
            return .inProgress
        }

        // Scheduled detection
        if tokens.contains("upcoming") || tokens.contains("scheduled") ||
           tokens.contains("planned") || normalized.contains("not started") {
            return .scheduled
        }

        return nil
    }
}

// MARK: - Workout Model Extension
// v21.0: Extension removed - Workout now stores status: ExecutionStatus directly
// WorkoutStatus enum kept for query parsing only
