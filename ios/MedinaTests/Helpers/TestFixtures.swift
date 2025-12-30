//
// TestFixtures.swift
// MedinaTests
//
// Test fixtures and helper functions for tool handler tests
// Created: December 4, 2025
//
// Provides:
// - Standard test user with complete profile
// - Helper functions for extracting data from tool outputs
// - Common test data generators
//

import Foundation
@testable import Medina

/// Test fixtures for tool handler tests
enum TestFixtures {

    // MARK: - Test User IDs (static for LocalDataStore registration)

    private static let testUserId = "test_handler_user"
    private static let beginnerUserId = "test_beginner_user"
    private static let advancedUserId = "test_advanced_user"

    // MARK: - Test Users

    /// Standard test user with complete profile (intermediate, 5 days/week, 60 min sessions)
    /// Automatically registered in LocalDataStore when accessed
    /// v89: Also sets up a library with common exercises and protocols
    static var testUser: UnifiedUser {
        let user = UnifiedUser(
            id: testUserId,
            firebaseUID: "test_firebase_uid",
            authProvider: .email,
            email: "test@medina.app",
            name: "Test User",
            birthdate: Calendar.current.date(byAdding: .year, value: -30, to: Date())!,
            gender: .male,
            roles: [.member],
            memberProfile: MemberProfile(
                fitnessGoal: .strength,
                experienceLevel: .intermediate,
                preferredWorkoutDays: [.monday, .tuesday, .wednesday, .thursday, .friday],
                preferredSessionDuration: 60,
                membershipStatus: .active,
                memberSince: Date()
            )
        )
        // Register in LocalDataStore so WorkoutCreationService can find it
        LocalDataStore.shared.users[user.id] = user

        // v89: Set up library with common exercises and protocols for tests
        setupTestLibrary(for: user.id)

        return user
    }

    /// v89: Set up a test library with common exercises and protocols
    /// This ensures tests work correctly with the new empty-by-default library system
    /// v100.1: Include ALL exercises to ensure adequate variety for all test scenarios
    private static func setupTestLibrary(for userId: String) {
        // Include ALL exercises to ensure variety for all test scenarios
        // (home/gym, upper/lower/push/pull splits, supersets, etc.)
        let exerciseIds = Array(LocalDataStore.shared.exercises.keys)

        // Get common protocol IDs
        let protocolIds = [
            "strength_3x5_moderate",
            "accessory_3x10_rpe8",
            "gbc_compound",
            "gbc_isolation"
        ]

        // Build library
        var library = UserLibrary(userId: userId)
        library.exercises = Set(exerciseIds)
        library.protocols = protocolIds.compactMap { protocolId in
            guard LocalDataStore.shared.protocolConfigs[protocolId] != nil else { return nil }
            return ProtocolLibraryEntry(
                protocolConfigId: protocolId,
                isEnabled: true,
                applicableTo: [.compound, .isolation],
                intensityRange: 0.0...1.0,
                preferredGoals: []
            )
        }
        library.lastModified = Date()

        LocalDataStore.shared.libraries[userId] = library
    }

    /// Beginner test user (for testing experience-appropriate protocols)
    /// Automatically registered in LocalDataStore when accessed
    static var beginnerUser: UnifiedUser {
        let user = UnifiedUser(
            id: beginnerUserId,
            firebaseUID: "test_firebase_beginner",
            authProvider: .email,
            email: "beginner@medina.app",
            name: "Beginner User",
            birthdate: Calendar.current.date(byAdding: .year, value: -25, to: Date())!,
            gender: .female,
            roles: [.member],
            memberProfile: MemberProfile(
                fitnessGoal: .generalFitness,
                experienceLevel: .beginner,
                preferredWorkoutDays: [.monday, .wednesday, .friday],
                preferredSessionDuration: 45,
                membershipStatus: .active,
                memberSince: Date()
            )
        )
        LocalDataStore.shared.users[user.id] = user
        setupTestLibrary(for: user.id)  // v89: Set up library
        return user
    }

    /// Advanced test user (for testing high-intensity protocols)
    /// Automatically registered in LocalDataStore when accessed
    static var advancedUser: UnifiedUser {
        let user = UnifiedUser(
            id: advancedUserId,
            firebaseUID: "test_firebase_advanced",
            authProvider: .email,
            email: "advanced@medina.app",
            name: "Advanced User",
            birthdate: Calendar.current.date(byAdding: .year, value: -28, to: Date())!,
            gender: .male,
            roles: [.member],
            memberProfile: MemberProfile(
                fitnessGoal: .muscleGain,
                experienceLevel: .advanced,
                preferredWorkoutDays: [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday],
                preferredSessionDuration: 90,
                membershipStatus: .active,
                memberSince: Date()
            )
        )
        LocalDataStore.shared.users[user.id] = user
        setupTestLibrary(for: user.id)  // v89: Set up library
        return user
    }

    /// v89: Create an empty library for a user (for testing empty library scenarios)
    static func setupEmptyLibrary(for userId: String) {
        var library = UserLibrary(userId: userId)
        library.exercises = []
        library.protocols = []
        library.lastModified = Date()
        LocalDataStore.shared.libraries[userId] = library
    }

    // MARK: - Output Parsing Helpers

    /// Extract workout ID from tool output
    /// - Parameter output: Tool output string containing "WORKOUT_ID: xyz"
    /// - Returns: Extracted workout ID or nil
    static func extractWorkoutId(from output: String) -> String? {
        let pattern = "WORKOUT_ID: ([a-zA-Z0-9_-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return String(output[range])
    }

    /// Extract plan ID from tool output
    /// - Parameter output: Tool output string containing "PLAN_ID: xyz"
    /// - Returns: Extracted plan ID or nil
    static func extractPlanId(from output: String) -> String? {
        let pattern = "PLAN_ID: ([a-zA-Z0-9_-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return String(output[range])
    }

    /// Check if output indicates success
    /// - Parameter output: Tool output string
    /// - Returns: True if output starts with "SUCCESS"
    static func isSuccess(_ output: String) -> Bool {
        return output.hasPrefix("SUCCESS")
    }

    /// Check if output indicates error
    /// - Parameter output: Tool output string
    /// - Returns: True if output starts with "ERROR"
    static func isError(_ output: String) -> Bool {
        return output.hasPrefix("ERROR")
    }

    // MARK: - Date Helpers

    /// Get tomorrow's date as ISO8601 string (YYYY-MM-DD)
    static var tomorrowDateString: String {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        return formatDateString(tomorrow)
    }

    /// Get a date N days from now as ISO8601 string
    /// - Parameter days: Number of days to add (can be negative)
    /// - Returns: ISO8601 date string (YYYY-MM-DD)
    static func dateString(daysFromNow days: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date())!
        return formatDateString(date)
    }

    /// Format date as ISO8601 string (YYYY-MM-DD)
    private static func formatDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return String(formatter.string(from: date).prefix(10))
    }
}
