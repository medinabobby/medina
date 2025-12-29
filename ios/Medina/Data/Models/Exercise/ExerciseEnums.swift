//
// ExerciseEnums.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

enum ExerciseType: String, Codable, CaseIterable {
    case compound = "compound"
    case isolation = "isolation"
    case warmup = "warmup"
    case cooldown = "cooldown"
    case cardio = "cardio"

    var displayName: String {
        switch self {
        case .compound: return "Compound"
        case .isolation: return "Isolation"
        case .warmup: return "Warm-up"
        case .cooldown: return "Cool Down"
        case .cardio: return "Cardio"
        }
    }
}

enum MovementPattern: String, Codable, CaseIterable {
    // v51.0: Enhanced movement patterns for library selection
    case squat = "squat"
    case hinge = "hinge"
    case horizontalPress = "horizontal_press"
    case verticalPress = "vertical_press"
    case horizontalPull = "horizontal_pull"
    case verticalPull = "vertical_pull"
    case lunge = "lunge"
    case carry = "carry"
    case core = "core"
    case accessory = "accessory"

    // Legacy patterns (keep for backwards compatibility)
    case push = "push"
    case pull = "pull"
    case rotation = "rotation"
    case dynamic = "dynamic"
    case staticStretch = "static_stretch"

    var displayName: String {
        switch self {
        case .squat: return "Squat"
        case .hinge: return "Hinge"
        case .horizontalPress: return "Horizontal Press"
        case .verticalPress: return "Vertical Press"
        case .horizontalPull: return "Horizontal Pull"
        case .verticalPull: return "Vertical Pull"
        case .lunge: return "Lunge"
        case .carry: return "Carry"
        case .core: return "Core"
        case .accessory: return "Accessory"
        case .push: return "Push"
        case .pull: return "Pull"
        case .rotation: return "Rotation"
        case .dynamic: return "Dynamic"
        case .staticStretch: return "Static Stretch"
        }
    }

    // MARK: - v87.0: Pattern Expansion for Movement-First Selection

    /// Expand generic patterns to include specific variants
    /// Example: .pull → [.pull, .horizontalPull, .verticalPull]
    /// This allows AI to send "pull" and match exercises tagged "horizontalPull"
    var expanded: [MovementPattern] {
        switch self {
        case .pull:
            return [.pull, .horizontalPull, .verticalPull]
        case .push:
            return [.push, .horizontalPress, .verticalPress]
        default:
            return [self]
        }
    }

    /// Expand an array of patterns into a set including all variants
    static func expand(_ patterns: [MovementPattern]) -> Set<MovementPattern> {
        Set(patterns.flatMap { $0.expanded })
    }
}

enum ProtocolType: String, Codable, CaseIterable {
    case working = "working"
    case calibration = "calibration"
    case warmup = "warmup"
    case cooldown = "cooldown"
    case assessment = "assessment"
    
    var displayName: String {
        rawValue.capitalized
    }
}

enum TargetType: String, Codable {
    case max = "max"
    case working = "working"

    var displayName: String {
        switch self {
        case .max: return "1 Rep Max"
        case .working: return "Working Weight"
        }
    }

    enum RPE: String, Codable, CaseIterable {
        case warmup = "warmup"           // 4-5
        case easy = "easy"                // 5-6
        case moderate = "moderate"        // 6-7
        case hard = "hard"                // 7-8
        case veryHard = "very_hard"       // 8-9
        case maximal = "maximal"          // 9-10

        var numericValue: Double {
            switch self {
            case .warmup: return 5.0
            case .easy: return 6.0
            case .moderate: return 7.0
            case .hard: return 8.0
            case .veryHard: return 9.0
            case .maximal: return 10.0
            }
        }

        var displayName: String {
            switch self {
            case .warmup: return "Warmup"
            case .easy: return "Easy"
            case .moderate: return "Moderate"
            case .hard: return "Hard"
            case .veryHard: return "Very Hard"
            case .maximal: return "Maximum"
            }
        }

        var description: String {
            switch self {
            case .warmup: return "Very light, warming up"
            case .easy: return "Could do 4-5 more reps"
            case .moderate: return "Could do 3 more reps"
            case .hard: return "Could do 2 more reps"
            case .veryHard: return "Could do 1 more rep"
            case .maximal: return "No reps left"
            }
        }

        // Helper to convert from numeric input
        static func fromNumeric(_ value: Double) -> RPE {
            switch value {
            case 0..<5.5: return .warmup
            case 5.5..<6.5: return .easy
            case 6.5..<7.5: return .moderate
            case 7.5..<8.5: return .hard
            case 8.5..<9.5: return .veryHard
            default: return .maximal
            }
        }
    }

}

// MARK: - Tempo

/// Tempo notation for exercise execution
/// Format: "ABCD" where each digit/character represents a phase duration in seconds
/// - A: Eccentric (lowering) phase
/// - B: Bottom pause (stretch position)
/// - C: Concentric (lifting) phase
/// - D: Top pause (contracted position)
/// - X: Explosive tempo (as fast as possible)
/// Example: "20X0" = 2 seconds down, no pause, explosive up, no pause
enum Tempo: String, Codable, CaseIterable {
    // Power/Explosive patterns
    case explosive_20X0 = "20X0"           // Standard explosive: controlled down, explosive up
    case explosive_30X0 = "30X0"           // Slower eccentric, explosive concentric
    case explosive_10X0 = "10X0"           // Quick eccentric, explosive concentric

    // Strength patterns
    case strength_2010 = "2010"            // Standard strength tempo
    case strength_3010 = "3010"            // Slower eccentric for strength
    case strength_4010 = "4010"            // Very slow eccentric

    // Hypertrophy/Time Under Tension patterns
    case hypertrophy_3110 = "3110"         // Classic hypertrophy tempo
    case hypertrophy_4210 = "4210"         // Extended TUT with pauses
    case hypertrophy_5110 = "5110"         // Long eccentric for muscle damage

    // Pause patterns (strength from dead stop)
    case pause_3030 = "3030"               // Pause squats, bench
    case pause_2020 = "2020"               // Short pauses top and bottom

    // Isometric/Control patterns
    case isometric_3333 = "3333"           // Equal time all phases
    case control_2222 = "2222"             // Controlled constant tempo

    var code: String {
        return rawValue
    }

    var displayName: String {
        switch self {
        // Power patterns
        case .explosive_20X0: return "Standard Explosive"
        case .explosive_30X0: return "Controlled Explosive"
        case .explosive_10X0: return "Fast Explosive"

        // Strength patterns
        case .strength_2010: return "Standard Strength"
        case .strength_3010: return "Slow Eccentric Strength"
        case .strength_4010: return "Extra Slow Eccentric"

        // Hypertrophy patterns
        case .hypertrophy_3110: return "Classic Hypertrophy"
        case .hypertrophy_4210: return "Extended Time Under Tension"
        case .hypertrophy_5110: return "Long Eccentric"

        // Pause patterns
        case .pause_3030: return "Pause Reps"
        case .pause_2020: return "Short Pause"

        // Control patterns
        case .isometric_3333: return "Isometric Control"
        case .control_2222: return "Constant Control"
        }
    }

    var humanDescription: String {
        let phases = parsePhases(code)
        var description = ""

        // Eccentric
        if phases.eccentric.isExplosive {
            description += "Drop down explosively"
        } else if phases.eccentric.duration >= 4 {
            description += "Lower for a slow \(phases.eccentric.duration) count"
        } else if phases.eccentric.duration >= 2 {
            description += "Take \(phases.eccentric.duration) seconds to lower down slowly"
        } else if phases.eccentric.duration == 1 {
            description += "Lower down in 1 second"
        } else {
            description += "Lower down quickly"
        }

        // Bottom pause
        if phases.bottomPause.duration >= 2 {
            description += ", pause \(phases.bottomPause.duration) seconds at the bottom"
        } else if phases.bottomPause.duration == 1 {
            description += ", pause 1 second at the bottom"
        }

        // Concentric
        if phases.concentric.isExplosive {
            description += ", then explode back up"
        } else if phases.concentric.duration >= 2 {
            description += ", then drive up in \(phases.concentric.duration) seconds"
        } else if phases.concentric.duration == 1 {
            description += ", then drive up in 1 second"
        } else {
            description += ", then drive up quickly"
        }

        // Top pause
        if phases.topPause.duration >= 2 {
            description += ", and hold \(phases.topPause.duration) seconds at the top"
        } else if phases.topPause.duration == 1 {
            description += ", and hold 1 second at the top"
        }

        return description
    }

    var purposeDescription: String {
        switch self {
        // Power patterns
        case .explosive_20X0, .explosive_30X0, .explosive_10X0:
            return "This explosive power pattern builds speed and strength"

        // Strength patterns
        case .strength_2010, .strength_3010:
            return "This controlled tempo keeps constant tension on the muscle"
        case .strength_4010:
            return "The long eccentric maximizes time under tension for muscle growth"

        // Hypertrophy patterns
        case .hypertrophy_3110, .hypertrophy_4210, .hypertrophy_5110:
            return "The extended time under tension maximizes muscle fiber recruitment"

        // Pause patterns
        case .pause_3030, .pause_2020:
            return "The pause at the bottom eliminates momentum and builds strength from a dead stop"

        // Control patterns
        case .isometric_3333, .control_2222:
            return "The constant tempo creates peak muscle contraction throughout the range of motion"
        }
    }

    // Helper to parse tempo code into phases
    private func parsePhases(_ code: String) -> (eccentric: (duration: Int, isExplosive: Bool),
                                                   bottomPause: (duration: Int, isExplosive: Bool),
                                                   concentric: (duration: Int, isExplosive: Bool),
                                                   topPause: (duration: Int, isExplosive: Bool)) {
        guard code.count == 4 else {
            return ((0, false), (0, false), (0, false), (0, false))
        }

        let chars = Array(code)

        func parseChar(_ char: Character) -> (duration: Int, isExplosive: Bool) {
            if char.uppercased() == "X" {
                return (0, true)
            } else if let duration = Int(String(char)) {
                return (duration, false)
            }
            return (0, false)
        }

        return (
            parseChar(chars[0]),
            parseChar(chars[1]),
            parseChar(chars[2]),
            parseChar(chars[3])
        )
    }

    // Helper to convert from string code to enum (best match)
    static func fromCode(_ code: String) -> Tempo? {
        return Tempo(rawValue: code)
    }
}

