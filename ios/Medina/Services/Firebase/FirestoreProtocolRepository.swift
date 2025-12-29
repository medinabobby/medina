//
// FirestoreProtocolRepository.swift
// Medina
//
// v196: Firestore-backed protocol repository using REST API
// Fetches protocol configs from Firestore, with local JSON fallback for seeding
//

import Foundation

/// Firestore-backed repository for training protocols
/// Uses Firebase Auth ID token for authentication
actor FirestoreProtocolRepository {

    // MARK: - Configuration

    private let projectId = "medinaintelligence"
    private let baseURL: String

    private let session: URLSession
    private let decoder: JSONDecoder

    // MARK: - Singleton

    static let shared = FirestoreProtocolRepository()

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

    // MARK: - Fetch All Protocols

    /// Fetch all protocol configs from Firestore
    nonisolated func fetchAll() async throws -> [String: ProtocolConfig] {
        let startTime = Date()

        // Get auth token
        let token = try await FirebaseAuthService.shared.getIDToken()

        // Build URL for listing all documents in protocols collection
        guard let url = URL(string: "\(baseURL)/protocols?pageSize=500") else {
            throw ProtocolRepositoryError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProtocolRepositoryError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ProtocolRepositoryError.notAuthenticated
            }
            throw ProtocolRepositoryError.networkError(URLError(.init(rawValue: httpResponse.statusCode)))
        }

        // Parse Firestore response
        let firestoreResponse = try JSONDecoder().decode(FirestoreListResponse.self, from: data)

        // Convert to ProtocolConfig dictionary
        var protocols: [String: ProtocolConfig] = [:]
        for document in firestoreResponse.documents ?? [] {
            if let protocol_ = try? parseProtocolDocument(document) {
                protocols[protocol_.id] = protocol_
            }
        }

        let latency = Date().timeIntervalSince(startTime) * 1000
        Logger.log(.info, component: "FirestoreProtocols", message: "Fetched \(protocols.count) protocols in \(Int(latency))ms")

        return protocols
    }

    // MARK: - Seed Protocols to Firestore

    /// Seed protocols from local JSON to Firestore
    /// Call this once when protocols collection is empty
    nonisolated func seedFromLocalJSON() async throws -> Int {
        // Load local JSON
        guard let url = Bundle.main.url(forResource: "protocol_configs", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            Logger.log(.warning, component: "FirestoreProtocols", message: "Local protocol_configs.json not found")
            return 0
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let protocols = try decoder.decode([String: ProtocolConfig].self, from: data)
        Logger.log(.info, component: "FirestoreProtocols", message: "Loaded \(protocols.count) protocols from local JSON")

        // Get auth token
        let token = try await FirebaseAuthService.shared.getIDToken()

        // Upload each protocol to Firestore
        var uploadedCount = 0
        for (id, protocolConfig) in protocols {
            do {
                try await uploadProtocol(protocolConfig, withId: id, token: token)
                uploadedCount += 1
            } catch {
                Logger.log(.error, component: "FirestoreProtocols", message: "Failed to upload protocol \(id): \(error)")
            }
        }

        Logger.log(.info, component: "FirestoreProtocols", message: "Seeded \(uploadedCount) protocols to Firestore")
        return uploadedCount
    }

    /// Upload a single protocol to Firestore
    private nonisolated func uploadProtocol(_ protocolConfig: ProtocolConfig, withId id: String, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/protocols?documentId=\(id)") else {
            throw ProtocolRepositoryError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Convert to Firestore document format using JSONSerialization
        let firestoreDoc = protocolToFirestoreDocument(protocolConfig)
        request.httpBody = try JSONSerialization.data(withJSONObject: firestoreDoc)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ProtocolRepositoryError.networkError(URLError(.badServerResponse))
        }
    }

    // MARK: - Firestore Document Conversion

    private nonisolated func protocolToFirestoreDocument(_ protocol_: ProtocolConfig) -> [String: Any] {
        var fields: [String: [String: Any]] = [:]

        fields["id"] = ["stringValue": protocol_.id]

        if let protocolFamily = protocol_.protocolFamily {
            fields["protocolFamily"] = ["stringValue": protocolFamily]
        }
        fields["variantName"] = ["stringValue": protocol_.variantName]

        // Arrays
        fields["reps"] = ["arrayValue": ["values": protocol_.reps.map { ["integerValue": String($0)] }]]
        fields["intensityAdjustments"] = ["arrayValue": ["values": protocol_.intensityAdjustments.map { ["doubleValue": $0] }]]
        fields["restBetweenSets"] = ["arrayValue": ["values": protocol_.restBetweenSets.map { ["integerValue": String($0)] }]]

        if let rpe = protocol_.rpe {
            fields["rpe"] = ["arrayValue": ["values": rpe.map { ["doubleValue": $0] }]]
        }

        if let tempo = protocol_.tempo {
            fields["tempo"] = ["stringValue": tempo]
        }

        // executionNotes is required
        fields["executionNotes"] = ["stringValue": protocol_.executionNotes]

        if let duration = protocol_.duration {
            fields["duration"] = ["integerValue": String(duration)]
        }
        if let methodology = protocol_.methodology {
            fields["methodology"] = ["stringValue": methodology]
        }
        if let loadingPattern = protocol_.loadingPattern {
            fields["loadingPattern"] = ["stringValue": loadingPattern.rawValue]
        }
        if let createdByMemberId = protocol_.createdByMemberId {
            fields["createdByMemberId"] = ["stringValue": createdByMemberId]
        }
        if let createdByTrainerId = protocol_.createdByTrainerId {
            fields["createdByTrainerId"] = ["stringValue": createdByTrainerId]
        }
        if let createdByGymId = protocol_.createdByGymId {
            fields["createdByGymId"] = ["stringValue": createdByGymId]
        }

        return ["fields": fields]
    }

    private nonisolated func parseProtocolDocument(_ document: FirestoreDocument) throws -> ProtocolConfig {
        guard let fields = document.fields else {
            throw ProtocolRepositoryError.decodingError
        }

        // Extract document ID from name path
        let id = document.name?.components(separatedBy: "/").last ?? fields["id"]?.stringValue ?? ""

        // Build JSON dictionary for decoder (using legacy keys for compatibility)
        var jsonDict: [String: Any] = [
            "id": id,
            "variantName": fields["variantName"]?.stringValue ?? "",
            "reps": (fields["reps"]?.arrayValue?.values ?? []).compactMap { Int($0.integerValue ?? "") },
            "intensityAdjustments": (fields["intensityAdjustments"]?.arrayValue?.values ?? []).compactMap { $0.doubleValue },
            "restBetweenSets": (fields["restBetweenSets"]?.arrayValue?.values ?? []).compactMap { Int($0.integerValue ?? "") }
        ]

        // Optional fields
        if let protocolFamily = fields["protocolFamily"]?.stringValue {
            jsonDict["protocolFamily"] = protocolFamily
        }
        if let tempo = fields["tempo"]?.stringValue {
            jsonDict["tempo"] = tempo
        }
        if let rpeValues = fields["rpe"]?.arrayValue?.values {
            jsonDict["rpe"] = rpeValues.compactMap { $0.doubleValue }
        }
        if let loadingPattern = fields["loadingPattern"]?.stringValue {
            jsonDict["loadingPattern"] = loadingPattern
        }
        if let duration = fields["duration"]?.integerValue {
            jsonDict["duration"] = Int(duration)
        }

        // executionNotes (or legacy defaultInstructions)
        if let executionNotes = fields["executionNotes"]?.stringValue {
            jsonDict["executionNotes"] = executionNotes
        } else if let defaultInstructions = fields["defaultInstructions"]?.stringValue {
            jsonDict["defaultInstructions"] = defaultInstructions
        } else {
            jsonDict["defaultInstructions"] = ""  // Required field
        }

        if let methodology = fields["methodology"]?.stringValue {
            jsonDict["methodology"] = methodology
        }
        if let createdByMemberId = fields["createdByMemberId"]?.stringValue {
            jsonDict["createdByMemberId"] = createdByMemberId
        }
        if let createdByTrainerId = fields["createdByTrainerId"]?.stringValue {
            jsonDict["createdByTrainerId"] = createdByTrainerId
        }
        if let createdByGymId = fields["createdByGymId"]?.stringValue {
            jsonDict["createdByGymId"] = createdByGymId
        }

        // Convert to Data and decode using standard decoder
        let jsonData = try JSONSerialization.data(withJSONObject: jsonDict)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProtocolConfig.self, from: jsonData)
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

// MARK: - Error Types

enum ProtocolRepositoryError: Error {
    case networkError(Error)
    case notAuthenticated
    case decodingError
}
