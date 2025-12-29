//
// OneRMCalculationService.swift
// Medina
//
// v74.7: Centralized 1RM calculation with quality scoring
// Uses Epley formula (more accurate for 3-10 reps)
// Quality-weighted set selection based on rep accuracy + freshness
// Recency weighting for historical aggregation
// Created: December 2, 2025
//

import Foundation

// MARK: - Set Data Input

/// Input data for 1RM calculation from a single set
struct SetDataForRM {
    let weight: Double
    let reps: Int
    let setIndex: Int  // 0-based position in workout (earlier = fresher)

    init(weight: Double, reps: Int, setIndex: Int = 0) {
        self.weight = weight
        self.reps = reps
        self.setIndex = setIndex
    }
}

/// Input data for historical 1RM aggregation
struct SessionDataForRM {
    let date: Date
    let best1RM: Double
}

// MARK: - One RM Calculation Service

enum OneRMCalculationService {

    // MARK: - Single Set Calculation

    /// Calculate 1RM from a single set using Epley formula
    /// Formula: 1RM = weight × (1 + reps/30)
    ///
    /// Research shows Epley is most accurate for 3-10 reps.
    /// Brzycki formula 1RM = weight × (36 / (37 - reps)) produces
    /// nearly identical results at 10 reps but diverges at lower counts.
    ///
    /// - Parameters:
    ///   - weight: Weight lifted
    ///   - reps: Number of reps completed
    /// - Returns: Estimated 1RM, or nil if invalid input
    static func calculate(weight: Double, reps: Int) -> Double? {
        guard reps > 0 && reps < 37 && weight > 0 else { return nil }

        // Epley formula (preferred for 3-10 reps)
        return weight * (1.0 + Double(reps) / 30.0)
    }

    // MARK: - Quality-Weighted Multi-Set Selection

    /// Select best 1RM from multiple sets using quality scoring
    ///
    /// Quality factors:
    /// - Rep accuracy: 3-5 reps most accurate (1.0), degrades outside
    /// - Freshness: Earlier sets (less fatigue) are more reliable
    ///
    /// Returns weighted average favoring high-quality sets rather than
    /// just taking the maximum (which could be from a fatigued high-rep set).
    ///
    /// - Parameter sets: Array of set data with weights, reps, and set index
    /// - Returns: Quality-weighted 1RM estimate
    static func selectBest1RM(from sets: [SetDataForRM]) -> Double? {
        guard !sets.isEmpty else { return nil }

        let totalSets = sets.count

        let scored = sets.compactMap { set -> (rm: Double, score: Double)? in
            guard let rm = calculate(weight: set.weight, reps: set.reps) else { return nil }
            let score = qualityScore(reps: set.reps, setIndex: set.setIndex, totalSets: totalSets)
            return (rm, score)
        }

        guard !scored.isEmpty else { return nil }

        // Weighted average favoring high-quality sets
        let totalWeight = scored.reduce(0) { $0 + $1.score }
        guard totalWeight > 0 else { return scored.first?.rm }

        return scored.reduce(0) { $0 + $1.rm * $1.score } / totalWeight
    }

    /// Quality score: lower reps + earlier sets = higher quality
    ///
    /// Based on research:
    /// - 1RM formulas are most accurate at 3-5 reps
    /// - Sets 1-2 reps are risky (form may suffer)
    /// - 6-10 reps are good but less precise
    /// - 11+ reps have significant error margin
    /// - Earlier sets are fresher (less accumulated fatigue)
    private static func qualityScore(reps: Int, setIndex: Int, totalSets: Int) -> Double {
        // Rep accuracy score (3-5 reps most accurate)
        let repScore: Double
        switch reps {
        case 3...5:
            repScore = 1.0      // Optimal accuracy
        case 1...2:
            repScore = 0.8      // Too heavy, form may suffer
        case 6...8:
            repScore = 0.9      // Good accuracy
        case 9...10:
            repScore = 0.7      // Moderate accuracy
        case 11...15:
            repScore = 0.5      // Lower accuracy
        default:
            repScore = 0.3      // 16+ reps, poor accuracy
        }

        // Freshness score: first set = 1.0, last set = 0.6
        // This accounts for accumulated fatigue throughout workout
        let freshnessScore: Double
        if totalSets <= 1 {
            freshnessScore = 1.0
        } else {
            freshnessScore = 1.0 - (Double(setIndex) / Double(totalSets - 1)) * 0.4
        }

        return repScore * freshnessScore
    }

    // MARK: - Recency-Weighted Historical Aggregation

    /// Calculate recency-weighted 1RM from historical sessions
    ///
    /// Uses exponential decay with 14-day half-life.
    /// More recent sessions dominate the calculation because:
    /// - Older data contains accumulated noise
    /// - Strength levels change over time
    /// - Recent performance better reflects current capacity
    ///
    /// - Parameter sessions: Array of historical session data with dates and 1RMs
    /// - Returns: Recency-weighted 1RM estimate
    static func recencyWeighted1RM(from sessions: [SessionDataForRM]) -> Double? {
        guard !sessions.isEmpty else { return nil }

        let now = Date()
        let halfLifeDays: Double = 14.0  // 14-day half-life

        let scored = sessions.compactMap { session -> (rm: Double, weight: Double)? in
            // Calculate days ago
            let daysAgo = now.timeIntervalSince(session.date) / 86400.0

            // Exponential decay: weight halves every 14 days
            let recencyWeight = pow(0.5, daysAgo / halfLifeDays)

            return (session.best1RM, recencyWeight)
        }

        guard !scored.isEmpty else { return nil }

        // Weighted average
        let totalWeight = scored.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return scored.first?.rm }

        return scored.reduce(0) { $0 + $1.rm * $1.weight } / totalWeight
    }

    // MARK: - Convenience Methods

    /// Calculate best 1RM from ImportedSet array (convenience wrapper)
    static func calculateFromImportedSets(_ sets: [ImportedSet]) -> Double? {
        let setData = sets.enumerated().map { index, set in
            SetDataForRM(weight: set.weight, reps: set.reps, setIndex: index)
        }
        return selectBest1RM(from: setData)
    }

    /// Calculate best 1RM from ParsedSet array (for CSV import)
    static func calculateFromParsedSets(_ sets: [ParsedSet]) -> Double? {
        let setData = sets.enumerated().map { index, set in
            SetDataForRM(weight: set.weight, reps: set.reps, setIndex: index)
        }
        return selectBest1RM(from: setData)
    }
}
