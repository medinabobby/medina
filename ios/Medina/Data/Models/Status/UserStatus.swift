//
// UserStatus.swift
// Medina
//
// Created: October 2025 (v16.6 parsing refactor)
//

import Foundation

/// User-specific status vocabulary
///
/// Replaces the old shared StatusSlot enum with user-specific semantics.
/// Applies to both members and trainers.
///
/// Status Lifecycle:
/// .pending → .active → .inactive → .expired
enum UserStatus: String, CaseIterable, Codable {
    case active    // Current membership/employment (paying member, working trainer)
    case inactive  // Dormant membership (not training but still member)
    case expired   // Membership/employment ended (cancelled, terminated)
    case pending   // Pending approval (trial member, new trainer onboarding)

    var displayName: String {
        switch self {
        case .active:
            return "Active"
        case .inactive:
            return "Inactive"
        case .expired:
            return "Expired"
        case .pending:
            return "Pending"
        }
    }

    var icon: String {
        switch self {
        case .active:
            return "person.fill.checkmark"
        case .inactive:
            return "person.fill.questionmark"
        case .expired:
            return "person.fill.xmark"
        case .pending:
            return "hourglass"
        }
    }

    // MARK: - Parsing

    /// Parse user status from user query
    ///
    /// Handles various phrasings for both members and trainers:
    /// - "active member" → .active
    /// - "former trainer" → .expired
    /// - "new member" → .pending
    /// - "inactive member" → .inactive
    ///
    /// Returns nil if no status keywords found
    static func detect(tokens: Set<String>, normalized: String) -> UserStatus? {
        // Active status detection
        if tokens.contains("active") ||
           normalized.contains("active member") ||
           normalized.contains("active trainer") ||
           normalized.contains("currently training") ||
           normalized.contains("working trainer") {
            return .active
        }

        // Expired status detection (check before "past" to be specific)
        if tokens.contains("former") || tokens.contains("expired") ||
           tokens.contains("cancelled") ||
           normalized.contains("former member") ||
           normalized.contains("former trainer") ||
           normalized.contains("ex-member") ||
           normalized.contains("ex-trainer") ||
           normalized.contains("membership expired") ||
           normalized.contains("membership ended") {
            return .expired
        }

        // Pending status detection
        if tokens.contains("new") || tokens.contains("pending") ||
           tokens.contains("trial") ||
           normalized.contains("new member") ||
           normalized.contains("new trainer") ||
           normalized.contains("recently joined") ||
           normalized.contains("trial member") {
            return .pending
        }

        // Inactive status detection
        if tokens.contains("inactive") || tokens.contains("dormant") ||
           normalized.contains("not training") ||
           normalized.contains("hasn't been") ||
           normalized.contains("not active") {
            return .inactive
        }

        return nil
    }
}

// MARK: - UnifiedUser Model Extension

extension UnifiedUser {
    /// Computed status based on memberProfile or trainerProfile
    ///
    /// Determines user status by checking:
    /// 1. Member profile membershipStatus (if member)
    /// 2. Trainer profile isActive flag (if trainer)
    ///
    /// Priority: If user has both roles, member status takes precedence
    var status: UserStatus {
        // Check member profile first (if exists)
        if let memberProfile = memberProfile {
            // Map MembershipStatus to UserStatus
            switch memberProfile.membershipStatus {
            case .active:
                return .active
            case .pending:
                return .pending
            case .expired:
                return .expired
            case .suspended:
                return .inactive  // Suspended maps to inactive
            case .cancelled:
                return .expired   // Cancelled maps to expired
            }
        }

        // Check trainer profile
        // Note: TrainerProfile doesn't have explicit status field
        // Default trainers to .active (future: add TrainerStatus to model)
        if trainerProfile != nil {
            return .active
        }

        // No profiles found (shouldn't happen)
        return .inactive
    }
}
