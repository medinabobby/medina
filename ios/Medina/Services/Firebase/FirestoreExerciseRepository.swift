//
// FirestoreExerciseRepository.swift
// Medina
//
// v188.2: Firestore-backed exercise repository using REST API
// Uses Firebase Auth token for authentication
//

import Foundation

/// Firestore-backed ExerciseRepository using REST API
/// Uses Firebase Auth ID token for authentication
actor FirestoreExerciseRepository: ExerciseRepository {

    // MARK: - Configuration

    private let projectId = "medinaintelligence"
    private let baseURL: String

    private let session: URLSession
    private let decoder: JSONDecoder

    // MARK: - Singleton

    static let shared = FirestoreExerciseRepository()

    // MARK: - Initialization

    init() {
        self.baseURL = "https://firestore.googleapis.com/v1/projects/medinaintelligence/databases/(default)/documents"

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - ExerciseRepository Implementation

    nonisolated func fetchAll() async throws -> [String: Exercise] {
        let startTime = Date()

        // Get auth token
        let token = try await FirebaseAuthService.shared.getIDToken()

        // Build URL for listing all documents in exercises collection
        // pageSize=500 should cover all exercises (we have ~200)
        guard let url = URL(string: "\(baseURL)/exercises?pageSize=500") else {
            throw ExerciseRepositoryError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExerciseRepositoryError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ExerciseRepositoryError.notAuthenticated
            }
            throw ExerciseRepositoryError.networkError(URLError(.init(rawValue: httpResponse.statusCode)))
        }

        // Parse Firestore response
        let firestoreResponse = try JSONDecoder().decode(FirestoreListResponse.self, from: data)

        // Convert to Exercise dictionary
        var exercises: [String: Exercise] = [:]
        for document in firestoreResponse.documents ?? [] {
            if let exercise = try? parseExerciseDocument(document) {
                exercises[exercise.id] = exercise
            }
        }

        let latency = Date().timeIntervalSince(startTime) * 1000
        Logger.log(.info, component: "FirestoreExercises", message: "Fetched \(exercises.count) exercises in \(Int(latency))ms")

        return exercises
    }

    nonisolated func fetch(byId id: String) async throws -> Exercise? {
        let token = try await FirebaseAuthService.shared.getIDToken()

        guard let url = URL(string: "\(baseURL)/exercises/\(id)") else {
            throw ExerciseRepositoryError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExerciseRepositoryError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 404 {
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            throw ExerciseRepositoryError.networkError(URLError(.init(rawValue: httpResponse.statusCode)))
        }

        let document = try JSONDecoder().decode(FirestoreDocument.self, from: data)
        return try parseExerciseDocument(document)
    }

    nonisolated func fetch(byIds ids: [String]) async throws -> [Exercise] {
        // For small sets, fetch individually
        // For larger sets, use the batch get API
        if ids.count <= 10 {
            var exercises: [Exercise] = []
            for id in ids {
                if let exercise = try await fetch(byId: id) {
                    exercises.append(exercise)
                }
            }
            return exercises
        }

        // Use batch get for larger sets
        let token = try await FirebaseAuthService.shared.getIDToken()

        guard let url = URL(string: "\(baseURL):batchGet") else {
            throw ExerciseRepositoryError.networkError(URLError(.badURL))
        }

        let documentPaths = ids.map { "projects/\(projectId)/databases/(default)/documents/exercises/\($0)" }
        let body = try JSONEncoder().encode(["documents": documentPaths])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ExerciseRepositoryError.networkError(URLError(.badServerResponse))
        }

        let batchResponse = try JSONDecoder().decode([FirestoreBatchGetResult].self, from: data)
        return batchResponse.compactMap { result in
            guard let document = result.found else { return nil }
            return try? parseExerciseDocument(document)
        }
    }

    // MARK: - Firestore Document Parsing

    private nonisolated func parseExerciseDocument(_ document: FirestoreDocument) throws -> Exercise {
        guard let fields = document.fields else {
            throw ExerciseRepositoryError.decodingError(DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "No fields in document")
            ))
        }

        // Extract document ID from name path
        let id = document.name?.components(separatedBy: "/").last ?? fields["id"]?.stringValue ?? ""

        return Exercise(
            id: id,
            name: fields["name"]?.stringValue ?? "",
            baseExercise: fields["baseExercise"]?.stringValue ?? "",
            equipment: Equipment(rawValue: fields["equipment"]?.stringValue ?? "") ?? .bodyweight,
            type: ExerciseType(rawValue: fields["type"]?.stringValue ?? "") ?? .compound,
            muscleGroups: (fields["muscleGroups"]?.arrayValue?.values ?? []).compactMap {
                MuscleGroup(rawValue: $0.stringValue ?? "")
            },
            movementPattern: MovementPattern(rawValue: fields["movementPattern"]?.stringValue ?? ""),
            description: fields["description"]?.stringValue ?? "",
            instructions: fields["instructions"]?.stringValue ?? "",
            videoLink: fields["videoLink"]?.stringValue,
            experienceLevel: ExperienceLevel(rawValue: fields["experienceLevel"]?.stringValue ?? "") ?? .intermediate,
            createdByMemberId: fields["createdByMemberId"]?.stringValue,
            createdByTrainerId: fields["createdByTrainerId"]?.stringValue,
            createdByGymId: fields["createdByGymId"]?.stringValue
        )
    }
}

// MARK: - Firestore Response Types

private struct FirestoreListResponse: Decodable {
    let documents: [FirestoreDocument]?
    let nextPageToken: String?
}

private struct FirestoreDocument: Decodable {
    let name: String?
    let fields: [String: FirestoreValue]?
    let createTime: String?
    let updateTime: String?
}

private struct FirestoreValue: Decodable {
    let stringValue: String?
    let integerValue: String?
    let doubleValue: Double?
    let booleanValue: Bool?
    let nullValue: String?
    let arrayValue: FirestoreArrayValue?
    let mapValue: FirestoreMapValue?
}

private struct FirestoreArrayValue: Decodable {
    let values: [FirestoreValue]?
}

private struct FirestoreMapValue: Decodable {
    let fields: [String: FirestoreValue]?
}

private struct FirestoreBatchGetResult: Decodable {
    let found: FirestoreDocument?
    let missing: String?
    let readTime: String?
}
