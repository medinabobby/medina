//
// WorkoutRepository.swift
// Medina
//
// v181: Repository pattern for persistence abstraction
// v206: Removed FileWorkoutRepository (Firestore is now source of truth)
//

import Foundation

// MARK: - Protocol

/// Repository protocol for Workout persistence
/// Implementations: MockWorkoutRepository (tests), FirestoreWorkoutRepository (production)
protocol WorkoutRepository {
    /// Save a workout (insert or update)
    func save(_ workout: Workout, userId: String) async throws

    /// Save multiple workouts at once (batch operation)
    func saveAll(_ workouts: [Workout], userId: String) async throws

    /// Load a workout by ID
    func load(id: String) async throws -> Workout?

    /// Load all workouts for a user
    func loadAll(for userId: String) async throws -> [Workout]

    /// Load workouts for a specific program
    func loadForProgram(programId: String, userId: String) async throws -> [Workout]

    /// Delete a workout by ID
    func delete(id: String, userId: String) async throws

    /// Delete all workouts for a program (cascade delete)
    func deleteForProgram(programId: String, userId: String) async throws

    /// Update workout status only (optimized for frequent status changes)
    func updateStatus(id: String, status: ExecutionStatus, userId: String) async throws

    /// Observe real-time changes to a workout (Firebase prep)
    func observe(id: String) -> AsyncStream<Workout?>
}

// MARK: - Mock Implementation (for tests)

/// In-memory mock repository for unit tests
final class MockWorkoutRepository: WorkoutRepository {

    var workouts: [String: Workout] = [:]
    var saveCallCount = 0
    var loadCallCount = 0
    var deleteCallCount = 0
    var shouldThrowOnSave = false
    var shouldThrowOnLoad = false

    func save(_ workout: Workout, userId: String) async throws {
        saveCallCount += 1
        if shouldThrowOnSave {
            throw RepositoryError.saveFailed("Mock save error")
        }
        workouts[workout.id] = workout
    }

    func saveAll(_ workoutsToSave: [Workout], userId: String) async throws {
        saveCallCount += 1
        if shouldThrowOnSave {
            throw RepositoryError.saveFailed("Mock save error")
        }
        for workout in workoutsToSave {
            workouts[workout.id] = workout
        }
    }

    func load(id: String) async throws -> Workout? {
        loadCallCount += 1
        if shouldThrowOnLoad {
            throw RepositoryError.loadFailed("Mock load error")
        }
        return workouts[id]
    }

    func loadAll(for userId: String) async throws -> [Workout] {
        loadCallCount += 1
        if shouldThrowOnLoad {
            throw RepositoryError.loadFailed("Mock load error")
        }
        return Array(workouts.values)
    }

    func loadForProgram(programId: String, userId: String) async throws -> [Workout] {
        loadCallCount += 1
        if shouldThrowOnLoad {
            throw RepositoryError.loadFailed("Mock load error")
        }
        return workouts.values.filter { $0.programId == programId }
    }

    func delete(id: String, userId: String) async throws {
        deleteCallCount += 1
        workouts.removeValue(forKey: id)
    }

    func deleteForProgram(programId: String, userId: String) async throws {
        deleteCallCount += 1
        let toRemove = workouts.values.filter { $0.programId == programId }.map { $0.id }
        for id in toRemove {
            workouts.removeValue(forKey: id)
        }
    }

    func updateStatus(id: String, status: ExecutionStatus, userId: String) async throws {
        guard var workout = workouts[id] else {
            throw RepositoryError.notFound("Workout \(id) not found")
        }
        workout.status = status
        workouts[id] = workout
    }

    func observe(id: String) -> AsyncStream<Workout?> {
        return AsyncStream { continuation in
            continuation.yield(workouts[id])
            continuation.finish()
        }
    }

    func reset() {
        workouts.removeAll()
        saveCallCount = 0
        loadCallCount = 0
        deleteCallCount = 0
        shouldThrowOnSave = false
        shouldThrowOnLoad = false
    }
}
