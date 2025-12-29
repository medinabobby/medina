import Foundation

/// REST client for Firebase Functions
/// Release 1.2: Validates iOS can communicate with Firebase backend
actor FirebaseAPIClient {

    // MARK: - Configuration

    // Cloud Run Gen 2 function URLs
    private let endpoints: [String: String] = [
        "hello": "https://hello-dpkc2km3oa-uc.a.run.app",
        "chat": "https://chat-dpkc2km3oa-uc.a.run.app",
        "getUser": "https://getuser-dpkc2km3oa-uc.a.run.app"
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
