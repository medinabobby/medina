//
// ProtocolCustomization.swift
// Medina
//
// v82.4: AI Protocol Customization Model
// v83.5: Expanded ranges to support named protocols (GBC, etc.)
// Created: December 4, 2025
//
// Allows AI to make bounded modifications to base protocols:
// - Sets: ±2
// - Reps: ±10 per set (expanded for GBC: 5→12 requires +7)
// - Rest: ±60 seconds (GBC uses 30-60s vs standard 90s)
//

import Foundation

/// AI-specified modifications to a base protocol
/// Used when AI wants to customize a protocol for user preferences
struct ProtocolCustomization: Codable, Hashable {

    // MARK: - Properties

    /// Base protocol ID this customization modifies
    let baseProtocolId: String

    /// Sets adjustment (-2 to +2)
    /// Positive adds sets, negative removes sets
    var setsAdjustment: Int

    /// Reps adjustment per set (-3 to +3)
    /// Applied uniformly to all sets
    var repsAdjustment: Int

    /// Rest adjustment in seconds (-30 to +30)
    /// Applied between all sets
    var restAdjustment: Int

    /// Optional tempo override (must be from approved list)
    var tempoOverride: String?

    /// Optional RPE override (must be 6.0-10.0)
    var rpeOverride: Double?

    /// AI's rationale for this customization
    let rationale: String?

    // MARK: - Validation Bounds

    static let setsRange = -2...2
    static let repsRange = -10...10  // v83.5: Expanded for named protocols (GBC: 5→12 = +7)
    static let restRange = -60...60  // v83.5: Expanded for GBC (90→30 = -60)
    static let rpeRange: ClosedRange<Double> = 6.0...10.0

    /// Approved tempo patterns
    /// Format: eccentric-pause_bottom-concentric-pause_top (e.g., 3010 = 3s down, 0 pause, 1s up, 0 pause)
    static let approvedTempos = [
        "1010",  // Fast/standard
        "2010",  // Controlled eccentric
        "2011",  // Pause at bottom
        "2020",  // Balanced tempo
        "3010",  // Slow eccentric (GBC default)
        "3011",  // Slow eccentric + pause
        "4010",  // Very slow eccentric
        "4020",  // Tempo focus
        "4040"   // Time under tension
    ]

    // MARK: - Initialization

    init(
        baseProtocolId: String,
        setsAdjustment: Int = 0,
        repsAdjustment: Int = 0,
        restAdjustment: Int = 0,
        tempoOverride: String? = nil,
        rpeOverride: Double? = nil,
        rationale: String? = nil
    ) {
        self.baseProtocolId = baseProtocolId
        self.setsAdjustment = setsAdjustment.clamped(to: Self.setsRange)
        self.repsAdjustment = repsAdjustment.clamped(to: Self.repsRange)
        self.restAdjustment = restAdjustment.clamped(to: Self.restRange)
        self.tempoOverride = tempoOverride
        self.rpeOverride = rpeOverride
        self.rationale = rationale
    }

    // MARK: - Validation

    /// Check if customization values are within bounds
    func isValid() -> Bool {
        let setsValid = Self.setsRange.contains(setsAdjustment)
        let repsValid = Self.repsRange.contains(repsAdjustment)
        let restValid = Self.restRange.contains(restAdjustment)
        let tempoValid = tempoOverride == nil || Self.approvedTempos.contains(tempoOverride!)
        let rpeValid = rpeOverride == nil || Self.rpeRange.contains(rpeOverride!)

        return setsValid && repsValid && restValid && tempoValid && rpeValid
    }

    /// Returns validation errors if any
    func validationErrors() -> [String] {
        var errors: [String] = []

        if !Self.setsRange.contains(setsAdjustment) {
            errors.append("setsAdjustment \(setsAdjustment) out of range \(Self.setsRange)")
        }
        if !Self.repsRange.contains(repsAdjustment) {
            errors.append("repsAdjustment \(repsAdjustment) out of range \(Self.repsRange)")
        }
        if !Self.restRange.contains(restAdjustment) {
            errors.append("restAdjustment \(restAdjustment) out of range \(Self.restRange)")
        }
        if let tempo = tempoOverride, !Self.approvedTempos.contains(tempo) {
            errors.append("tempoOverride '\(tempo)' not in approved list")
        }
        if let rpe = rpeOverride, !Self.rpeRange.contains(rpe) {
            errors.append("rpeOverride \(rpe) out of range \(Self.rpeRange)")
        }

        return errors
    }

    // MARK: - Application

    /// Apply customization to a base protocol config
    /// Returns a new config with adjustments applied
    func apply(to base: ProtocolConfig) -> ProtocolConfig {
        var modified = base

        // Adjust reps (apply to each set)
        modified.reps = base.reps.map { rep in
            Swift.max(1, rep + repsAdjustment)  // Minimum 1 rep
        }

        // Adjust sets (add or remove from end)
        if setsAdjustment > 0 {
            // Add sets (duplicate last set's values)
            let lastRep = modified.reps.last ?? 10
            let lastRPE = base.rpe?.last ?? 8.0
            let lastRest = base.restBetweenSets.last ?? 90

            for _ in 0..<setsAdjustment {
                modified.reps.append(lastRep)
                if var rpe = modified.rpe {
                    rpe.append(lastRPE)
                    modified.rpe = rpe
                }
                modified.restBetweenSets.append(lastRest)
            }
        } else if setsAdjustment < 0 {
            // Remove sets (from end, keep at least 1)
            let removeCount = Swift.min(-setsAdjustment, modified.reps.count - 1)
            modified.reps = Array(modified.reps.dropLast(removeCount))
            if let rpe = modified.rpe {
                modified.rpe = Array(rpe.dropLast(removeCount))
            }
            modified.restBetweenSets = Array(modified.restBetweenSets.dropLast(removeCount))
        }

        // Adjust rest (apply to all rest periods)
        modified.restBetweenSets = modified.restBetweenSets.map { r in
            Swift.max(15, r + restAdjustment)  // Minimum 15 seconds
        }

        // Override tempo if specified
        if let tempo = tempoOverride {
            modified.tempo = tempo
        }

        // v83.4: Override RPE if specified
        if let rpe = rpeOverride {
            modified.rpe = Array(repeating: rpe, count: modified.reps.count)
        }

        return modified
    }
}

// MARK: - Clamped Extension

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
