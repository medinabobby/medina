//
// EntityListFormatters.swift
// Medina
//
// v54.7: Helper functions to format entities for EntityListModal display
// v99.1: Added user formatter for admin sidebar
// v158: Check for active session when determining workout status color
// v186: Removed class formatters (class booking deferred for beta)
// Created: November 2025
// Purpose: Convert domain models to StatusListRowConfig for consistent UI
//

import Foundation
import SwiftUI

/// Formats entities for display in EntityListModal using StatusListRow
enum EntityListFormatters {

    // MARK: - Workout Formatting

    /// v101.5: Simplified workout formatting
    /// - Removed redundant status text (colored stripe indicates status)
    /// - Subtitle: Type or split day (e.g., "Cardio" or "Full Body")
    /// - Metadata: Exercise count + duration only if exercises exist
    static func formatWorkout(_ workout: Workout) -> StatusListRowConfig {
        // Title: Date + name
        let title: String = {
            guard let date = workout.scheduledDate else {
                return workout.name
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: date)) - \(workout.name)"
        }()

        // v101.5: Subtitle - just type/split, no status (stripe shows that)
        let subtitle: String? = {
            if workout.type == .cardio {
                return "Cardio"
            } else {
                // For strength: show split day name
                return workout.splitDay?.displayName ?? "Strength"
            }
        }()

        // Metadata: Exercise count + duration (only if exercises exist)
        let metadata: String? = {
            var parts: [String] = []

            let exerciseCount = workout.exerciseIds.count
            if exerciseCount > 0 {
                parts.append("\(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s")")

                // Calculate duration from instances if available
                let instances = LocalDataStore.shared.exerciseInstances.values.filter { $0.workoutId == workout.id }
                let protocolConfigs = instances.compactMap { instance in
                    LocalDataStore.shared.protocolConfigs[instance.protocolVariantId]
                }
                if !protocolConfigs.isEmpty {
                    // v132: Include transition time (90s) to match DurationAwareWorkoutBuilder
                    let minutes = ExerciseTimeCalculator.calculateWorkoutTime(
                        protocolConfigs: protocolConfigs,
                        workoutType: workout.type,
                        restBetweenExercises: 90
                    )
                    if minutes > 0 {
                        parts.append("~\(minutes) min")
                    }
                }
            }
            // v101.5: Don't show "0 exercises" - just show nothing until runtime selection

            return parts.isEmpty ? nil : parts.joined(separator: " • ")
        }()

        // Status color based on execution status
        // v158: Check for active session - if this workout has an active session, show blue
        let statusColor: Color = {
            // Check if there's an active session for this workout
            let hasActiveSession = LocalDataStore.shared.sessions.values.contains { session in
                session.workoutId == workout.id && session.status == .active
            }

            if hasActiveSession {
                return .blue  // Active session = blue, regardless of original status
            }

            switch workout.status {
            case .completed:
                return .green
            case .inProgress:
                return .blue
            case .scheduled:
                return Color("SecondaryText")
            case .skipped:
                return .orange
            }
        }()

        return StatusListRowConfig(
            number: nil,
            title: title,
            subtitle: subtitle,
            metadata: metadata,
            statusText: nil,
            statusColor: statusColor,
            timeText: nil
        )
    }

    // MARK: - Exercise Formatting

    static func formatExercise(_ exercise: Exercise) -> StatusListRowConfig {
        let title = exercise.exerciseDisplayName

        // Subtitle: Type and equipment
        let subtitle: String? = {
            var parts: [String] = []

            // Type
            parts.append(exercise.type.rawValue.capitalized)

            // Equipment if not bodyweight
            if exercise.equipment != .bodyweight {
                parts.append(exercise.equipment.rawValue.capitalized)
            }

            return parts.isEmpty ? nil : parts.joined(separator: " • ")
        }()

        return StatusListRowConfig(
            number: nil,
            title: title,
            subtitle: subtitle,
            metadata: nil,
            statusText: nil,
            statusColor: Color("SecondaryText"),
            timeText: nil
        )
    }

    // MARK: - Protocol Formatting

    static func formatProtocol(_ config: ProtocolConfig) -> StatusListRowConfig {
        let title = config.variantName

        // Subtitle: Structure description (sets × reps)
        let subtitle: String? = {
            let setCount = config.reps.count
            let repsText: String

            // Check if all reps are the same
            let uniqueReps = Set(config.reps)
            if uniqueReps.count == 1, let reps = uniqueReps.first {
                repsText = "\(reps)"
            } else {
                // Variable reps - show range
                if let minReps = config.reps.min(), let maxReps = config.reps.max() {
                    repsText = "\(minReps)-\(maxReps)"
                } else {
                    repsText = "varied"
                }
            }

            return "\(setCount) × \(repsText)"
        }()

        // Metadata: Rest time
        let metadata: String? = {
            // Use first rest period if available
            if let firstRest = config.restBetweenSets.first, firstRest > 0 {
                return "\(firstRest)s rest"
            }
            return nil
        }()

        return StatusListRowConfig(
            number: nil,
            title: title,
            subtitle: subtitle,
            metadata: metadata,
            statusText: nil,
            statusColor: Color("SecondaryText"),
            timeText: nil
        )
    }

    // MARK: - Plan Formatting

    static func formatPlan(_ plan: Plan) -> StatusListRowConfig {
        let title = plan.name

        // Subtitle: Status and date range
        let subtitle: String? = {
            var parts: [String] = []

            // Status badge
            // v172: Removed abandoned - plans are now draft/active/completed only
            switch plan.status {
            case .active:
                parts.append("Active")
            case .draft:
                parts.append("Draft")
            case .completed:
                parts.append("Completed")
            }

            // Date range
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            parts.append("\(formatter.string(from: plan.startDate)) - \(formatter.string(from: plan.endDate))")

            return parts.joined(separator: " • ")
        }()

        // Metadata: Training frequency
        let metadata: String? = {
            let totalDays = plan.weightliftingDays + plan.cardioDays
            if totalDays > 0 {
                return "\(totalDays)x/week"
            }
            return nil
        }()

        // Status color - v142: Aligned with StatusHelpers.swift canonical scheme
        let (_, statusColor) = plan.status.statusInfo()

        return StatusListRowConfig(
            number: nil,
            title: title,
            subtitle: subtitle,
            metadata: metadata,
            statusText: nil,
            statusColor: statusColor,
            timeText: nil
        )
    }

    // MARK: - Program Formatting

    static func formatProgram(_ program: Program) -> StatusListRowConfig {
        let title = program.name

        // Subtitle: Training focus and date range
        let subtitle: String? = {
            var parts: [String] = []

            // Training focus
            parts.append(program.focus.rawValue.capitalized)

            // Date range
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            parts.append("\(formatter.string(from: program.startDate)) - \(formatter.string(from: program.endDate))")

            return parts.joined(separator: " • ")
        }()

        // Metadata: Intensity range
        let metadata: String? = {
            let startPct = Int(program.startingIntensity * 100)
            let endPct = Int(program.endingIntensity * 100)
            return "\(startPct)% → \(endPct)% intensity"
        }()

        return StatusListRowConfig(
            number: nil,
            title: title,
            subtitle: subtitle,
            metadata: metadata,
            statusText: nil,
            statusColor: Color("SecondaryText"),
            timeText: nil
        )
    }

    // MARK: - User Formatting (v99.1)
    // v186: Removed formatClass (class booking deferred for beta)

    static func formatUser(_ user: UnifiedUser) -> StatusListRowConfig {
        let title = user.name

        // Subtitle: Role and status
        let subtitle: String? = {
            var parts: [String] = []

            // Primary role
            if let role = user.primaryRole {
                parts.append(role.displayName)
            }

            // Membership status for members
            if user.hasRole(.member), let status = user.memberProfile?.membershipStatus {
                parts.append(status.rawValue.capitalized)
            }

            // Trainer assignment for members
            if user.hasRole(.member), let trainerId = user.memberProfile?.trainerId,
               let trainer = LocalDataStore.shared.users[trainerId] {
                parts.append("w/ \(trainer.name)")
            }

            return parts.isEmpty ? nil : parts.joined(separator: " • ")
        }()

        // Metadata: Email
        let metadata: String? = user.email

        // Status color based on membership/activity
        let statusColor: Color = {
            if user.hasRole(.member), let status = user.memberProfile?.membershipStatus {
                switch status {
                case .active:
                    return .green
                case .pending:
                    return .orange
                case .expired, .suspended, .cancelled:
                    return Color("SecondaryText")
                }
            }
            // For trainers, check if they have assigned members
            if user.hasRole(.trainer) {
                let assignedCount = UserDataStore.members(assignedToTrainer: user.id).count
                return assignedCount > 0 ? .green : Color("SecondaryText")
            }
            return Color("SecondaryText")
        }()

        return StatusListRowConfig(
            number: nil,
            title: title,
            subtitle: subtitle,
            metadata: metadata,
            statusText: nil,
            statusColor: statusColor,
            timeText: nil
        )
    }

    // MARK: - Message Thread Formatting (v189)

    /// Format message thread for list modal
    /// Note: No status bar (unlike plans/workouts) - messages use different visual pattern
    static func formatThread(_ thread: MessageThread, userId: String) -> StatusListRowConfig {
        let title = thread.subject

        // Subtitle: Preview of last message content (uses built-in previewText)
        let subtitle: String? = {
            let preview = thread.previewText
            if preview.count > 60 {
                return String(preview.prefix(60)) + "..."
            }
            return preview.isEmpty ? nil : preview
        }()

        // Metadata: Sender name (if from someone else)
        let metadata: String? = {
            guard let lastMessage = thread.messages.last else { return nil }
            if lastMessage.senderId != userId {
                if let sender = LocalDataStore.shared.users[lastMessage.senderId] {
                    return "From \(sender.name.components(separatedBy: " ").first ?? sender.name)"
                }
            }
            return nil
        }()

        // Time text: Use thread's built-in timeAgo
        let timeText: String? = thread.timeAgo

        // v189: No status bar for messages - use clear color
        // Unread could use blue, but for simplicity we hide the stripe
        let statusColor: Color = .clear

        return StatusListRowConfig(
            number: nil,
            title: title,
            subtitle: subtitle,
            metadata: metadata,
            statusText: nil,
            statusColor: statusColor,
            timeText: timeText
        )
    }
}
