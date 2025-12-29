//
// ExerciseRepository.swift
// Medina
//
// v188.2: Repository pattern for Exercise data
// Exercises are global (not user-specific), fetched from Firestore
//

import Foundation

// MARK: - Protocol

/// Repository protocol for Exercise data access
/// Implementations: LocalExerciseRepository (bundled JSON), FirestoreExerciseRepository (cloud)
protocol ExerciseRepository {
    /// Fetch all exercises
    func fetchAll() async throws -> [String: Exercise]

    /// Fetch a single exercise by ID
    func fetch(byId id: String) async throws -> Exercise?

    /// Fetch multiple exercises by IDs
    func fetch(byIds ids: [String]) async throws -> [Exercise]
}

// MARK: - Local Implementation (Bundled JSON)

/// Local repository that loads from bundled exercises.json
/// Used as fallback when Firestore is unavailable
final class LocalExerciseRepository: ExerciseRepository {

    func fetchAll() async throws -> [String: Exercise] {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") else {
            throw ExerciseRepositoryError.fileNotFound("exercises.json")
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: Exercise].self, from: data)
    }

    func fetch(byId id: String) async throws -> Exercise? {
        let all = try await fetchAll()
        return all[id]
    }

    func fetch(byIds ids: [String]) async throws -> [Exercise] {
        let all = try await fetchAll()
        return ids.compactMap { all[$0] }
    }
}

// MARK: - Errors

enum ExerciseRepositoryError: LocalizedError {
    case fileNotFound(String)
    case networkError(Error)
    case decodingError(Error)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let name):
            return "Exercise data file not found: \(name)"
        case .networkError(let error):
            return "Network error loading exercises: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode exercises: \(error.localizedDescription)"
        case .notAuthenticated:
            return "Not authenticated. Please sign in to load exercises."
        }
    }
}
