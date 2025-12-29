//
// ExecutionMode.swift
// Medina
//
// v52.3: Dual-mode workout execution (simple data entry vs guided coaching)
// Created: November 2025
//

import Foundation

/// Defines how a workout session is executed
enum ExecutionMode: String, Codable {
    /// Simple data entry mode: All sets unlocked, no rest timers, manual completion
    case simple

    /// Guided coaching mode: Progressive sets, rest timers, auto-navigation, voice feedback
    case guided
}
