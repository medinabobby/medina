//
// NavigationCoordinator.swift
// Medina
//
// v48 Navigation Refactor
// v99.1: Added navigateToMember for admin sidebar
// Created: November 2025
// Purpose: Centralized routing logic - translates app events into NavigationRoute pushes
//

import Foundation

/// Coordinates navigation from various sources (sidebar, chat, intents)
@MainActor
class NavigationCoordinator {
    private let navigationModel: NavigationModel

    init(navigationModel: NavigationModel) {
        self.navigationModel = navigationModel
    }

    // MARK: - Sidebar Navigation

    /// Handle sidebar plan tap
    func navigateToPlan(id: String) {
        Logger.log(.info, component: "NavigationCoordinator", message: "Navigate to plan: \(id)")
        navigationModel.push(.plan(id: id))
    }

    // MARK: - Chat Card Navigation

    /// Handle chat card chevron tap (workout drill-down)
    /// v78.8: Always go to WorkoutDetailView (user can see progress and tap Continue)
    func navigateToWorkout(id: String) {
        Logger.log(.info, component: "NavigationCoordinator", message: "Navigate to workout: \(id)")
        navigationModel.push(.workout(id: id))
    }

    /// Handle program card tap
    func navigateToProgram(id: String) {
        Logger.log(.info, component: "NavigationCoordinator", message: "Navigate to program: \(id)")
        navigationModel.push(.program(id: id))
    }

    /// v62.0: Navigate to workout summary (opens workout detail with summary sheet)
    func navigateToWorkoutSummary(id: String) {
        Logger.log(.info, component: "NavigationCoordinator", message: "Navigate to workout summary: \(id)")
        // Navigate to workout detail - the summary sheet can be triggered via notification
        navigationModel.push(.workout(id: id))
        // Post notification to show summary sheet (WorkoutDetailView listens for this)
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowWorkoutSummary"),
            object: nil,
            userInfo: ["workoutId": id]
        )
    }

    /// Handle exercise tap - shows general exercise overview
    func navigateToExercise(id: String) {
        Logger.log(.info, component: "NavigationCoordinator", message: "Navigate to exercise: \(id)")
        navigationModel.push(.exercise(id: id))
    }

    /// Handle protocol tap from library
    func navigateToProtocol(id: String) {
        Logger.log(.info, component: "NavigationCoordinator", message: "Navigate to protocol: \(id)")
        navigationModel.push(.protocol(id: id))
    }

    /// v88.0: Handle protocol family tap from sidebar
    func navigateToProtocolFamily(id: String) {
        Logger.log(.info, component: "NavigationCoordinator", message: "Navigate to protocol family: \(id)")
        navigationModel.push(.protocolFamily(id: id))
    }

    /// v99.1: Handle member/trainer tap from admin sidebar
    func navigateToMember(id: String) {
        Logger.log(.info, component: "NavigationCoordinator", message: "Navigate to member: \(id)")
        navigationModel.push(.member(id: id))
    }

    /// v189: Handle message thread tap from messages list
    func navigateToThread(id: String) {
        Logger.log(.info, component: "NavigationCoordinator", message: "Navigate to thread: \(id)")
        navigationModel.push(.thread(id: id))
    }

    /// v76.0: Navigate to focused workout execution mode
    func enterFocusedExecution(workoutId: String) {
        Logger.log(.info, component: "NavigationCoordinator", message: "Enter focused execution: \(workoutId)")
        navigationModel.push(.focusedExecution(workoutId: workoutId))
    }

    // MARK: - Intent Navigation

    /// Handle intent result that requires navigation
    /// Example: "Start my workout" → navigate to workout after starting
    func handleIntentNavigation(_ intent: String, workoutId: String? = nil, exerciseId: String? = nil) {
        Logger.log(.info, component: "NavigationCoordinator", message: "Handle intent navigation: \(intent)")

        // Parse intent and navigate accordingly
        if let workoutId = workoutId {
            navigationModel.push(.workout(id: workoutId))
        } else if let exerciseId = exerciseId {
            navigationModel.push(.exercise(id: exerciseId))
        }
    }

    // MARK: - Deep Link Navigation

    /// Handle deep link (e.g., plan → program → workout)
    /// Builds a navigation path by pushing routes sequentially
    func navigateToDeepLink(planId: String?, programId: String?, workoutId: String?, exerciseId: String?) {
        Logger.log(.info, component: "NavigationCoordinator", message: "Navigate to deep link")

        // Clear current navigation
        navigationModel.popToRoot()

        // Build path step by step
        if let planId = planId {
            navigationModel.push(.plan(id: planId))
        }

        if let programId = programId {
            navigationModel.push(.program(id: programId))
        }

        if let workoutId = workoutId {
            navigationModel.push(.workout(id: workoutId))
        }

        if let exerciseId = exerciseId {
            navigationModel.push(.exercise(id: exerciseId))
        }
    }

    // MARK: - Navigation Control

    /// Pop current view
    func popCurrent() {
        navigationModel.pop()
    }

    /// Pop to root
    func popToRoot() {
        navigationModel.popToRoot()
    }

    /// Replace current path with a new route
    func replace(with route: NavigationRoute) {
        navigationModel.replace(with: route)
    }
}
