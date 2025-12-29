//
// FirestoreTargetsRepository.swift
// Medina
//
// v195: Firestore-backed exercise targets for cloud-only architecture
// Targets stored at: users/{userId}/targets/{targetId}
//

import Foundation

/// Firestore-backed repository for ExerciseTarget (1RM data)
/// Enables cross-device strength baseline sync
actor FirestoreTargetsRepository {

    // MARK: - Configuration

    private let projectId = "medinaintelligence"
    private let baseURL: String

    private let session: URLSession

    // MARK: - Singleton

    static let shared = FirestoreTargetsRepository()

    // MARK: - Initialization

    init() {
        self.baseURL = "https://firestore.googleapis.com/v1/projects/medinaintelligence/databases/(default)/documents"

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Target Operations

    /// Save a single target to Firestore
    nonisolated func saveTarget(_ target: ExerciseTarget) async throws {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(target.memberId)/targets/\(target.id)"

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestoreTargetsError.invalidURL
        }

        let firestoreDoc = targetToFirestoreDocument(target)
        let body = try JSONEncoder().encode(firestoreDoc)

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirestoreTargetsError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.log(.error, component: "FirestoreTargets", message: "Save failed: \(httpResponse.statusCode) - \(errorBody)")
            throw FirestoreTargetsError.saveFailed(httpResponse.statusCode)
        }

        Logger.log(.debug, component: "FirestoreTargets", message: "Saved target \(target.id)")
    }

    /// Save multiple targets for a user
    nonisolated func saveTargets(_ targets: [ExerciseTarget], memberId: String) async throws {
        for target in targets {
            try await saveTarget(target)
        }
        Logger.log(.info, component: "FirestoreTargets", message: "Saved \(targets.count) targets for user \(memberId)")
    }

    /// Fetch all targets for a user
    nonisolated func fetchTargets(memberId: String) async throws -> [ExerciseTarget] {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(memberId)/targets"

        guard let url = URL(string: "\(baseURL)/\(path)?pageSize=200") else {
            throw FirestoreTargetsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirestoreTargetsError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 404 {
            return []  // No targets set yet
        }

        guard httpResponse.statusCode == 200 else {
            throw FirestoreTargetsError.fetchFailed
        }

        let listResponse = try JSONDecoder().decode(FirestoreListResponse.self, from: data)
        return (listResponse.documents ?? []).compactMap { doc in
            try? parseTargetDocument(doc)
        }
    }

    /// Fetch a specific target
    nonisolated func fetchTarget(targetId: String, memberId: String) async throws -> ExerciseTarget? {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(memberId)/targets/\(targetId)"

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestoreTargetsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirestoreTargetsError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 404 {
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            throw FirestoreTargetsError.fetchFailed
        }

        let doc = try JSONDecoder().decode(FirestoreDocument.self, from: data)
        return try parseTargetDocument(doc)
    }

    /// Delete a target
    nonisolated func deleteTarget(targetId: String, memberId: String) async throws {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(memberId)/targets/\(targetId)"

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestoreTargetsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw FirestoreTargetsError.deleteFailed
        }

        Logger.log(.info, component: "FirestoreTargets", message: "Deleted target \(targetId)")
    }

    // MARK: - Firestore Document Conversion

    private nonisolated func targetToFirestoreDocument(_ target: ExerciseTarget) -> FirestoreWriteDocument {
        let dateFormatter = ISO8601DateFormatter()

        var fields: [String: FirestoreWriteValue] = [
            "id": .init(stringValue: target.id),
            "exerciseId": .init(stringValue: target.exerciseId),
            "memberId": .init(stringValue: target.memberId),
            "targetType": .init(stringValue: target.targetType.rawValue)
        ]

        if let currentTarget = target.currentTarget {
            fields["currentTarget"] = .init(doubleValue: currentTarget)
        }

        if let lastCalibrated = target.lastCalibrated {
            fields["lastCalibrated"] = .init(timestampValue: dateFormatter.string(from: lastCalibrated))
        }

        // Target history as array of maps
        var historyArray: [FirestoreWriteValue] = []
        for entry in target.targetHistory {
            let entryMap = FirestoreWriteValue(mapValue: .init(fields: [
                "date": .init(timestampValue: dateFormatter.string(from: entry.date)),
                "target": .init(doubleValue: entry.target),
                "calibrationSource": .init(stringValue: entry.calibrationSource)
            ]))
            historyArray.append(entryMap)
        }
        fields["targetHistory"] = .init(arrayValue: .init(values: historyArray))

        return FirestoreWriteDocument(fields: fields)
    }

    private nonisolated func parseTargetDocument(_ doc: FirestoreDocument) throws -> ExerciseTarget {
        guard let fields = doc.fields else {
            throw FirestoreTargetsError.parseError("No fields in document")
        }

        let dateFormatter = ISO8601DateFormatter()

        let id = fields["id"]?.stringValue ?? doc.name?.components(separatedBy: "/").last ?? ""

        // Parse target history
        var targetHistory: [ExerciseTarget.TargetEntry] = []
        if let historyArray = fields["targetHistory"]?.arrayValue?.values {
            for entryValue in historyArray {
                if let mapFields = entryValue.mapValue?.fields,
                   let dateStr = mapFields["date"]?.timestampValue,
                   let date = dateFormatter.date(from: dateStr),
                   let target = mapFields["target"]?.doubleValue,
                   let source = mapFields["calibrationSource"]?.stringValue {
                    targetHistory.append(ExerciseTarget.TargetEntry(
                        date: date,
                        target: target,
                        calibrationSource: source
                    ))
                }
            }
        }

        return ExerciseTarget(
            id: id,
            exerciseId: fields["exerciseId"]?.stringValue ?? "",
            memberId: fields["memberId"]?.stringValue ?? "",
            targetType: TargetType(rawValue: fields["targetType"]?.stringValue ?? "") ?? .max,
            currentTarget: fields["currentTarget"]?.doubleValue,
            lastCalibrated: fields["lastCalibrated"]?.timestampValue.flatMap { dateFormatter.date(from: $0) },
            targetHistory: targetHistory
        )
    }
}

// MARK: - Firestore Write Types

private struct FirestoreWriteDocument: Encodable {
    let fields: [String: FirestoreWriteValue]
}

private struct FirestoreWriteValue: Encodable {
    var stringValue: String?
    var integerValue: String?
    var doubleValue: Double?
    var booleanValue: Bool?
    var timestampValue: String?
    var arrayValue: FirestoreWriteArrayValue?
    var mapValue: FirestoreWriteMapValue?

    init(stringValue: String) { self.stringValue = stringValue }
    init(integerValue: String) { self.integerValue = integerValue }
    init(doubleValue: Double) { self.doubleValue = doubleValue }
    init(booleanValue: Bool) { self.booleanValue = booleanValue }
    init(timestampValue: String) { self.timestampValue = timestampValue }
    init(arrayValue: FirestoreWriteArrayValue) { self.arrayValue = arrayValue }
    init(mapValue: FirestoreWriteMapValue) { self.mapValue = mapValue }
}

private struct FirestoreWriteArrayValue: Encodable {
    let values: [FirestoreWriteValue]
}

private struct FirestoreWriteMapValue: Encodable {
    let fields: [String: FirestoreWriteValue]
}

// MARK: - Firestore Read Types

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
    let timestampValue: String?
    let arrayValue: FirestoreArrayValue?
    let mapValue: FirestoreMapValue?
}

private struct FirestoreArrayValue: Decodable {
    let values: [FirestoreValue]?
}

private struct FirestoreMapValue: Decodable {
    let fields: [String: FirestoreValue]?
}

// MARK: - Errors

enum FirestoreTargetsError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case saveFailed(Int)
    case fetchFailed
    case deleteFailed
    case parseError(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Firestore URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .saveFailed(let code):
            return "Failed to save target (HTTP \(code))"
        case .fetchFailed:
            return "Failed to fetch targets"
        case .deleteFailed:
            return "Failed to delete target"
        case .parseError(let msg):
            return "Parse error: \(msg)"
        case .notAuthenticated:
            return "Not authenticated"
        }
    }
}
