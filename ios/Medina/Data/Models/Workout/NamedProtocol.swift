//
// NamedProtocol.swift
// Medina
//
// v84.0: Named protocols for clean protocol switching
// Created: December 5, 2025
//
// Defines common training protocols with their exact parameters.
// AI just specifies the protocol name, system resolves all values.
//

import Foundation

/// Named training protocols with pre-defined parameters
/// System resolves these to exact rep/rest/tempo/RPE values
enum NamedProtocol: String, Codable, CaseIterable {
    case gbc = "gbc"                    // German Body Composition
    case hypertrophy = "hypertrophy"    // Muscle building
    case strength = "strength"          // Heavy, low rep
    case endurance = "endurance"        // High rep, light weight
    case power = "power"                // Explosive, low rep

    /// Display name for UI
    var displayName: String {
        switch self {
        case .gbc: return "GBC (German Body Composition)"
        case .hypertrophy: return "Hypertrophy"
        case .strength: return "Strength"
        case .endurance: return "Muscular Endurance"
        case .power: return "Power"
        }
    }

    /// Target reps per set
    var targetReps: Int {
        switch self {
        case .gbc: return 12
        case .hypertrophy: return 10
        case .strength: return 5
        case .endurance: return 15
        case .power: return 3
        }
    }

    /// Number of sets
    var sets: Int {
        switch self {
        case .gbc: return 3
        case .hypertrophy: return 4
        case .strength: return 5
        case .endurance: return 3
        case .power: return 5
        }
    }

    /// Rest between sets in seconds
    var restBetweenSets: Int {
        switch self {
        case .gbc: return 30           // Short rest for metabolic stress
        case .hypertrophy: return 60   // Moderate rest
        case .strength: return 180     // Long rest for recovery
        case .endurance: return 30     // Short rest
        case .power: return 180        // Full recovery for explosiveness
        }
    }

    /// Tempo (eccentric-pause-concentric-pause)
    var tempo: String {
        switch self {
        case .gbc: return "3010"        // Controlled eccentric
        case .hypertrophy: return "3010" // Time under tension
        case .strength: return "2010"   // Controlled but not slow
        case .endurance: return "2010"  // Moderate pace
        case .power: return "10X0"      // Explosive concentric
        }
    }

    /// Target RPE
    var targetRPE: Double {
        switch self {
        case .gbc: return 8.0
        case .hypertrophy: return 8.0
        case .strength: return 9.0
        case .endurance: return 7.0
        case .power: return 8.0
        }
    }

    /// Brief description for AI/user
    var description: String {
        switch self {
        case .gbc:
            return "High volume, short rest, controlled tempo for metabolic stress and fat loss"
        case .hypertrophy:
            return "Moderate volume and rest for muscle growth"
        case .strength:
            return "Heavy weight, low reps, long rest for maximum strength"
        case .endurance:
            return "High reps, light weight, short rest for muscular endurance"
        case .power:
            return "Explosive movements, full recovery between sets"
        }
    }
}
