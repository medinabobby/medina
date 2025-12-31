//
// Logger.swift
// Medina
//
// v80.0: Standardized logging for Responses API architecture
//
// ## Console Filtering Guide
//
// Filter in Xcode console with these prefixes:
// - [MEDINA]  - All app logs (verbose, includes debug)
// - [SPINE]   - Critical request flow only (AI → Tool → Response)
//
// ## When to Share Logs with AI
//
// For debugging issues, filter console with [SPINE] and share:
// - User message → API request
// - Tool calls detected
// - Tool execution results
// - Response streaming
//
// This shows the complete AI interaction flow without noise.
//

import Foundation

enum LogLevel: String {
    case debug = "🔍 DEBUG"    // Development details, filtered in release
    case info = "ℹ️ INFO"      // Key milestones and state changes
    case warning = "⚠️ WARNING" // Recoverable issues
    case error = "❌ ERROR"     // Failures requiring attention
    case api = "🌐 API"        // Network requests/responses
    case voice = "🎤 VOICE"    // TTS and speech recognition
    case spine = "🦴 SPINE"    // Critical AI request flow

    var priority: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        case .api: return 1
        case .voice: return 1
        case .spine: return 1
        }
    }
}

class Logger {
    static let shared = Logger()
    private let dateFormatter: DateFormatter

    // MARK: - Configuration

    /// Unique prefix for filtering Medina logs in Xcode console
    private static let prefix = "[MEDINA]"

    /// Spine prefix for filtering critical request flow
    /// Filter in Xcode console with: [SPINE]
    private static let spinePrefix = "[SPINE]"

    /// Detect if running in debug build
    private static let isDebugBuild: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// Minimum log level to display (DEBUG in debug builds, INFO in release)
    private static let minimumLogLevel: LogLevel = isDebugBuild ? .debug : .info

    /// v80.0: Components included in spine logging
    /// These are the critical path components for debugging AI request flow
    private static let spineComponents: Set<String> = [
        // v80.0: Responses API architecture
        "ResponsesManager",
        "ResponsesAPIClient",
        "ResponseStreamProcessor",
        "ChatViewModel",
        // v236: Tool handlers now on Firebase server
        "LibraryProtocolSelector",
        // Legacy (deprecated)
        "AssistantManager",
        "StreamProcessor"
    ]

    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }

    // MARK: - Log Level Filtering

    private static func shouldLog(_ level: LogLevel) -> Bool {
        return level.priority >= minimumLogLevel.priority
    }

    private static func isSpineComponent(_ component: String) -> Bool {
        return spineComponents.contains(component)
    }

    // MARK: - Core Logging

    static func log(_ level: LogLevel, component: String, message: String, data: Any? = nil) {
        guard shouldLog(level) else { return }

        let timestamp = Logger.shared.dateFormatter.string(from: Date())

        print("\n\(prefix) [\(timestamp)] \(level.rawValue) - \(component)")
        print("\(prefix) Message: \(message)")

        if let data = data {
            print("\(prefix) Data: \(data)")
        }
        print("\(prefix) ---")

        // v66.4: Also log to spine if this is a spine component
        if isSpineComponent(component) {
            printSpine(timestamp: timestamp, component: component, message: message)
        }
    }

    // MARK: - Spine Logging (v66.4)
    // Filter in Xcode console with: [SPINE]
    // Shows critical request flow: API → Stream → Tool → Response

    /// Log to spine output (filterable with [SPINE] in Xcode console)
    static func spine(_ component: String, _ message: String) {
        guard shouldLog(.spine) else { return }
        let timestamp = Logger.shared.dateFormatter.string(from: Date())
        printSpine(timestamp: timestamp, component: component, message: message)
    }

    private static func printSpine(timestamp: String, component: String, message: String) {
        print("\(spinePrefix) [\(timestamp)] \(component): \(message)")
    }

    /// v66.4: Log API error with FULL response body - critical for debugging
    /// Always logs regardless of level since API errors are always important
    static func apiError(endpoint: String, statusCode: Int, body: String?, error: Error? = nil) {
        let timestamp = Logger.shared.dateFormatter.string(from: Date())

        print("\n\(prefix) ❌ API ERROR [\(timestamp)]")
        print("\(prefix) Endpoint: \(endpoint)")
        print("\(prefix) Status: \(statusCode)")

        if let body = body, !body.isEmpty {
            print("\(prefix) Response Body: \(body)")
        }

        if let error = error {
            print("\(prefix) Error: \(error.localizedDescription)")
        }
        print("\(prefix) ---")

        // Always log API errors to spine
        let spineMsg = "HTTP \(statusCode) - \(body ?? "no body")"
        printSpine(timestamp: timestamp, component: "API", message: spineMsg)
    }
    
    // MARK: - Voice Interaction Logging (v13.7.3.3)

    static func voice(_ interaction: String) {
        guard shouldLog(.voice) else { return }

        let timestamp = Logger.shared.dateFormatter.string(from: Date())
        print("\(prefix) [\(timestamp)] 🎤 VOICE: \(interaction)")
    }
    
    static func voiceUser(_ transcript: String) {
        voice("User: \"\(transcript)\"")
    }
    
    static func voiceParsed(reps: Int?, weight: Double?, raw: String) {
        let repsText = reps != nil ? "\(reps!) reps" : "no reps"
        let weightText = weight != nil ? "\(String(format: "%.1f", weight!)) lbs" : "no weight"
        voice("Parsed: \(repsText), \(weightText)")
    }
    
    static func voiceSpeaking(_ text: String) {
        voice("Speaking: \"\(text)\"")
    }
    
    static func voiceSetLogged(reps: Int, weight: Double) {
        voice("Set logged: \(reps) reps @ \(String(format: "%.1f", weight)) lbs")
    }
    
    static func voiceError(_ error: String) {
        voice("ERROR: \(error)")
    }
    
    // MARK: - API Logging (Existing)

    static func logAPIRequest(endpoint: String, payload: Any) {
        guard shouldLog(.api) else { return }

        print("\n\(prefix) 🚀 API REQUEST [\(Logger.shared.dateFormatter.string(from: Date()))]")
        print("\(prefix) Endpoint: \(endpoint)")
        print("\(prefix) Payload:")
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            // Add prefix to each line of JSON output
            let prefixedJSON = jsonString.split(separator: "\n").map { "\(prefix) \($0)" }.joined(separator: "\n")
            print(prefixedJSON)
        } else {
            print("\(prefix) \(payload)")
        }
        print("\(prefix) ---")
    }

    static func logAPIResponse(endpoint: String, response: Any, duration: TimeInterval) {
        guard shouldLog(.api) else { return }

        print("\n\(prefix) ✅ API RESPONSE [\(Logger.shared.dateFormatter.string(from: Date()))]")
        print("\(prefix) Endpoint: \(endpoint)")
        print("\(prefix) Duration: \(String(format: "%.2f", duration))s")
        print("\(prefix) Response:")
        if let jsonData = try? JSONSerialization.data(withJSONObject: response, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            // Add prefix to each line of JSON output
            let prefixedJSON = jsonString.split(separator: "\n").map { "\(prefix) \($0)" }.joined(separator: "\n")
            print(prefixedJSON)
        } else {
            print("\(prefix) \(response)")
        }
        print("\(prefix) ---")
    }

    static func logAPIError(endpoint: String, error: Error, payload: Any? = nil) {
        guard shouldLog(.error) else { return }

        print("\n\(prefix) ❌ API ERROR [\(Logger.shared.dateFormatter.string(from: Date()))]")
        print("\(prefix) Endpoint: \(endpoint)")
        print("\(prefix) Error: \(error.localizedDescription)")
        if let payload = payload {
            print("\(prefix) Original Payload:")
            print("\(prefix) \(payload)")
        }
        print("\(prefix) ---")
    }

    // MARK: - UserContext Logging (v15.0)

    static func log(_ level: LogLevel, component: String, userContext: UserContext, message: String, data: Any? = nil) {
        let prefix = userContext.logPrefix
        log(level, component: component, message: "\(prefix) \(message)", data: data)
    }
}
