//
// AnalyzeTrainingDataHandler.swift
// Medina
//
// v107.0: Handler for analyze_training_data AI tool
// v108.0: Added analysis card data for visualizations
// Enables rich historical data analysis across date ranges
//

import Foundation
import SwiftUI

@MainActor
struct AnalyzeTrainingDataHandler: ToolHandler {
    static let toolName = "analyze_training_data"

    static func executeOnly(args: [String: Any], context: ToolCallContext) async -> String {
        let (output, cardData) = executeWithCardData(args: args, context: context)

        // v108.1: Store card data for batch execution path
        // When called via executeOnly (batch tools), we can't attach card to streamed message
        // so we store it in context for later attachment
        if let cardData = cardData {
            context.pendingAnalysisCardData = cardData
        }

        return output
    }

    /// Execute and return both text output and optional card data
    private static func executeWithCardData(args: [String: Any], context: ToolCallContext) -> (String, AnalysisCardData?) {
        Logger.log(.info, component: "AnalyzeTrainingDataHandler", message: "🔧 Executing analyze_training_data")

        // 1. Parse analysis type (required)
        guard let analysisTypeStr = args["analysisType"] as? String,
              let analysisType = AnalysisRequest.AnalysisType(rawValue: analysisTypeStr) else {
            return ("ERROR: Missing or invalid 'analysisType'. Must be one of: period_summary, exercise_progression, strength_trends, period_comparison", nil)
        }

        // 2. Parse date range
        // v108.2: For exercise_progression, always use 1 year to enable time-frame filtering
        // AI might pass shorter ranges, but we need full data for chart filters to work
        let dateRange: DateInterval
        if analysisType == .exerciseProgression {
            dateRange = defaultDateRange() // Always 1 year for progression charts
        } else {
            dateRange = parseDateRange(from: args["dateRange"] as? [String: Any]) ?? defaultDateRange()
        }

        // 3. Parse optional parameters
        let comparisonDateRange = parseDateRange(from: args["comparisonDateRange"] as? [String: Any])
        let exerciseId = resolveExerciseId(
            id: args["exerciseId"] as? String,
            name: args["exerciseName"] as? String
        )
        let muscleGroup = (args["muscleGroup"] as? String).flatMap { MuscleGroup(rawValue: $0) }
        let includeDetails = args["includeDetails"] as? Bool ?? false

        // 4. Build request
        let request = AnalysisRequest(
            memberId: context.user.id,
            analysisType: analysisType,
            dateRange: dateRange,
            comparisonDateRange: comparisonDateRange,
            exerciseId: exerciseId,
            muscleGroup: muscleGroup,
            includeDetails: includeDetails
        )

        // 5. Execute analysis
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        Logger.log(.debug, component: "AnalyzeTrainingDataHandler",
                  message: "📊 Analyzing \(analysisType.rawValue) for date range: \(dateFormatter.string(from: dateRange.start)) to \(dateFormatter.string(from: dateRange.end))")

        let result = TrainingDataAnalyzer.analyze(request: request)

        // 6. Format output for AI consumption
        let output = formatResultForAI(result)

        // 7. Build card data for visualization
        let cardData = buildCardData(from: result)

        return (output, cardData)
    }

    static func handle(
        toolCall: StreamProcessor.ToolCall,
        args: [String: Any],
        context: ToolCallContext
    ) async {
        let (output, cardData) = executeWithCardData(args: args, context: context)

        if output.hasPrefix("ERROR:") {
            await ToolHandlerUtilities.submitToolError(
                toolCall: toolCall,
                output: output,
                context: context
            )
            return
        }

        // Submit and stream response
        Logger.log(.debug, component: "AnalyzeTrainingDataHandler", message: "Submitting analysis output")

        // Add placeholder message for streaming (with card data attached)
        let placeholder = Message(content: "", isUser: false, analysisCardData: cardData)
        context.addMessage(placeholder)
        let messageIndex = context.messagesCount() - 1

        var responseText = ""

        do {
            let continueStream = context.assistantManager.submitToolOutput(
                toolCallId: toolCall.id,
                runId: toolCall.runId,
                output: output
            )

            for try await event in continueStream {
                switch event {
                case .textDelta(let delta):
                    responseText += delta
                    context.updateMessage(messageIndex, Message(content: responseText, isUser: false, analysisCardData: cardData))
                case .textDone, .runCompleted:
                    break
                case .runFailed(let error):
                    Logger.log(.error, component: "AnalyzeTrainingDataHandler", message: "Run failed: \(error)")
                case .toolCall:
                    Logger.log(.warning, component: "AnalyzeTrainingDataHandler", message: "Nested tool call not supported")
                case .toolCalls:
                    Logger.log(.warning, component: "AnalyzeTrainingDataHandler", message: "Nested batch tool calls not supported")
                case .error(let error):
                    Logger.log(.error, component: "AnalyzeTrainingDataHandler", message: "Error: \(error)")
                }
            }
        } catch {
            Logger.log(.error, component: "AnalyzeTrainingDataHandler", message: "Failed to submit: \(error)")
        }
    }

    // MARK: - Card Data Building

    private static func buildCardData(from result: AnalysisResult) -> AnalysisCardData? {
        switch result {
        case .exerciseProgression(let progression):
            return buildProgressionCard(from: progression)
        case .strengthTrends(let trends):
            return buildTrendsCard(from: trends)
        case .periodComparison(let comparison):
            return buildComparisonCard(from: comparison)
        case .periodSummary(let summary):
            return buildVolumeCard(from: summary)
        case .error:
            return nil
        }
    }

    private static func buildProgressionCard(from progression: ExerciseProgressionResult) -> AnalysisCardData? {
        guard !progression.dataPoints.isEmpty else { return nil }

        Logger.log(.debug, component: "AnalyzeTrainingDataHandler",
                  message: "📊 Building card with \(progression.dataPoints.count) data points")

        let points = progression.dataPoints.map { point in
            ProgressionPoint(
                date: point.date,
                value: point.estimated1RM,
                label: nil
            )
        }

        let trend: ChartTrendDirection = {
            switch progression.trend.direction {
            case .improving: return .improving
            case .maintaining: return .maintaining
            case .regressing: return .regressing
            }
        }()

        return .progression(
            exerciseName: progression.exerciseName,
            dataPoints: points,
            trend: trend,
            percentChange: progression.trend.percentChange
        )
    }

    private static func buildTrendsCard(from trends: StrengthTrendsResult) -> AnalysisCardData? {
        let improving = trends.improving.prefix(6).map { exercise in
            TrendExercise(
                exerciseName: exercise.exerciseName,
                percentChange: exercise.percentChange,
                startValue: exercise.startingEstimated1RM,
                endValue: exercise.currentEstimated1RM
            )
        }

        let maintaining = trends.maintaining.prefix(4).map { exercise in
            TrendExercise(
                exerciseName: exercise.exerciseName,
                percentChange: exercise.percentChange,
                startValue: exercise.startingEstimated1RM,
                endValue: exercise.currentEstimated1RM
            )
        }

        let regressing = trends.regressing.prefix(6).map { exercise in
            TrendExercise(
                exerciseName: exercise.exerciseName,
                percentChange: exercise.percentChange,
                startValue: exercise.startingEstimated1RM,
                endValue: exercise.currentEstimated1RM
            )
        }

        guard !improving.isEmpty || !maintaining.isEmpty || !regressing.isEmpty else { return nil }

        return .trends(
            improving: Array(improving),
            maintaining: Array(maintaining),
            regressing: Array(regressing)
        )
    }

    private static func buildComparisonCard(from comparison: PeriodComparisonResult) -> AnalysisCardData? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM yyyy"

        let periodALabel = dateFormatter.string(from: comparison.periodA.dateRange.start)
        let periodBLabel = dateFormatter.string(from: comparison.periodB.dateRange.start)

        let metrics = [
            ComparisonMetric(
                label: "Volume",
                periodAValue: comparison.periodA.totalVolume,
                periodBValue: comparison.periodB.totalVolume,
                unit: "lbs",
                formatAsPercent: false
            ),
            ComparisonMetric(
                label: "Workouts",
                periodAValue: Double(comparison.periodA.completedWorkouts),
                periodBValue: Double(comparison.periodB.completedWorkouts),
                unit: "",
                formatAsPercent: false
            ),
            ComparisonMetric(
                label: "Adherence",
                periodAValue: comparison.periodA.adherenceRate * 100,
                periodBValue: comparison.periodB.adherenceRate * 100,
                unit: "",
                formatAsPercent: true
            )
        ]

        return .comparison(
            periodALabel: periodALabel,
            periodBLabel: periodBLabel,
            metrics: metrics
        )
    }

    private static func buildVolumeCard(from summary: PeriodSummaryResult) -> AnalysisCardData? {
        let sortedMuscles = summary.muscleGroupBreakdown.sorted { $0.value.totalVolume > $1.value.totalVolume }

        guard !sortedMuscles.isEmpty else { return nil }

        let totalVolume = summary.totalVolume
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .yellow, .red]

        let muscleData = sortedMuscles.prefix(6).enumerated().map { index, item in
            let percentage = totalVolume > 0 ? (item.value.totalVolume / totalVolume) * 100 : 0
            return MuscleVolumeData(
                muscleGroup: item.key.displayName,
                volume: item.value.totalVolume,
                percentage: percentage,
                color: colors[index % colors.count]
            )
        }

        return .volume(
            muscleGroups: Array(muscleData),
            totalVolume: totalVolume
        )
    }

    // MARK: - Output Formatting

    private static func formatResultForAI(_ result: AnalysisResult) -> String {
        switch result {
        case .periodSummary(let summary):
            return formatPeriodSummary(summary)
        case .exerciseProgression(let progression):
            return formatExerciseProgression(progression)
        case .strengthTrends(let trends):
            return formatStrengthTrends(trends)
        case .periodComparison(let comparison):
            return formatPeriodComparison(comparison)
        case .error(let message):
            return "ERROR: \(message)"
        }
    }

    private static func formatPeriodSummary(_ summary: PeriodSummaryResult) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"

        var output = """
        TRAINING ANALYSIS: Period Summary
        Date Range: \(dateFormatter.string(from: summary.dateRange.start)) - \(dateFormatter.string(from: summary.dateRange.end))

        OVERVIEW:
        - Workouts: \(summary.completedWorkouts)/\(summary.workoutCount) completed (\(Int(summary.adherenceRate * 100))% adherence)
        - Total Volume: \(formatWeight(summary.totalVolume))
        - Total Sets: \(summary.totalSets)
        - Total Reps: \(summary.totalReps)

        MUSCLE GROUP BREAKDOWN:
        """

        let sortedMuscles = summary.muscleGroupBreakdown.sorted { $0.value.totalVolume > $1.value.totalVolume }
        for (muscle, stats) in sortedMuscles.prefix(8) {
            output += "\n- \(muscle.displayName): \(formatWeight(stats.totalVolume)) (\(stats.totalSets) sets, \(stats.exerciseCount) exercises)"
        }

        output += "\n\nTOP EXERCISES BY VOLUME:"
        for (index, exercise) in summary.topExercises.prefix(8).enumerated() {
            var line = "\n\(index + 1). \(exercise.exerciseName): \(formatWeight(exercise.totalVolume)) (\(exercise.sessions) sessions)"
            if let rm = exercise.estimated1RM, rm > 0 {
                line += " - Est 1RM: \(formatWeight(rm))"
            }
            output += line
        }

        if let weekly = summary.weeklyBreakdown, !weekly.isEmpty {
            output += "\n\nWEEKLY BREAKDOWN:"
            let weekFormatter = DateFormatter()
            weekFormatter.dateFormat = "MMM d"
            for week in weekly.suffix(8) {
                output += "\n- Week of \(weekFormatter.string(from: week.weekStart)): \(week.workouts) workouts, \(formatWeight(week.volume))"
            }
        }

        output += """


        RESPONSE_GUIDANCE:
        1. Summarize the key metrics conversationally (volume, adherence, workout count)
        2. Highlight the most trained muscle groups and top exercises
        3. Note adherence rate and suggest improvements if below 80%
        4. Reference specific exercises the user has been focusing on
        5. If volume is high, acknowledge their hard work
        """

        return output
    }

    private static func formatExerciseProgression(_ progression: ExerciseProgressionResult) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"

        var output = """
        TRAINING ANALYSIS: \(progression.exerciseName) Progression
        Date Range: \(dateFormatter.string(from: progression.dateRange.start)) - \(dateFormatter.string(from: progression.dateRange.end))

        """

        if progression.dataPoints.isEmpty {
            output += "NO DATA: No completed sessions found for this exercise in the date range.\n"
            output += "\nRESPONSE_GUIDANCE:\n"
            output += "1. Let the user know you couldn't find data for this exercise\n"
            output += "2. Suggest they may have the exercise name wrong or haven't done it recently\n"
            output += "3. Offer to search for similar exercises or show overall strength trends\n"
            return output
        }

        output += """
        TREND: \(progression.trend.direction.rawValue.uppercased())
        - Change: \(progression.trend.percentChange > 0 ? "+" : "")\(String(format: "%.1f", progression.trend.percentChange))%
        - Weekly Rate: \(progression.trend.weeklyRate > 0 ? "+" : "")\(String(format: "%.1f", progression.trend.weeklyRate)) lbs/week
        - Data Points: \(progression.dataPoints.count) sessions
        - Confidence: \(progression.trend.confidence > 0.7 ? "High" : progression.trend.confidence > 0.4 ? "Medium" : "Low")

        SESSION HISTORY (most recent first):
        """

        for point in progression.dataPoints.prefix(10) {
            output += "\n- \(dateFormatter.string(from: point.date)): \(formatWeight(point.bestWeight)) x \(point.bestReps) reps (Est 1RM: \(formatWeight(point.estimated1RM)))"
        }

        if !progression.personalRecords.isEmpty {
            output += "\n\nPERSONAL RECORDS:"
            for pr in progression.personalRecords {
                output += "\n- \(pr.type.rawValue.capitalized): \(formatWeight(pr.value)) on \(dateFormatter.string(from: pr.date))"
            }
        }

        output += """


        RESPONSE_GUIDANCE:
        1. Celebrate if improving - mention specific weight/rep improvements
        2. If maintaining, acknowledge consistency and suggest progressive overload
        3. If regressing, diagnose possible causes (recovery, form, programming, life stress)
        4. Reference specific recent sessions with actual weights and reps
        5. Mention PRs if any were set in this period
        """

        return output
    }

    private static func formatStrengthTrends(_ trends: StrengthTrendsResult) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"

        var output = """
        TRAINING ANALYSIS: Strength Trends Overview
        Date Range: \(dateFormatter.string(from: trends.dateRange.start)) - \(dateFormatter.string(from: trends.dateRange.end))

        """

        if trends.improving.isEmpty && trends.maintaining.isEmpty && trends.regressing.isEmpty {
            output += "NO DATA: No exercises with enough data points (need 2+ sessions) found in this date range.\n"
            output += "\nRESPONSE_GUIDANCE:\n"
            output += "1. Let the user know there's not enough data to analyze trends\n"
            output += "2. Suggest they need to complete more workouts for trend analysis\n"
            output += "3. Offer to show a period summary instead\n"
            return output
        }

        output += "IMPROVING (\(trends.improving.count) exercises):"
        if trends.improving.isEmpty {
            output += "\n(none)"
        } else {
            for exercise in trends.improving.prefix(6) {
                output += "\n- \(exercise.exerciseName): +\(String(format: "%.1f", exercise.percentChange))% (\(formatWeight(exercise.startingEstimated1RM)) → \(formatWeight(exercise.currentEstimated1RM)))"
            }
        }

        output += "\n\nMAINTAINING (\(trends.maintaining.count) exercises):"
        if trends.maintaining.isEmpty {
            output += "\n(none)"
        } else {
            for exercise in trends.maintaining.prefix(4) {
                output += "\n- \(exercise.exerciseName): \(String(format: "%.1f", exercise.percentChange))% (\(exercise.sessionsAnalyzed) sessions)"
            }
        }

        output += "\n\nREGRESSING (\(trends.regressing.count) exercises):"
        if trends.regressing.isEmpty {
            output += "\n(none)"
        } else {
            for exercise in trends.regressing.prefix(6) {
                output += "\n- \(exercise.exerciseName): \(String(format: "%.1f", exercise.percentChange))% (\(formatWeight(exercise.startingEstimated1RM)) → \(formatWeight(exercise.currentEstimated1RM)))"
            }
        }

        output += """


        RESPONSE_GUIDANCE:
        1. Lead with the positive - celebrate improving exercises first
        2. Acknowledge exercises being maintained (consistency is good)
        3. Be honest but encouraging about regression - it happens
        4. Suggest focusing on regressing exercises if there are many
        5. Consider if regression might be intentional (deload week, focus shift)
        6. Reference actual weight numbers to show you understand their training
        """

        return output
    }

    private static func formatPeriodComparison(_ comparison: PeriodComparisonResult) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"

        let periodALabel = "\(dateFormatter.string(from: comparison.periodA.dateRange.start)) - \(dateFormatter.string(from: comparison.periodA.dateRange.end))"
        let periodBLabel = "\(dateFormatter.string(from: comparison.periodB.dateRange.start)) - \(dateFormatter.string(from: comparison.periodB.dateRange.end))"

        var output = """
        TRAINING ANALYSIS: Period Comparison
        Period A: \(periodALabel)
        Period B: \(periodBLabel)

        COMPARISON SUMMARY:
        - Volume: \(comparison.comparison.volumeChange > 0 ? "+" : "")\(String(format: "%.1f", comparison.comparison.volumeChange))% (\(formatWeight(comparison.periodA.totalVolume)) → \(formatWeight(comparison.periodB.totalVolume)))
        - Workout Frequency: \(comparison.comparison.frequencyChange > 0 ? "+" : "")\(String(format: "%.1f", comparison.comparison.frequencyChange))%
        - Adherence: \(comparison.comparison.adherenceChange > 0 ? "+" : "")\(String(format: "%.1f", comparison.comparison.adherenceChange)) percentage points

        PERIOD A (\(periodALabel)):
        - Workouts: \(comparison.periodA.completedWorkouts)/\(comparison.periodA.workoutCount) (\(Int(comparison.periodA.adherenceRate * 100))%)
        - Volume: \(formatWeight(comparison.periodA.totalVolume))
        - Sets: \(comparison.periodA.totalSets)

        PERIOD B (\(periodBLabel)):
        - Workouts: \(comparison.periodB.completedWorkouts)/\(comparison.periodB.workoutCount) (\(Int(comparison.periodB.adherenceRate * 100))%)
        - Volume: \(formatWeight(comparison.periodB.totalVolume))
        - Sets: \(comparison.periodB.totalSets)
        """

        if !comparison.comparison.strengthChanges.isEmpty {
            output += "\n\nSTRENGTH CHANGES (exercises in both periods):"
            for change in comparison.comparison.strengthChanges.prefix(6) {
                if let pctChange = change.percentChange {
                    let direction = pctChange > 0 ? "+" : ""
                    output += "\n- \(change.exerciseName): \(direction)\(String(format: "%.1f", pctChange))%"
                    if let a = change.periodA1RM, let b = change.periodB1RM {
                        output += " (\(formatWeight(a)) → \(formatWeight(b)))"
                    }
                }
            }
        }

        output += """


        RESPONSE_GUIDANCE:
        1. Summarize the overall trend (better/worse/similar between periods)
        2. Highlight the biggest changes (volume, frequency, specific exercises)
        3. Provide context - higher isn't always better, recovery matters
        4. If one period was clearly better, help diagnose why
        5. Be encouraging regardless of direction
        """

        return output
    }

    // MARK: - Helpers

    private static func parseDateRange(from dict: [String: Any]?) -> DateInterval? {
        guard let dict = dict,
              let startStr = dict["start"] as? String,
              let endStr = dict["end"] as? String else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        guard let start = formatter.date(from: startStr),
              let end = formatter.date(from: endStr) else { return nil }

        // Make end date inclusive (end of day)
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end

        return DateInterval(start: start, end: endOfDay)
    }

    private static func defaultDateRange() -> DateInterval {
        // v108.2: Default to 1 year for exercise progression to enable time frame filtering
        // Charts can filter down (1M, 3M, 6M) but can't show data beyond what's queried
        let end = Date()
        let start = Calendar.current.date(byAdding: .year, value: -1, to: end)!
        return DateInterval(start: start, end: end)
    }

    private static func resolveExerciseId(id: String?, name: String?) -> String? {
        if let id = id, TestDataManager.shared.exercises[id] != nil {
            return id
        }

        guard let name = name else { return nil }

        // Fuzzy match exercise name to ID
        let normalized = name.lowercased()

        // Try exact name match first
        if let match = TestDataManager.shared.exercises.first(where: {
            $0.value.name.lowercased() == normalized
        }) {
            return match.key
        }

        // Try contains match
        if let match = TestDataManager.shared.exercises.first(where: {
            $0.value.name.lowercased().contains(normalized) ||
            $0.key.replacingOccurrences(of: "_", with: " ").contains(normalized)
        }) {
            return match.key
        }

        // Try partial word match
        let words = normalized.split(separator: " ")
        if let match = TestDataManager.shared.exercises.first(where: { _, exercise in
            let exerciseName = exercise.name.lowercased()
            return words.allSatisfy { exerciseName.contains($0) }
        }) {
            return match.key
        }

        return nil
    }

    private static func formatWeight(_ weight: Double) -> String {
        if weight >= 10000 {
            return String(format: "%.1fK lbs", weight / 1000)
        } else if weight >= 1000 {
            return String(format: "%.0f lbs", weight)
        }
        return "\(Int(weight)) lbs"
    }
}
