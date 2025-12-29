//
// StatusHelpers.swift
// Medina
//
// v46 Handler Refactor: Shared status display helpers for detail views
// Created: November 2025
// Purpose: Centralized status info to eliminate duplication across detail views
//

import SwiftUI

// MARK: - ExecutionStatus Helpers

extension ExecutionStatus {
    /// Returns display text and color for this execution status
    func statusInfo() -> (String, Color) {
        switch self {
        case .completed:
            return ("Completed", .green)
        case .inProgress:
            return ("In Progress", .accentColor)
        case .scheduled:
            return ("Scheduled", Color("SecondaryText"))
        case .skipped:
            return ("Skipped", .orange)
        }
    }
}

// MARK: - ProgramStatus Helpers

extension ProgramStatus {
    /// Returns display text and color for this program status
    /// v172: Removed abandoned - programs are now draft/active/completed only
    func statusInfo() -> (String, Color) {
        switch self {
        case .draft:
            return ("Draft", Color("SecondaryText"))
        case .active:
            return ("Active", .accentColor)
        case .completed:
            return ("Completed", .green)
        }
    }
}

// MARK: - PlanStatus Helpers

extension PlanStatus {
    /// Returns display text and color for this plan status
    /// v172: Removed abandoned - plans are now draft/active/completed only
    func statusInfo() -> (String, Color) {
        switch self {
        case .draft:
            return ("Draft", Color("SecondaryText"))
        case .active:
            return ("Active", .accentColor)
        case .completed:
            return ("Completed", .green)
        }
    }
}
