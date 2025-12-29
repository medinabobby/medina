//
// UserLibrary.swift
// Medina
//
// v51.0 - Exercise & Protocol Library (Phase 1a)
// v54.x - Simplified exercises to Set<String> (removed ExerciseLibraryEntry)
// Created: November 5, 2025
//
// Purpose: User-scoped library containing curated exercises and protocols
// Trainer owns library, clients inherit with exclusions
//

import Foundation

struct UserLibrary: Codable, Identifiable {
    var id: String  // userId
    var exercises: Set<String>  // Exercise IDs
    var protocols: [ProtocolLibraryEntry]
    var lastModified: Date

    init(userId: String) {
        self.id = userId
        self.exercises = []
        self.protocols = []
        self.lastModified = Date()
    }

    /// Get protocols filtered by enabled status
    func enabledProtocols() -> [ProtocolLibraryEntry] {
        protocols.filter { $0.isEnabled }
    }
}
