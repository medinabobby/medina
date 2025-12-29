//
// SubstitutionCandidate.swift
// Medina
//
// v61.0 - Exercise Substitution Service
// Model for exercise alternatives with scoring
//

import Foundation

/// Represents a candidate exercise for substitution
/// Score indicates how similar the candidate is to the original exercise
struct SubstitutionCandidate: Identifiable {
    let id: String  // exercise.id
    let exercise: Exercise
    let score: Double           // 0.0 - 1.0 similarity
    let reasons: [String]       // Human-readable reasons for voice

    /// Score as a percentage (0-100)
    var scorePercentage: Int {
        Int(score * 100)
    }

    /// Display string for the match quality
    var matchQuality: String {
        switch scorePercentage {
        case 90...100: return "Excellent match"
        case 75..<90: return "Good match"
        case 60..<75: return "Moderate match"
        case 45..<60: return "Fair match"
        default: return "Possible alternative"
        }
    }
}
