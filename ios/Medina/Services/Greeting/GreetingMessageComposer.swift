//
// GreetingMessageComposer.swift
// Medina
//
// v99.7: Composes rich trainer-style greeting messages from context
//

import Foundation

/// Composes multi-line trainer-style greetings from GreetingContext
struct GreetingMessageComposer {

    // MARK: - Public API

    /// Compose a rich greeting message from context
    static func compose(name: String, context: GreetingContext) -> String {
        var lines: [String] = []

        // Line 1: Opening greeting with key context
        lines.append(buildOpeningLine(name: name, context: context))

        // Line 2: Workout/class details
        if let detailLine = buildDetailLine(context: context) {
            lines.append(detailLine)
        }

        // Line 3: Progress/motivation (only if we have something meaningful)
        if let progressLine = buildProgressLine(context: context) {
            lines.append(progressLine)
        }

        return lines.joined(separator: "\n\n")
    }

    // MARK: - Opening Line

    private static func buildOpeningLine(name: String, context: GreetingContext) -> String {
        // Priority 1: In-progress workout
        if let inProgress = context.inProgressWorkout {
            return "Welcome back, \(name)! Ready to finish your \(inProgress.name)?"
        }

        // Priority 2: Been away too long (3+ days)
        if let daysSince = context.daysSinceLastWorkout, daysSince >= 3 {
            if daysSince == 1 {
                return "Hey \(name)! Good to see you back."
            } else {
                return "Welcome back, \(name)! It's been \(daysSince) days - let's get moving."
            }
        }

        // Priority 3: Has workout today with plan context
        if context.hasWorkoutToday, let planName = context.planName {
            if let progress = context.planProgressPercent, let weeks = context.weeksRemaining {
                if weeks == 1 {
                    return "Hey \(name)! You're \(progress)% through \(planName) - final week!"
                } else {
                    return "Hey \(name)! You're \(progress)% through \(planName) - \(weeks) weeks left."
                }
            }
            return "Hey \(name)! Ready for today's workout?"
        }

        // Priority 4: Good weekly progress
        if context.completedThisWeek >= 3 {
            return "Hey \(name)! Great momentum this week."
        }

        // Priority 6: Has active plan
        if context.planName != nil {
            return "Welcome back, \(name)!"
        }

        // Default
        return "Hi \(name)! What should we work on today?"
    }

    // MARK: - Detail Line

    private static func buildDetailLine(context: GreetingContext) -> String? {
        // In-progress workout: show completion status
        if context.hasInProgressWorkout && context.totalExercises > 0 {
            let completed = context.completedExercises
            let total = context.totalExercises
            let remaining = total - completed
            if remaining > 0 {
                return "You've completed \(completed) of \(total) exercises. \(remaining) to go!"
            } else {
                return "Just finishing up - all exercises done!"
            }
        }

        // Today's workout details
        if let workout = context.todaysWorkout {
            return buildWorkoutDetailLine(workout: workout, context: context)
        }

        return nil
    }

    private static func buildWorkoutDetailLine(workout: Workout, context: GreetingContext) -> String {
        let exerciseCount = context.exerciseCount
        let duration = context.durationMinutes

        switch workout.type {
        case .cardio:
            if let mins = duration {
                return "Today's \(mins)-minute cardio session is ready."
            }
            return "Today's cardio session is ready."

        case .strength:
            let splitName = context.splitDay?.displayName.lowercased() ?? "strength"
            if exerciseCount > 0, let mins = duration {
                return "Today's \(splitName) workout has \(exerciseCount) exercises (~\(mins) min)."
            } else if exerciseCount > 0 {
                return "Today's \(splitName) workout has \(exerciseCount) exercises."
            } else if let mins = duration {
                return "Today's \(splitName) workout is ~\(mins) minutes."
            }
            return "Today's \(splitName) workout is ready."

        case .mobility:
            if let mins = duration {
                return "Today's \(mins)-minute mobility session is ready."
            }
            return "Today's mobility session is ready."

        case .class:
            return "Today's class is ready."

        case .hybrid:
            if exerciseCount > 0, let mins = duration {
                return "Today's workout has \(exerciseCount) exercises (~\(mins) min)."
            }
            return "Today's workout is ready."
        }
    }

    // MARK: - Progress Line

    private static func buildProgressLine(context: GreetingContext) -> String? {
        // Don't show progress for in-progress workouts (already showing completion)
        if context.hasInProgressWorkout {
            return nil
        }

        // Behind schedule - encourage catch-up
        if context.isBehindSchedule {
            if context.remainingThisWeek > 0 {
                return "You have \(context.remainingThisWeek) workout\(context.remainingThisWeek == 1 ? "" : "s") scheduled this week."
            }
            return nil
        }

        // Show weekly adherence if we have target
        if context.targetThisWeek > 0 {
            let completed = context.completedThisWeek
            let target = context.targetThisWeek

            if completed >= target {
                return "You've hit all \(target) workouts this week! Amazing!"
            } else if completed > 0 {
                return "You've hit \(completed) of \(target) workouts this week. Keep it up!"
            } else if context.remainingThisWeek > 0 {
                return "You have \(context.remainingThisWeek) workout\(context.remainingThisWeek == 1 ? "" : "s") scheduled this week."
            }
        }

        return nil
    }
}
