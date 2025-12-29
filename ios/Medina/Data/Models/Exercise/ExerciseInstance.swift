//
// ExerciseInstance.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

struct ExerciseInstance: Identifiable, Codable {
    let id: String
    let exerciseId: String  // Now references unified Exercise model
    let workoutId: String
    var protocolVariantId: String  // v84.1: Made mutable for protocol changes
    var setIds: [String]
    // v21.0: Renamed completion → status, ExecutionStatus → ExecutionStatus
    var status: ExecutionStatus
    var trainerInstructions: String?

    // v50: Superset Support
    var supersetLabel: String?  // Display label like "1a", "1b", "2a", "2b"
}