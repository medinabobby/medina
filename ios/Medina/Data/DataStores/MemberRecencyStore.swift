//
//  MemberRecencyStore.swift
//  Medina
//
//  v191: Tracks member selection recency for trainers
//  Recently-selected members appear at top of sidebar list
//

import Foundation

/// Tracks member selection recency for trainers
/// v191: Recently-selected members appear at top of sidebar list
enum MemberRecencyStore {
    private static let keyPrefix = "medina.memberRecency."

    // MARK: - Public API

    /// Record member access (call when trainer selects a member)
    static func recordAccess(memberId: String, trainerId: String) {
        var timestamps = getTimestamps(trainerId: trainerId)
        timestamps[memberId] = Date().timeIntervalSince1970
        saveTimestamps(timestamps, trainerId: trainerId)
    }

    /// Get members sorted by recency (most recent first)
    /// Members without timestamps fall back to alphabetical order
    static func sortedByRecency(_ members: [UnifiedUser], trainerId: String) -> [UnifiedUser] {
        let timestamps = getTimestamps(trainerId: trainerId)

        return members.sorted { m1, m2 in
            let t1 = timestamps[m1.id] ?? 0
            let t2 = timestamps[m2.id] ?? 0

            // Most recent first
            if t1 != t2 {
                return t1 > t2
            }

            // Alphabetical fallback for members without timestamps
            return m1.name.lowercased() < m2.name.lowercased()
        }
    }

    /// Clear all recency data for a trainer (for testing/reset)
    static func clearRecency(trainerId: String) {
        let key = keyPrefix + trainerId
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Private Helpers

    private static func getTimestamps(trainerId: String) -> [String: Double] {
        let key = keyPrefix + trainerId
        return UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    private static func saveTimestamps(_ timestamps: [String: Double], trainerId: String) {
        let key = keyPrefix + trainerId
        UserDefaults.standard.set(timestamps, forKey: key)
    }
}
