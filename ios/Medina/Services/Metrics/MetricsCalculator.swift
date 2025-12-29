//
// MetricsCalculator.swift
// Medina
//
// Core metrics calculator for all display metrics (workout/program/plan)
//

import Foundation

struct ProgressBreakdown: Equatable {
    let completed: Int
    let total: Int
    let percentage: Double  // v19.2: Completed/total ratio (0.0 to 1.0)

    init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
        self.percentage = total > 0 ? Double(completed) / Double(total) : 0.0
    }

    func adding(_ other: ProgressBreakdown) -> ProgressBreakdown {
        ProgressBreakdown(
            completed: completed + other.completed,
            total: total + other.total
        )
    }

    /// v19.2: Formatted percentage string for display
    var formattedPercentage: String {
        String(format: "%.0f%%", percentage * 100)
    }
}

struct CardProgressMetrics: Equatable {
    let sessions: ProgressBreakdown
    let exercises: ProgressBreakdown
    let sets: ProgressBreakdown
    let reps: ProgressBreakdown

    // v19.3.1: Session type breakdown (for plans only)
    let strengthSessions: ProgressBreakdown?
    let cardioSessions: ProgressBreakdown?

    init(sessions: ProgressBreakdown, exercises: ProgressBreakdown, sets: ProgressBreakdown, reps: ProgressBreakdown, strengthSessions: ProgressBreakdown? = nil, cardioSessions: ProgressBreakdown? = nil) {
        self.sessions = sessions
        self.exercises = exercises
        self.sets = sets
        self.reps = reps
        self.strengthSessions = strengthSessions
        self.cardioSessions = cardioSessions
    }

    static var zero: CardProgressMetrics {
        CardProgressMetrics(
            sessions: ProgressBreakdown(completed: 0, total: 0),
            exercises: ProgressBreakdown(completed: 0, total: 0),
            sets: ProgressBreakdown(completed: 0, total: 0),
            reps: ProgressBreakdown(completed: 0, total: 0),
            strengthSessions: nil,
            cardioSessions: nil
        )
    }

    func adding(_ other: CardProgressMetrics) -> CardProgressMetrics {
        CardProgressMetrics(
            sessions: sessions.adding(other.sessions),
            exercises: exercises.adding(other.exercises),
            sets: sets.adding(other.sets),
            reps: reps.adding(other.reps),
            strengthSessions: combineOptional(strengthSessions, other.strengthSessions),
            cardioSessions: combineOptional(cardioSessions, other.cardioSessions)
        )
    }

    private func combineOptional(_ a: ProgressBreakdown?, _ b: ProgressBreakdown?) -> ProgressBreakdown? {
        switch (a, b) {
        case (.some(let aVal), .some(let bVal)):
            return aVal.adding(bVal)
        case (.some(let aVal), .none):
            return aVal
        case (.none, .some(let bVal)):
            return bVal
        case (.none, .none):
            return nil
        }
    }
}

enum MetricsCalculator {

    static func workoutProgress(for workout: Workout, memberId: String?) -> CardProgressMetrics {
        // v17.5 fix: Reload latest deltas from UserDefaults before calculating
        // During a workout session, deltas are saved but not re-applied to TestDataManager
        // This ensures we see the most recent set/instance/workout completion data
        let manager = TestDataManager.shared
        manager.exerciseSets = DeltaStore.shared.applySetDeltas(to: manager.exerciseSets)
        manager.exerciseInstances = DeltaStore.shared.applyInstanceDeltas(to: manager.exerciseInstances)
        manager.workouts = DeltaStore.shared.applyWorkoutDeltas(to: manager.workouts)

        // Reload the workout to get latest completion status from deltas
        guard let updatedWorkout = manager.workouts[workout.id] else {
            return .zero
        }

        // v35.3: Only count exercises for strength/hybrid workouts
        // Cardio workouts have exerciseIds but no instances/sets/reps tracked
        let totalExercises = (updatedWorkout.type == .strength || updatedWorkout.type == .hybrid) ? updatedWorkout.exerciseIds.count : 0
        var completedExercises = 0

        // v35.3: Debug logging to verify cardio exclusion
        if updatedWorkout.type == .cardio {
            Logger.log(.debug, component: "MetricsCalculator",
                      message: "🏃 Cardio workout \(updatedWorkout.id): totalExercises=0 (excluded from exercise metrics)")
        } else if totalExercises > 0 {
            Logger.log(.debug, component: "MetricsCalculator",
                      message: "💪 Strength workout \(updatedWorkout.id): totalExercises=\(totalExercises)")
        }

        var totalSets = 0
        var completedSets = 0

        var totalReps = 0
        var completedReps = 0

        let userContext = memberId.map { UserContext(userId: $0) }
        var instanceByExercise: [String: ExerciseInstance] = [:]

        if let context = userContext {
            let instances = InstanceResolver.instances(forWorkout: updatedWorkout, for: context)
            for instance in instances {
                instanceByExercise[instance.exerciseId] = instance

                // v17.5: Count exercise as completed if ANY set has actualReps > 0 (attempted)
                // This ensures: 1 set attempted = 1/6 exercises, 0 sets attempted = 0/6 exercises
                let sets = InstanceResolver.sets(forInstance: instance, for: context)
                let hasAttemptedSet = sets.contains { ($0.actualReps ?? 0) > 0 }
                if instance.status == .completed || hasAttemptedSet {
                    completedExercises += 1
                }
            }
        }

        for (index, exerciseId) in updatedWorkout.exerciseIds.enumerated() {
            guard let context = userContext else {
                continue
            }

            // Calculate expected sets from protocol config
            let protocolVariantId = updatedWorkout.protocolVariantIds[index] ?? "strength_3x8_moderate"
            let expectedSetsCount: Int
            let repsPerSet: Int

            if let protocolConfig = TestDataManager.shared.protocolConfigs[protocolVariantId] {
                // ProtocolConfig has reps: [Int] array (one per set)
                expectedSetsCount = protocolConfig.reps.count
                // For reps calculation, use first set's target (assumes uniform reps per set)
                repsPerSet = protocolConfig.reps.first ?? 8
            } else {
                // Fallback: assume 3 sets of 8 reps
                expectedSetsCount = 3
                repsPerSet = 8
            }

            // v58.3: "Assigned Universe" - include ALL exercises in denominator
            // Add expected sets/reps regardless of whether exercise was attempted
            totalSets += expectedSetsCount
            totalReps += expectedSetsCount * repsPerSet

            // Only count completed sets/reps if exercise was attempted
            if let instance = instanceByExercise[exerciseId] {
                let sets = InstanceResolver.sets(forInstance: instance, for: context)
                completedSets += sets.filter { $0.completion == .completed }.count
                completedReps += sets.compactMap { $0.actualReps }.reduce(0, +)
            }
            // If exercise was skipped: completed stays at 0, but total is still counted
        }

        if memberId == nil {
            completedExercises = 0
        }

        let sessionProgress = ProgressBreakdown(
            completed: updatedWorkout.status == .completed ? 1 : 0,
            total: 1
        )

        let exerciseProgress = ProgressBreakdown(
            completed: completedExercises,
            total: totalExercises
        )

        let setProgress = ProgressBreakdown(
            completed: completedSets,
            total: totalSets
        )

        let repProgress = ProgressBreakdown(
            completed: completedReps,
            total: totalReps
        )

        let metrics = CardProgressMetrics(
            sessions: sessionProgress,
            exercises: exerciseProgress,
            sets: setProgress,
            reps: repProgress
        )

        // v19.8: Removed verbose metrics logging (metrics visible in UI cards)

        return metrics
    }

    static func programProgress(for program: Program, memberId: String?) -> CardProgressMetrics {
        let workouts = WorkoutDataStore.workouts(forProgramId: program.id)

        return workouts.reduce(CardProgressMetrics.zero) { partialResult, workout in
            partialResult.adding(workoutProgress(for: workout, memberId: memberId))
        }
    }

    // MARK: - v34.1: Performance-Based Progress Tracking

    /// Calculate performance metrics for a program (time-aware)
    ///
    /// **Performance Tracking vs Progress Tracking:**
    /// - Progress: Completed / Total in program (e.g., 11/22 = 50%)
    /// - Performance: Completed / Assigned up to today (e.g., 11/15 = 73%)
    ///
    /// **v58.3: "Assigned Universe" Principle (updated from "Attempted"):**
    /// - Sessions: Completed / Assigned (adherence metric)
    /// - Exercises: Completed / Expected in workout (coverage metric)
    /// - Sets: Completed / Expected in **all** exercises (thoroughness metric)
    /// - Reps: Completed / Expected in **all** exercises (thoroughness metric)
    ///
    /// **Why "Assigned" not "Attempted"?**
    /// - Users expect intuitive metrics: "I did 42% of my workout" not "62% of what I tried"
    /// - Skipped exercises should count against completion percentages
    /// - Single number tells the full story without needing to cross-reference
    ///
    /// - Parameters:
    ///   - program: Program to evaluate
    ///   - memberId: Member ID for exercise instance lookup
    /// - Returns: CardProgressMetrics with performance-based percentages
    static func programPerformance(for program: Program, memberId: String?) -> CardProgressMetrics {
        let allWorkouts = WorkoutDataStore.workouts(forProgramId: program.id)
        let today = Date()

        // Filter to "assigned" workouts (scheduled before today, or today if completed)
        let assignedWorkouts = allWorkouts.filter { workout in
            guard let scheduledDate = workout.scheduledDate else { return false }

            // Before today: always assigned
            if scheduledDate < today {
                return true
            }

            // Today: only assigned if completed
            if Calendar.current.isDate(scheduledDate, inSameDayAs: today) {
                return workout.status == .completed
            }

            // Future: not yet assigned
            return false
        }

        // Filter to "attempted" workouts (completed or in-progress, NOT skipped/scheduled)
        // These are the parent universe for child metrics (exercises/sets/reps)
        let attemptedWorkouts = assignedWorkouts.filter { workout in
            workout.status == .completed || workout.status == .inProgress
        }

        // Session metric: Completed / Assigned (adherence - includes skipped)
        let completedSessions = attemptedWorkouts.filter { $0.status == .completed }.count
        let sessionProgress = ProgressBreakdown(completed: completedSessions, total: assignedWorkouts.count)

        // v34.1.2: Filter to STRENGTH workouts only for exercise/set/rep metrics
        // Cardio workouts have exerciseIds but no instances/sets/reps tracked
        let attemptedStrengthWorkouts = attemptedWorkouts.filter { workout in
            workout.type == .strength || workout.type == .hybrid
        }

        // Child metrics: Only from attempted strength workouts (excludes cardio)
        let childMetrics = attemptedStrengthWorkouts.reduce(CardProgressMetrics.zero) { partialResult, workout in
            partialResult.adding(workoutProgress(for: workout, memberId: memberId))
        }

        // Combine: session from assigned, children from attempted
        return CardProgressMetrics(
            sessions: sessionProgress,
            exercises: childMetrics.exercises,
            sets: childMetrics.sets,
            reps: childMetrics.reps
        )
    }

    /// Calculate performance metrics for a plan (time-aware, performance vs assigned workouts)
    ///
    /// Aggregates performance across all programs in the plan using time-aware assignment logic.
    ///
    /// - Parameters:
    ///   - plan: Plan to evaluate
    ///   - memberId: Member ID for exercise instance lookup
    /// - Returns: CardProgressMetrics with performance-based percentages
    static func planPerformance(for plan: Plan, memberId: String?) -> CardProgressMetrics {
        let programs = ProgramDataStore.programs(for: plan.id)

        let metrics = programs.reduce(CardProgressMetrics.zero) { partialResult, program in
            partialResult.adding(programPerformance(for: program, memberId: memberId))
        }

        // v19.3.1: Calculate session type breakdown (using performance-based logic)
        let allWorkouts = programs.flatMap { program in
            WorkoutDataStore.workouts(forProgramId: program.id)
        }

        let today = Date()
        let assignedWorkouts = allWorkouts.filter { workout in
            guard let scheduledDate = workout.scheduledDate else { return false }
            return scheduledDate < today || (Calendar.current.isDate(scheduledDate, inSameDayAs: today) && workout.status == .completed)
        }

        let strengthWorkouts = assignedWorkouts.filter { $0.type == .strength }
        let cardioWorkouts = assignedWorkouts.filter { $0.type == .cardio }

        let strengthCompleted = strengthWorkouts.filter { $0.status == .completed }.count
        let cardioCompleted = cardioWorkouts.filter { $0.status == .completed }.count

        let strengthBreakdown = strengthWorkouts.isEmpty ? nil : ProgressBreakdown(completed: strengthCompleted, total: strengthWorkouts.count)
        let cardioBreakdown = cardioWorkouts.isEmpty ? nil : ProgressBreakdown(completed: cardioCompleted, total: cardioWorkouts.count)

        return CardProgressMetrics(
            sessions: metrics.sessions,
            exercises: metrics.exercises,
            sets: metrics.sets,
            reps: metrics.reps,
            strengthSessions: strengthBreakdown,
            cardioSessions: cardioBreakdown
        )
    }

    static func planProgress(for plan: Plan, memberId: String?) -> CardProgressMetrics {
        let programs = ProgramDataStore.programs(for: plan.id)

        let metrics = programs.reduce(CardProgressMetrics.zero) { partialResult, program in
            partialResult.adding(programProgress(for: program, memberId: memberId))
        }

        // v19.3.1: Calculate session type breakdown
        let allWorkouts = programs.flatMap { program in
            WorkoutDataStore.workouts(forProgramId: program.id)
        }

        let strengthWorkouts = allWorkouts.filter { $0.type == .strength }
        let cardioWorkouts = allWorkouts.filter { $0.type == .cardio }

        let strengthCompleted = strengthWorkouts.filter { $0.status == .completed }.count
        let cardioCompleted = cardioWorkouts.filter { $0.status == .completed }.count

        let strengthBreakdown = strengthWorkouts.isEmpty ? nil : ProgressBreakdown(completed: strengthCompleted, total: strengthWorkouts.count)
        let cardioBreakdown = cardioWorkouts.isEmpty ? nil : ProgressBreakdown(completed: cardioCompleted, total: cardioWorkouts.count)

        // v19.2: Debug logging for plan metrics verification
        // v19.8: Removed verbose metrics logging (metrics visible in UI cards)

        return CardProgressMetrics(
            sessions: metrics.sessions,
            exercises: metrics.exercises,
            sets: metrics.sets,
            reps: metrics.reps,
            strengthSessions: strengthBreakdown,
            cardioSessions: cardioBreakdown
        )
    }
}
