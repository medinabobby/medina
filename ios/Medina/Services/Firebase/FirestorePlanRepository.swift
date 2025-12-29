//
// FirestorePlanRepository.swift
// Medina
//
// v188.3: Firestore-backed plan repository for trainer-member sync
// Plans stored at: users/{memberId}/plans/{planId}
// Programs stored at: users/{memberId}/plans/{planId}/programs/{programId}
//

import Foundation

/// Firestore-backed repository for Plans and Programs
/// Enables trainer-member sync across devices
actor FirestorePlanRepository {

    // MARK: - Configuration

    private let projectId = "medinaintelligence"
    private let baseURL: String

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - Singleton

    static let shared = FirestorePlanRepository()

    // MARK: - Initialization

    init() {
        self.baseURL = "https://firestore.googleapis.com/v1/projects/medinaintelligence/databases/(default)/documents"

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Plan Operations

    /// Save a plan to Firestore (create or update)
    nonisolated func savePlan(_ plan: Plan) async throws {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(plan.memberId)/plans/\(plan.id)"

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestorePlanError.invalidURL
        }

        let firestoreDoc = planToFirestoreDocument(plan)
        let body = try JSONEncoder().encode(firestoreDoc)

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"  // PATCH creates or updates
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirestorePlanError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.log(.error, component: "FirestorePlans", message: "Save failed: \(httpResponse.statusCode) - \(errorBody)")
            throw FirestorePlanError.saveFailed(httpResponse.statusCode)
        }

        Logger.log(.info, component: "FirestorePlans", message: "Saved plan \(plan.id) for member \(plan.memberId)")
    }

    /// Save a program to Firestore
    nonisolated func saveProgram(_ program: Program, memberId: String) async throws {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(memberId)/plans/\(program.planId)/programs/\(program.id)"

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestorePlanError.invalidURL
        }

        let firestoreDoc = programToFirestoreDocument(program)
        let body = try JSONEncoder().encode(firestoreDoc)

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw FirestorePlanError.saveFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        Logger.log(.debug, component: "FirestorePlans", message: "Saved program \(program.id)")
    }

    /// Fetch all plans for a member
    nonisolated func fetchPlans(forMember memberId: String) async throws -> [Plan] {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(memberId)/plans"

        guard let url = URL(string: "\(baseURL)/\(path)?pageSize=100") else {
            throw FirestorePlanError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                return []  // No plans yet
            }
            throw FirestorePlanError.fetchFailed
        }

        let listResponse = try JSONDecoder().decode(FirestoreListResponse.self, from: data)
        return (listResponse.documents ?? []).compactMap { doc in
            try? parsePlanDocument(doc)
        }
    }

    /// v211: Fetch a single plan by ID (for server-created plan sync)
    nonisolated func fetchPlan(id: String, memberId: String) async throws -> Plan? {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(memberId)/plans/\(id)"

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestorePlanError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirestorePlanError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 404 {
            return nil  // Plan doesn't exist
        }

        guard httpResponse.statusCode == 200 else {
            throw FirestorePlanError.fetchFailed
        }

        let doc = try JSONDecoder().decode(FirestoreDocument.self, from: data)
        return try parsePlanDocument(doc)
    }

    /// Fetch all plans for a trainer (across all assigned members)
    /// Uses Firestore collectionGroup query
    nonisolated func fetchPlansForTrainer(trainerId: String) async throws -> [Plan] {
        let token = try await FirebaseAuthService.shared.getIDToken()

        // Use structured query for collectionGroup
        guard let url = URL(string: "\(baseURL):runQuery") else {
            throw FirestorePlanError.invalidURL
        }

        // Query: SELECT * FROM plans WHERE trainerId == trainerId
        let query: [String: Any] = [
            "structuredQuery": [
                "from": [
                    ["collectionId": "plans", "allDescendants": true]
                ],
                "where": [
                    "fieldFilter": [
                        "field": ["fieldPath": "trainerId"],
                        "op": "EQUAL",
                        "value": ["stringValue": trainerId]
                    ]
                ]
            ]
        ]

        let body = try JSONSerialization.data(withJSONObject: query)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw FirestorePlanError.fetchFailed
        }

        // Parse query results
        let results = try JSONDecoder().decode([FirestoreQueryResult].self, from: data)
        return results.compactMap { result in
            guard let doc = result.document else { return nil }
            return try? parsePlanDocument(doc)
        }
    }

    /// Fetch programs for a plan
    nonisolated func fetchPrograms(forPlan planId: String, memberId: String) async throws -> [Program] {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(memberId)/plans/\(planId)/programs"

        guard let url = URL(string: "\(baseURL)/\(path)?pageSize=50") else {
            throw FirestorePlanError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return []
        }

        let listResponse = try JSONDecoder().decode(FirestoreListResponse.self, from: data)
        return (listResponse.documents ?? []).compactMap { doc in
            try? parseProgramDocument(doc)
        }
    }

    /// Delete a plan and its programs
    nonisolated func deletePlan(_ planId: String, memberId: String) async throws {
        let token = try await FirebaseAuthService.shared.getIDToken()

        // First delete programs
        let programs = try await fetchPrograms(forPlan: planId, memberId: memberId)
        for program in programs {
            let programPath = "users/\(memberId)/plans/\(planId)/programs/\(program.id)"
            try await deleteDocument(path: programPath, token: token)
        }

        // Then delete the plan
        let planPath = "users/\(memberId)/plans/\(planId)"
        try await deleteDocument(path: planPath, token: token)

        Logger.log(.info, component: "FirestorePlans", message: "Deleted plan \(planId)")
    }

    private nonisolated func deleteDocument(path: String, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestorePlanError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw FirestorePlanError.deleteFailed
        }
    }

    // MARK: - Firestore Document Conversion

    private nonisolated func planToFirestoreDocument(_ plan: Plan) -> FirestoreWriteDocument {
        var fields: [String: FirestoreWriteValue] = [
            "id": .init(stringValue: plan.id),
            "memberId": .init(stringValue: plan.memberId),
            "isSingleWorkout": .init(booleanValue: plan.isSingleWorkout),
            "status": .init(stringValue: plan.status.rawValue),
            "name": .init(stringValue: plan.name),
            "description": .init(stringValue: plan.description),
            "goal": .init(stringValue: plan.goal.rawValue),
            "weightliftingDays": .init(integerValue: String(plan.weightliftingDays)),
            "cardioDays": .init(integerValue: String(plan.cardioDays)),
            "splitType": .init(stringValue: plan.splitType.rawValue),
            "targetSessionDuration": .init(integerValue: String(plan.targetSessionDuration)),
            "trainingLocation": .init(stringValue: plan.trainingLocation.rawValue),
            "compoundTimeAllocation": .init(doubleValue: plan.compoundTimeAllocation),
            "isolationApproach": .init(stringValue: plan.isolationApproach.rawValue),
            "startDate": .init(timestampValue: ISO8601DateFormatter().string(from: plan.startDate)),
            "endDate": .init(timestampValue: ISO8601DateFormatter().string(from: plan.endDate)),
            // v210: Add timestamps for web sync compatibility
            "createdAt": .init(timestampValue: ISO8601DateFormatter().string(from: Date())),
            "updatedAt": .init(timestampValue: ISO8601DateFormatter().string(from: Date()))
        ]

        // Optional fields
        if let trainerId = plan.trainerId {
            fields["trainerId"] = .init(stringValue: trainerId)
        }
        if let createdBy = plan.createdBy {
            fields["createdBy"] = .init(stringValue: createdBy)
        }
        if let experienceLevel = plan.experienceLevel {
            fields["experienceLevel"] = .init(stringValue: experienceLevel.rawValue)
        }
        if let reasoning = plan.splitRecommendationReasoning {
            fields["splitRecommendationReasoning"] = .init(stringValue: reasoning)
        }

        // Arrays
        let preferredDaysArray = plan.preferredDays.map { FirestoreWriteValue(stringValue: $0.rawValue) }
        fields["preferredDays"] = .init(arrayValue: .init(values: preferredDaysArray))

        if let emphasized = plan.emphasizedMuscleGroups {
            let emphArray = emphasized.map { FirestoreWriteValue(stringValue: $0.rawValue) }
            fields["emphasizedMuscleGroups"] = .init(arrayValue: .init(values: emphArray))
        }

        if let excluded = plan.excludedMuscleGroups {
            let exclArray = excluded.map { FirestoreWriteValue(stringValue: $0.rawValue) }
            fields["excludedMuscleGroups"] = .init(arrayValue: .init(values: exclArray))
        }

        if let equipment = plan.availableEquipment {
            let equipArray = equipment.map { FirestoreWriteValue(stringValue: $0.rawValue) }
            fields["availableEquipment"] = .init(arrayValue: .init(values: equipArray))
        }

        return FirestoreWriteDocument(fields: fields)
    }

    private nonisolated func programToFirestoreDocument(_ program: Program) -> FirestoreWriteDocument {
        let fields: [String: FirestoreWriteValue] = [
            "id": .init(stringValue: program.id),
            "planId": .init(stringValue: program.planId),
            "name": .init(stringValue: program.name),
            "focus": .init(stringValue: program.focus.rawValue),
            "rationale": .init(stringValue: program.rationale),
            "startDate": .init(timestampValue: ISO8601DateFormatter().string(from: program.startDate)),
            "endDate": .init(timestampValue: ISO8601DateFormatter().string(from: program.endDate)),
            "startingIntensity": .init(doubleValue: program.startingIntensity),
            "endingIntensity": .init(doubleValue: program.endingIntensity),
            "progressionType": .init(stringValue: program.progressionType.rawValue),
            "status": .init(stringValue: program.status.rawValue)
        ]

        return FirestoreWriteDocument(fields: fields)
    }

    private nonisolated func parsePlanDocument(_ doc: FirestoreDocument) throws -> Plan {
        guard let fields = doc.fields else {
            throw FirestorePlanError.parseError("No fields in document")
        }

        let id = fields["id"]?.stringValue ?? doc.name?.components(separatedBy: "/").last ?? ""
        let memberId = fields["memberId"]?.stringValue ?? ""

        // Parse dates
        let dateFormatter = ISO8601DateFormatter()
        let startDate = fields["startDate"]?.timestampValue.flatMap { dateFormatter.date(from: $0) } ?? Date()
        let endDate = fields["endDate"]?.timestampValue.flatMap { dateFormatter.date(from: $0) } ?? Date()

        // Parse arrays
        let preferredDays: Set<DayOfWeek> = Set(
            (fields["preferredDays"]?.arrayValue?.values ?? []).compactMap {
                DayOfWeek(rawValue: $0.stringValue ?? "")
            }
        )

        let emphasizedMuscles: Set<MuscleGroup>? = fields["emphasizedMuscleGroups"]?.arrayValue?.values.map {
            Set($0.compactMap { MuscleGroup(rawValue: $0.stringValue ?? "") })
        }.flatMap { $0.isEmpty ? nil : $0 }

        let excludedMuscles: Set<MuscleGroup>? = fields["excludedMuscleGroups"]?.arrayValue?.values.map {
            Set($0.compactMap { MuscleGroup(rawValue: $0.stringValue ?? "") })
        }.flatMap { $0.isEmpty ? nil : $0 }

        let availableEquipment: Set<Equipment>? = fields["availableEquipment"]?.arrayValue?.values.map {
            Set($0.compactMap { Equipment(rawValue: $0.stringValue ?? "") })
        }.flatMap { $0.isEmpty ? nil : $0 }

        return Plan(
            id: id,
            memberId: memberId,
            trainerId: fields["trainerId"]?.stringValue,
            createdBy: fields["createdBy"]?.stringValue,
            isSingleWorkout: fields["isSingleWorkout"]?.booleanValue ?? false,
            status: PlanStatus(rawValue: fields["status"]?.stringValue ?? "") ?? .draft,
            name: fields["name"]?.stringValue ?? "",
            description: fields["description"]?.stringValue ?? "",
            goal: FitnessGoal(rawValue: fields["goal"]?.stringValue ?? "") ?? .strength,
            weightliftingDays: Int(fields["weightliftingDays"]?.integerValue ?? "0") ?? 0,
            cardioDays: Int(fields["cardioDays"]?.integerValue ?? "0") ?? 0,
            splitType: SplitType(rawValue: fields["splitType"]?.stringValue ?? "") ?? .fullBody,
            splitRecommendationReasoning: fields["splitRecommendationReasoning"]?.stringValue,
            targetSessionDuration: Int(fields["targetSessionDuration"]?.integerValue ?? "60") ?? 60,
            trainingLocation: TrainingLocation(rawValue: fields["trainingLocation"]?.stringValue ?? "") ?? .gym,
            compoundTimeAllocation: fields["compoundTimeAllocation"]?.doubleValue ?? 0.7,
            isolationApproach: IsolationApproach(rawValue: fields["isolationApproach"]?.stringValue ?? "") ?? .antagonistPairing,
            preferredDays: preferredDays,
            startDate: startDate,
            endDate: endDate,
            emphasizedMuscleGroups: emphasizedMuscles,
            excludedMuscleGroups: excludedMuscles,
            goalWeight: fields["goalWeight"]?.doubleValue,
            contextualGoals: fields["contextualGoals"]?.stringValue,
            experienceLevel: fields["experienceLevel"]?.stringValue.flatMap { ExperienceLevel(rawValue: $0) },
            availableEquipment: availableEquipment
        )
    }

    private nonisolated func parseProgramDocument(_ doc: FirestoreDocument) throws -> Program {
        guard let fields = doc.fields else {
            throw FirestorePlanError.parseError("No fields in document")
        }

        let id = fields["id"]?.stringValue ?? doc.name?.components(separatedBy: "/").last ?? ""
        let dateFormatter = ISO8601DateFormatter()

        return Program(
            id: id,
            planId: fields["planId"]?.stringValue ?? "",
            name: fields["name"]?.stringValue ?? "",
            focus: TrainingFocus(rawValue: fields["focus"]?.stringValue ?? "") ?? .development,
            rationale: fields["rationale"]?.stringValue ?? "",
            startDate: fields["startDate"]?.timestampValue.flatMap { dateFormatter.date(from: $0) } ?? Date(),
            endDate: fields["endDate"]?.timestampValue.flatMap { dateFormatter.date(from: $0) } ?? Date(),
            startingIntensity: fields["startingIntensity"]?.doubleValue ?? 0.75,
            endingIntensity: fields["endingIntensity"]?.doubleValue ?? 0.85,
            progressionType: ProgressionType(rawValue: fields["progressionType"]?.stringValue ?? "") ?? .linear,
            status: ProgramStatus(rawValue: fields["status"]?.stringValue ?? "") ?? .draft
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

    init(stringValue: String) { self.stringValue = stringValue }
    init(integerValue: String) { self.integerValue = integerValue }
    init(doubleValue: Double) { self.doubleValue = doubleValue }
    init(booleanValue: Bool) { self.booleanValue = booleanValue }
    init(timestampValue: String) { self.timestampValue = timestampValue }
    init(arrayValue: FirestoreWriteArrayValue) { self.arrayValue = arrayValue }
}

private struct FirestoreWriteArrayValue: Encodable {
    let values: [FirestoreWriteValue]
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
}

private struct FirestoreArrayValue: Decodable {
    let values: [FirestoreValue]?
}

private struct FirestoreQueryResult: Decodable {
    let document: FirestoreDocument?
    let readTime: String?
}

// MARK: - Errors

enum FirestorePlanError: LocalizedError {
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
            return "Failed to save plan (HTTP \(code))"
        case .fetchFailed:
            return "Failed to fetch plans"
        case .deleteFailed:
            return "Failed to delete plan"
        case .parseError(let msg):
            return "Parse error: \(msg)"
        case .notAuthenticated:
            return "Not authenticated"
        }
    }
}
