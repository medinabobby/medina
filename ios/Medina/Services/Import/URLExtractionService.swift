//
// URLExtractionService.swift
// Medina
//
// v106: Extract workout/plan data from URLs using GPT-4
// Created: December 10, 2025
//
// Supports:
// - Fitness articles (T-Nation, Bodybuilding.com, etc.)
// - Reddit posts (r/Fitness, r/weightroom)
// - Blog posts with workout programs
// - YouTube video descriptions
//

import Foundation

// MARK: - URL Extraction Models

/// Source type detected from URL
enum URLSourceType: String, Codable {
    case article        // Fitness article/blog post
    case reddit         // Reddit post
    case youtube        // YouTube video description
    case forum          // Forum post
    case socialMedia    // Instagram, Twitter, etc.
    case unknown        // Unidentified

    var displayName: String {
        switch self {
        case .article: return "Article"
        case .reddit: return "Reddit Post"
        case .youtube: return "YouTube"
        case .forum: return "Forum Post"
        case .socialMedia: return "Social Media"
        case .unknown: return "Webpage"
        }
    }
}

/// Result from URL extraction
struct URLExtractionResult {
    let programName: String?            // Name of the program (e.g., "Reddit PPL")
    let description: String?            // Program description/summary
    let exercises: [ExtractedExercise]  // Reuse from VisionExtractionService
    let weeklySchedule: [String]?       // e.g., ["Push", "Pull", "Legs", "Push", "Pull", "Legs", "Rest"]
    let duration: Int?                  // Program duration in weeks
    let sourceType: URLSourceType       // Detected source type
    let sourceTitle: String?            // Page title
    let confidence: Double              // Overall extraction confidence (0-1)
    let rawText: String?                // Extracted text for debugging
}

// MARK: - URL Extraction Service

enum URLExtractionService {

    // MARK: - Errors

    enum ExtractionError: LocalizedError {
        case invalidURL
        case fetchFailed(String)
        case apiError(String)
        case parseError(String)
        case noDataExtracted

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL provided"
            case .fetchFailed(let message):
                return "Failed to fetch URL: \(message)"
            case .apiError(let message):
                return "AI extraction error: \(message)"
            case .parseError(let message):
                return "Failed to parse extraction result: \(message)"
            case .noDataExtracted:
                return "No workout data could be extracted from the page"
            }
        }
    }

    // MARK: - Main Extraction

    /// Extract workout/plan data from URL using GPT-4
    static func extractProgramData(from urlString: String) async throws -> URLExtractionResult {
        // 1. Validate URL
        guard let url = URL(string: urlString) else {
            throw ExtractionError.invalidURL
        }

        // 2. Fetch and parse HTML
        let (content, title, sourceType) = try await fetchAndParseURL(url)

        // 3. Build the prompt
        let prompt = buildExtractionPrompt(content: content, sourceType: sourceType)

        // 4. Call GPT-4 API
        let response = try await callExtractionAPI(prompt: prompt)

        // 5. Parse the response
        let result = try parseExtractionResponse(response, sourceType: sourceType, sourceTitle: title, rawText: content)

        Logger.log(.info, component: "URLExtractionService",
                   message: "Extracted program '\(result.programName ?? "Unknown")' with \(result.exercises.count) exercises")

        return result
    }

    // MARK: - URL Fetching

    private static func fetchAndParseURL(_ url: URL) async throws -> (content: String, title: String?, sourceType: URLSourceType) {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExtractionError.fetchFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw ExtractionError.fetchFailed("HTTP \(httpResponse.statusCode)")
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw ExtractionError.fetchFailed("Could not decode response")
        }

        // Detect source type from URL
        let sourceType = detectSourceType(url)

        // Extract title from HTML
        let title = extractTitle(from: html)

        // Strip HTML to get clean text
        let content = stripHTML(html)

        // Truncate to reasonable length for API (max ~15k chars)
        let truncatedContent = String(content.prefix(15000))

        Logger.log(.debug, component: "URLExtractionService",
                   message: "Fetched \(truncatedContent.count) chars from \(sourceType.displayName)")

        return (truncatedContent, title, sourceType)
    }

    private static func detectSourceType(_ url: URL) -> URLSourceType {
        let host = url.host?.lowercased() ?? ""

        if host.contains("reddit.com") || host.contains("redd.it") {
            return .reddit
        } else if host.contains("youtube.com") || host.contains("youtu.be") {
            return .youtube
        } else if host.contains("t-nation") || host.contains("bodybuilding.com") ||
                    host.contains("muscleandstrength") || host.contains("strongerbyscience") {
            return .article
        } else if host.contains("instagram") || host.contains("twitter") || host.contains("x.com") {
            return .socialMedia
        } else {
            return .unknown
        }
    }

    private static func extractTitle(from html: String) -> String? {
        // Simple title extraction
        if let titleRange = html.range(of: "<title>"),
           let titleEndRange = html.range(of: "</title>", range: titleRange.upperBound..<html.endIndex) {
            let title = String(html[titleRange.upperBound..<titleEndRange.lowerBound])
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func stripHTML(_ html: String) -> String {
        var text = html

        // Remove script and style blocks
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)

        // Remove HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")

        // Collapse whitespace
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompt Engineering

    private static func buildExtractionPrompt(content: String, sourceType: URLSourceType) -> String {
        """
        Extract workout program data from this \(sourceType.displayName.lowercased()) content.

        CONTENT:
        \(content)

        Return a JSON object with this exact structure:
        {
            "programName": "Name of the program (e.g., 'Reddit PPL', 'PHUL', '5/3/1')" or null,
            "description": "Brief program description/goals" or null,
            "confidence": 0.0-1.0,
            "duration": number of weeks or null,
            "weeklySchedule": ["Day1", "Day2", ...] or null,
            "exercises": [
                {
                    "name": "Exercise Name",
                    "day": "Push" or "Day 1" or null,
                    "notes": "3x8-12, RPE 8" or null,
                    "sets": [
                        {
                            "setNumber": 1,
                            "reps": 8,
                            "weight": null
                        }
                    ]
                }
            ]
        }

        Guidelines:
        - Extract ALL exercises mentioned in the program
        - For "3x8-12" format: create 3 sets with reps=10 (midpoint)
        - For "5x5" format: create 5 sets with reps=5
        - Weight is usually not specified in programs - leave as null
        - Include day/split information if available (Push/Pull/Legs, Upper/Lower, etc.)
        - programName should capture the program's actual name if mentioned
        - weeklySchedule should show the training split (e.g., ["Push", "Pull", "Legs", "Rest", "Push", "Pull", "Legs"])
        - Confidence reflects how clearly the program is structured (0.9+ for well-defined programs)
        - If this is NOT a workout program, return empty exercises array with confidence 0

        IMPORTANT: Return ONLY valid JSON, no markdown formatting or explanation.
        """
    }

    // MARK: - API Call

    private static func callExtractionAPI(prompt: String) async throws -> [String: Any] {
        let apiKey = Config.openAIKey
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "system",
                    "content": "You are a fitness program analyzer. Extract structured workout data from webpage content. Return only valid JSON."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "max_tokens": 4096,
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExtractionError.apiError("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ExtractionError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExtractionError.parseError("Invalid JSON response")
        }

        return json
    }

    // MARK: - Response Parsing

    private static func parseExtractionResponse(
        _ response: [String: Any],
        sourceType: URLSourceType,
        sourceTitle: String?,
        rawText: String
    ) throws -> URLExtractionResult {
        // Extract content from OpenAI response structure
        guard let choices = response["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ExtractionError.parseError("Could not extract content from response")
        }

        // Parse the JSON content
        guard let contentData = content.data(using: .utf8),
              let extractedData = try JSONSerialization.jsonObject(with: contentData) as? [String: Any] else {
            throw ExtractionError.parseError("Could not parse content JSON")
        }

        // Parse program info
        let programName = extractedData["programName"] as? String
        let description = extractedData["description"] as? String
        let confidence = extractedData["confidence"] as? Double ?? 0.5
        let duration = extractedData["duration"] as? Int
        let weeklySchedule = extractedData["weeklySchedule"] as? [String]

        // Parse exercises
        var exercises: [ExtractedExercise] = []
        if let exerciseArray = extractedData["exercises"] as? [[String: Any]] {
            for exerciseDict in exerciseArray {
                guard let name = exerciseDict["name"] as? String else { continue }

                let notes = exerciseDict["notes"] as? String
                let day = exerciseDict["day"] as? String

                // Combine day and notes
                var fullNotes = notes
                if let day = day {
                    fullNotes = fullNotes != nil ? "\(day): \(fullNotes!)" : day
                }

                // Parse sets
                var sets: [ExtractedSet] = []
                if let setsArray = exerciseDict["sets"] as? [[String: Any]] {
                    for setDict in setsArray {
                        let weight = setDict["weight"] as? Double
                        let reps = setDict["reps"] as? Int
                        let setNumber = setDict["setNumber"] as? Int

                        sets.append(ExtractedSet(
                            weight: weight,
                            reps: reps,
                            setNumber: setNumber
                        ))
                    }
                }

                // Add exercise even if sets are empty (we have the prescription in notes)
                exercises.append(ExtractedExercise(
                    name: name,
                    sets: sets,
                    date: nil,
                    notes: fullNotes
                ))
            }
        }

        // Validate we got something
        if exercises.isEmpty && confidence > 0.3 {
            throw ExtractionError.noDataExtracted
        }

        return URLExtractionResult(
            programName: programName,
            description: description,
            exercises: exercises,
            weeklySchedule: weeklySchedule,
            duration: duration,
            sourceType: sourceType,
            sourceTitle: sourceTitle,
            confidence: confidence,
            rawText: String(rawText.prefix(500))  // Truncate for storage
        )
    }
}
