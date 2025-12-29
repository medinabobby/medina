//
// TrainingDataAnalyzer.swift
// Medina
//
// v107.0: Rich historical training data analysis for AI
// Unified service for date-range queries, exercise progression, and strength trends
// Entry point for analyze_training_data AI tool
//

import Foundation

// MARK: - Analysis Request Types

struct AnalysisRequest {
    let memberId: String
    let analysisType: AnalysisType
    let dateRange: DateInterval
    let comparisonDateRange: DateInterval?
    let exerciseId: String?
    let muscleGroup: MuscleGroup?
    let includeDetails: Bool

    enum AnalysisType: String {
        case periodSummary = "period_summary"
        case exerciseProgression = "exercise_progression"
        case strengthTrends = "strength_trends"
        case periodComparison = "period_comparison"
    }
}

// MARK: - Analysis Response Types

struct PeriodSummaryResult {
    let dateRange: DateInterval
    let workoutCount: Int
    let completedWorkouts: Int
    let adherenceRate: Double
    let totalVolume: Double
    let totalSets: Int
    let totalReps: Int
    let muscleGroupBreakdown: [MuscleGroup: MuscleGroupStats]
    let topExercises: [ExerciseVolumeStats]
    let weeklyBreakdown: [WeekSummary]?
}

struct MuscleGroupStats {
    let muscleGroup: MuscleGroup
    let totalVolume: Double
    let totalSets: Int
    let exerciseCount: Int
}

struct ExerciseVolumeStats {
    let exerciseId: String
    let exerciseName: String
    let totalVolume: Double
    let totalSets: Int
    let sessions: Int
    let bestWeight: Double?
    let bestReps: Int?
    let estimated1RM: Double?
}

struct WeekSummary {
    let weekStart: Date
    let workouts: Int
    let volume: Double
    let sets: Int
}

struct ExerciseProgressionResult {
    let exerciseId: String
    let exerciseName: String
    let dateRange: DateInterval
    let dataPoints: [ProgressionDataPoint]
    let trend: TrendAnalysis
    let personalRecords: [PersonalRecord]
}

struct ProgressionDataPoint {
    let date: Date
    let workoutId: String
    let bestWeight: Double
    let bestReps: Int
    let totalVolume: Double
    let estimated1RM: Double
}

struct TrendAnalysis {
    let direction: TrendDirection
    let percentChange: Double
    let weeklyRate: Double
    let confidence: Double
}

enum TrendDirection: String {
    case improving
    case maintaining
    case regressing
}

struct PersonalRecord {
    let type: PRType
    let value: Double
    let date: Date
    let workoutId: String
}

enum PRType: String {
    case weight
    case volume
    case estimated1RM
    case reps
}

struct StrengthTrendsResult {
    let dateRange: DateInterval
    let improving: [ExerciseTrend]
    let maintaining: [ExerciseTrend]
    let regressing: [ExerciseTrend]
}

struct ExerciseTrend {
    let exerciseId: String
    let exerciseName: String
    let muscleGroup: MuscleGroup?
    let startingEstimated1RM: Double
    let currentEstimated1RM: Double
    let percentChange: Double
    let sessionsAnalyzed: Int
}

struct PeriodComparisonResult {
    let periodA: PeriodSummaryResult
    let periodB: PeriodSummaryResult
    let comparison: ComparisonMetrics
}

struct ComparisonMetrics {
    let volumeChange: Double
    let frequencyChange: Double
    let adherenceChange: Double
    let strengthChanges: [ExerciseComparison]
}

struct ExerciseComparison {
    let exerciseId: String
    let exerciseName: String
    let periodA1RM: Double?
    let periodB1RM: Double?
    let percentChange: Double?
}

// MARK: - Result Enum

enum AnalysisResult {
    case periodSummary(PeriodSummaryResult)
    case exerciseProgression(ExerciseProgressionResult)
    case strengthTrends(StrengthTrendsResult)
    case periodComparison(PeriodComparisonResult)
    case error(String)
}

// MARK: - Main Analyzer Service

enum TrainingDataAnalyzer {

    /// Main entry point - routes to appropriate analysis method
    static func analyze(request: AnalysisRequest) -> AnalysisResult {
        switch request.analysisType {
        case .periodSummary:
            return .periodSummary(analyzePeriod(request))
        case .exerciseProgression:
            if let result = analyzeExerciseProgression(request) {
                return .exerciseProgression(result)
            } else {
                return .error("No exercise specified or no data found for exercise")
            }
        case .strengthTrends:
            return .strengthTrends(analyzeStrengthTrends(request))
        case .periodComparison:
            if let result = comparePeriods(request) {
                return .periodComparison(result)
            } else {
                return .error("No comparison date range specified")
            }
        }
    }

    // MARK: - Period Summary Analysis

    private static func analyzePeriod(_ request: AnalysisRequest) -> PeriodSummaryResult {
        let userContext = UserContext(userId: request.memberId)

        // Get all workouts in date range
        let allWorkouts = WorkoutDataStore.workouts(
            for: request.memberId,
            temporal: .unspecified,
            status: nil,
            dateInterval: request.dateRange
        )

        let completedWorkouts = allWorkouts.filter { $0.status == .completed }

        var totalVolume: Double = 0
        var totalSets = 0
        var totalReps = 0
        var muscleGroupStats: [MuscleGroup: (volume: Double, sets: Int, exercises: Set<String>)] = [:]
        var exerciseStats: [String: (volume: Double, sets: Int, sessions: Int, bestWeight: Double, bestReps: Int, name: String)] = [:]
        var weeklyData: [Date: (workouts: Int, volume: Double, sets: Int)] = [:]

        let calendar = Calendar.current

        for workout in completedWorkouts {
            let instances = InstanceResolver.instances(forWorkout: workout, for: userContext)

            // Track weekly data
            if let scheduledDate = workout.scheduledDate {
                let weekStart = calendar.dateInterval(of: .weekOfYear, for: scheduledDate)?.start ?? scheduledDate
                var weekData = weeklyData[weekStart] ?? (0, 0, 0)
                weekData.workouts += 1
                weeklyData[weekStart] = weekData
            }

            for instance in instances {
                let sets = InstanceResolver.sets(forInstance: instance, for: userContext)
                guard let exercise = TestDataManager.shared.exercises[instance.exerciseId] else { continue }

                // Apply muscle group filter if specified
                if let filterMuscle = request.muscleGroup {
                    guard exercise.muscleGroups.contains(filterMuscle) else { continue }
                }

                var sessionBestWeight: Double = 0
                var sessionBestReps: Int = 0
                var sessionVolume: Double = 0
                var sessionSets: Int = 0

                for set in sets where set.completion == .completed {
                    let weight = set.actualWeight ?? 0
                    let reps = set.actualReps ?? 0
                    let volume = weight * Double(reps)

                    totalVolume += volume
                    totalSets += 1
                    totalReps += reps
                    sessionVolume += volume
                    sessionSets += 1

                    sessionBestWeight = max(sessionBestWeight, weight)
                    sessionBestReps = max(sessionBestReps, reps)

                    // Update muscle group stats
                    for muscle in exercise.muscleGroups {
                        var stats = muscleGroupStats[muscle] ?? (0, 0, Set())
                        stats.volume += volume
                        stats.sets += 1
                        stats.exercises.insert(instance.exerciseId)
                        muscleGroupStats[muscle] = stats
                    }

                    // Update weekly volume
                    if let scheduledDate = workout.scheduledDate {
                        let weekStart = calendar.dateInterval(of: .weekOfYear, for: scheduledDate)?.start ?? scheduledDate
                        var weekData = weeklyData[weekStart] ?? (0, 0, 0)
                        weekData.volume += volume
                        weekData.sets += 1
                        weeklyData[weekStart] = weekData
                    }
                }

                // Update exercise stats
                var exStats = exerciseStats[instance.exerciseId] ?? (0, 0, 0, 0, 0, exercise.name)
                exStats.volume += sessionVolume
                exStats.sets += sessionSets
                exStats.sessions += 1
                exStats.bestWeight = max(exStats.bestWeight, sessionBestWeight)
                exStats.bestReps = max(exStats.bestReps, sessionBestReps)
                exerciseStats[instance.exerciseId] = exStats
            }
        }

        // Convert muscle group stats
        let muscleBreakdown = muscleGroupStats.mapValues { stats in
            MuscleGroupStats(
                muscleGroup: .chest, // Placeholder - will be set by key
                totalVolume: stats.volume,
                totalSets: stats.sets,
                exerciseCount: stats.exercises.count
            )
        }

        // Convert and sort exercise stats by volume
        let topExercises = exerciseStats.map { exerciseId, stats in
            let setData = [SetDataForRM(weight: stats.bestWeight, reps: stats.bestReps)]
            let estimated1RM = OneRMCalculationService.selectBest1RM(from: setData)

            return ExerciseVolumeStats(
                exerciseId: exerciseId,
                exerciseName: stats.name,
                totalVolume: stats.volume,
                totalSets: stats.sets,
                sessions: stats.sessions,
                bestWeight: stats.bestWeight > 0 ? stats.bestWeight : nil,
                bestReps: stats.bestReps > 0 ? stats.bestReps : nil,
                estimated1RM: estimated1RM
            )
        }.sorted { $0.totalVolume > $1.totalVolume }

        // Convert weekly breakdown
        let weeklyBreakdown: [WeekSummary]? = request.includeDetails ? weeklyData.map { weekStart, data in
            WeekSummary(
                weekStart: weekStart,
                workouts: data.workouts,
                volume: data.volume,
                sets: data.sets
            )
        }.sorted { $0.weekStart < $1.weekStart } : nil

        let adherenceRate = allWorkouts.isEmpty ? 0 : Double(completedWorkouts.count) / Double(allWorkouts.count)

        return PeriodSummaryResult(
            dateRange: request.dateRange,
            workoutCount: allWorkouts.count,
            completedWorkouts: completedWorkouts.count,
            adherenceRate: adherenceRate,
            totalVolume: totalVolume,
            totalSets: totalSets,
            totalReps: totalReps,
            muscleGroupBreakdown: muscleBreakdown,
            topExercises: Array(topExercises.prefix(10)),
            weeklyBreakdown: weeklyBreakdown
        )
    }

    // MARK: - Exercise Progression Analysis

    private static func analyzeExerciseProgression(_ request: AnalysisRequest) -> ExerciseProgressionResult? {
        guard let exerciseId = request.exerciseId else { return nil }
        guard let exercise = TestDataManager.shared.exercises[exerciseId] else { return nil }

        let userContext = UserContext(userId: request.memberId)

        // Get all instances for this exercise
        let allInstancesWithWorkouts = InstanceResolver.instancesForExercise(
            exerciseId: exerciseId,
            for: userContext
        )

        // Filter to date range and completed workouts
        let filteredInstances = allInstancesWithWorkouts.filter { instance, workout in
            guard let date = workout.scheduledDate else { return false }
            return request.dateRange.contains(date) && workout.status == .completed
        }

        guard !filteredInstances.isEmpty else {
            return ExerciseProgressionResult(
                exerciseId: exerciseId,
                exerciseName: exercise.name,
                dateRange: request.dateRange,
                dataPoints: [],
                trend: TrendAnalysis(direction: .maintaining, percentChange: 0, weeklyRate: 0, confidence: 0),
                personalRecords: []
            )
        }

        // Build data points
        var dataPoints: [ProgressionDataPoint] = []
        var allTime1RMs: [(date: Date, rm: Double, workoutId: String)] = []
        var allTimeWeights: [(date: Date, weight: Double, workoutId: String)] = []
        var allTimeVolumes: [(date: Date, volume: Double, workoutId: String)] = []

        for (instance, workout) in filteredInstances {
            let sets = InstanceResolver.sets(forInstance: instance, for: userContext)
            let completedSets = sets.filter { $0.completion == .completed }

            guard !completedSets.isEmpty else { continue }

            let setData = completedSets.enumerated().map { index, set in
                SetDataForRM(
                    weight: set.actualWeight ?? 0,
                    reps: set.actualReps ?? 0,
                    setIndex: index
                )
            }

            let estimated1RM = OneRMCalculationService.selectBest1RM(from: setData) ?? 0
            let bestSet = completedSets.max(by: { ($0.actualWeight ?? 0) < ($1.actualWeight ?? 0) })
            let totalVolume = completedSets.reduce(0.0) { $0 + (($1.actualWeight ?? 0) * Double($1.actualReps ?? 0)) }

            let date = workout.scheduledDate ?? Date()

            dataPoints.append(ProgressionDataPoint(
                date: date,
                workoutId: workout.id,
                bestWeight: bestSet?.actualWeight ?? 0,
                bestReps: bestSet?.actualReps ?? 0,
                totalVolume: totalVolume,
                estimated1RM: estimated1RM
            ))

            if estimated1RM > 0 {
                allTime1RMs.append((date, estimated1RM, workout.id))
            }
            if let weight = bestSet?.actualWeight, weight > 0 {
                allTimeWeights.append((date, weight, workout.id))
            }
            if totalVolume > 0 {
                allTimeVolumes.append((date, totalVolume, workout.id))
            }
        }

        // Sort data points by date (oldest first for trend calculation)
        dataPoints.sort { $0.date < $1.date }

        // Calculate trend
        let trend = calculateTrend(from: dataPoints)

        // Identify personal records
        var personalRecords: [PersonalRecord] = []

        if let best1RM = allTime1RMs.max(by: { $0.rm < $1.rm }) {
            personalRecords.append(PersonalRecord(
                type: .estimated1RM,
                value: best1RM.rm,
                date: best1RM.date,
                workoutId: best1RM.workoutId
            ))
        }

        if let bestWeight = allTimeWeights.max(by: { $0.weight < $1.weight }) {
            personalRecords.append(PersonalRecord(
                type: .weight,
                value: bestWeight.weight,
                date: bestWeight.date,
                workoutId: bestWeight.workoutId
            ))
        }

        if let bestVolume = allTimeVolumes.max(by: { $0.volume < $1.volume }) {
            personalRecords.append(PersonalRecord(
                type: .volume,
                value: bestVolume.volume,
                date: bestVolume.date,
                workoutId: bestVolume.workoutId
            ))
        }

        return ExerciseProgressionResult(
            exerciseId: exerciseId,
            exerciseName: exercise.name,
            dateRange: request.dateRange,
            dataPoints: dataPoints, // Chronological order (oldest first) - matches trend calculation
            trend: trend,
            personalRecords: personalRecords
        )
    }

    // MARK: - Strength Trends Analysis

    private static func analyzeStrengthTrends(_ request: AnalysisRequest) -> StrengthTrendsResult {
        let userContext = UserContext(userId: request.memberId)

        // Get all completed workouts in date range
        let workouts = WorkoutDataStore.workouts(
            for: request.memberId,
            temporal: .unspecified,
            status: .completed,
            dateInterval: request.dateRange
        )

        // Collect unique exercises performed
        var exerciseData: [String: [(date: Date, estimated1RM: Double)]] = [:]

        for workout in workouts {
            guard let workoutDate = workout.scheduledDate else { continue }

            let instances = InstanceResolver.instances(forWorkout: workout, for: userContext)

            for instance in instances {
                guard let exercise = TestDataManager.shared.exercises[instance.exerciseId] else { continue }

                // Apply muscle group filter if specified
                if let filterMuscle = request.muscleGroup {
                    guard exercise.muscleGroups.contains(filterMuscle) else { continue }
                }

                // Skip cardio exercises
                guard exercise.exerciseType != .cardio else { continue }

                let sets = InstanceResolver.sets(forInstance: instance, for: userContext)
                let completedSets = sets.filter { $0.completion == .completed }

                guard !completedSets.isEmpty else { continue }

                let setData = completedSets.enumerated().map { index, set in
                    SetDataForRM(
                        weight: set.actualWeight ?? 0,
                        reps: set.actualReps ?? 0,
                        setIndex: index
                    )
                }

                if let estimated1RM = OneRMCalculationService.selectBest1RM(from: setData), estimated1RM > 0 {
                    var data = exerciseData[instance.exerciseId] ?? []
                    data.append((workoutDate, estimated1RM))
                    exerciseData[instance.exerciseId] = data
                }
            }
        }

        // Analyze trends for exercises with 3+ data points
        var improving: [ExerciseTrend] = []
        var maintaining: [ExerciseTrend] = []
        var regressing: [ExerciseTrend] = []

        for (exerciseId, data) in exerciseData {
            guard data.count >= 2 else { continue }
            guard let exercise = TestDataManager.shared.exercises[exerciseId] else { continue }

            // Sort by date
            let sortedData = data.sorted { $0.date < $1.date }

            // Get first and last 1RMs
            let startingRM = sortedData.first!.estimated1RM
            let currentRM = sortedData.last!.estimated1RM
            let percentChange = ((currentRM - startingRM) / startingRM) * 100

            let trend = ExerciseTrend(
                exerciseId: exerciseId,
                exerciseName: exercise.name,
                muscleGroup: exercise.muscleGroups.first,
                startingEstimated1RM: startingRM,
                currentEstimated1RM: currentRM,
                percentChange: percentChange,
                sessionsAnalyzed: data.count
            )

            // Categorize: >5% improving, <-5% regressing, else maintaining
            if percentChange > 5 {
                improving.append(trend)
            } else if percentChange < -5 {
                regressing.append(trend)
            } else {
                maintaining.append(trend)
            }
        }

        // Sort by absolute percent change
        improving.sort { $0.percentChange > $1.percentChange }
        regressing.sort { $0.percentChange < $1.percentChange }

        return StrengthTrendsResult(
            dateRange: request.dateRange,
            improving: improving,
            maintaining: maintaining,
            regressing: regressing
        )
    }

    // MARK: - Period Comparison

    private static func comparePeriods(_ request: AnalysisRequest) -> PeriodComparisonResult? {
        guard let comparisonRange = request.comparisonDateRange else { return nil }

        // Get period A summary
        let periodARequest = AnalysisRequest(
            memberId: request.memberId,
            analysisType: .periodSummary,
            dateRange: request.dateRange,
            comparisonDateRange: nil,
            exerciseId: nil,
            muscleGroup: request.muscleGroup,
            includeDetails: false
        )
        let periodA = analyzePeriod(periodARequest)

        // Get period B summary
        let periodBRequest = AnalysisRequest(
            memberId: request.memberId,
            analysisType: .periodSummary,
            dateRange: comparisonRange,
            comparisonDateRange: nil,
            exerciseId: nil,
            muscleGroup: request.muscleGroup,
            includeDetails: false
        )
        let periodB = analyzePeriod(periodBRequest)

        // Calculate comparison metrics
        let volumeChange = periodA.totalVolume > 0
            ? ((periodB.totalVolume - periodA.totalVolume) / periodA.totalVolume) * 100
            : 0

        let periodAWeeks = max(1, request.dateRange.duration / (7 * 24 * 60 * 60))
        let periodBWeeks = max(1, comparisonRange.duration / (7 * 24 * 60 * 60))
        let periodAFrequency = Double(periodA.completedWorkouts) / periodAWeeks
        let periodBFrequency = Double(periodB.completedWorkouts) / periodBWeeks
        let frequencyChange = periodAFrequency > 0
            ? ((periodBFrequency - periodAFrequency) / periodAFrequency) * 100
            : 0

        let adherenceChange = (periodB.adherenceRate - periodA.adherenceRate) * 100

        // Compare top exercises
        var strengthChanges: [ExerciseComparison] = []
        let exercisesInBothPeriods = Set(periodA.topExercises.map { $0.exerciseId })
            .intersection(Set(periodB.topExercises.map { $0.exerciseId }))

        for exerciseId in exercisesInBothPeriods {
            guard let exerciseA = periodA.topExercises.first(where: { $0.exerciseId == exerciseId }),
                  let exerciseB = periodB.topExercises.first(where: { $0.exerciseId == exerciseId }) else {
                continue
            }

            var percentChange: Double? = nil
            if let rmA = exerciseA.estimated1RM, let rmB = exerciseB.estimated1RM, rmA > 0 {
                percentChange = ((rmB - rmA) / rmA) * 100
            }

            strengthChanges.append(ExerciseComparison(
                exerciseId: exerciseId,
                exerciseName: exerciseA.exerciseName,
                periodA1RM: exerciseA.estimated1RM,
                periodB1RM: exerciseB.estimated1RM,
                percentChange: percentChange
            ))
        }

        return PeriodComparisonResult(
            periodA: periodA,
            periodB: periodB,
            comparison: ComparisonMetrics(
                volumeChange: volumeChange,
                frequencyChange: frequencyChange,
                adherenceChange: adherenceChange,
                strengthChanges: strengthChanges
            )
        )
    }

    // MARK: - Trend Calculation Helpers

    private static func calculateTrend(from dataPoints: [ProgressionDataPoint]) -> TrendAnalysis {
        guard dataPoints.count >= 2 else {
            return TrendAnalysis(direction: .maintaining, percentChange: 0, weeklyRate: 0, confidence: 0)
        }

        // Simple linear regression on estimated 1RM over time
        let n = Double(dataPoints.count)
        let firstDate = dataPoints.first!.date

        // Convert dates to days from start
        let xValues = dataPoints.map { $0.date.timeIntervalSince(firstDate) / (24 * 60 * 60) }
        let yValues = dataPoints.map { $0.estimated1RM }

        let sumX = xValues.reduce(0, +)
        let sumY = yValues.reduce(0, +)
        let sumXY = zip(xValues, yValues).map { $0 * $1 }.reduce(0, +)
        let sumX2 = xValues.map { $0 * $0 }.reduce(0, +)

        let denominator = n * sumX2 - sumX * sumX
        guard denominator != 0 else {
            return TrendAnalysis(direction: .maintaining, percentChange: 0, weeklyRate: 0, confidence: 0)
        }

        let slope = (n * sumXY - sumX * sumY) / denominator
        let weeklyRate = slope * 7 // Convert daily rate to weekly

        // Calculate percent change
        let startRM = dataPoints.first!.estimated1RM
        let endRM = dataPoints.last!.estimated1RM
        let percentChange = startRM > 0 ? ((endRM - startRM) / startRM) * 100 : 0

        // Determine direction
        let direction: TrendDirection
        if percentChange > 5 {
            direction = .improving
        } else if percentChange < -5 {
            direction = .regressing
        } else {
            direction = .maintaining
        }

        // Calculate R-squared for confidence
        let meanY = sumY / n
        let ssTotal = yValues.map { pow($0 - meanY, 2) }.reduce(0, +)
        let intercept = (sumY - slope * sumX) / n
        let predictions = xValues.map { slope * $0 + intercept }
        let ssResidual = zip(yValues, predictions).map { pow($0 - $1, 2) }.reduce(0, +)
        let rSquared = ssTotal > 0 ? 1 - (ssResidual / ssTotal) : 0
        let confidence = min(1.0, max(0.0, rSquared))

        return TrendAnalysis(
            direction: direction,
            percentChange: percentChange,
            weeklyRate: weeklyRate,
            confidence: confidence
        )
    }
}
