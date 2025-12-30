import Foundation

/// REST client for Firebase Functions
/// Release 1.2: Validates iOS can communicate with Firebase backend
actor FirebaseAPIClient {

    // MARK: - Configuration

    // Cloud Run Gen 2 function URLs
    private let endpoints: [String: String] = [
        "hello": "https://hello-dpkc2km3oa-uc.a.run.app",
        "chat": "https://chat-dpkc2km3oa-uc.a.run.app",
        "getUser": "https://getuser-dpkc2km3oa-uc.a.run.app",
        "tts": "https://us-central1-medinaintelligence.cloudfunctions.net/tts",
        "vision": "https://us-central1-medinaintelligence.cloudfunctions.net/vision",
        "chatSimple": "https://us-central1-medinaintelligence.cloudfunctions.net/chatSimple",
        "calculate": "https://calculate-dpkc2km3oa-uc.a.run.app",
        // Plan API endpoints - direct REST calls for iOS UI
        "activatePlan": "https://us-central1-medinaintelligence.cloudfunctions.net/activatePlan",
        "abandonPlan": "https://us-central1-medinaintelligence.cloudfunctions.net/abandonPlan",
        "deletePlan": "https://us-central1-medinaintelligence.cloudfunctions.net/deletePlan",
        "reschedulePlan": "https://us-central1-medinaintelligence.cloudfunctions.net/reschedulePlan",
        // Initial chips endpoint - context-aware suggestion chips
        "initialChips": "https://us-central1-medinaintelligence.cloudfunctions.net/initialChips"
    ]
    private let session: URLSession

    /// Current Firebase Auth ID token (set after sign-in)
    private var authToken: String?

    // MARK: - Singleton

    static let shared = FirebaseAPIClient()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Auth Token Management

    /// Set the Firebase Auth ID token for authenticated requests
    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    // MARK: - API Endpoints

    /// Test endpoint - no auth required
    /// GET /hello
    func hello() async throws -> HelloResponse {
        let start = Date()
        let response: HelloResponse = try await get(endpoint: "hello", requiresAuth: false)
        let latency = Date().timeIntervalSince(start) * 1000
        print("[FirebaseAPI] /hello completed in \(Int(latency))ms")
        return response
    }

    /// Get or create user profile
    /// GET /getUser (requires auth)
    func getUser() async throws -> UserResponse {
        let start = Date()
        let response: UserResponse = try await get(endpoint: "getUser", requiresAuth: true)
        let latency = Date().timeIntervalSince(start) * 1000
        print("[FirebaseAPI] /getUser completed in \(Int(latency))ms")
        return response
    }

    /// Send chat message (echo for now, AI in 1.3)
    /// POST /chat (requires auth)
    func chat(message: String) async throws -> ChatResponse {
        let start = Date()
        let body = ChatRequest(message: message)
        let response: ChatResponse = try await post(endpoint: "chat", body: body, requiresAuth: true)
        let latency = Date().timeIntervalSince(start) * 1000
        print("[FirebaseAPI] /chat completed in \(Int(latency))ms")
        return response
    }

    /// Text-to-speech - returns audio data
    /// POST /tts (requires auth)
    func tts(text: String, voice: String = "nova", speed: Double = 1.0) async throws -> Data {
        let start = Date()
        let body = TTSRequest(text: text, voice: voice, speed: speed)
        let audioData = try await postBinary(endpoint: "tts", body: body, requiresAuth: true)
        let latency = Date().timeIntervalSince(start) * 1000
        print("[FirebaseAPI] /tts completed in \(Int(latency))ms (\(audioData.count) bytes)")
        return audioData
    }

    /// Vision - analyze image with GPT-4o
    /// POST /vision (requires auth)
    func vision(imageBase64: String, prompt: String, model: String = "gpt-4o", jsonMode: Bool = false) async throws -> VisionResponse {
        let start = Date()
        let body = VisionRequest(imageBase64: imageBase64, prompt: prompt, model: model, jsonMode: jsonMode)
        let response: VisionResponse = try await post(endpoint: "vision", body: body, requiresAuth: true)
        let latency = Date().timeIntervalSince(start) * 1000
        print("[FirebaseAPI] /vision completed in \(Int(latency))ms")
        return response
    }

    /// Simple chat completion - no streaming, no tools
    /// POST /chatSimple (requires auth)
    func chatSimple(messages: [[String: String]], model: String = "gpt-4o-mini", temperature: Double = 0.7) async throws -> ChatSimpleResponse {
        let start = Date()
        let body = ChatSimpleRequest(messages: messages, model: model, temperature: temperature)
        let response: ChatSimpleResponse = try await post(endpoint: "chatSimple", body: body, requiresAuth: true)
        let latency = Date().timeIntervalSince(start) * 1000
        print("[FirebaseAPI] /chatSimple completed in \(Int(latency))ms")
        return response
    }

    /// Calculation endpoint - centralized formulas for iOS and web
    /// POST /calculate (requires auth)
    func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
        let start = Date()
        let response: CalculationResponse = try await post(endpoint: "calculate", body: request, requiresAuth: true)
        let latency = Date().timeIntervalSince(start) * 1000
        print("[FirebaseAPI] /calculate completed in \(Int(latency))ms")
        return response
    }

    // MARK: - Plan API

    /// Activate a draft plan
    /// POST /activatePlan (requires auth)
    func activatePlan(planId: String, confirmOverlap: Bool = false) async throws -> PlanActionResponse {
        let start = Date()
        let body = PlanActionRequest(planId: planId, confirmOverlap: confirmOverlap)
        let response: PlanActionResponse = try await post(endpoint: "activatePlan", body: body, requiresAuth: true)
        let latency = Date().timeIntervalSince(start) * 1000
        print("[FirebaseAPI] /activatePlan completed in \(Int(latency))ms")
        return response
    }

    /// Abandon (complete early) an active plan
    /// POST /abandonPlan (requires auth)
    func abandonPlan(planId: String) async throws -> PlanActionResponse {
        let start = Date()
        let body = PlanActionRequest(planId: planId)
        let response: PlanActionResponse = try await post(endpoint: "abandonPlan", body: body, requiresAuth: true)
        let latency = Date().timeIntervalSince(start) * 1000
        print("[FirebaseAPI] /abandonPlan completed in \(Int(latency))ms")
        return response
    }

    /// Delete a plan (cascade deletes programs, workouts)
    /// POST /deletePlan (requires auth)
    func deletePlan(planId: String) async throws -> PlanActionResponse {
        let start = Date()
        let body = PlanActionRequest(planId: planId)
        let response: PlanActionResponse = try await post(endpoint: "deletePlan", body: body, requiresAuth: true)
        let latency = Date().timeIntervalSince(start) * 1000
        print("[FirebaseAPI] /deletePlan completed in \(Int(latency))ms")
        return response
    }

    /// Reschedule a plan to a new start date
    /// POST /reschedulePlan (requires auth)
    func reschedulePlan(planId: String, newStartDate: Date) async throws -> PlanActionResponse {
        let start = Date()
        let formatter = ISO8601DateFormatter()
        let dateString = formatter.string(from: newStartDate)
        let body = PlanActionRequest(planId: planId, newStartDate: dateString)
        let response: PlanActionResponse = try await post(endpoint: "reschedulePlan", body: body, requiresAuth: true)
        let latency = Date().timeIntervalSince(start) * 1000
        print("[FirebaseAPI] /reschedulePlan completed in \(Int(latency))ms")
        return response
    }

    /// Get initial suggestion chips for chat
    /// GET /initialChips (requires auth)
    func initialChips() async throws -> InitialChipsResponse {
        let start = Date()
        let response: InitialChipsResponse = try await get(endpoint: "initialChips", requiresAuth: true)
        let latency = Date().timeIntervalSince(start) * 1000
        print("[FirebaseAPI] /initialChips completed in \(Int(latency))ms (\(response.chips.count) chips)")
        return response
    }

    // MARK: - HTTP Methods

    private func get<T: Decodable>(endpoint: String, requiresAuth: Bool) async throws -> T {
        guard let urlString = endpoints[endpoint],
              let url = URL(string: urlString) else {
            throw FirebaseAPIError.notFound
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if requiresAuth {
            guard let token = authToken else {
                throw FirebaseAPIError.notAuthenticated
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return try await execute(request)
    }

    private func post<T: Decodable, B: Encodable>(endpoint: String, body: B, requiresAuth: Bool) async throws -> T {
        guard let urlString = endpoints[endpoint],
              let url = URL(string: urlString) else {
            throw FirebaseAPIError.notFound
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        if requiresAuth {
            guard let token = authToken else {
                throw FirebaseAPIError.notAuthenticated
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return try await execute(request)
    }

    /// POST that returns binary data (for TTS audio)
    private func postBinary<B: Encodable>(endpoint: String, body: B, requiresAuth: Bool) async throws -> Data {
        guard let urlString = endpoints[endpoint],
              let url = URL(string: urlString) else {
            throw FirebaseAPIError.notFound
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        if requiresAuth {
            guard let token = authToken else {
                throw FirebaseAPIError.notAuthenticated
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirebaseAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            throw FirebaseAPIError.unauthorized
        case 403:
            throw FirebaseAPIError.forbidden
        case 404:
            throw FirebaseAPIError.notFound
        case 500...599:
            throw FirebaseAPIError.serverError(httpResponse.statusCode)
        default:
            throw FirebaseAPIError.httpError(httpResponse.statusCode)
        }
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirebaseAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                print("[FirebaseAPI] Decode error: \(error)")
                print("[FirebaseAPI] Response body: \(String(data: data, encoding: .utf8) ?? "nil")")
                throw FirebaseAPIError.decodingError(error)
            }
        case 401:
            throw FirebaseAPIError.unauthorized
        case 403:
            throw FirebaseAPIError.forbidden
        case 404:
            throw FirebaseAPIError.notFound
        case 500...599:
            throw FirebaseAPIError.serverError(httpResponse.statusCode)
        default:
            throw FirebaseAPIError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Response Types

struct HelloResponse: Codable {
    let message: String
    let timestamp: String
}

struct UserResponse: Codable {
    let uid: String?
    let email: String?
    let displayName: String?
    let profile: [String: String]?  // Simplified for now
    let createdAt: String?
    let updatedAt: String?
}

struct ChatRequest: Codable {
    let message: String
}

struct ChatResponse: Codable {
    let reply: String
    let timestamp: String
}

struct TTSRequest: Codable {
    let text: String
    let voice: String
    let speed: Double
}

struct VisionRequest: Codable {
    let imageBase64: String
    let prompt: String
    let model: String
    let jsonMode: Bool
}

struct VisionResponse: Codable {
    let content: String
}

struct ChatSimpleRequest: Codable {
    let messages: [[String: String]]
    let model: String
    let temperature: Double
}

struct ChatSimpleResponse: Codable {
    let content: String
}

// MARK: - Calculation Types

enum CalculationType: String, Codable {
    case oneRM
    case weightForReps
    case best1RM
    case recency1RM
    case targetWeight
}

struct CalculationSetData: Codable {
    let weight: Double
    let reps: Int
    let setIndex: Int
}

struct CalculationSessionData: Codable {
    let date: String  // ISO8601 format
    let best1RM: Double
}

struct CalculationRequest: Codable {
    let type: CalculationType

    // oneRM
    var weight: Double?
    var reps: Int?

    // weightForReps
    var oneRM: Double?
    var targetReps: Int?

    // best1RM
    var sets: [CalculationSetData]?

    // recency1RM
    var sessions: [CalculationSessionData]?

    // targetWeight
    var exerciseType: String?
    var baseIntensity: Double?
    var intensityOffset: Double?
    var rpe: Int?
    var workingWeight: Double?

    init(type: CalculationType,
         weight: Double? = nil,
         reps: Int? = nil,
         oneRM: Double? = nil,
         targetReps: Int? = nil,
         sets: [CalculationSetData]? = nil,
         sessions: [CalculationSessionData]? = nil,
         exerciseType: String? = nil,
         baseIntensity: Double? = nil,
         intensityOffset: Double? = nil,
         rpe: Int? = nil,
         workingWeight: Double? = nil) {
        self.type = type
        self.weight = weight
        self.reps = reps
        self.oneRM = oneRM
        self.targetReps = targetReps
        self.sets = sets
        self.sessions = sessions
        self.exerciseType = exerciseType
        self.baseIntensity = baseIntensity
        self.intensityOffset = intensityOffset
        self.rpe = rpe
        self.workingWeight = workingWeight
    }
}

struct CalculationResponse: Codable {
    let result: Double?
    let isEstimated: Bool?
    let error: String?

    init(result: Double? = nil, isEstimated: Bool? = nil, error: String? = nil) {
        self.result = result
        self.isEstimated = isEstimated
        self.error = error
    }
}

// MARK: - Plan API Types

struct PlanActionRequest: Codable {
    let planId: String
    var confirmOverlap: Bool?
    var newStartDate: String?  // For reschedule, ISO8601 format

    init(planId: String, confirmOverlap: Bool? = nil, newStartDate: String? = nil) {
        self.planId = planId
        self.confirmOverlap = confirmOverlap
        self.newStartDate = newStartDate
    }
}

/// API response chip (distinct from UI SuggestionChip)
struct APIChip: Codable {
    let label: String
    let command: String
}

struct PlanActionResponse: Codable {
    let success: Bool
    let message: String?
    let suggestionChips: [APIChip]?
    let error: String?
}

struct InitialChipsResponse: Codable {
    let success: Bool
    let greeting: String
    let chips: [APIChip]
}

// MARK: - Errors

enum FirebaseAPIError: LocalizedError {
    case notAuthenticated
    case unauthorized
    case forbidden
    case notFound
    case invalidResponse
    case decodingError(Error)
    case httpError(Int)
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please sign in first."
        case .unauthorized:
            return "Authentication failed. Please sign in again."
        case .forbidden:
            return "Access denied."
        case .notFound:
            return "Endpoint not found."
        case .invalidResponse:
            return "Invalid response from server."
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .serverError(let code):
            return "Server error: \(code)"
        }
    }
}
