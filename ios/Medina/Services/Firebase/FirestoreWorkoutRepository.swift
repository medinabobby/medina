//
// FirestoreWorkoutRepository.swift
// Medina
//
// v189: Firestore-backed workout repository for trainer-member sync
// Workouts stored at: users/{memberId}/workouts/{workoutId}
// Instances stored at: users/{memberId}/workouts/{workoutId}/instances/{instanceId}
// Sets stored at: users/{memberId}/workouts/{workoutId}/instances/{instanceId}/sets/{setId}
//

import Foundation

/// Firestore-backed repository for Workouts, ExerciseInstances, and ExerciseSets
/// Enables trainer-member sync across devices
actor FirestoreWorkoutRepository {

    // MARK: - Configuration

    private let projectId = "medinaintelligence"
    private let baseURL: String

    private let session: URLSession

    // MARK: - Singleton

    static let shared = FirestoreWorkoutRepository()

    // MARK: - Initialization

    init() {
        self.baseURL = "https://firestore.googleapis.com/v1/projects/medinaintelligence/databases/(default)/documents"

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Workout Operations

    /// Save a workout to Firestore (create or update)
    nonisolated func saveWorkout(_ workout: Workout, memberId: String) async throws {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(memberId)/workouts/\(workout.id)"

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestoreWorkoutError.invalidURL
        }

        let firestoreDoc = workoutToFirestoreDocument(workout)
        let body = try JSONEncoder().encode(firestoreDoc)

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirestoreWorkoutError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.log(.error, component: "FirestoreWorkouts", message: "Save failed: \(httpResponse.statusCode) - \(errorBody)")
            throw FirestoreWorkoutError.saveFailed(httpResponse.statusCode)
        }

        Logger.log(.debug, component: "FirestoreWorkouts", message: "Saved workout \(workout.id)")
    }

    /// Save an exercise instance to Firestore
    nonisolated func saveInstance(_ instance: ExerciseInstance, memberId: String) async throws {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(memberId)/workouts/\(instance.workoutId)/instances/\(instance.id)"

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestoreWorkoutError.invalidURL
        }

        let firestoreDoc = instanceToFirestoreDocument(instance)
        let body = try JSONEncoder().encode(firestoreDoc)

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw FirestoreWorkoutError.saveFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        Logger.log(.debug, component: "FirestoreWorkouts", message: "Saved instance \(instance.id)")
    }

    /// Save an exercise set to Firestore
    nonisolated func saveSet(_ set: ExerciseSet, workoutId: String, memberId: String) async throws {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(memberId)/workouts/\(workoutId)/instances/\(set.exerciseInstanceId)/sets/\(set.id)"

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestoreWorkoutError.invalidURL
        }

        let firestoreDoc = setToFirestoreDocument(set)
        let body = try JSONEncoder().encode(firestoreDoc)

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw FirestoreWorkoutError.saveFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        Logger.log(.debug, component: "FirestoreWorkouts", message: "Saved set \(set.id)")
    }

    /// Fetch all workouts for a member
    nonisolated func fetchWorkouts(forMember memberId: String) async throws -> [Workout] {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(memberId)/workouts"

        guard let url = URL(string: "\(baseURL)/\(path)?pageSize=500") else {
            throw FirestoreWorkoutError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                return []  // No workouts yet
            }
            throw FirestoreWorkoutError.fetchFailed
        }

        let listResponse = try JSONDecoder().decode(FirestoreListResponse.self, from: data)
        return (listResponse.documents ?? []).compactMap { doc in
            try? parseWorkoutDocument(doc)
        }
    }

    /// v211: Fetch a single workout by ID (for server-created workout sync)
    nonisolated func fetchWorkout(id: String, memberId: String) async throws -> Workout? {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(memberId)/workouts/\(id)"

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestoreWorkoutError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirestoreWorkoutError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 404 {
            return nil  // Workout doesn't exist
        }

        guard httpResponse.statusCode == 200 else {
            throw FirestoreWorkoutError.fetchFailed
        }

        let doc = try JSONDecoder().decode(FirestoreDocument.self, from: data)
        return try parseWorkoutDocument(doc)
    }

    /// v235: Fetch workouts for a specific plan
    nonisolated func fetchWorkouts(forPlan planId: String, memberId: String) async throws -> [Workout] {
        let token = try await FirebaseAuthService.shared.getIDToken()

        // Query within user's workouts collection
        guard let url = URL(string: "\(baseURL)/users/\(memberId):runQuery") else {
            throw FirestoreWorkoutError.invalidURL
        }

        // Query: SELECT * FROM users/{memberId}/workouts WHERE planId == planId
        let query: [String: Any] = [
            "structuredQuery": [
                "from": [
                    ["collectionId": "workouts"]
                ],
                "where": [
                    "fieldFilter": [
                        "field": ["fieldPath": "planId"],
                        "op": "EQUAL",
                        "value": ["stringValue": planId]
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
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                return []
            }
            throw FirestoreWorkoutError.fetchFailed
        }

        // Parse query results
        let results = try JSONDecoder().decode([FirestoreQueryResult].self, from: data)
        return results.compactMap { result in
            guard let doc = result.document else { return nil }
            return try? parseWorkoutDocument(doc)
        }
    }

    /// Fetch all workouts for a trainer (across all assigned members)
    nonisolated func fetchWorkoutsForTrainer(trainerId: String) async throws -> [Workout] {
        let token = try await FirebaseAuthService.shared.getIDToken()

        guard let url = URL(string: "\(baseURL):runQuery") else {
            throw FirestoreWorkoutError.invalidURL
        }

        // Query: SELECT * FROM workouts WHERE trainerId == trainerId
        let query: [String: Any] = [
            "structuredQuery": [
                "from": [
                    ["collectionId": "workouts", "allDescendants": true]
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
            throw FirestoreWorkoutError.fetchFailed
        }

        let results = try JSONDecoder().decode([FirestoreQueryResult].self, from: data)
        return results.compactMap { result in
            guard let doc = result.document else { return nil }
            return try? parseWorkoutDocument(doc)
        }
    }

    /// Fetch instances for a workout
    nonisolated func fetchInstances(forWorkout workoutId: String, memberId: String) async throws -> [ExerciseInstance] {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(memberId)/workouts/\(workoutId)/instances"

        guard let url = URL(string: "\(baseURL)/\(path)?pageSize=50") else {
            throw FirestoreWorkoutError.invalidURL
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
            try? parseInstanceDocument(doc)
        }
    }

    /// Fetch sets for an instance
    nonisolated func fetchSets(forInstance instanceId: String, workoutId: String, memberId: String) async throws -> [ExerciseSet] {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(memberId)/workouts/\(workoutId)/instances/\(instanceId)/sets"

        guard let url = URL(string: "\(baseURL)/\(path)?pageSize=20") else {
            throw FirestoreWorkoutError.invalidURL
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
            try? parseSetDocument(doc)
        }
    }

    /// Delete a workout and all its instances/sets
    nonisolated func deleteWorkout(_ workoutId: String, memberId: String) async throws {
        let token = try await FirebaseAuthService.shared.getIDToken()

        // First delete instances (and their sets)
        let instances = try await fetchInstances(forWorkout: workoutId, memberId: memberId)
        for instance in instances {
            // Delete sets for this instance
            let sets = try await fetchSets(forInstance: instance.id, workoutId: workoutId, memberId: memberId)
            for set in sets {
                let setPath = "users/\(memberId)/workouts/\(workoutId)/instances/\(instance.id)/sets/\(set.id)"
                try await deleteDocument(path: setPath, token: token)
            }

            // Delete the instance
            let instancePath = "users/\(memberId)/workouts/\(workoutId)/instances/\(instance.id)"
            try await deleteDocument(path: instancePath, token: token)
        }

        // Finally delete the workout
        let workoutPath = "users/\(memberId)/workouts/\(workoutId)"
        try await deleteDocument(path: workoutPath, token: token)

        Logger.log(.info, component: "FirestoreWorkouts", message: "Deleted workout \(workoutId)")
    }

    private nonisolated func deleteDocument(path: String, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestoreWorkoutError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw FirestoreWorkoutError.deleteFailed
        }
    }

    // MARK: - Convenience: Save Full Workout with Instances and Sets

    /// Save a complete workout with all instances and sets
    /// Used when creating new workouts
    nonisolated func saveFullWorkout(
        workout: Workout,
        instances: [ExerciseInstance],
        sets: [ExerciseSet],
        memberId: String
    ) async throws {
        // Save workout first
        try await saveWorkout(workout, memberId: memberId)

        // Save all instances
        for instance in instances {
            try await saveInstance(instance, memberId: memberId)
        }

        // Save all sets
        for set in sets {
            try await saveSet(set, workoutId: workout.id, memberId: memberId)
        }

        Logger.log(.info, component: "FirestoreWorkouts",
                  message: "Saved full workout \(workout.id) with \(instances.count) instances, \(sets.count) sets")
    }

    // MARK: - Firestore Document Conversion

    private nonisolated func workoutToFirestoreDocument(_ workout: Workout) -> FirestoreWriteDocument {
        var fields: [String: FirestoreWriteValue] = [
            "id": .init(stringValue: workout.id),
            "programId": .init(stringValue: workout.programId),
            "name": .init(stringValue: workout.name),
            "type": .init(stringValue: workout.type.rawValue),
            "status": .init(stringValue: workout.status.rawValue)
        ]

        // Exercise IDs array
        let exerciseIdArray = workout.exerciseIds.map { FirestoreWriteValue(stringValue: $0) }
        fields["exerciseIds"] = .init(arrayValue: .init(values: exerciseIdArray))

        // Protocol variant IDs map (position -> variantId)
        // Convert [Int: String] to array of objects for Firestore
        var protocolVariants: [FirestoreWriteValue] = []
        for (position, variantId) in workout.protocolVariantIds {
            let entry = FirestoreWriteValue(mapValue: .init(fields: [
                "position": .init(integerValue: String(position)),
                "variantId": .init(stringValue: variantId)
            ]))
            protocolVariants.append(entry)
        }
        if !protocolVariants.isEmpty {
            fields["protocolVariantIds"] = .init(arrayValue: .init(values: protocolVariants))
        }

        // Optional dates
        let dateFormatter = ISO8601DateFormatter()
        if let scheduledDate = workout.scheduledDate {
            fields["scheduledDate"] = .init(timestampValue: dateFormatter.string(from: scheduledDate))
        }
        if let completedDate = workout.completedDate {
            fields["completedDate"] = .init(timestampValue: dateFormatter.string(from: completedDate))
        }
        if let exercisesSelectedAt = workout.exercisesSelectedAt {
            fields["exercisesSelectedAt"] = .init(timestampValue: dateFormatter.string(from: exercisesSelectedAt))
        }

        // Optional split day
        if let splitDay = workout.splitDay {
            fields["splitDay"] = .init(stringValue: splitDay.rawValue)
        }

        // v50: Superset groups (optional, complex)
        if let supersetGroups = workout.supersetGroups, !supersetGroups.isEmpty {
            var groupsArray: [FirestoreWriteValue] = []
            for group in supersetGroups {
                let positions = group.exercisePositions.map { FirestoreWriteValue(integerValue: String($0)) }
                let restValues = group.restBetweenExercises.map { FirestoreWriteValue(integerValue: String($0)) }
                let groupMap = FirestoreWriteValue(mapValue: .init(fields: [
                    "id": .init(stringValue: group.id),
                    "groupNumber": .init(integerValue: String(group.groupNumber)),
                    "exercisePositions": .init(arrayValue: .init(values: positions)),
                    "restBetweenExercises": .init(arrayValue: .init(values: restValues))
                ]))
                groupsArray.append(groupMap)
            }
            fields["supersetGroups"] = .init(arrayValue: .init(values: groupsArray))
        }

        return FirestoreWriteDocument(fields: fields)
    }

    private nonisolated func instanceToFirestoreDocument(_ instance: ExerciseInstance) -> FirestoreWriteDocument {
        var fields: [String: FirestoreWriteValue] = [
            "id": .init(stringValue: instance.id),
            "exerciseId": .init(stringValue: instance.exerciseId),
            "workoutId": .init(stringValue: instance.workoutId),
            "protocolVariantId": .init(stringValue: instance.protocolVariantId),
            "status": .init(stringValue: instance.status.rawValue)
        ]

        // Set IDs array
        let setIdArray = instance.setIds.map { FirestoreWriteValue(stringValue: $0) }
        fields["setIds"] = .init(arrayValue: .init(values: setIdArray))

        // Optional fields
        if let trainerInstructions = instance.trainerInstructions {
            fields["trainerInstructions"] = .init(stringValue: trainerInstructions)
        }
        if let supersetLabel = instance.supersetLabel {
            fields["supersetLabel"] = .init(stringValue: supersetLabel)
        }

        return FirestoreWriteDocument(fields: fields)
    }

    private nonisolated func setToFirestoreDocument(_ set: ExerciseSet) -> FirestoreWriteDocument {
        var fields: [String: FirestoreWriteValue] = [
            "id": .init(stringValue: set.id),
            "exerciseInstanceId": .init(stringValue: set.exerciseInstanceId),
            "setNumber": .init(integerValue: String(set.setNumber))
        ]

        // Strength training fields
        if let targetWeight = set.targetWeight {
            fields["targetWeight"] = .init(doubleValue: targetWeight)
        }
        if let targetReps = set.targetReps {
            fields["targetReps"] = .init(integerValue: String(targetReps))
        }
        if let targetRPE = set.targetRPE {
            fields["targetRPE"] = .init(integerValue: String(targetRPE))
        }
        if let actualWeight = set.actualWeight {
            fields["actualWeight"] = .init(doubleValue: actualWeight)
        }
        if let actualReps = set.actualReps {
            fields["actualReps"] = .init(integerValue: String(actualReps))
        }

        // Cardio fields
        if let targetDuration = set.targetDuration {
            fields["targetDuration"] = .init(integerValue: String(targetDuration))
        }
        if let targetDistance = set.targetDistance {
            fields["targetDistance"] = .init(doubleValue: targetDistance)
        }
        if let actualDuration = set.actualDuration {
            fields["actualDuration"] = .init(integerValue: String(actualDuration))
        }
        if let actualDistance = set.actualDistance {
            fields["actualDistance"] = .init(doubleValue: actualDistance)
        }

        // Common fields
        if let completion = set.completion {
            fields["completion"] = .init(stringValue: completion.rawValue)
        }

        let dateFormatter = ISO8601DateFormatter()
        if let startTime = set.startTime {
            fields["startTime"] = .init(timestampValue: dateFormatter.string(from: startTime))
        }
        if let endTime = set.endTime {
            fields["endTime"] = .init(timestampValue: dateFormatter.string(from: endTime))
        }
        if let recordedDate = set.recordedDate {
            fields["recordedDate"] = .init(timestampValue: dateFormatter.string(from: recordedDate))
        }
        if let notes = set.notes {
            fields["notes"] = .init(stringValue: notes)
        }

        return FirestoreWriteDocument(fields: fields)
    }

    private nonisolated func parseWorkoutDocument(_ doc: FirestoreDocument) throws -> Workout {
        guard let fields = doc.fields else {
            throw FirestoreWorkoutError.parseError("No fields in document")
        }

        let id = fields["id"]?.stringValue ?? doc.name?.components(separatedBy: "/").last ?? ""
        let programId = fields["programId"]?.stringValue ?? ""
        let dateFormatter = ISO8601DateFormatter()

        // Parse exercise IDs
        let exerciseIds: [String] = (fields["exerciseIds"]?.arrayValue?.values ?? []).compactMap { $0.stringValue }

        // Parse protocol variant IDs
        var protocolVariantIds: [Int: String] = [:]
        if let variants = fields["protocolVariantIds"]?.arrayValue?.values {
            for variant in variants {
                if let mapFields = variant.mapValue?.fields,
                   let posStr = mapFields["position"]?.integerValue,
                   let position = Int(posStr),
                   let variantId = mapFields["variantId"]?.stringValue {
                    protocolVariantIds[position] = variantId
                }
            }
        }

        // Parse superset groups
        var supersetGroups: [SupersetGroup]?
        if let groupsArray = fields["supersetGroups"]?.arrayValue?.values {
            supersetGroups = groupsArray.compactMap { groupValue -> SupersetGroup? in
                guard let mapFields = groupValue.mapValue?.fields,
                      let groupId = mapFields["id"]?.stringValue,
                      let groupNumberStr = mapFields["groupNumber"]?.integerValue,
                      let groupNumber = Int(groupNumberStr),
                      let positions = mapFields["exercisePositions"]?.arrayValue?.values,
                      let restValues = mapFields["restBetweenExercises"]?.arrayValue?.values else {
                    return nil
                }

                let exercisePositions = positions.compactMap { Int($0.integerValue ?? "") }
                let restBetweenExercises = restValues.compactMap { Int($0.integerValue ?? "") }

                return SupersetGroup(
                    id: groupId,
                    groupNumber: groupNumber,
                    exercisePositions: exercisePositions,
                    restBetweenExercises: restBetweenExercises
                )
            }
        }

        return Workout(
            id: id,
            programId: programId,
            name: fields["name"]?.stringValue ?? "",
            scheduledDate: fields["scheduledDate"]?.timestampValue.flatMap { dateFormatter.date(from: $0) },
            type: SessionType(rawValue: fields["type"]?.stringValue ?? "") ?? .strength,
            splitDay: fields["splitDay"]?.stringValue.flatMap { SplitDay(rawValue: $0) },
            status: ExecutionStatus(rawValue: fields["status"]?.stringValue ?? "") ?? .scheduled,
            completedDate: fields["completedDate"]?.timestampValue.flatMap { dateFormatter.date(from: $0) },
            exerciseIds: exerciseIds,
            protocolVariantIds: protocolVariantIds,
            exercisesSelectedAt: fields["exercisesSelectedAt"]?.timestampValue.flatMap { dateFormatter.date(from: $0) },
            supersetGroups: supersetGroups
        )
    }

    private nonisolated func parseInstanceDocument(_ doc: FirestoreDocument) throws -> ExerciseInstance {
        guard let fields = doc.fields else {
            throw FirestoreWorkoutError.parseError("No fields in document")
        }

        let id = fields["id"]?.stringValue ?? doc.name?.components(separatedBy: "/").last ?? ""
        let setIds: [String] = (fields["setIds"]?.arrayValue?.values ?? []).compactMap { $0.stringValue }

        return ExerciseInstance(
            id: id,
            exerciseId: fields["exerciseId"]?.stringValue ?? "",
            workoutId: fields["workoutId"]?.stringValue ?? "",
            protocolVariantId: fields["protocolVariantId"]?.stringValue ?? "",
            setIds: setIds,
            status: ExecutionStatus(rawValue: fields["status"]?.stringValue ?? "") ?? .scheduled,
            trainerInstructions: fields["trainerInstructions"]?.stringValue,
            supersetLabel: fields["supersetLabel"]?.stringValue
        )
    }

    private nonisolated func parseSetDocument(_ doc: FirestoreDocument) throws -> ExerciseSet {
        guard let fields = doc.fields else {
            throw FirestoreWorkoutError.parseError("No fields in document")
        }

        let id = fields["id"]?.stringValue ?? doc.name?.components(separatedBy: "/").last ?? ""
        let dateFormatter = ISO8601DateFormatter()

        return ExerciseSet(
            id: id,
            exerciseInstanceId: fields["exerciseInstanceId"]?.stringValue ?? "",
            setNumber: Int(fields["setNumber"]?.integerValue ?? "1") ?? 1,
            targetWeight: fields["targetWeight"]?.doubleValue,
            targetReps: fields["targetReps"]?.integerValue.flatMap { Int($0) },
            targetRPE: fields["targetRPE"]?.integerValue.flatMap { Int($0) },
            actualWeight: fields["actualWeight"]?.doubleValue,
            actualReps: fields["actualReps"]?.integerValue.flatMap { Int($0) },
            targetDuration: fields["targetDuration"]?.integerValue.flatMap { Int($0) },
            targetDistance: fields["targetDistance"]?.doubleValue,
            actualDuration: fields["actualDuration"]?.integerValue.flatMap { Int($0) },
            actualDistance: fields["actualDistance"]?.doubleValue,
            completion: fields["completion"]?.stringValue.flatMap { ExecutionStatus(rawValue: $0) },
            startTime: fields["startTime"]?.timestampValue.flatMap { dateFormatter.date(from: $0) },
            endTime: fields["endTime"]?.timestampValue.flatMap { dateFormatter.date(from: $0) },
            notes: fields["notes"]?.stringValue,
            recordedDate: fields["recordedDate"]?.timestampValue.flatMap { dateFormatter.date(from: $0) }
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

private struct FirestoreQueryResult: Decodable {
    let document: FirestoreDocument?
    let readTime: String?
}

// MARK: - Errors

enum FirestoreWorkoutError: LocalizedError {
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
            return "Failed to save workout (HTTP \(code))"
        case .fetchFailed:
            return "Failed to fetch workouts"
        case .deleteFailed:
            return "Failed to delete workout"
        case .parseError(let msg):
            return "Parse error: \(msg)"
        case .notAuthenticated:
            return "Not authenticated"
        }
    }
}
