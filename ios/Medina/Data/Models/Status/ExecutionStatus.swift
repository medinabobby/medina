//
// ExecutionStatus.swift
// Medina
//
// Created: v21.0 Status Architecture Cleanup
// Last reviewed: October 2025
//

import Foundation

/// Execution-level status for workouts and exercise instances
///
/// Shared by Workout (session) and ExerciseInstance (exercise within session)
/// Replaces the old ExecutionStatus enum with clearer semantics.
///
/// Lifecycle: scheduled → inProgress → completed/skipped
///
/// Use Cases:
/// - Workout.status: Overall session execution state
/// - ExerciseInstance.status: Individual exercise execution state
///
/// Business Rules:
/// - .scheduled: Not started yet (no completion data)
/// - .inProgress: Partially complete (some sets logged)
/// - .completed: Fully complete (all required sets logged)
/// - .skipped: User explicitly skipped workout/exercise
enum ExecutionStatus: String, CaseIterable, Codable {
    case scheduled   = "scheduled"    // Not started yet
    case inProgress  = "inProgress"   // Partially complete
    case completed   = "completed"    // Fully complete
    case skipped     = "skipped"      // User skipped

    var displayName: String {
        switch self {
        case .scheduled:   return "Scheduled"
        case .inProgress:  return "In Progress"
        case .completed:   return "Completed"
        case .skipped:     return "Skipped"
        }
    }

    var icon: String {
        switch self {
        case .scheduled:   return "calendar"
        case .inProgress:  return "figure.run"
        case .completed:   return "checkmark.circle.fill"
        case .skipped:     return "xmark.circle"
        }
    }

    // v53.0 Phase 2: Removed badge property (CardBadge deleted with card infrastructure)

    // MARK: - Parsing

    /// Parse execution status from user query
    ///
    /// Handles various phrasings:
    /// - "skipped workout" → .skipped
    /// - "completed workout" → .completed
    /// - "in progress" → .inProgress
    /// - "upcoming workout" → .scheduled
    ///
    /// Returns nil if no status keywords found
    static func detect(tokens: Set<String>, normalized: String) -> ExecutionStatus? {
        // Skipped detection
        if tokens.contains("skipped") || tokens.contains("missed") {
            return .skipped
        }

        // Completed detection
        if tokens.contains("completed") || tokens.contains("finished") ||
           normalized.contains("i completed") || normalized.contains("done") {
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
