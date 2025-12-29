//
// WorkoutFilteringService.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

// MARK: - Workout Filtering Service

/// Provides specialized filtering logic for workouts, extracted from WorkoutDataStore
/// to improve separation of concerns and testability.
enum WorkoutFilteringService {

    // MARK: - Temporal Filtering

    /// Filter workouts by temporal criteria
    static func filterByTemporal(_ workouts: [Workout], temporal: TemporalSlot, referenceDate: Date = Date()) -> [Workout] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)

        switch temporal {
        case .today:
            return workouts.filter { workout in
                guard let date = workout.scheduledDate else { return false }
                return calendar.isDate(date, inSameDayAs: today)
            }

        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
            return workouts.filter { workout in
                guard let date = workout.scheduledDate else { return false }
                return calendar.isDate(date, inSameDayAs: tomorrow)
            }

        case .thisWeek:
            return workouts.filter { workout in
                guard let date = workout.scheduledDate else { return false }
                return calendar.isDate(date, equalTo: today, toGranularity: .weekOfYear) && date >= today
            }

        case .upcoming:
            return workouts.filter { workout in
                // Include workouts without dates (they're available anytime)
                guard let date = workout.scheduledDate else { return true }
                return date >= today
            }

        case .past:
            return workouts.filter { workout in
                guard let date = workout.scheduledDate else { return false }
                return date < today
            }

        case .unspecified:
            return workouts
        }
    }

    // MARK: - Status Filtering

    /// Filter workouts by status criteria
    static func filterByStatus(_ workouts: [Workout], status: WorkoutStatus?, referenceDate: Date = Date()) -> [Workout] {
        guard let status = status else { return workouts }

        return workouts.filter { workout in
            matchesStatus(workout, status: status, referenceDate: referenceDate)
        }
    }

    private static func matchesStatus(_ workout: Workout, status: WorkoutStatus, referenceDate: Date) -> Bool {
        _ = referenceDate  // Reserved for future temporal status filtering

        // Map WorkoutStatus to ExecutionStatus for filtering
        switch status {
        case .scheduled:
            return workout.status == .scheduled
        case .inProgress:
            return workout.status == .inProgress
        case .completed:
            return workout.status == .completed
        case .skipped:
            return workout.status == .skipped
        }
    }

    // MARK: - Modality Filtering

    /// Filter workouts by modality type
    static func filterByModality(_ workouts: [Workout], modality: ModalitySlot) -> [Workout] {
        return workouts.filter { workout in
            matchesModality(workout, modality: modality)
        }
    }

    private static func matchesModality(_ workout: Workout, modality: ModalitySlot) -> Bool {
        switch modality {
        case .unspecified:
            return true
        case .cardio:
            return workout.type == .cardio
        case .strength:
            return workout.type == .strength || workout.type == .hybrid
        case .mobility:
            return workout.type == .mobility
        case .recovery:
            return workout.type == .mobility || workout.type == .hybrid
        }
    }

    // MARK: - Split Day Filtering (v16.7)

    /// Filter workouts by split day type
    static func filterBySplitDay(_ workouts: [Workout], splitDay: SplitDay?) -> [Workout] {
        guard let splitDay = splitDay else { return workouts }

        return workouts.filter { workout in
            workout.splitDay == splitDay
        }
    }

    // MARK: - Plan/Program Filtering (v116.5: Re-enabled for sidebar)

    /// Filter workouts by plan (includes all programs in that plan)
    static func filterByPlan(_ workouts: [Workout], plan: Plan?) -> [Workout] {
        guard let plan = plan else { return workouts }
        let programIds = Set(ProgramDataStore.programs(for: plan.id).map { $0.id })
        return workouts.filter { programIds.contains($0.programId) }
    }

    /// Filter workouts by specific program
    static func filterByProgram(_ workouts: [Workout], program: Program?) -> [Workout] {
        guard let program = program else { return workouts }
        return workouts.filter { $0.programId == program.id }
    }

    // MARK: - Date Interval Filtering

    /// Filter workouts by date interval
    static func filterByDateInterval(_ workouts: [Workout], interval: DateInterval?) -> [Workout] {
        guard let interval else { return workouts }

        return workouts.filter { workout in
            guard let date = workout.scheduledDate else { return false }
            return interval.contains(date)
        }
    }

    // MARK: - Sorting

    /// Sort workouts based on temporal context
    static func sort(_ workouts: [Workout], temporal: TemporalSlot) -> [Workout] {
        switch temporal {
        case .past:
            return workouts.sorted(by: { ascendingSchedule($1, $0) })
        default:
            return workouts.sorted(by: ascendingSchedule)
        }
    }

    private static func ascendingSchedule(_ lhs: Workout, _ rhs: Workout) -> Bool {
        let lhsDate = lhs.scheduledDate ?? Date.distantFuture
        let rhsDate = rhs.scheduledDate ?? Date.distantFuture
        if lhsDate == rhsDate {
            return lhs.id < rhs.id
        }
        return lhsDate < rhsDate
    }

    // MARK: - Utility

    /// Check if a workout is incomplete
    static func isIncomplete(_ workout: Workout) -> Bool {
        workout.status != .completed  // ExecutionStatus.completed
    }

    // MARK: - Composite Filtering

    /// Apply all filters in the correct order for consistent behavior
    static func applyFilters(
        to workouts: [Workout],
        temporal: TemporalSlot,
        status: WorkoutStatus?,
        modality: ModalitySlot,
        splitDay: SplitDay? = nil,
        plan: Plan?,
        program: Program?,
        dateInterval: DateInterval?,
        referenceDate: Date = Date()
    ) -> [Workout] {
        let temporalFiltered = filterByTemporal(workouts, temporal: temporal, referenceDate: referenceDate)
        let statusFiltered = filterByStatus(temporalFiltered, status: status, referenceDate: referenceDate)
        let modalityFiltered = filterByModality(statusFiltered, modality: modality)
        let splitDayFiltered = filterBySplitDay(modalityFiltered, splitDay: splitDay)
        // v116.5: Re-enabled plan/program filtering for sidebar
        let planFiltered = filterByPlan(splitDayFiltered, plan: plan)
        let programFiltered = filterByProgram(planFiltered, program: program)
        let intervalFiltered = filterByDateInterval(programFiltered, interval: dateInterval)

        return sort(intervalFiltered, temporal: temporal)
    }
}