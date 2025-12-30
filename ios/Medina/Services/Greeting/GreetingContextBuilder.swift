//
// GreetingContextBuilder.swift
// Medina
//
// v99.7: Assembles rich context for trainer-style greetings
//

import Foundation

/// Builds GreetingContext by querying various data stores
@MainActor
struct GreetingContextBuilder {

    // MARK: - Public API

    /// Build complete greeting context for a user
    static func build(for user: UnifiedUser) -> GreetingContext {
        let userId = user.id

        // Get active plan and progress
        let plan = PlanResolver.activePlan(for: userId)
        let planProgress = plan.map { calculatePlanProgress(plan: $0, memberId: userId) }
        let weeksRemaining = plan.map { calculateWeeksRemaining(plan: $0) }

        // Get today's scheduled workout
        let todaysWorkout = getTodaysScheduledWorkout(for: userId)

        // v136: Get next scheduled workout (fallback when no workout today)
        let nextWorkout = todaysWorkout == nil ? getNextScheduledWorkout(for: userId) : nil

        // Get in-progress workout
        let inProgressWorkout = getInProgressWorkout(for: userId)
        let (completedExercises, totalExercises) = getInProgressExerciseCounts(workout: inProgressWorkout)

        // Calculate adherence metrics
        let daysSinceLastWorkout = calculateDaysSinceLastWorkout(for: userId)
        let completedThisWeek = getCompletedWorkoutsThisWeek(for: userId)
        let targetThisWeek = plan.map { $0.weightliftingDays + $0.cardioDays } ?? 0
        let remainingThisWeek = getRemainingWorkoutsThisWeek(for: userId)

        // Get workout details
        let workout = inProgressWorkout ?? todaysWorkout
        let exerciseCount = workout?.exerciseIds.count ?? 0
        let durationMinutes = plan?.targetSessionDuration

        return GreetingContext(
            planName: plan?.name,
            planProgressPercent: planProgress,
            weeksRemaining: weeksRemaining,
            todaysWorkout: todaysWorkout,
            nextWorkout: nextWorkout,
            workoutType: workout?.type,
            splitDay: workout?.splitDay,
            exerciseCount: exerciseCount,
            durationMinutes: durationMinutes,
            inProgressWorkout: inProgressWorkout,
            completedExercises: completedExercises,
            totalExercises: totalExercises,
            daysSinceLastWorkout: daysSinceLastWorkout,
            completedThisWeek: completedThisWeek,
            targetThisWeek: targetThisWeek,
            remainingThisWeek: remainingThisWeek
        )
    }

    // MARK: - Plan Progress

    /// Calculate time-based plan progress (% of duration elapsed)
    /// This ensures progress % and weeks remaining are consistent
    private static func calculatePlanProgress(plan: Plan, memberId: String) -> Int {
        let calendar = Calendar.current
        let today = Date()
        let startDate = plan.startDate
        let endDate = plan.endDate

        // If plan hasn't started yet
        guard today >= startDate else { return 0 }

        // If plan is complete
        guard today < endDate else { return 100 }

        // Calculate time-based progress
        let totalDays = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1
        let elapsedDays = calendar.dateComponents([.day], from: startDate, to: today).day ?? 0

        guard totalDays > 0 else { return 0 }

        let progress = Double(elapsedDays) / Double(totalDays) * 100
        return min(99, Int(progress)) // Cap at 99% until actually complete
    }

    private static func calculateWeeksRemaining(plan: Plan) -> Int {
        let calendar = Calendar.current
        let today = Date()
        let endDate = plan.endDate

        guard endDate > today else { return 0 }

        let days = calendar.dateComponents([.day], from: today, to: endDate).day ?? 0
        return max(1, (days + 6) / 7) // Round up to nearest week
    }

    // MARK: - Today's Workout

    private static func getTodaysScheduledWorkout(for userId: String) -> Workout? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let todayInterval = DateInterval(start: today, end: tomorrow)

        let todaysWorkouts = WorkoutResolver.workouts(
            for: userId,
            temporal: .upcoming,
            status: .scheduled,
            modality: .unspecified,
            splitDay: nil,
            source: nil,
            plan: PlanResolver.activePlan(for: userId),
            program: nil,
            dateInterval: todayInterval
        )

        return todaysWorkouts.first
    }

    // MARK: - v136: Next Scheduled Workout

    /// Get the next scheduled workout (when no workout today)
    /// v136: Fixed to use TODAY as start date to exclude past-dated workouts
    private static func getNextScheduledWorkout(for userId: String) -> Workout? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let upcomingWorkouts = WorkoutResolver.workouts(
            for: userId,
            temporal: .upcoming,
            status: .scheduled,
            modality: .unspecified,
            splitDay: nil,
            source: nil,
            plan: PlanResolver.activePlan(for: userId),
            program: nil,
            dateInterval: DateInterval(start: today, end: Date.distantFuture)
        )

        // Sort ascending to get earliest workout first
        // WorkoutDataStore returns descending order, but we need the EARLIEST upcoming workout
        return upcomingWorkouts
            .sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
            .first
    }

    // MARK: - In-Progress Workout

    /// v161: Check active session FIRST, then fall back to workout status
    private static func getInProgressWorkout(for userId: String) -> Workout? {
        // Priority 1: Active session (most accurate, in-memory state)
        if let activeSession = LocalDataStore.shared.activeSession(for: userId),
           let workout = LocalDataStore.shared.workouts[activeSession.workoutId] {
            return workout
        }

        // Priority 2: Workout with .inProgress status (persisted fallback after app restart)
        let workouts = WorkoutDataStore.workouts(for: userId, temporal: .unspecified, dateInterval: nil)
        return workouts.first { $0.status == .inProgress }
    }

    private static func getInProgressExerciseCounts(workout: Workout?) -> (completed: Int, total: Int) {
        guard let workout = workout else { return (0, 0) }

        let instances = InstanceDataStore.instances(forWorkout: workout.id)
        let completed = instances.filter { $0.status == .completed }.count
        let total = instances.count

        return (completed, total)
    }

    // MARK: - Adherence Metrics

    private static func calculateDaysSinceLastWorkout(for userId: String) -> Int? {
        let workouts = WorkoutDataStore.workouts(for: userId, temporal: .past, dateInterval: nil)
        let completedWorkouts = workouts
            .filter { $0.status == .completed }
            .sorted { ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast) }

        guard let lastWorkout = completedWorkouts.first,
              let completedDate = lastWorkout.completedDate else {
            return nil
        }

        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: completedDate, to: Date()).day
    }

    private static func getCompletedWorkoutsThisWeek(for userId: String) -> Int {
        let calendar = Calendar.current
        let today = Date()

        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else {
            return 0
        }

        let thisWeekInterval = DateInterval(start: weekStart, end: today)
        let workouts = WorkoutDataStore.workouts(
            for: userId,
            temporal: .past,
            dateInterval: thisWeekInterval
        )

        return workouts.filter { $0.status == .completed }.count
    }

    private static func getRemainingWorkoutsThisWeek(for userId: String) -> Int {
        let calendar = Calendar.current
        let today = Date()

        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)),
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return 0
        }

        let remainingInterval = DateInterval(start: today, end: weekEnd)
        let workouts = WorkoutDataStore.workouts(
            for: userId,
            temporal: .upcoming,
            dateInterval: remainingInterval
        )

        return workouts.filter { $0.status == .scheduled }.count
    }
}
