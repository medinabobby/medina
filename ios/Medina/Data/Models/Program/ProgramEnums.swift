//
// ProgramEnums.swift
// Medina
//
// Last reviewed: October 2025
// v69.0: Added PeriodizationStyle enum for multi-program plan generation
//

import Foundation

enum TrainingFocus: String, CaseIterable, Codable {
    case foundation = "foundation"
    case development = "development"
    case peak = "peak"
    case maintenance = "maintenance"
    case deload = "deload"

    var displayName: String {
        rawValue.capitalized
    }

    var description: String {
        switch self {
        case .foundation:
            return "Build movement skills and work capacity"
        case .development:
            return "Progressive volume and intensity"
        case .peak:
            return "Maximum performance and intensity"
        case .maintenance:
            return "Sustain current fitness level"
        case .deload:
            return "Recovery week with reduced volume"
        }
    }

    var educationalDescription: String {
        switch self {
        case .foundation:
            return "This involves building movement patterns, establishing training habits, and creating a base level of fitness to support future progress."
        case .development:
            return "This involves progressive overload, skill refinement, and systematically building strength, power, or endurance capacity."
        case .peak:
            return "This involves competition preparation, performance optimization, and fine-tuning systems to achieve maximum output."
        case .maintenance:
            return "This involves maintaining current fitness levels with minimal effective dose training while managing life stressors or recovery periods."
        case .deload:
            return "This involves strategic recovery with reduced training intensity and volume to prepare the body for the next training phase."
        }
    }
}

enum ProgressionType: String, CaseIterable, Codable {
    case staticProgression = "static"
    case linear = "linear"
    case undulating = "undulating"

    var displayName: String {
        switch self {
        case .staticProgression: return "Static"
        case .linear: return "Linear"
        case .undulating: return "Undulating"
        }
    }

    var description: String {
        switch self {
        case .staticProgression:
            return "Same intensity throughout program"
        case .linear:
            return "Add weight consistently each week"
        case .undulating:
            return "Vary intensity within and across weeks"
        }
    }

    var educationalDescription: String {
        switch self {
        case .staticProgression:
            return "This maintains current loads to preserve fitness during recovery periods or when managing life stress."
        case .linear:
            return "This involves progressive increases in weight, reps, or sets each session for steady advancement and strength building."
        case .undulating:
            return "This varies intensities and rep ranges session to session to prevent plateaus and maintain consistent progress."
        }
    }
}

/// v172: Simplified - removed abandoned (programs inherit from plan, which no longer has abandoned)
enum ProgramStatus: String, CaseIterable, Codable {
    case draft      = "draft"       // v21.1: Plan/program created but not activated
    case active     = "active"      // v21.1: Program currently running
    case completed  = "completed"   // v21.1: Program finished (normal or early)

    var displayName: String {
        rawValue.capitalized
    }

    // v53.0 Phase 2: Removed badge property (CardBadge deleted with card infrastructure)

    // MARK: - Parsing

    /// Parse program status from user query
    /// v172: Removed abandoned - maps to completed
    static func detect(tokens: Set<String>, normalized: String) -> ProgramStatus? {
        // Draft detection
        if tokens.contains("draft") {
            return .draft
        }

        // Active detection
        if tokens.contains("active") || tokens.contains("current") {
            return .active
        }

        // Completed detection (v172: includes abandoned/cancelled for backward compatibility)
        if tokens.contains("completed") || tokens.contains("complete") || tokens.contains("finished") ||
           tokens.contains("done") || tokens.contains("abandoned") || tokens.contains("cancelled") {
            return .completed
        }

        return nil
    }
}

// MARK: - v69.0: Periodization

/// v69.0: How training phases are structured across a plan
enum PeriodizationStyle: String, CaseIterable, Codable {
    case auto = "auto"                  // AI decides based on goal/duration
    case linear = "linear"              // Foundation → Development → Peak (traditional)
    case block = "block"                // Focused blocks (hypertrophy → strength → power)
    case undulating = "undulating"      // Alternating intensity within phases
    case none = "none"                  // Single program, no phase structure

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .linear: return "Linear"
        case .block: return "Block"
        case .undulating: return "Undulating"
        case .none: return "None"
        }
    }

    var description: String {
        switch self {
        case .auto:
            return "AI selects optimal periodization based on your goal and plan duration"
        case .linear:
            return "Progressive phases from foundation through peak performance"
        case .block:
            return "Focused training blocks targeting specific adaptations"
        case .undulating:
            return "Varied intensity patterns within and across phases"
        case .none:
            return "Single continuous program without distinct phases"
        }
    }
}
