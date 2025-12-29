//
// PlanStatus.swift
// Medina
//
// Created: October 2025 (v16.6 parsing refactor)
// v172: Removed .abandoned - simplified to draft/active/completed
// v172.1: Added backward-compatible decoder for legacy "abandoned" data
//

import Foundation

/// Plan-specific status vocabulary
///
/// Simplified lifecycle (v172):
/// ```
/// .draft → (manual activate) → .active → (endDate passes OR manual complete) → .completed
/// ```
///
/// Filtering (v172):
/// - "show plans" → active + draft (default view)
/// - "show archived plans" → completed only
///
/// Deletion (v172):
/// - Draft plans: can delete immediately
/// - Active plans: must complete first
/// - Completed plans: can delete with confirmation
///
/// effectiveStatus:
/// - Respects manual activation (status == .active) even if startDate is future
/// - Auto-completes when endDate passes (active → completed)
/// - Draft plans with startDate > now remain draft (wait for manual activation)
enum PlanStatus: String, CaseIterable, Codable {
    case draft      // Plan created but not started (before startDate)
    case active     // Plan currently running (between startDate and endDate)
    case completed  // Plan finished (endDate passed OR manually completed early)

    // MARK: - v172.1: Backward Compatible Decoding

    /// Custom decoder to handle legacy "abandoned" status from persisted data
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "draft": self = .draft
        case "active": self = .active
        case "completed": self = .completed
        case "abandoned": self = .completed  // v172.1: Legacy migration
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown PlanStatus: \(rawValue)"
                )
            )
        }
    }

    var displayName: String {
        switch self {
        case .draft:
            return "Draft"
        case .active:
            return "Active"
        case .completed:
            return "Completed"
        }
    }

    var icon: String {
        switch self {
        case .draft:
            return "doc.text"
        case .active:
            return "play.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        }
    }

    // MARK: - Parsing

    /// Parse plan status from user query
    ///
    /// Handles various phrasings:
    /// - "draft plan" → .draft
    /// - "active plan" → .active
    /// - "completed plan" → .completed
    /// - "archived plan" → .completed (v172: archived = completed)
    ///
    /// Returns nil if no status keywords found
    static func detect(tokens: Set<String>, normalized: String) -> PlanStatus? {
        // Draft detection
        if tokens.contains("draft") || tokens.contains("upcoming") || tokens.contains("future") {
            return .draft
        }

        // Active detection
        if tokens.contains("active") || tokens.contains("current") ||
           tokens.contains("running") || tokens.contains("ongoing") {
            return .active
        }

        // Completed detection (v172: includes "archived" and "abandoned" for backward compatibility)
        if tokens.contains("completed") || tokens.contains("complete") ||
           tokens.contains("finished") || tokens.contains("done") || tokens.contains("past") ||
           tokens.contains("archived") || tokens.contains("abandoned") || tokens.contains("cancelled") {
            return .completed
        }

        return nil
    }
}
