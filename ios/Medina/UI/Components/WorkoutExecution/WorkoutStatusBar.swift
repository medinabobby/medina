//
// WorkoutStatusBar.swift
// Medina
//
// v52.5: Extracted from WorkoutDetailView
// v68.0: Added draft plan UX - shows "Activate Plan" instead of "Start Workout" for draft plans
// v78.8: Fixed Continue Workout detection using LocalDataStore.sessions (not workout.status)
// Created: November 12, 2025
// Purpose: Workout execution status bar - shows different UI based on workout state
//

import SwiftUI

struct WorkoutStatusBar: View {
    let workout: Workout
    @ObservedObject var coordinator: WorkoutSessionCoordinator  // v57.5: Observe coordinator directly
    let onFinishWorkout: () -> Void
    let onStartWorkout: () -> Void
    let onContinueWorkout: () -> Void
    let onReviewWorkout: () -> Void

    // v68.0: Draft plan support
    var isInDraftPlan: Bool = false
    var onActivatePlan: (() -> Void)?

    // v78.8: Check for active session in LocalDataStore (persists across coordinator instances)
    private var hasActiveSession: Bool {
        LocalDataStore.shared.sessions.values.contains { session in
            session.workoutId == workout.id && session.status == .active
        }
    }

    var body: some View {
        // v163: Removed in-place execution UI ("Log: X Set Y of Z")
        // FocusedExecution is now the only workout mode
        // Always show action button - it handles active sessions with "Continue Workout"
        workoutActionButton()
    }

    // MARK: - Workout Action Button

    @ViewBuilder
    private func workoutActionButton() -> some View {
        // v68.0: If workout is in draft plan, show "Activate Plan" instead of "Start Workout"
        // v78.8: Check hasActiveSession for Continue (workout.status doesn't update to .inProgress)
        let buttonConfig: (text: String, icon: String, color: Color) = {
            if isInDraftPlan && (workout.status == .scheduled || workout.status == .skipped) && !hasActiveSession {
                return ("Activate Plan to Start", "play.circle", .orange)
            }
            // v78.8: Check hasActiveSession first (takes priority over workout.status)
            if hasActiveSession {
                return ("Continue Workout", "play.circle.fill", .accentColor)
            }
            return getButtonConfig(for: workout.status)
        }()

        Button(action: {
            // v68.0: Handle draft plan activation
            if isInDraftPlan && (workout.status == .scheduled || workout.status == .skipped) && !hasActiveSession {
                onActivatePlan?()
                return
            }

            // v78.8: Check hasActiveSession first (takes priority over workout.status)
            if hasActiveSession {
                onContinueWorkout()
                return
            }

            switch workout.status {
            case .completed:
                onReviewWorkout()
            case .inProgress:
                onContinueWorkout()
            case .scheduled, .skipped:
                onStartWorkout()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: buttonConfig.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(buttonConfig.color)

                Text(buttonConfig.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color("PrimaryText"))

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color("SecondaryText"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(buttonConfig.color.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(hasActiveSession ? "continueWorkoutButton" : workout.status == .scheduled || workout.status == .skipped ? "startWorkoutButton" : workout.status == .inProgress ? "continueWorkoutButton" : "reviewWorkoutButton")
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    /// Get button configuration based on workout status
    private func getButtonConfig(for status: ExecutionStatus) -> (text: String, icon: String, color: Color) {
        switch status {
        case .completed:
            return ("Review Workout", "checkmark.circle.fill", Color("Success"))
        case .inProgress:
            return ("Continue Workout", "play.circle.fill", .accentColor)
        case .scheduled, .skipped:
            return ("Start Workout", "play.circle.fill", .accentColor)
        }
    }
}

// MARK: - Previews

#Preview("No Active Session - Scheduled") {
    let workout = Workout(
        id: "test_workout",
        programId: "test_program",
        name: "Upper Body A",
        scheduledDate: Date(),
        type: .strength,
        splitDay: nil as SplitDay?,
        status: .scheduled,
        completedDate: nil as Date?,
        exerciseIds: ["ex1", "ex2"],
        protocolVariantIds: [0: "proto1", 1: "proto2"],
        exercisesSelectedAt: nil,
        supersetGroups: nil as [SupersetGroup]?,
        protocolCustomizations: nil
    )

    let coordinator = WorkoutSessionCoordinator(memberId: "test_user")

    WorkoutStatusBar(
        workout: workout,
        coordinator: coordinator,
        onFinishWorkout: { print("Finish") },
        onStartWorkout: { print("Start") },
        onContinueWorkout: { print("Continue") },
        onReviewWorkout: { print("Review") }
    )
    .padding()
}

#Preview("Guided Mode Active - First Set") {
    let workout = Workout(
        id: "test_workout",
        programId: "test_program",
        name: "Upper Body A",
        scheduledDate: Date(),
        type: .strength,
        splitDay: nil as SplitDay?,
        status: .inProgress,
        completedDate: nil as Date?,
        exerciseIds: ["ex1", "ex2"],
        protocolVariantIds: [0: "proto1", 1: "proto2"],
        exercisesSelectedAt: nil,
        supersetGroups: nil as [SupersetGroup]?,
        protocolCustomizations: nil
    )

    let coordinator = WorkoutSessionCoordinator(memberId: "test_user")

    WorkoutStatusBar(
        workout: workout,
        coordinator: coordinator,
        onFinishWorkout: { print("Finish") },
        onStartWorkout: { print("Start") },
        onContinueWorkout: { print("Continue") },
        onReviewWorkout: { print("Review") }
    )
    .padding()
}

#Preview("Guided Mode Active - Mid Workout") {
    let workout = Workout(
        id: "test_workout",
        programId: "test_program",
        name: "Upper Body A",
        scheduledDate: Date(),
        type: .strength,
        splitDay: nil as SplitDay?,
        status: .inProgress,
        completedDate: nil as Date?,
        exerciseIds: ["ex1", "ex2"],
        protocolVariantIds: [0: "proto1", 1: "proto2"],
        exercisesSelectedAt: nil,
        supersetGroups: nil as [SupersetGroup]?,
        protocolCustomizations: nil
    )

    let coordinator = WorkoutSessionCoordinator(memberId: "test_user")

    WorkoutStatusBar(
        workout: workout,
        coordinator: coordinator,
        onFinishWorkout: { print("Finish") },
        onStartWorkout: { print("Start") },
        onContinueWorkout: { print("Continue") },
        onReviewWorkout: { print("Review") }
    )
    .padding()
}
