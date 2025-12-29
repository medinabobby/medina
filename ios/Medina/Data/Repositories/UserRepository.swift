//
// UserRepository.swift
// Medina
//
// v181: Repository pattern for persistence abstraction
// v206: Removed FileUserRepository (Firestore is now source of truth)
//

import Foundation

// MARK: - Protocol

/// Repository protocol for User persistence
/// Implementations: MockUserRepository (tests), FirestoreUserRepository (production)
protocol UserRepository {
    /// Save a user profile
    func save(_ user: UnifiedUser) async throws

    /// Load a user by ID
    func load(id: String) async throws -> UnifiedUser?

    /// Observe real-time changes to a user profile (Firebase prep)
    func observe(id: String) -> AsyncStream<UnifiedUser?>
}

// MARK: - Mock Implementation (for tests)

/// In-memory mock repository for unit tests
final class MockUserRepository: UserRepository {

    var users: [String: UnifiedUser] = [:]
    var saveCallCount = 0
    var loadCallCount = 0
    var shouldThrowOnSave = false
    var shouldThrowOnLoad = false

    func save(_ user: UnifiedUser) async throws {
        saveCallCount += 1
        if shouldThrowOnSave {
            throw RepositoryError.saveFailed("Mock save error")
        }
        users[user.id] = user
    }

    func load(id: String) async throws -> UnifiedUser? {
        loadCallCount += 1
        if shouldThrowOnLoad {
            throw RepositoryError.loadFailed("Mock load error")
        }
        return users[id]
    }

    func observe(id: String) -> AsyncStream<UnifiedUser?> {
        return AsyncStream { continuation in
            continuation.yield(users[id])
            continuation.finish()
        }
    }

    func reset() {
        users.removeAll()
        saveCallCount = 0
        loadCallCount = 0
        shouldThrowOnSave = false
        shouldThrowOnLoad = false
    }
}
