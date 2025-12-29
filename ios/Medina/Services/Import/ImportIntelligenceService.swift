//
// ImportIntelligenceService.swift
// Medina
//
// v75.0: Intelligence extraction from imported workout data
// Infers experience level, training style, muscle preferences from import history
// Created: December 2, 2025
//

import Foundation

// MARK: - Result Models

/// Intelligence extracted from imported workout data
struct ImportIntelligence: Codable {
    let inferredExperience: ExperienceLevel?
    let trainingStyle: InferredTrainingStyle?
    let topMuscleGroups: Set<MuscleGroup>
    let avoidedMuscles: Set<MuscleGroup>
    let inferredSplit: SplitType?
    let estimatedSessionDuration: Int
    let confidenceScore: Double  // 0-1, how reliable is this inference?
    let indicators: ExperienceIndicators
}

/// Detailed breakdown of experience level indicators
struct ExperienceIndicators: Codable {
    var strengthScore: Double?      // 0-3 scale based on relative strength
    var historyScore: Double?       // 0-3 based on months trained
    var volumeScore: Double?        // 0-3 based on avg sets/session
    var varietyScore: Double?       // 0-3 based on unique exercises

    /// Compute final experience level from weighted indicators
    func computeFinalLevel() -> ExperienceLevel {
        // Weights: strength 40%, history 30%, volume 20%, variety 10%
        var totalWeight = 0.0
        var weightedSum = 0.0

        if let s = strengthScore {
            weightedSum += s * 0.4
            totalWeight += 0.4
        }
        if let h = historyScore {
            weightedSum += h * 0.3
            totalWeight += 0.3
        }
        if let v = volumeScore {
            weightedSum += v * 0.2
            totalWeight += 0.2
        }
        if let variety = varietyScore {
            weightedSum += variety * 0.1
            totalWeight += 0.1
        }

        guard totalWeight > 0 else { return .beginner }
        let finalScore = weightedSum / totalWeight

        // Map 0-3 score to experience level
        switch finalScore {
        case 0..<1.0: return .beginner
        case 1.0..<2.0: return .intermediate
        case 2.0..<2.75: return .advanced
        default: return .expert
        }
    }
}

/// Training style inferred from exercise selection and patterns
/// Indicates powerlifting/bodybuilding/hybrid focus based on import history
enum InferredTrainingStyle: String, Codable {
    case powerlifting
    case bodybuilding
    case hybrid
    case generalFitness

    var displayName: String {
        switch self {
        case .powerlifting: return "Powerlifting"
        case .bodybuilding: return "Bodybuilding"
        case .hybrid: return "Hybrid/Strength"
        case .generalFitness: return "General Fitness"
        }
    }
}

// MARK: - Service

struct ImportIntelligenceService {

    // MARK: - Main Analysis

    /// Extract intelligence from imported workout data
    @MainActor
    static func analyze(
        importData: ImportedWorkoutData,
        userWeight: Double?
    ) -> ImportIntelligence {

        // 1. Build experience indicators
        let indicators = buildExperienceIndicators(
            exercises: importData.exercises,
            sessions: importData.sessions,
            dateRange: importData.dateRange,
            userWeight: userWeight
        )

        // 2. Infer training style
        let trainingStyle = inferTrainingStyle(
            exercises: importData.exercises,
            sessions: importData.sessions
        )

        // 3. Analyze muscle groups
        let topMuscles = inferEmphasizedMuscles(from: importData.exercises)
        let avoidedMuscles = inferAvoidedMuscles(from: importData.exercises)

        // 4. Detect split type
        let inferredSplit = inferSplitType(from: importData.sessions)

        // 5. Estimate session duration
        let sessionDuration = estimateSessionDuration(from: importData.sessions)

        // 6. Calculate confidence
        let confidence = calculateConfidence(
            sessionCount: importData.sessionCount,
            exerciseCount: importData.exercises.count,
            hasWeightData: userWeight != nil
        )

        Logger.log(.info, component: "ImportIntelligence",
                   message: "Analyzed import: exp=\(indicators.computeFinalLevel().displayName), style=\(trainingStyle?.displayName ?? "unknown"), confidence=\(String(format: "%.2f", confidence))")

        return ImportIntelligence(
            inferredExperience: indicators.computeFinalLevel(),
            trainingStyle: trainingStyle,
            topMuscleGroups: topMuscles,
            avoidedMuscles: avoidedMuscles,
            inferredSplit: inferredSplit,
            estimatedSessionDuration: sessionDuration,
            confidenceScore: confidence,
            indicators: indicators
        )
    }

    // MARK: - Experience Indicators

    private static func buildExperienceIndicators(
        exercises: [ImportedExerciseData],
        sessions: [ImportedSession],
        dateRange: (start: Date, end: Date)?,
        userWeight: Double?
    ) -> ExperienceIndicators {
        var indicators = ExperienceIndicators()

        // 1. Strength score (relative or absolute)
        indicators.strengthScore = calculateStrengthScore(exercises: exercises, userWeight: userWeight)

        // 2. History score (months of training)
        if let range = dateRange {
            indicators.historyScore = calculateHistoryScore(dateRange: range)
        }

        // 3. Volume score (sets per session)
        if !sessions.isEmpty {
            indicators.volumeScore = calculateVolumeScore(sessions: sessions)
        }

        // 4. Variety score (unique exercises)
        indicators.varietyScore = calculateVarietyScore(exerciseCount: exercises.count)

        return indicators
    }

    // MARK: - Strength Score

    /// Calculate strength score from exercise maxes (relative to bodyweight if available)
    private static func calculateStrengthScore(exercises: [ImportedExerciseData], userWeight: Double?) -> Double? {
        // Find big 3 lifts
        let squatMax = findExerciseMax(exercises, matching: ["squat", "back squat", "front squat"])
        let benchMax = findExerciseMax(exercises, matching: ["bench press", "bench", "flat bench"])
        let deadliftMax = findExerciseMax(exercises, matching: ["deadlift", "conventional deadlift", "sumo deadlift"])

        // If we have bodyweight, use relative strength standards
        if let weight = userWeight, weight > 0 {
            return calculateRelativeStrengthScore(
                squatMax: squatMax,
                benchMax: benchMax,
                deadliftMax: deadliftMax,
                bodyweight: weight
            )
        }

        // Fallback to absolute strength (less accurate)
        return calculateAbsoluteStrengthScore(
            squatMax: squatMax,
            benchMax: benchMax,
            deadliftMax: deadliftMax
        )
    }

    /// Find max 1RM for exercises matching keywords
    private static func findExerciseMax(_ exercises: [ImportedExerciseData], matching keywords: [String]) -> Double? {
        let matches = exercises.filter { exercise in
            let name = exercise.exerciseName.lowercased()
            return keywords.contains { name.contains($0.lowercased()) }
        }
        return matches.compactMap { $0.effectiveMax }.max()
    }

    /// Relative strength scoring (ratio to bodyweight)
    /// Standards based on typical strength levels for adult males
    /// Adjusted for population averages, not competition standards
    private static func calculateRelativeStrengthScore(
        squatMax: Double?,
        benchMax: Double?,
        deadliftMax: Double?,
        bodyweight: Double
    ) -> Double? {
        var scores: [Double] = []

        // Squat standards: <1x=beginner, 1-1.5x=intermediate, 1.5-2x=advanced, >2x=expert
        if let squat = squatMax {
            let ratio = squat / bodyweight
            scores.append(scoreForSquatRatio(ratio))
        }

        // Bench standards: <0.75x=beginner, 0.75-1.25x=intermediate, 1.25-1.75x=advanced, >1.75x=expert
        if let bench = benchMax {
            let ratio = bench / bodyweight
            scores.append(scoreForBenchRatio(ratio))
        }

        // Deadlift standards: <1.25x=beginner, 1.25-2x=intermediate, 2-2.75x=advanced, >2.75x=expert
        if let deadlift = deadliftMax {
            let ratio = deadlift / bodyweight
            scores.append(scoreForDeadliftRatio(ratio))
        }

        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private static func scoreForSquatRatio(_ ratio: Double) -> Double {
        switch ratio {
        case ..<1.0: return 0.5
        case 1.0..<1.5: return 1.5
        case 1.5..<2.0: return 2.5
        default: return 3.0
        }
    }

    private static func scoreForBenchRatio(_ ratio: Double) -> Double {
        switch ratio {
        case ..<0.75: return 0.5
        case 0.75..<1.25: return 1.5
        case 1.25..<1.75: return 2.5
        default: return 3.0
        }
    }

    private static func scoreForDeadliftRatio(_ ratio: Double) -> Double {
        switch ratio {
        case ..<1.25: return 0.5
        case 1.25..<2.0: return 1.5
        case 2.0..<2.75: return 2.5
        default: return 3.0
        }
    }

    /// Absolute strength scoring (when bodyweight unavailable)
    /// Uses general population averages for adult males
    private static func calculateAbsoluteStrengthScore(
        squatMax: Double?,
        benchMax: Double?,
        deadliftMax: Double?
    ) -> Double? {
        var scores: [Double] = []

        // Squat: <135=beginner, 135-225=intermediate, 225-315=advanced, >315=expert
        if let squat = squatMax {
            scores.append(scoreForAbsoluteSquat(squat))
        }

        // Bench: <135=beginner, 135-185=intermediate, 185-275=advanced, >275=expert
        if let bench = benchMax {
            scores.append(scoreForAbsoluteBench(bench))
        }

        // Deadlift: <185=beginner, 185-315=intermediate, 315-405=advanced, >405=expert
        if let deadlift = deadliftMax {
            scores.append(scoreForAbsoluteDeadlift(deadlift))
        }

        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private static func scoreForAbsoluteSquat(_ weight: Double) -> Double {
        switch weight {
        case ..<135: return 0.5
        case 135..<225: return 1.5
        case 225..<315: return 2.5
        default: return 3.0
        }
    }

    private static func scoreForAbsoluteBench(_ weight: Double) -> Double {
        switch weight {
        case ..<135: return 0.5
        case 135..<185: return 1.5
        case 185..<275: return 2.5
        default: return 3.0
        }
    }

    private static func scoreForAbsoluteDeadlift(_ weight: Double) -> Double {
        switch weight {
        case ..<185: return 0.5
        case 185..<315: return 1.5
        case 315..<405: return 2.5
        default: return 3.0
        }
    }

    // MARK: - History Score

    private static func calculateHistoryScore(dateRange: (start: Date, end: Date)) -> Double {
        let months = Calendar.current.dateComponents([.month], from: dateRange.start, to: dateRange.end).month ?? 0

        switch months {
        case ..<6: return 0.5      // < 6 months = beginner
        case 6..<18: return 1.5    // 6-18 months = intermediate
        case 18..<36: return 2.5   // 18-36 months = advanced
        default: return 3.0        // > 3 years = expert
        }
    }

    // MARK: - Volume Score

    private static func calculateVolumeScore(sessions: [ImportedSession]) -> Double {
        guard !sessions.isEmpty else { return 0.5 }

        let totalSets = sessions.flatMap { $0.exercises.flatMap { $0.sets } }.count
        let avgSetsPerSession = Double(totalSets) / Double(sessions.count)

        switch avgSetsPerSession {
        case ..<12: return 0.5      // < 12 sets/session = beginner volume
        case 12..<20: return 1.5    // 12-20 = intermediate
        case 20..<30: return 2.5    // 20-30 = advanced
        default: return 3.0         // > 30 = expert/bodybuilder
        }
    }

    // MARK: - Variety Score

    private static func calculateVarietyScore(exerciseCount: Int) -> Double {
        switch exerciseCount {
        case ..<15: return 0.5      // < 15 exercises = limited
        case 15..<30: return 1.5    // 15-30 = intermediate
        case 30..<50: return 2.5    // 30-50 = advanced
        default: return 3.0         // > 50 = expert
        }
    }

    // MARK: - Training Style Inference

    private static func inferTrainingStyle(
        exercises: [ImportedExerciseData],
        sessions: [ImportedSession]
    ) -> InferredTrainingStyle? {
        guard !exercises.isEmpty else { return nil }

        // Count "big 3" exercises (squat, bench, deadlift)
        let big3Keywords = ["squat", "bench", "deadlift"]
        let big3Count = exercises.filter { exercise in
            let name = exercise.exerciseName.lowercased()
            return big3Keywords.contains { name.contains($0) }
        }.count
        let big3Percentage = Double(big3Count) / Double(exercises.count)

        // Count isolation exercises (typically single-joint movements)
        let isolationKeywords = ["curl", "extension", "raise", "fly", "flye", "kickback", "pushdown", "pulldown", "lateral"]
        let isolationCount = exercises.filter { exercise in
            let name = exercise.exerciseName.lowercased()
            return isolationKeywords.contains { name.contains($0) }
        }.count
        let isolationPercentage = Double(isolationCount) / Double(exercises.count)

        // Calculate average reps (if session data available)
        var avgReps = 8.0  // Default mid-range
        if !sessions.isEmpty {
            let allSets = sessions.flatMap { $0.exercises.flatMap { $0.sets } }
            if !allSets.isEmpty {
                avgReps = Double(allSets.map { $0.reps }.reduce(0, +)) / Double(allSets.count)
            }
        }

        // Determine style
        if big3Percentage > 0.4 && avgReps < 6 {
            return .powerlifting
        } else if isolationPercentage > 0.4 && avgReps > 8 {
            return .bodybuilding
        } else if exercises.count > 20 && big3Percentage > 0.15 {
            return .hybrid
        } else {
            return .generalFitness
        }
    }

    // MARK: - Muscle Group Analysis

    @MainActor
    private static func inferEmphasizedMuscles(from exercises: [ImportedExerciseData]) -> Set<MuscleGroup> {
        var muscleFrequency: [MuscleGroup: Int] = [:]

        for exercise in exercises {
            // Try to match exercise to database to get muscle groups
            if let exerciseId = exercise.matchedExerciseId,
               let exerciseData = TestDataManager.shared.exercises[exerciseId] {
                for muscle in exerciseData.muscleGroups {
                    muscleFrequency[muscle, default: 0] += 1
                }
            } else {
                // Infer from exercise name if not matched
                let inferredMuscles = inferMuscleGroupsFromName(exercise.exerciseName)
                for muscle in inferredMuscles {
                    muscleFrequency[muscle, default: 0] += 1
                }
            }
        }

        // Get top 3 most frequent (excluding fullBody)
        let top3 = muscleFrequency
            .filter { $0.key != .fullBody }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }

        return Set(top3)
    }

    private static func inferMuscleGroupsFromName(_ name: String) -> [MuscleGroup] {
        let lowercased = name.lowercased()
        var muscles: [MuscleGroup] = []

        // Chest
        if lowercased.contains("bench") || lowercased.contains("chest") || lowercased.contains("fly") || lowercased.contains("press") && lowercased.contains("chest") {
            muscles.append(.chest)
        }

        // Back
        if lowercased.contains("row") || lowercased.contains("pull") || lowercased.contains("lat") || lowercased.contains("back") {
            muscles.append(.back)
        }

        // Shoulders
        if lowercased.contains("shoulder") || lowercased.contains("delt") || lowercased.contains("overhead") || lowercased.contains("lateral raise") {
            muscles.append(.shoulders)
        }

        // Legs
        if lowercased.contains("squat") || lowercased.contains("leg") || lowercased.contains("lunge") || lowercased.contains("calf") {
            if lowercased.contains("quad") { muscles.append(.quadriceps) }
            else if lowercased.contains("ham") { muscles.append(.hamstrings) }
            else if lowercased.contains("glute") { muscles.append(.glutes) }
            else if lowercased.contains("calf") || lowercased.contains("calves") { muscles.append(.calves) }
            else { muscles.append(.quadriceps) } // Default leg to quads
        }

        // Arms
        if lowercased.contains("bicep") || lowercased.contains("curl") {
            muscles.append(.biceps)
        }
        if lowercased.contains("tricep") || lowercased.contains("pushdown") || lowercased.contains("extension") && lowercased.contains("tricep") {
            muscles.append(.triceps)
        }

        // Core
        if lowercased.contains("core") || lowercased.contains("ab") || lowercased.contains("plank") || lowercased.contains("crunch") {
            muscles.append(.core)
        }

        // Deadlift is posterior chain
        if lowercased.contains("deadlift") {
            muscles.append(contentsOf: [.back, .hamstrings, .glutes])
        }

        return muscles
    }

    @MainActor
    private static func inferAvoidedMuscles(from exercises: [ImportedExerciseData]) -> Set<MuscleGroup> {
        // Only flag muscles as "avoided" if sufficient data
        guard exercises.count > 15 else { return [] }

        let trainedMuscles = inferEmphasizedMuscles(from: exercises)
        let allMajorMuscles: Set<MuscleGroup> = [.chest, .back, .shoulders, .quadriceps, .hamstrings, .biceps, .triceps]

        // Find muscles never trained (but only major groups)
        let avoided = allMajorMuscles.subtracting(trainedMuscles)

        // Only return if 1-2 muscle groups completely absent (likely intentional)
        return avoided.count <= 2 ? avoided : []
    }

    // MARK: - Split Type Inference

    private static func inferSplitType(from sessions: [ImportedSession]) -> SplitType? {
        // Need sufficient data
        guard sessions.count >= 8 else { return nil }

        // Analyze muscle groups per session
        var sessionMusclePatterns: [[MuscleGroup]] = []

        for session in sessions {
            var muscles: [MuscleGroup] = []
            for exercise in session.exercises {
                let inferred = inferMuscleGroupsFromName(exercise.exerciseName)
                muscles.append(contentsOf: inferred)
            }
            sessionMusclePatterns.append(muscles)
        }

        // Check for full body (6+ muscle groups per session)
        let fullBodySessions = sessionMusclePatterns.filter { Set($0).count >= 5 }.count
        if fullBodySessions > sessions.count / 2 {
            return .fullBody
        }

        // Check for upper/lower pattern
        let upperMuscles: Set<MuscleGroup> = [.chest, .back, .shoulders, .biceps, .triceps]
        let lowerMuscles: Set<MuscleGroup> = [.quadriceps, .hamstrings, .glutes, .calves]

        var upperDays = 0
        var lowerDays = 0

        for pattern in sessionMusclePatterns {
            let patternSet = Set(pattern)
            let upperCount = patternSet.intersection(upperMuscles).count
            let lowerCount = patternSet.intersection(lowerMuscles).count

            if upperCount > lowerCount * 2 {
                upperDays += 1
            } else if lowerCount > upperCount * 2 {
                lowerDays += 1
            }
        }

        if upperDays > 3 && lowerDays > 3 {
            return .upperLower
        }

        // Default to PPL if variety is high
        if sessions.count >= 12 {
            return .pushPullLegs
        }

        return nil
    }

    // MARK: - Session Duration

    private static func estimateSessionDuration(from sessions: [ImportedSession]) -> Int {
        guard !sessions.isEmpty else { return 60 }  // Default

        // Estimate: 3-5 min per set (including rest) + 10 min warmup/cooldown
        let totalSets = sessions.flatMap { $0.exercises.flatMap { $0.sets } }.count
        let avgSetsPerSession = totalSets / sessions.count

        let estimatedMinutes = avgSetsPerSession * 4 + 10

        // Round to nearest 15 minutes, clamp 45-120
        let rounded = ((estimatedMinutes + 7) / 15) * 15
        return min(max(rounded, 45), 120)
    }

    // MARK: - Confidence Score

    private static func calculateConfidence(
        sessionCount: Int,
        exerciseCount: Int,
        hasWeightData: Bool
    ) -> Double {
        var confidence = 0.5  // Base confidence

        // Session count bonus
        if sessionCount >= 20 { confidence += 0.2 }
        else if sessionCount >= 10 { confidence += 0.15 }
        else if sessionCount >= 5 { confidence += 0.1 }

        // Exercise variety bonus
        if exerciseCount >= 20 { confidence += 0.15 }
        else if exerciseCount >= 10 { confidence += 0.1 }

        // Bodyweight data bonus (better relative strength calc)
        if hasWeightData { confidence += 0.15 }

        return min(confidence, 1.0)
    }
}
