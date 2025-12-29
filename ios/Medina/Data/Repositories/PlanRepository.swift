//
// PlanRepository.swift
// Medina
//
// v181: Repository pattern for persistence abstraction
// v206: Removed FilePlanRepository (Firestore is now source of truth)
//

import Foundation

// MARK: - Protocol

/// Repository protocol for Plan persistence
/// Implementations: MockPlanRepository (tests), FirestorePlanRepository (production)
protocol PlanRepository {
    /// Save a plan (insert or update)
    func save(_ plan: Plan) async throws

    /// Load a plan by ID
    func load(id: String) async throws -> Plan?

    /// Load all plans for a user
    func loadAll(for userId: String) async throws -> [Plan]

    /// Delete a plan by ID (does NOT cascade - caller handles that)
    func delete(id: String, userId: String) async throws

    /// Observe real-time changes to a plan (Firebase prep)
    func observe(id: String) -> AsyncStream<Plan?>
}

// MARK: - Mock Implementation (for tests)

/// In-memory mock repository for unit tests
final class MockPlanRepository: PlanRepository {

    var plans: [String: Plan] = [:]
    var saveCallCount = 0
    var loadCallCount = 0
    var deleteCallCount = 0
    var shouldThrowOnSave = false
    var shouldThrowOnLoad = false

    func save(_ plan: Plan) async throws {
        saveCallCount += 1
        if shouldThrowOnSave {
            throw RepositoryError.saveFailed("Mock save error")
        }
        plans[plan.id] = plan
    }

    func load(id: String) async throws -> Plan? {
        loadCallCount += 1
        if shouldThrowOnLoad {
            throw RepositoryError.loadFailed("Mock load error")
        }
        return plans[id]
    }

    func loadAll(for userId: String) async throws -> [Plan] {
        loadCallCount += 1
        if shouldThrowOnLoad {
            throw RepositoryError.loadFailed("Mock load error")
        }
        return plans.values.filter { $0.memberId == userId }
    }

    func delete(id: String, userId: String) async throws {
        deleteCallCount += 1
        plans.removeValue(forKey: id)
    }

    func observe(id: String) -> AsyncStream<Plan?> {
        return AsyncStream { continuation in
            continuation.yield(plans[id])
            continuation.finish()
        }
    }

    /// Reset mock state between tests
    func reset() {
        plans.removeAll()
        saveCallCount = 0
        loadCallCount = 0
        deleteCallCount = 0
        shouldThrowOnSave = false
        shouldThrowOnLoad = false
    }
}

// MARK: - Repository Errors

enum RepositoryError: Error, LocalizedError {
    case saveFailed(String)
    case loadFailed(String)
    case deleteFailed(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let msg): return "Save failed: \(msg)"
        case .loadFailed(let msg): return "Load failed: \(msg)"
        case .deleteFailed(let msg): return "Delete failed: \(msg)"
        case .notFound(let msg): return "Not found: \(msg)"
        }
    }
}
