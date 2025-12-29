//
// JSONValidator.swift
// Medina
//
// v60.0 - AI Workout Creation: JSON Validation
// v81.0 - AI-first: validateWorkoutIntent now parses exerciseIds from AI
// Two validation paths:
// - validateWorkoutIntent(): Primary path - AI provides exerciseIds
// - validateWorkout(): Flexible path with exercise/protocol validation
// Last reviewed: December 2025
//

import Foundation

/// Validation errors for AI-generated workout JSON
enum WorkoutValidationError: LocalizedError {
    case missingRequiredField(String)
    case invalidExerciseId(String)
    case invalidProtocolId(String)
    case exerciseCountMismatch(expected: Int, actual: Int)
    case invalidSplitDay(String)
    case invalidDate(String)
    case protocolCountMismatch(expected: Int, actual: Int)
    case invalidEffortLevel(String)
    case invalidDuration(Int)
    case dateInPast(String)

    var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidExerciseId(let id):
            return "Exercise ID '\(id)' does not exist in database"
        case .invalidProtocolId(let id):
            return "Protocol ID '\(id)' does not exist in database"
        case .exerciseCountMismatch(let expected, let actual):
            return "Exercise count mismatch: expected \(expected) for this duration, got \(actual)"
        case .invalidSplitDay(let value):
            return "Invalid split day '\(value)'. Must be: upper, lower, push, pull, legs, fullBody, chest, back, shoulders, or arms"
        case .invalidDate(let value):
            return "Invalid date format '\(value)'. Expected ISO8601 (YYYY-MM-DD)"
        case .protocolCountMismatch(let expected, let actual):
            return "Protocol count mismatch: expected \(expected) protocols for \(expected) exercises, got \(actual)"
        case .invalidEffortLevel(let value):
            return "Invalid effort level '\(value)'. Must be: recovery, standard, or push_it"
        case .invalidDuration(let value):
            return "Invalid duration \(value). Must be between 15 and 120 minutes"
        case .dateInPast(let value):
            return "Date '\(value)' is in the past. Please schedule for today or future"
        }
    }

    /// User-friendly error message for AI retry
    var userMessage: String {
        errorDescription ?? "Validation error"
    }
}

/// Validated workout data ready for entity creation
struct ValidatedWorkoutData {
    let name: String
    let splitDay: SplitDay
    let scheduledDate: Date
    let duration: Int
    let effortLevel: EffortLevel
    let exerciseIds: [String]
    let protocolVariantIds: [Int: String]
}

/// Service for validating AI-generated workout JSON
enum JSONValidator {

    // MARK: - v79.1: Flexible Effort Level Parsing

    /// Parse effort level flexibly to handle natural language variations
    /// v82.0: Extended to accept common synonyms (easy, light, normal, hard, intense, etc.)
    private static func parseEffortLevel(_ str: String) -> EffortLevel? {
        switch str.lowercased() {
        // Recovery / Light effort
        case "recovery", "easy", "light", "deload", "warmup", "warm_up":
            return .recovery
        // Standard / Normal effort
        case "standard", "normal", "moderate", "regular", "default":
            return .standard
        // Push It / High effort
        case "push", "pushit", "push_it", "hard", "intense", "challenging", "max", "maximum":
            return .pushIt
        default:
            return nil
        }
    }

    // MARK: - v85.0: Flexible Movement Pattern Parsing

    /// Parse movement pattern flexibly to handle snake_case from AI
    /// AI sends: "horizontal_press", "vertical_pull", etc.
    private static func parseMovementPattern(_ str: String) -> MovementPattern? {
        // Try rawValue first (camelCase: "horizontalPress")
        if let direct = MovementPattern(rawValue: str) { return direct }

        // Try snake_case → camelCase conversion
        switch str.lowercased() {
        case "squat": return .squat
        case "hinge": return .hinge
        case "horizontal_press", "horizontalpress": return .horizontalPress
        case "vertical_press", "verticalpress": return .verticalPress
        case "horizontal_pull", "horizontalpull": return .horizontalPull
        case "vertical_pull", "verticalpull": return .verticalPull
        case "lunge": return .lunge
        case "carry": return .carry
        case "core": return .core
        case "accessory": return .accessory
        case "push": return .push
        case "pull": return .pull
        case "rotation": return .rotation
        case "dynamic": return .dynamic
        case "static_stretch", "staticstretch": return .staticStretch
        default: return nil
        }
    }

    // MARK: - v81.2: Flexible Split Day Parsing

    /// Parse split day flexibly to handle camelCase vs snake_case variations
    /// Tool definition uses "fullBody" but enum rawValue is "full_body"
    private static func parseSplitDay(_ str: String) -> SplitDay? {
        // Try rawValue first (snake_case: "full_body", "not_applicable")
        if let direct = SplitDay(rawValue: str) { return direct }

        // Try camelCase → snake_case conversion
        switch str.lowercased() {
        case "fullbody", "full_body": return .fullBody
        case "notapplicable", "not_applicable": return .notApplicable
        case "upper": return .upper
        case "lower": return .lower
        case "push": return .push
        case "pull": return .pull
        case "legs": return .legs
        case "chest": return .chest
        case "back": return .back
        case "shoulders": return .shoulders
        case "arms": return .arms
        default: return nil
        }
    }

    /// v82.0: Guardrails for duration (any value within range is valid)
    /// DurationAwareWorkoutBuilder dynamically calculates exercise count based on protocols
    private static let minDuration = 15   // Minimum workout duration (quick session)
    private static let maxDuration = 120  // Maximum workout duration (2 hours)

    /// Validate AI-generated workout JSON
    /// - Parameters:
    ///   - json: Raw JSON object from AI tool call
    ///   - userId: User ID for constraint validation
    /// - Returns: Result with validated data or error
    static func validateWorkout(
        json: [String: Any],
        userId: String
    ) -> Result<ValidatedWorkoutData, WorkoutValidationError> {

        // 1. Validate required fields
        guard let name = json["name"] as? String, !name.isEmpty else {
            return .failure(.missingRequiredField("name"))
        }

        guard let splitDayString = json["splitDay"] as? String else {
            return .failure(.missingRequiredField("splitDay"))
        }

        guard let dateString = json["scheduledDate"] as? String else {
            return .failure(.missingRequiredField("scheduledDate"))
        }

        guard let duration = json["duration"] as? Int else {
            return .failure(.missingRequiredField("duration"))
        }

        guard let effortLevelString = json["effortLevel"] as? String else {
            return .failure(.missingRequiredField("effortLevel"))
        }

        guard let exerciseIds = json["exerciseIds"] as? [String] else {
            return .failure(.missingRequiredField("exerciseIds"))
        }

        // 2. Validate split day enum (v81.2: use flexible parser to handle "fullBody" → .fullBody)
        guard let splitDay = parseSplitDay(splitDayString) else {
            return .failure(.invalidSplitDay(splitDayString))
        }

        // 3. Validate effort level enum (v79.1: use flexible parser to handle "push" → pushIt)
        guard let effortLevel = parseEffortLevel(effortLevelString) else {
            return .failure(.invalidEffortLevel(effortLevelString))
        }

        // 4. Validate duration (guardrails, not hardset values)
        guard duration >= minDuration && duration <= maxDuration else {
            return .failure(.invalidDuration(duration))
        }

        // 5. Validate date format and not in past
        // v82.0: Use DateFormatter with local timezone to avoid UTC vs local mismatch
        // ISO8601DateFormatter parses "2025-12-04" as UTC midnight, which can be "yesterday" in local time
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current  // Parse as local midnight, not UTC

        guard let scheduledDate = dateFormatter.date(from: dateString) else {
            return .failure(.invalidDate(dateString))
        }

        // Check date is not in past (allow today)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let scheduleDay = calendar.startOfDay(for: scheduledDate)

        if scheduleDay < today {
            return .failure(.dateInPast(dateString))
        }

        // 6. Validate all exercise IDs exist in database (v102.4: with fuzzy matching)
        // v82.0: Removed exercise count validation - DurationAwareWorkoutBuilder handles this dynamically
        // v102.4: Use fuzzy matching to correct AI typos in exercise IDs
        Logger.log(.info, component: "JSONValidator",
            message: "📝 AI sent exercise IDs: \(exerciseIds)")
        var correctedExerciseIds: [String] = []
        for exerciseId in exerciseIds {
            if let exercise = ExerciseFuzzyMatcher.match(exerciseId) {
                if exercise.id != exerciseId {
                    Logger.log(.info, component: "JSONValidator",
                        message: "✓ Corrected '\(exerciseId)' → '\(exercise.id)'")
                }
                correctedExerciseIds.append(exercise.id)
            } else {
                return .failure(.invalidExerciseId(exerciseId))
            }
        }

        // 8. Parse protocol variant IDs (accept both array and object formats)
        var protocolVariantIds: [Int: String] = [:]

        // Try array format first (what AI naturally sends)
        if let protocolArray = json["protocolVariantIds"] as? [String] {
            for (index, protocolId) in protocolArray.enumerated() {
                protocolVariantIds[index] = protocolId
            }
        }
        // Fall back to object format (backward compatibility)
        else if let protocolObject = json["protocolVariantIds"] as? [String: String] {
            for (positionStr, protocolId) in protocolObject {
                guard let position = Int(positionStr) else {
                    continue
                }
                protocolVariantIds[position] = protocolId
            }
        }
        // Neither format found
        else {
            return .failure(.missingRequiredField("protocolVariantIds"))
        }

        // 9. Validate protocol count matches exercise count
        if protocolVariantIds.count != correctedExerciseIds.count {
            return .failure(.protocolCountMismatch(expected: correctedExerciseIds.count, actual: protocolVariantIds.count))
        }

        // 10. Validate all protocol IDs exist in database (v102.4: with fuzzy matching)
        // v102.4: Use fuzzy matching to correct AI typos in protocol IDs
        var correctedProtocolIds: [Int: String] = [:]
        for (position, protocolId) in protocolVariantIds {
            if let config = ProtocolFuzzyMatcher.match(protocolId) {
                correctedProtocolIds[position] = config.id
            } else {
                return .failure(.invalidProtocolId(protocolId))
            }
        }

        // 11. All validations passed - return validated data
        // v102.4: Use correctedExerciseIds with fuzzy-matched IDs
        let validatedData = ValidatedWorkoutData(
            name: name,
            splitDay: splitDay,
            scheduledDate: scheduledDate,
            duration: duration,
            effortLevel: effortLevel,
            exerciseIds: correctedExerciseIds,
            protocolVariantIds: correctedProtocolIds
        )

        return .success(validatedData)
    }

    // MARK: - v60.0: Intent-Only Validation (Fast Path)

    /// Validate intent-only workout JSON (no exercise IDs)
    /// - Parameters:
    ///   - json: Raw JSON object from AI tool call
    ///   - userId: User ID for constraint validation
    /// - Returns: Result with intent data or error
    static func validateWorkoutIntent(
        json: [String: Any],
        userId: String
    ) -> Result<WorkoutIntentData, WorkoutValidationError> {

        // 1. Validate required fields
        guard let name = json["name"] as? String, !name.isEmpty else {
            return .failure(.missingRequiredField("name"))
        }

        guard let splitDayString = json["splitDay"] as? String else {
            return .failure(.missingRequiredField("splitDay"))
        }

        guard let dateString = json["scheduledDate"] as? String else {
            return .failure(.missingRequiredField("scheduledDate"))
        }

        guard let duration = json["duration"] as? Int else {
            return .failure(.missingRequiredField("duration"))
        }

        guard let effortLevelString = json["effortLevel"] as? String else {
            return .failure(.missingRequiredField("effortLevel"))
        }

        // 2. Validate split day enum (v81.2: use flexible parser to handle "fullBody" → .fullBody)
        guard let splitDay = parseSplitDay(splitDayString) else {
            return .failure(.invalidSplitDay(splitDayString))
        }

        // 3. Validate effort level enum (v79.1: use flexible parser to handle "push" → pushIt)
        guard let effortLevel = parseEffortLevel(effortLevelString) else {
            return .failure(.invalidEffortLevel(effortLevelString))
        }

        // 4. Validate duration (guardrails, not hardset values)
        guard duration >= minDuration && duration <= maxDuration else {
            return .failure(.invalidDuration(duration))
        }

        // 5. Validate date format and not in past
        // v82.0: Use DateFormatter with local timezone to avoid UTC vs local mismatch
        // ISO8601DateFormatter parses "2025-12-04" as UTC midnight, which can be "yesterday" in local time
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current  // Parse as local midnight, not UTC

        guard let scheduledDate = dateFormatter.date(from: dateString) else {
            return .failure(.invalidDate(dateString))
        }

        // Check date is not in past (allow today)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let scheduleDay = calendar.startOfDay(for: scheduledDate)

        if scheduleDay < today {
            return .failure(.dateInPast(dateString))
        }

        // No exercise/protocol validation needed for intent-only path

        // 6. v80.3: Parse optional equipment constraints
        var trainingLocation: TrainingLocation?
        if let locationString = json["trainingLocation"] as? String {
            trainingLocation = TrainingLocation(rawValue: locationString)
        }

        var availableEquipment: Set<Equipment>?
        if let equipmentArray = json["availableEquipment"] as? [String] {
            let parsed = equipmentArray.compactMap { Equipment(rawValue: $0) }
            if !parsed.isEmpty {
                availableEquipment = Set(parsed)
            }
        }

        // 7. v81.0: Parse AI-provided exercise IDs (optional but expected)
        var exerciseIds: [String]?
        if let ids = json["exerciseIds"] as? [String], !ids.isEmpty {
            exerciseIds = ids
        }

        // 8. v81.0: Parse AI's selection reasoning (optional)
        let selectionReasoning = json["selectionReasoning"] as? String

        // 9. v82.4: Parse protocol customizations (optional)
        var protocolCustomizations: [Int: ProtocolCustomization]?
        if let customArray = json["protocolCustomizations"] as? [[String: Any]] {
            var customs: [Int: ProtocolCustomization] = [:]
            for customObj in customArray {
                guard let position = customObj["exercisePosition"] as? Int else { continue }

                let setsAdj = customObj["setsAdjustment"] as? Int ?? 0
                let repsAdj = customObj["repsAdjustment"] as? Int ?? 0
                let restAdj = customObj["restAdjustment"] as? Int ?? 0
                let rationale = customObj["rationale"] as? String

                // Customization clamps values to valid bounds internally
                let customization = ProtocolCustomization(
                    baseProtocolId: "",  // Will be set during workout creation
                    setsAdjustment: setsAdj,
                    repsAdjustment: repsAdj,
                    restAdjustment: restAdj,
                    rationale: rationale
                )

                // Only add if at least one adjustment is non-zero
                if setsAdj != 0 || repsAdj != 0 || restAdj != 0 {
                    customs[position] = customization
                }
            }
            if !customs.isEmpty {
                protocolCustomizations = customs
            }
        }

        // 10. v85.0: Parse movement pattern filter (optional)
        var movementPatternFilter: [MovementPattern]?
        if let patternsArray = json["movementPatterns"] as? [String] {
            let parsed = patternsArray.compactMap { parseMovementPattern($0) }
            if !parsed.isEmpty {
                movementPatternFilter = parsed
                Logger.log(.info, component: "JSONValidator",
                    message: "v85.0: Parsed movementPatterns filter: \(parsed.map { $0.rawValue })")
            }
        }

        // 11. v87.1: Parse protocol ID (optional - applies to ALL exercises)
        // v87.3: Validate that protocolId exists in protocolConfigs before using
        var protocolId: String?
        if let rawProtocolId = json["protocolId"] as? String, !rawProtocolId.isEmpty {
            // Check if this protocol exists
            if TestDataManager.shared.protocolConfigs[rawProtocolId] != nil {
                protocolId = rawProtocolId
                Logger.log(.info, component: "JSONValidator",
                    message: "v87.1: Parsed protocolId for all exercises: \(rawProtocolId)")
            } else {
                // v87.3: Protocol doesn't exist - ignore and let system use default
                Logger.log(.warning, component: "JSONValidator",
                    message: "v87.3: AI sent invalid protocolId '\(rawProtocolId)' - ignoring (will use default)")
            }
        }

        // 12. v101.1: Parse session type (optional - defaults to strength)
        var sessionType: SessionType?
        if let sessionTypeString = json["sessionType"] as? String {
            sessionType = SessionType(rawValue: sessionTypeString)
            if sessionType != nil {
                Logger.log(.info, component: "JSONValidator",
                    message: "v101.1: Parsed sessionType: \(sessionTypeString)")
            }
        }

        // 13. v83.0: Parse superset style and groups (optional)
        var supersetStyle: SupersetStyle?
        if let styleString = json["supersetStyle"] as? String {
            supersetStyle = SupersetStyle(rawValue: styleString)
        }

        var supersetGroups: [SupersetGroupIntent]?
        if let groupsArray = json["supersetGroups"] as? [[String: Any]] {
            var groups: [SupersetGroupIntent] = []
            for groupObj in groupsArray {
                guard let positions = groupObj["positions"] as? [Int],
                      let restBetween = groupObj["restBetween"] as? Int,
                      let restAfter = groupObj["restAfter"] as? Int else {
                    continue
                }
                groups.append(SupersetGroupIntent(
                    positions: positions,
                    restBetween: restBetween,
                    restAfter: restAfter
                ))
            }
            if !groups.isEmpty {
                supersetGroups = groups
            }
        }

        // 14. v103: Parse exercise count override for image-based workout creation
        // v127: IGNORE exerciseCount for home workouts - let duration drive exercise selection
        // This fixes the bug where AI sends exerciseCount:5 for 60min home request → 36min workout
        var exerciseCountOverride: Int?
        if trainingLocation == .home {
            // Home workouts need duration-based calculation, not AI count override
            if let count = json["exerciseCount"] as? Int {
                Logger.log(.warning, component: "JSONValidator",
                    message: "v127: IGNORING exerciseCount \(count) for home workout - using duration-based calculation")
            }
        } else if let count = json["exerciseCount"] as? Int {
            // Validate range (3-12 exercises)
            if count >= 3 && count <= 12 {
                exerciseCountOverride = count
                Logger.log(.info, component: "JSONValidator",
                    message: "v103: Exercise count override: \(count)")
            } else {
                Logger.log(.warning, component: "JSONValidator",
                    message: "v103: Exercise count \(count) out of range (3-12) - ignoring")
            }
        }

        // 15. All validations passed - return intent data
        let intentData = WorkoutIntentData(
            name: name,
            splitDay: splitDay,
            scheduledDate: scheduledDate,
            duration: duration,
            effortLevel: effortLevel,
            sessionType: sessionType,  // v101.1: Cardio vs strength
            trainingLocation: trainingLocation,
            availableEquipment: availableEquipment,
            exerciseIds: exerciseIds,
            selectionReasoning: selectionReasoning,
            protocolCustomizations: protocolCustomizations,
            supersetStyle: supersetStyle,
            supersetGroups: supersetGroups,
            preserveProtocolId: protocolId,  // v87.1: Apply specific protocol to all exercises
            movementPatternFilter: movementPatternFilter,  // v85.0: Movement pattern filtering
            exerciseCountOverride: exerciseCountOverride  // v103: Image extraction override
        )

        return .success(intentData)
    }
}
