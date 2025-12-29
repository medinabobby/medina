//
// ExerciseTarget.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

struct ExerciseTarget: Identifiable, Codable {
    let id: String
    let exerciseId: String
    let memberId: String
    var targetType: TargetType      // max or working
    var currentTarget: Double?      // Current 1RM or working weight
    var lastCalibrated: Date?       // When this was last verified
    var targetHistory: [TargetEntry]
    
    struct TargetEntry: Codable {
        let date: Date
        let target: Double
        let calibrationSource: String
    }
}

struct ExerciseTimeEstimate: Codable {
    let exerciseId: String
    let protocolId: String
    let estimatedMinutes: Int
    let reasoning: String?
}
