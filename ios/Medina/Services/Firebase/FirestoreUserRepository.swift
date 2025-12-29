//
// FirestoreUserRepository.swift
// Medina
//
// v195: Firestore-backed user repository for cloud-only architecture
// Users stored at: users/{userId}
//

import Foundation

/// Firestore-backed repository for UnifiedUser profiles
/// Enables cross-device user data sync
actor FirestoreUserRepository {

    // MARK: - Configuration

    private let projectId = "medinaintelligence"
    private let baseURL: String

    private let session: URLSession

    // MARK: - Singleton

    static let shared = FirestoreUserRepository()

    // MARK: - Initialization

    init() {
        self.baseURL = "https://firestore.googleapis.com/v1/projects/medinaintelligence/databases/(default)/documents"

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - User Operations

    /// Save a user to Firestore (create or update)
    nonisolated func saveUser(_ user: UnifiedUser) async throws {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(user.id)"

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestoreUserError.invalidURL
        }

        let firestoreDoc = userToFirestoreDocument(user)
        let body = try JSONEncoder().encode(firestoreDoc)

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirestoreUserError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.log(.error, component: "FirestoreUsers", message: "Save failed: \(httpResponse.statusCode) - \(errorBody)")
            throw FirestoreUserError.saveFailed(httpResponse.statusCode)
        }

        Logger.log(.info, component: "FirestoreUsers", message: "Saved user \(user.id)")
    }

    /// Fetch a user from Firestore
    nonisolated func fetchUser(userId: String) async throws -> UnifiedUser? {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(userId)"

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestoreUserError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirestoreUserError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 404 {
            return nil  // User doesn't exist yet
        }

        guard httpResponse.statusCode == 200 else {
            throw FirestoreUserError.fetchFailed
        }

        let doc = try JSONDecoder().decode(FirestoreDocument.self, from: data)
        return try parseUserDocument(doc)
    }

    /// Delete a user from Firestore
    nonisolated func deleteUser(userId: String) async throws {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let path = "users/\(userId)"

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw FirestoreUserError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw FirestoreUserError.deleteFailed
        }

        Logger.log(.info, component: "FirestoreUsers", message: "Deleted user \(userId)")
    }

    // MARK: - Firestore Document Conversion

    private nonisolated func userToFirestoreDocument(_ user: UnifiedUser) -> FirestoreWriteDocument {
        var fields: [String: FirestoreWriteValue] = [
            "id": .init(stringValue: user.id),
            "firebaseUID": .init(stringValue: user.firebaseUID),
            "authProvider": .init(stringValue: user.authProvider.rawValue),
            "name": .init(stringValue: user.name),
            "gender": .init(stringValue: user.gender.rawValue)
        ]

        // Optional contact info
        if let email = user.email {
            fields["email"] = .init(stringValue: email)
        }
        if let phone = user.phoneNumber {
            fields["phoneNumber"] = .init(stringValue: phone)
        }
        if let photoURL = user.photoURL {
            fields["photoURL"] = .init(stringValue: photoURL)
        }
        if let providerUID = user.providerUID {
            fields["providerUID"] = .init(stringValue: providerUID)
        }
        if let emailVerified = user.emailVerified {
            fields["emailVerified"] = .init(booleanValue: emailVerified)
        }

        // Birthdate
        let dateFormatter = ISO8601DateFormatter()
        if let birthdate = user.birthdate {
            fields["birthdate"] = .init(timestampValue: dateFormatter.string(from: birthdate))
        }

        // Roles array
        let rolesArray = user.roles.map { FirestoreWriteValue(stringValue: $0.rawValue) }
        fields["roles"] = .init(arrayValue: .init(values: rolesArray))

        if let gymId = user.gymId {
            fields["gymId"] = .init(stringValue: gymId)
        }

        // Member profile (as nested map)
        if let memberProfile = user.memberProfile {
            fields["memberProfile"] = .init(mapValue: .init(fields: memberProfileToFields(memberProfile)))
        }

        // Trainer profile (as nested map)
        if let trainerProfile = user.trainerProfile {
            fields["trainerProfile"] = .init(mapValue: .init(fields: trainerProfileToFields(trainerProfile)))
        }

        return FirestoreWriteDocument(fields: fields)
    }

    private nonisolated func memberProfileToFields(_ profile: MemberProfile) -> [String: FirestoreWriteValue] {
        var fields: [String: FirestoreWriteValue] = [
            "fitnessGoal": .init(stringValue: profile.fitnessGoal.rawValue),
            "experienceLevel": .init(stringValue: profile.experienceLevel.rawValue),
            "preferredSessionDuration": .init(integerValue: String(profile.preferredSessionDuration)),
            "membershipStatus": .init(stringValue: profile.membershipStatus.rawValue)
        ]

        let dateFormatter = ISO8601DateFormatter()
        fields["memberSince"] = .init(timestampValue: dateFormatter.string(from: profile.memberSince))

        // Optional physical info
        if let height = profile.height {
            fields["height"] = .init(doubleValue: height)
        }
        if let currentWeight = profile.currentWeight {
            fields["currentWeight"] = .init(doubleValue: currentWeight)
        }
        if let goalWeight = profile.goalWeight {
            fields["goalWeight"] = .init(doubleValue: goalWeight)
        }
        if let goalDate = profile.goalDate {
            fields["goalDate"] = .init(timestampValue: dateFormatter.string(from: goalDate))
        }
        if let startingWeight = profile.startingWeight {
            fields["startingWeight"] = .init(doubleValue: startingWeight)
        }
        if let motivation = profile.personalMotivation {
            fields["personalMotivation"] = .init(stringValue: motivation)
        }

        // Preferred days
        if let days = profile.preferredWorkoutDays {
            let daysArray = days.map { FirestoreWriteValue(stringValue: $0.rawValue) }
            fields["preferredWorkoutDays"] = .init(arrayValue: .init(values: daysArray))
        }

        // Split type and cardio
        if let splitType = profile.preferredSplitType {
            fields["preferredSplitType"] = .init(stringValue: splitType.rawValue)
        }
        if let cardioDays = profile.preferredCardioDays {
            fields["preferredCardioDays"] = .init(integerValue: String(cardioDays))
        }

        // Muscle groups
        if let emphasized = profile.emphasizedMuscleGroups {
            let emphArray = emphasized.map { FirestoreWriteValue(stringValue: $0.rawValue) }
            fields["emphasizedMuscleGroups"] = .init(arrayValue: .init(values: emphArray))
        }
        if let excluded = profile.excludedMuscleGroups {
            let exclArray = excluded.map { FirestoreWriteValue(stringValue: $0.rawValue) }
            fields["excludedMuscleGroups"] = .init(arrayValue: .init(values: exclArray))
        }

        // Training context
        if let location = profile.trainingLocation {
            fields["trainingLocation"] = .init(stringValue: location.rawValue)
        }
        if let equipment = profile.availableEquipment {
            let equipArray = equipment.map { FirestoreWriteValue(stringValue: $0.rawValue) }
            fields["availableEquipment"] = .init(arrayValue: .init(values: equipArray))
        }

        // Exercise constraints
        if let maxExercises = profile.maxTargetExercises {
            let maxArray = maxExercises.map { FirestoreWriteValue(stringValue: $0) }
            fields["maxTargetExercises"] = .init(arrayValue: .init(values: maxArray))
        }
        if let excludedExercises = profile.excludedExerciseIds {
            let exclArray = excludedExercises.map { FirestoreWriteValue(stringValue: $0) }
            fields["excludedExerciseIds"] = .init(arrayValue: .init(values: exclArray))
        }

        // Relationships
        if let trainerId = profile.trainerId {
            fields["trainerId"] = .init(stringValue: trainerId)
        }
        if let tierId = profile.subscriptionTierId {
            fields["subscriptionTierId"] = .init(stringValue: tierId)
        }

        return fields
    }

    private nonisolated func trainerProfileToFields(_ profile: TrainerProfile) -> [String: FirestoreWriteValue] {
        var fields: [String: FirestoreWriteValue] = [
            "bio": .init(stringValue: profile.bio)
        ]

        // Specialties array
        let specialtiesArray = profile.specialties.map { FirestoreWriteValue(stringValue: $0.rawValue) }
        fields["specialties"] = .init(arrayValue: .init(values: specialtiesArray))

        if let years = profile.yearsExperience {
            fields["yearsExperience"] = .init(integerValue: String(years))
        }
        if let certs = profile.certifications {
            let certsArray = certs.map { FirestoreWriteValue(stringValue: $0) }
            fields["certifications"] = .init(arrayValue: .init(values: certsArray))
        }
        if let rate = profile.hourlyRate {
            fields["hourlyRate"] = .init(doubleValue: rate)
        }
        if let availability = profile.availability {
            let availArray = availability.map { FirestoreWriteValue(stringValue: $0) }
            fields["availability"] = .init(arrayValue: .init(values: availArray))
        }

        return fields
    }

    private nonisolated func parseUserDocument(_ doc: FirestoreDocument) throws -> UnifiedUser {
        guard let fields = doc.fields else {
            throw FirestoreUserError.parseError("No fields in document")
        }

        let id = fields["id"]?.stringValue ?? doc.name?.components(separatedBy: "/").last ?? ""
        let dateFormatter = ISO8601DateFormatter()

        // Parse roles
        let roles: [UserRole] = (fields["roles"]?.arrayValue?.values ?? []).compactMap {
            UserRole(rawValue: $0.stringValue ?? "")
        }

        // Parse member profile
        var memberProfile: MemberProfile?
        if let mpFields = fields["memberProfile"]?.mapValue?.fields {
            memberProfile = parseMemberProfileFields(mpFields)
        }

        // Parse trainer profile
        var trainerProfile: TrainerProfile?
        if let tpFields = fields["trainerProfile"]?.mapValue?.fields {
            trainerProfile = parseTrainerProfileFields(tpFields)
        }

        return UnifiedUser(
            id: id,
            firebaseUID: fields["firebaseUID"]?.stringValue ?? "",
            authProvider: AuthProvider(rawValue: fields["authProvider"]?.stringValue ?? "") ?? .apple,
            email: fields["email"]?.stringValue,
            phoneNumber: fields["phoneNumber"]?.stringValue,
            name: fields["name"]?.stringValue ?? "",
            photoURL: fields["photoURL"]?.stringValue,
            providerUID: fields["providerUID"]?.stringValue,
            emailVerified: fields["emailVerified"]?.booleanValue,
            birthdate: fields["birthdate"]?.timestampValue.flatMap { dateFormatter.date(from: $0) },
            gender: Gender(rawValue: fields["gender"]?.stringValue ?? "") ?? .preferNotToSay,
            roles: roles,
            gymId: fields["gymId"]?.stringValue,
            passwordHash: nil,
            memberProfile: memberProfile,
            trainerProfile: trainerProfile
        )
    }

    private nonisolated func parseMemberProfileFields(_ fields: [String: FirestoreValue]) -> MemberProfile {
        let dateFormatter = ISO8601DateFormatter()

        // Parse sets
        let preferredDays: Set<DayOfWeek>? = fields["preferredWorkoutDays"]?.arrayValue?.values.map {
            Set($0.compactMap { DayOfWeek(rawValue: $0.stringValue ?? "") })
        }.flatMap { $0.isEmpty ? nil : $0 }

        let emphasizedMuscles: Set<MuscleGroup>? = fields["emphasizedMuscleGroups"]?.arrayValue?.values.map {
            Set($0.compactMap { MuscleGroup(rawValue: $0.stringValue ?? "") })
        }.flatMap { $0.isEmpty ? nil : $0 }

        let excludedMuscles: Set<MuscleGroup>? = fields["excludedMuscleGroups"]?.arrayValue?.values.map {
            Set($0.compactMap { MuscleGroup(rawValue: $0.stringValue ?? "") })
        }.flatMap { $0.isEmpty ? nil : $0 }

        let equipment: Set<Equipment>? = fields["availableEquipment"]?.arrayValue?.values.map {
            Set($0.compactMap { Equipment(rawValue: $0.stringValue ?? "") })
        }.flatMap { $0.isEmpty ? nil : $0 }

        let maxExercises: Set<String>? = fields["maxTargetExercises"]?.arrayValue?.values.map {
            Set($0.compactMap { $0.stringValue })
        }.flatMap { $0.isEmpty ? nil : $0 }

        let excludedExercises: Set<String>? = fields["excludedExerciseIds"]?.arrayValue?.values.map {
            Set($0.compactMap { $0.stringValue })
        }.flatMap { $0.isEmpty ? nil : $0 }

        return MemberProfile(
            height: fields["height"]?.doubleValue,
            currentWeight: fields["currentWeight"]?.doubleValue,
            goalWeight: fields["goalWeight"]?.doubleValue,
            goalDate: fields["goalDate"]?.timestampValue.flatMap { dateFormatter.date(from: $0) },
            startingWeight: fields["startingWeight"]?.doubleValue,
            personalMotivation: fields["personalMotivation"]?.stringValue,
            fitnessGoal: FitnessGoal(rawValue: fields["fitnessGoal"]?.stringValue ?? "") ?? .strength,
            experienceLevel: ExperienceLevel(rawValue: fields["experienceLevel"]?.stringValue ?? "") ?? .beginner,
            preferredWorkoutDays: preferredDays,
            preferredSessionDuration: Int(fields["preferredSessionDuration"]?.integerValue ?? "60") ?? 60,
            preferredSplitType: fields["preferredSplitType"]?.stringValue.flatMap { SplitType(rawValue: $0) },
            preferredCardioDays: fields["preferredCardioDays"]?.integerValue.flatMap { Int($0) },
            emphasizedMuscleGroups: emphasizedMuscles,
            excludedMuscleGroups: excludedMuscles,
            trainingLocation: fields["trainingLocation"]?.stringValue.flatMap { TrainingLocation(rawValue: $0) },
            availableEquipment: equipment,
            maxTargetExercises: maxExercises,
            excludedExerciseIds: excludedExercises,
            voiceSettings: nil,  // VoiceSettings stored separately if needed
            trainerId: fields["trainerId"]?.stringValue,
            subscriptionTierId: fields["subscriptionTierId"]?.stringValue,
            membershipStatus: MembershipStatus(rawValue: fields["membershipStatus"]?.stringValue ?? "") ?? .active,
            memberSince: fields["memberSince"]?.timestampValue.flatMap { dateFormatter.date(from: $0) } ?? Date()
        )
    }

    private nonisolated func parseTrainerProfileFields(_ fields: [String: FirestoreValue]) -> TrainerProfile {
        let specialties: [TrainerSpecialty] = (fields["specialties"]?.arrayValue?.values ?? []).compactMap {
            TrainerSpecialty(rawValue: $0.stringValue ?? "")
        }

        let certifications: [String]? = fields["certifications"]?.arrayValue?.values?.compactMap { $0.stringValue }
        let availability: [String]? = fields["availability"]?.arrayValue?.values?.compactMap { $0.stringValue }

        return TrainerProfile(
            bio: fields["bio"]?.stringValue ?? "",
            specialties: specialties,
            yearsExperience: fields["yearsExperience"]?.integerValue.flatMap { Int($0) },
            certifications: certifications,
            hourlyRate: fields["hourlyRate"]?.doubleValue,
            availability: availability
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

enum FirestoreUserError: LocalizedError {
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
            return "Failed to save user (HTTP \(code))"
        case .fetchFailed:
            return "Failed to fetch user"
        case .deleteFailed:
            return "Failed to delete user"
        case .parseError(let msg):
            return "Parse error: \(msg)"
        case .notAuthenticated:
            return "Not authenticated"
        }
    }
}
