//
// FirestoreExercisePreferencesRepository.swift
// Medina
//
// v195: Firestore-backed exercise preferences for cloud-only architecture
// Preferences stored at: users/{userId}/preferences/exercise
//

import Foundation

/// Firestore-backed repository for UserExercisePreferences
/// Stores favorites, excluded exercises, recent usage, and learned rules
actor FirestoreExercisePreferencesRepository {

    // MARK: - Configuration

    private let projectId = "medinaintelligence"
    private let baseURL: String

    private let session: URLSession

    // MARK: - Singleton

    static let shared = FirestoreExercisePreferencesRepository()

    // MARK: - Initialization

    init() {
        self.baseURL = "https://firestore.googleapis.com/v1/projects/medinaintelligence/databases/(default)/documents"

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Preferences Operations

    /// Save exercise preferences to Firestore
    nonisolated func savePreferences(_ prefs: UserExercisePreferences) async throws {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(prefs.id)/preferences/exercise"

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestorePreferencesError.invalidURL
        }

        let firestoreDoc = preferencesToFirestoreDocument(prefs)
        let body = try JSONEncoder().encode(firestoreDoc)

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirestorePreferencesError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.log(.error, component: "FirestorePrefs", message: "Save failed: \(httpResponse.statusCode) - \(errorBody)")
            throw FirestorePreferencesError.saveFailed(httpResponse.statusCode)
        }

        Logger.log(.debug, component: "FirestorePrefs", message: "Saved preferences for user \(prefs.id)")
    }

    /// Fetch exercise preferences from Firestore
    nonisolated func fetchPreferences(userId: String) async throws -> UserExercisePreferences? {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(userId)/preferences/exercise"

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestorePreferencesError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirestorePreferencesError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 404 {
            return nil  // No preferences set yet
        }

        guard httpResponse.statusCode == 200 else {
            throw FirestorePreferencesError.fetchFailed
        }

        let doc = try JSONDecoder().decode(FirestoreDocument.self, from: data)
        return try parsePreferencesDocument(doc, userId: userId)
    }

    /// Delete exercise preferences from Firestore
    nonisolated func deletePreferences(userId: String) async throws {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(userId)/preferences/exercise"

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestorePreferencesError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw FirestorePreferencesError.deleteFailed
        }

        Logger.log(.info, component: "FirestorePrefs", message: "Deleted preferences for user \(userId)")
    }

    // MARK: - Firestore Document Conversion

    private nonisolated func preferencesToFirestoreDocument(_ prefs: UserExercisePreferences) -> FirestoreWriteDocument {
        let dateFormatter = ISO8601DateFormatter()

        var fields: [String: FirestoreWriteValue] = [
            "userId": .init(stringValue: prefs.id),
            "lastModified": .init(timestampValue: dateFormatter.string(from: prefs.lastModified))
        ]

        // Favorites array
        let favoritesArray = prefs.favorites.map { FirestoreWriteValue(stringValue: $0) }
        fields["favorites"] = .init(arrayValue: .init(values: favoritesArray))

        // Excluded array
        let excludedArray = prefs.excluded.map { FirestoreWriteValue(stringValue: $0) }
        fields["excluded"] = .init(arrayValue: .init(values: excludedArray))

        // Recent exercises as array of maps
        var recentArray: [FirestoreWriteValue] = []
        for recent in prefs.recentExercises {
            let recentMap = FirestoreWriteValue(mapValue: .init(fields: [
                "exerciseId": .init(stringValue: recent.exerciseId),
                "lastUsed": .init(timestampValue: dateFormatter.string(from: recent.lastUsed)),
                "completionRate": .init(doubleValue: recent.completionRate)
            ]))
            recentArray.append(recentMap)
        }
        fields["recentExercises"] = .init(arrayValue: .init(values: recentArray))

        // Learned rules as array of maps
        var rulesArray: [FirestoreWriteValue] = []
        for rule in prefs.learnedRules {
            var ruleFields: [String: FirestoreWriteValue] = [
                "exerciseId": .init(stringValue: rule.exerciseId),
                "action": .init(stringValue: rule.action.rawValue),
                "source": .init(stringValue: rule.source),
                "createdAt": .init(timestampValue: dateFormatter.string(from: rule.createdAt))
            ]
            if let splitDay = rule.splitDay {
                ruleFields["splitDay"] = .init(stringValue: splitDay.rawValue)
            }
            rulesArray.append(FirestoreWriteValue(mapValue: .init(fields: ruleFields)))
        }
        fields["learnedRules"] = .init(arrayValue: .init(values: rulesArray))

        return FirestoreWriteDocument(fields: fields)
    }

    private nonisolated func parsePreferencesDocument(_ doc: FirestoreDocument, userId: String) throws -> UserExercisePreferences {
        guard let fields = doc.fields else {
            throw FirestorePreferencesError.parseError("No fields in document")
        }

        let dateFormatter = ISO8601DateFormatter()

        // Parse favorites
        let favorites: Set<String> = Set(
            (fields["favorites"]?.arrayValue?.values ?? []).compactMap { $0.stringValue }
        )

        // Parse excluded
        let excluded: Set<String> = Set(
            (fields["excluded"]?.arrayValue?.values ?? []).compactMap { $0.stringValue }
        )

        // Parse recent exercises
        var recentExercises: [RecentExercise] = []
        if let recentArray = fields["recentExercises"]?.arrayValue?.values {
            for recentValue in recentArray {
                if let mapFields = recentValue.mapValue?.fields,
                   let exerciseId = mapFields["exerciseId"]?.stringValue,
                   let lastUsedStr = mapFields["lastUsed"]?.timestampValue,
                   let lastUsed = dateFormatter.date(from: lastUsedStr),
                   let completionRate = mapFields["completionRate"]?.doubleValue {
                    recentExercises.append(RecentExercise(
                        exerciseId: exerciseId,
                        lastUsed: lastUsed,
                        completionRate: completionRate
                    ))
                }
            }
        }

        // Parse learned rules
        var learnedRules: [LearnedRule] = []
        if let rulesArray = fields["learnedRules"]?.arrayValue?.values {
            for ruleValue in rulesArray {
                if let mapFields = ruleValue.mapValue?.fields,
                   let exerciseId = mapFields["exerciseId"]?.stringValue,
                   let actionStr = mapFields["action"]?.stringValue,
                   let action = RuleAction(rawValue: actionStr),
                   let source = mapFields["source"]?.stringValue,
                   let createdAtStr = mapFields["createdAt"]?.timestampValue,
                   let createdAt = dateFormatter.date(from: createdAtStr) {
                    let splitDay = mapFields["splitDay"]?.stringValue.flatMap { SplitDay(rawValue: $0) }
                    learnedRules.append(LearnedRule(
                        exerciseId: exerciseId,
                        splitDay: splitDay,
                        action: action,
                        source: source,
                        createdAt: createdAt
                    ))
                }
            }
        }

        // Parse lastModified
        let lastModified = fields["lastModified"]?.timestampValue.flatMap {
            dateFormatter.date(from: $0)
        } ?? Date()

        var prefs = UserExercisePreferences(userId: userId)
        prefs.favorites = favorites
        prefs.excluded = excluded
        prefs.recentExercises = recentExercises
        prefs.learnedRules = learnedRules
        prefs.lastModified = lastModified

        return prefs
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

enum FirestorePreferencesError: LocalizedError {
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
            return "Failed to save preferences (HTTP \(code))"
        case .fetchFailed:
            return "Failed to fetch preferences"
        case .deleteFailed:
            return "Failed to delete preferences"
        case .parseError(let msg):
            return "Parse error: \(msg)"
        case .notAuthenticated:
            return "Not authenticated"
        }
    }
}
