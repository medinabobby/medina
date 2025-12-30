//
// WorkoutSkipService.swift
// Medina
//
// v46.3 - Workout Skip Service
// v168: Added DeltaStore and notification for consistency with handlers
// v209: Added workoutStatusDidChange notification definition (moved from deleted SkipWorkoutHandler)
// Created: October 30, 2025
//
// Purpose: Mark workouts as skipped with validation and persistence
// Used by: WorkoutSkipHandler (text queries) + ChatView (context menu actions)
//

import Foundation

// MARK: - Notification Names

extension NSNotification.Name {
    /// Posted when a workout's status changes (skipped, started, completed, etc.)
    /// Used by SidebarView to refresh workout lists
    static let workoutStatusDidChange = NSNotification.Name("workoutStatusDidChange")

    /// Posted when a plan's status changes (activated, abandoned, deleted, etc.)
    /// Used by SidebarView to refresh plan lists
    static let planStatusDidChange = NSNotification.Name("planStatusDidChange")
}

// MARK: - WorkoutSkipService

struct WorkoutSkipService {

    /// Skip a workout (mark as skipped)
    ///
    /// Validation:
    /// - Cannot skip completed workouts
    /// - Cannot skip if active session exists for workout
    ///
    /// Updates:
    /// - Sets workout.status = .skipped
    /// - Saves to DeltaStore (v168)
    /// - Persists to JSON
    /// - Posts notification (v168)
    ///
    /// - Parameters:
    ///   - workout: The workout to skip
    /// - Returns: Updated workout with .skipped status
    /// - Throws: WorkoutSkipError if validation fails
    static func skip(workout: Workout) async throws -> Workout {
        // 1. Validation: Cannot skip completed workouts
        guard workout.status != .completed else {
            throw WorkoutSkipError.alreadyCompleted(workoutName: workout.name)
        }

        // 2. Validation: Cannot skip if active session exists
        // Check if there's an active session for this workout
        let activeSession = LocalDataStore.shared.sessions.values.first { session in
            session.workoutId == workout.id && session.status == .active
        }

        if activeSession != nil {
            throw WorkoutSkipError.sessionInProgress(workoutName: workout.name)
        }

        // 3. Update workout status
        var updatedWorkout = workout
        updatedWorkout.status = .skipped

        // 4. Persist to in-memory store
        LocalDataStore.shared.workouts[workout.id] = updatedWorkout

        // v168: Save to DeltaStore for sync/audit consistency
        let delta = DeltaStore.WorkoutDelta(
            workoutId: workout.id,
            scheduledDate: nil,
            completion: .skipped
        )
        DeltaStore.shared.saveWorkoutDelta(delta)

        // 5. Persist to disk (all workouts for this member)
        // Get member ID through plan → program hierarchy
        guard let program = LocalDataStore.shared.programs.values.first(where: { $0.id == workout.programId }),
              let plan = LocalDataStore.shared.plans.values.first(where: { $0.id == program.planId }) else {
            // Rollback if we can't find parent plan
            LocalDataStore.shared.workouts[workout.id] = workout
            throw WorkoutSkipError.persistenceFailed
        }

        let memberId = plan.memberId

        // v206: Sync to Firestore (fire-and-forget)
        Task {
            do {
                try await FirestoreWorkoutRepository.shared.saveWorkout(updatedWorkout, memberId: memberId)
            } catch {
                Logger.log(.warning, component: "WorkoutSkipService",
                          message: "⚠️ Firestore sync failed: \(error)")
            }
        }

        Logger.log(.info, component: "WorkoutSkipService", message: "Skipped workout: \(workout.id) (\(workout.name))")

        // v168: Post notification so sidebar refreshes
        NotificationCenter.default.post(name: .workoutStatusDidChange, object: nil)

        return updatedWorkout
    }

    /// Skip summary for confirmation messages
    static func skipSummary(for workout: Workout) -> String {
        var parts: [String] = []

        // Date
        if let scheduledDate = workout.scheduledDate {
            let dateStr = DateFormatters.dayOfWeekFormatter.string(from: scheduledDate) + ", " +
                         DateFormatters.shortMonthDayFormatter.string(from: scheduledDate)
            parts.append(dateStr)
        }

        // Type + Split
        parts.append(workout.type.displayName)
        if let splitDay = workout.splitDay {
            parts.append(splitDay.displayName)
        }

        return parts.joined(separator: " • ")
    }

    /// Get all workouts for member (for persistence)
    private static func getMemberWorkouts(memberId: String) -> [Workout] {
        let allPlans = LocalDataStore.shared.plans.values.filter { $0.memberId == memberId }
        let planIds = Set(allPlans.map { $0.id })
        let programs = LocalDataStore.shared.programs.values.filter { planIds.contains($0.planId) }
        let programIds = Set(programs.map { $0.id })
        return Array(LocalDataStore.shared.workouts.values.filter { programIds.contains($0.programId) })
    }
}

// MARK: - Errors

enum WorkoutSkipError: Error {
    case alreadyCompleted(workoutName: String)
    case sessionInProgress(workoutName: String)
    case notFound
    case persistenceFailed

    var userMessage: String {
        switch self {
        case .alreadyCompleted(let workoutName):
            return "Cannot skip '\(workoutName)' - it's already completed."
        case .sessionInProgress(let workoutName):
            return "Cannot skip '\(workoutName)' - there's an active session. Abandon the session first."
        case .notFound:
            return "Workout not found."
        case .persistenceFailed:
            return "Failed to save changes. Please try again."
        }
    }
}
