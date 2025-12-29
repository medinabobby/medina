//
// NavigationModel.swift
// Medina
//
// v48 Navigation Refactor
// Created: November 2025
// Purpose: Centralized navigation state for unified NavigationStack
//

import Foundation
import SwiftUI

/// Navigation routes for all app destinations
enum NavigationRoute: Hashable {
    // Detail views
    case plan(id: String)
    case program(id: String)
    case workout(id: String)
    case exercise(id: String)  // General exercise overview
    case `protocol`(id: String)  // v51.0: Protocol detail view
    case protocolFamily(id: String)  // v88.0: Protocol family with variant selector
    // v186: Removed .class route (class booking deferred for beta)
    case member(id: String)  // v90.0: Member detail view (trainer mode)
    // v164: Removed deprecated .message() and .messages routes (superseded by .thread)
    case thread(id: String)  // v93.1: Message thread detail view

    // v76.0: Focused workout execution mode
    case focusedExecution(workoutId: String)
}

/// Global navigation state manager
@MainActor
class NavigationModel: ObservableObject {
    /// Navigation path for the main stack
    @Published var path: NavigationPath = NavigationPath()

    /// Current route (computed from path)
    var currentRoute: NavigationRoute? {
        // NavigationPath doesn't expose elements directly
        // Track manually if needed, or use path.count
        return nil
    }

    // MARK: - Navigation Methods

    /// Push a new route onto the stack
    func push(_ route: NavigationRoute) {
        Logger.log(.info, component: "Navigation", message: "Pushing route: \(route)")
        path.append(route)
    }

    /// Pop the top route from the stack
    func pop() {
        Logger.log(.info, component: "Navigation", message: "Popping route")
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// Pop to root (clear entire stack)
    func popToRoot() {
        Logger.log(.info, component: "Navigation", message: "Popping to root")
        path = NavigationPath()
    }

    /// Replace the entire path with a new route
    func replace(with route: NavigationRoute) {
        Logger.log(.info, component: "Navigation", message: "Replacing path with: \(route)")
        path = NavigationPath()
        path.append(route)
    }

    /// Pop to a specific depth
    func pop(count: Int) {
        Logger.log(.info, component: "Navigation", message: "Popping \(count) routes")
        for _ in 0..<min(count, path.count) {
            path.removeLast()
        }
    }

    // MARK: - Convenience Navigation (v79.4)

    /// Navigate to a specific exercise (replaces current exercise in stack)
    func navigateToExercise(_ exerciseId: String) {
        Logger.log(.info, component: "Navigation", message: "Navigating to exercise: \(exerciseId)")
        // Pop current exercise, push new one
        if !path.isEmpty {
            path.removeLast()
        }
        path.append(NavigationRoute.exercise(id: exerciseId))
    }

    // MARK: - State Queries

    /// Check if stack is empty (at root)
    var isAtRoot: Bool {
        path.isEmpty
    }

    /// Get stack depth
    var depth: Int {
        path.count
    }
}

/// Extension for debug descriptions
extension NavigationRoute: CustomStringConvertible {
    var description: String {
        switch self {
        case .plan(let id):
            return "plan(\(id))"
        case .program(let id):
            return "program(\(id))"
        case .workout(let id):
            return "workout(\(id))"
        case .exercise(let id):
            return "exercise(\(id))"
        case .protocol(let id):
            return "protocol(\(id))"
        case .protocolFamily(let id):
            return "protocolFamily(\(id))"
        case .member(let id):
            return "member(\(id))"
        case .thread(let id):
            return "thread(\(id))"
        case .focusedExecution(let workoutId):
            return "focusedExecution(\(workoutId))"
        }
    }
}
