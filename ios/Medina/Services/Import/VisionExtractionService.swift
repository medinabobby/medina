//
// VisionExtractionService.swift
// Medina
//
// v79.5: Extract workout data from images using GPT-4o Vision
// Created: December 3, 2025
//
// Supports:
// - Spreadsheet screenshots (1RM tables, workout logs)
// - Workout app screenshots (TrueCoach, etc.)
// - Handwritten logs, gym PR boards, machine displays
//

import Foundation
import UIKit

// MARK: - Vision Extraction Models

/// Source type detected from image
enum ImageSourceType: String, Codable {
    case spreadsheet    // Excel, Google Sheets
    case appScreenshot  // TrueCoach, Strong, etc.
    case handwritten    // Handwritten log
    case prBoard        // Gym PR board
    case machineDisplay // Gym machine display
    case unknown        // Unidentified

    var displayName: String {
        switch self {
        case .spreadsheet: return "Spreadsheet"
        case .appScreenshot: return "App Screenshot"
        case .handwritten: return "Handwritten Log"
        case .prBoard: return "PR Board"
        case .machineDisplay: return "Machine Display"
        case .unknown: return "Image"
        }
    }
}

/// Result from vision extraction
struct VisionExtractionResult {
    let exercises: [ExtractedExercise]
    let dates: [Date]?              // Dates visible in image
    let sourceType: ImageSourceType // Detected source type
    let rawText: String?            // OCR'd text for debugging
    let confidence: Double          // Overall extraction confidence (0-1)
}

/// Exercise data extracted from image
struct ExtractedExercise {
    let name: String                // Raw name from image
    let sets: [ExtractedSet]
    let date: Date?                 // Per-exercise date if available
    let notes: String?              // Protocol notes (RPE, tempo, rest)
}

/// Set data extracted from image
struct ExtractedSet {
    let weight: Double?
    let reps: Int?
    let setNumber: Int?
}

// MARK: - Vision Extraction Service

enum VisionExtractionService {

    // MARK: - Errors

    enum ExtractionError: LocalizedError {
        case imageConversionFailed
        case apiError(String)
        case parseError(String)
        case noDataExtracted

        var errorDescription: String? {
            switch self {
            case .imageConversionFailed:
                return "Failed to convert image for processing"
            case .apiError(let message):
                return "Vision API error: \(message)"
            case .parseError(let message):
                return "Failed to parse extraction result: \(message)"
            case .noDataExtracted:
                return "No workout data could be extracted from the image"
            }
        }
    }

    // MARK: - Main Extraction

    /// Extract workout data from image using GPT-4o Vision
    static func extractWorkoutData(from image: UIImage) async throws -> VisionExtractionResult {
        // 1. Convert image to base64
        guard let imageData = prepareImage(image),
              let base64String = imageData.base64EncodedString().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw ExtractionError.imageConversionFailed
        }

        // 2. Build the prompt
        let prompt = buildExtractionPrompt()

        // 3. Call GPT-4o Vision API
        let response = try await callVisionAPI(base64Image: base64String, prompt: prompt)

        // 4. Parse the response
        let result = try parseExtractionResponse(response)

        Logger.log(.info, component: "VisionExtractionService",
                   message: "Extracted \(result.exercises.count) exercises, confidence: \(result.confidence)")

        return result
    }

    // MARK: - Image Preparation

    /// Resize and compress image for API (max 4MB, reasonable resolution)
    private static func prepareImage(_ image: UIImage) -> Data? {
        // Target max dimension: 2048px (good balance of quality vs API cost)
        let maxDimension: CGFloat = 2048
        var targetImage = image

        // Resize if needed
        if max(image.size.width, image.size.height) > maxDimension {
            let scale = maxDimension / max(image.size.width, image.size.height)
            let newSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )

            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            if let resized = UIGraphicsGetImageFromCurrentImageContext() {
                targetImage = resized
            }
            UIGraphicsEndImageContext()
        }

        // Convert to JPEG with compression
        return targetImage.jpegData(compressionQuality: 0.8)
    }

    // MARK: - Prompt Engineering

    private static func buildExtractionPrompt() -> String {
        """
        Extract workout data from this image. The image may be:
        - A spreadsheet with workout logs or 1RM tracking
        - A screenshot from a workout app (TrueCoach, Strong, etc.)
        - A handwritten workout log
        - A gym PR board or machine display

        Return a JSON object with this exact structure:
        {
            "sourceType": "spreadsheet" | "appScreenshot" | "handwritten" | "prBoard" | "machineDisplay" | "unknown",
            "confidence": 0.0-1.0,
            "rawText": "any text visible in the image",
            "dates": ["YYYY-MM-DD", ...],
            "exercises": [
                {
                    "name": "Exercise Name",
                    "date": "YYYY-MM-DD" or null,
                    "notes": "any protocol notes (RPE, tempo, rest)" or null,
                    "sets": [
                        {
                            "setNumber": 1,
                            "weight": 135.0,
                            "reps": 8
                        }
                    ]
                }
            ]
        }

        Guidelines:
        - Extract ALL exercises visible in the image
        - Weight should be in pounds (convert from kg if needed: kg * 2.205)
        - Include ANY weight/rep data even if incomplete
        - For spreadsheets with columns for different dates, create separate exercises per date
        - Confidence should reflect how clearly readable the data is
        - If no workout data is visible, return empty exercises array with confidence 0

        IMPORTANT: Return ONLY valid JSON, no markdown formatting or explanation.
        """
    }

    // MARK: - Vision API Call

    private static func callVisionAPI(base64Image: String, prompt: String) async throws -> [String: Any] {
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
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)",
                                "detail": "high"
                            ]
                        ]
                    ]
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

    private static func parseExtractionResponse(_ response: [String: Any]) throws -> VisionExtractionResult {
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

        // Parse source type
        let sourceTypeString = extractedData["sourceType"] as? String ?? "unknown"
        let sourceType = ImageSourceType(rawValue: sourceTypeString) ?? .unknown

        // Parse confidence
        let confidence = extractedData["confidence"] as? Double ?? 0.5

        // Parse raw text
        let rawText = extractedData["rawText"] as? String

        // Parse dates
        var dates: [Date]?
        if let dateStrings = extractedData["dates"] as? [String] {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            dates = dateStrings.compactMap { formatter.date(from: $0) }
        }

        // Parse exercises
        var exercises: [ExtractedExercise] = []
        if let exerciseArray = extractedData["exercises"] as? [[String: Any]] {
            for exerciseDict in exerciseArray {
                guard let name = exerciseDict["name"] as? String else { continue }

                // Parse exercise date
                var exerciseDate: Date?
                if let dateString = exerciseDict["date"] as? String {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    exerciseDate = formatter.date(from: dateString)
                }

                // Parse notes
                let notes = exerciseDict["notes"] as? String

                // Parse sets
                var sets: [ExtractedSet] = []
                if let setsArray = exerciseDict["sets"] as? [[String: Any]] {
                    for setDict in setsArray {
                        let weight = setDict["weight"] as? Double
                        let reps = setDict["reps"] as? Int
                        let setNumber = setDict["setNumber"] as? Int

                        // Only add if we have at least weight or reps
                        if weight != nil || reps != nil {
                            sets.append(ExtractedSet(
                                weight: weight,
                                reps: reps,
                                setNumber: setNumber
                            ))
                        }
                    }
                }

                // Only add exercise if it has sets
                if !sets.isEmpty {
                    exercises.append(ExtractedExercise(
                        name: name,
                        sets: sets,
                        date: exerciseDate,
                        notes: notes
                    ))
                }
            }
        }

        // Validate we got something
        if exercises.isEmpty && confidence > 0 {
            throw ExtractionError.noDataExtracted
        }

        return VisionExtractionResult(
            exercises: exercises,
            dates: dates,
            sourceType: sourceType,
            rawText: rawText,
            confidence: confidence
        )
    }
}
