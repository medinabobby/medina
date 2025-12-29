//
// FirestoreGymRepository.swift
// Medina
//
// v196: Firestore-backed gym repository using REST API
// Fetches gym data from Firestore, with local JSON fallback for seeding
//

import Foundation

/// Firestore-backed repository for gym data
/// Uses Firebase Auth ID token for authentication
actor FirestoreGymRepository {

    // MARK: - Configuration

    private let projectId = "medinaintelligence"
    private let baseURL: String

    private let session: URLSession
    private let decoder: JSONDecoder

    // MARK: - Singleton

    static let shared = FirestoreGymRepository()

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

    // MARK: - Fetch All Gyms

    /// Fetch all gyms from Firestore
    nonisolated func fetchAll() async throws -> [String: Gym] {
        let startTime = Date()

        // Get auth token
        let token = try await FirebaseAuthService.shared.getIDToken()

        // Build URL for listing all documents in gyms collection
        guard let url = URL(string: "\(baseURL)/gyms?pageSize=100") else {
            throw GymRepositoryError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GymRepositoryError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw GymRepositoryError.notAuthenticated
            }
            throw GymRepositoryError.networkError(URLError(.init(rawValue: httpResponse.statusCode)))
        }

        // Parse Firestore response
        let firestoreResponse = try JSONDecoder().decode(FirestoreListResponse.self, from: data)

        // Convert to Gym dictionary
        var gyms: [String: Gym] = [:]
        for document in firestoreResponse.documents ?? [] {
            if let gym = try? parseGymDocument(document) {
                gyms[gym.id] = gym
            }
        }

        let latency = Date().timeIntervalSince(startTime) * 1000
        Logger.log(.info, component: "FirestoreGyms", message: "Fetched \(gyms.count) gyms in \(Int(latency))ms")

        return gyms
    }

    // MARK: - Fetch Single Gym

    /// Fetch a specific gym by ID
    nonisolated func fetch(byId id: String) async throws -> Gym? {
        let token = try await FirebaseAuthService.shared.getIDToken()

        guard let url = URL(string: "\(baseURL)/gyms/\(id)") else {
            throw GymRepositoryError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GymRepositoryError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 404 {
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            throw GymRepositoryError.networkError(URLError(.init(rawValue: httpResponse.statusCode)))
        }

        let document = try JSONDecoder().decode(FirestoreDocument.self, from: data)
        return try parseGymDocument(document)
    }

    // MARK: - Seed Gyms to Firestore

    /// Seed gyms from local JSON to Firestore
    /// Call this once when gyms collection is empty
    nonisolated func seedFromLocalJSON() async throws -> Int {
        // Load local JSON
        guard let url = Bundle.main.url(forResource: "gyms", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            Logger.log(.warning, component: "FirestoreGyms", message: "Local gyms.json not found")
            return 0
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let gyms = try decoder.decode([String: Gym].self, from: data)
        Logger.log(.info, component: "FirestoreGyms", message: "Loaded \(gyms.count) gyms from local JSON")

        // Get auth token
        let token = try await FirebaseAuthService.shared.getIDToken()

        // Upload each gym to Firestore
        var uploadedCount = 0
        for (id, gym) in gyms {
            do {
                try await uploadGym(gym, withId: id, token: token)
                uploadedCount += 1
            } catch {
                Logger.log(.error, component: "FirestoreGyms", message: "Failed to upload gym \(id): \(error)")
            }
        }

        Logger.log(.info, component: "FirestoreGyms", message: "Seeded \(uploadedCount) gyms to Firestore")
        return uploadedCount
    }

    /// Upload a single gym to Firestore
    private nonisolated func uploadGym(_ gym: Gym, withId id: String, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/gyms?documentId=\(id)") else {
            throw GymRepositoryError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Convert to Firestore document format
        let firestoreDoc = gymToFirestoreDocument(gym)
        request.httpBody = try JSONSerialization.data(withJSONObject: firestoreDoc)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GymRepositoryError.networkError(URLError(.badServerResponse))
        }
    }

    // MARK: - Firestore Document Conversion

    private nonisolated func gymToFirestoreDocument(_ gym: Gym) -> [String: Any] {
        var fields: [String: [String: Any]] = [:]

        fields["id"] = ["stringValue": gym.id]
        fields["name"] = ["stringValue": gym.name]
        fields["address"] = ["stringValue": gym.address]
        fields["neighborhood"] = ["stringValue": gym.neighborhood]
        fields["city"] = ["stringValue": gym.city]
        fields["state"] = ["stringValue": gym.state]
        fields["zipCode"] = ["stringValue": gym.zipCode]

        if let phone = gym.phone {
            fields["phone"] = ["stringValue": phone]
        }
        fields["email"] = ["stringValue": gym.email]
        if let website = gym.website {
            fields["website"] = ["stringValue": website]
        }

        // Hours as map
        fields["hours"] = ["mapValue": ["fields": [
            "monday": ["stringValue": gym.hours.monday],
            "tuesday": ["stringValue": gym.hours.tuesday],
            "wednesday": ["stringValue": gym.hours.wednesday],
            "thursday": ["stringValue": gym.hours.thursday],
            "friday": ["stringValue": gym.hours.friday],
            "saturday": ["stringValue": gym.hours.saturday],
            "sunday": ["stringValue": gym.hours.sunday]
        ]]]

        // Facility as map
        fields["facility"] = ["mapValue": ["fields": [
            "type": ["stringValue": gym.facility.type],
            "squareFeet": ["integerValue": String(gym.facility.squareFeet)],
            "levels": ["integerValue": String(gym.facility.levels)],
            "description": ["stringValue": gym.facility.description]
        ]]]

        // Arrays
        fields["services"] = ["arrayValue": ["values": gym.services.map { ["stringValue": $0] }]]
        fields["amenities"] = ["arrayValue": ["values": gym.amenities.map { ["stringValue": $0] }]]

        // Membership tiers as array of maps
        let tiersValues = gym.membershipTiers.map { tier -> [String: Any] in
            return ["mapValue": ["fields": [
                "id": ["stringValue": tier.id],
                "name": ["stringValue": tier.name],
                "price": ["integerValue": String(tier.price)],
                "classCredits": ["integerValue": String(tier.classCredits)],
                "benefits": ["arrayValue": ["values": tier.benefits.map { ["stringValue": $0] }]]
            ]]]
        }
        fields["membershipTiers"] = ["arrayValue": ["values": tiersValues]]

        // Other fields
        let isoFormatter = ISO8601DateFormatter()
        fields["foundedDate"] = ["timestampValue": isoFormatter.string(from: gym.foundedDate)]
        fields["memberCapacity"] = ["integerValue": String(gym.memberCapacity)]
        fields["activeMembers"] = ["integerValue": String(gym.activeMembers)]

        return ["fields": fields]
    }

    private nonisolated func parseGymDocument(_ document: FirestoreDocument) throws -> Gym {
        guard let fields = document.fields else {
            throw GymRepositoryError.decodingError
        }

        // Extract document ID from name path
        let id = document.name?.components(separatedBy: "/").last ?? fields["id"]?.stringValue ?? ""

        // Parse hours
        let hoursFields = fields["hours"]?.mapValue?.fields ?? [:]
        let hours = GymHours(
            monday: hoursFields["monday"]?.stringValue ?? "",
            tuesday: hoursFields["tuesday"]?.stringValue ?? "",
            wednesday: hoursFields["wednesday"]?.stringValue ?? "",
            thursday: hoursFields["thursday"]?.stringValue ?? "",
            friday: hoursFields["friday"]?.stringValue ?? "",
            saturday: hoursFields["saturday"]?.stringValue ?? "",
            sunday: hoursFields["sunday"]?.stringValue ?? ""
        )

        // Parse facility
        let facilityFields = fields["facility"]?.mapValue?.fields ?? [:]
        let facility = GymFacility(
            type: facilityFields["type"]?.stringValue ?? "",
            squareFeet: Int(facilityFields["squareFeet"]?.integerValue ?? "") ?? 0,
            levels: Int(facilityFields["levels"]?.integerValue ?? "") ?? 1,
            description: facilityFields["description"]?.stringValue ?? ""
        )

        // Parse services and amenities
        let services = (fields["services"]?.arrayValue?.values ?? []).compactMap { $0.stringValue }
        let amenities = (fields["amenities"]?.arrayValue?.values ?? []).compactMap { $0.stringValue }

        // Parse membership tiers
        let tiersValues = fields["membershipTiers"]?.arrayValue?.values ?? []
        let membershipTiers: [MembershipTier] = tiersValues.compactMap { tierValue in
            guard let tierFields = tierValue.mapValue?.fields else { return nil }
            let benefits = (tierFields["benefits"]?.arrayValue?.values ?? []).compactMap { $0.stringValue }
            return MembershipTier(
                id: tierFields["id"]?.stringValue ?? "",
                name: tierFields["name"]?.stringValue ?? "",
                price: Int(tierFields["price"]?.integerValue ?? "") ?? 0,
                benefits: benefits,
                classCredits: Int(tierFields["classCredits"]?.integerValue ?? "") ?? 2
            )
        }

        // Parse dates
        let isoFormatter = ISO8601DateFormatter()
        let foundedDate = fields["foundedDate"]?.timestampValue.flatMap { isoFormatter.date(from: $0) } ?? Date()

        return Gym(
            id: id,
            name: fields["name"]?.stringValue ?? "",
            address: fields["address"]?.stringValue ?? "",
            neighborhood: fields["neighborhood"]?.stringValue ?? "",
            city: fields["city"]?.stringValue ?? "",
            state: fields["state"]?.stringValue ?? "",
            zipCode: fields["zipCode"]?.stringValue ?? "",
            phone: fields["phone"]?.stringValue,
            email: fields["email"]?.stringValue ?? "",
            website: fields["website"]?.stringValue,
            hours: hours,
            facility: facility,
            services: services,
            amenities: amenities,
            membershipTiers: membershipTiers,
            foundedDate: foundedDate,
            memberCapacity: Int(fields["memberCapacity"]?.integerValue ?? "") ?? 0,
            activeMembers: Int(fields["activeMembers"]?.integerValue ?? "") ?? 0
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
    let timestampValue: String?
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

enum GymRepositoryError: Error {
    case networkError(Error)
    case notAuthenticated
    case decodingError
}
