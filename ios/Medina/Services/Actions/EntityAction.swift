//
// EntityAction.swift
// Medina
//
// v49: Unified entity action system for chat and detail views
// Created: November 2025
//
// Purpose: Centralized models for all entity actions (activate plan, start workout, etc.)
// Replaces scattered action logic in ChatCardView with single source of truth
//

import Foundation

// MARK: - Action Types

/// All available actions across entity types
/// v49: Immediate actions only (no input required)
/// v50+: Will add reschedule, edit, etc. (require user input)
enum EntityActionType: String, Codable {
    // Plan actions
    case activatePlan       // Draft → Active
    case abandonPlan        // Active → Abandoned
    case deletePlan         // Delete draft/abandoned plan

    // Workout actions
    case startWorkout       // Start scheduled workout (simple data entry mode) - v52.3
    case startGuidedWorkout // Start scheduled workout (guided coaching mode) - v52.3
    case continueWorkout    // Resume in-progress workout
    case skipWorkout        // Skip scheduled workout
    case completeWorkout    // Mark remaining sets as skipped, end session
    case resetWorkout       // Clear all data, reset to scheduled
    case refreshExercises   // v71.0: Reselect exercises for this workout

    // Protocol actions (v51.0)
    case enableProtocol     // Enable disabled protocol in library
    case disableProtocol    // Disable enabled protocol in library
    case removeProtocol     // Remove protocol from library

    // Exercise actions (v51.0, v70.0)
    case addExerciseToLibrary    // v70.0: Add exercise to library
    case removeExerciseFromLibrary // v70.0: Remove exercise from library
    case enableExercise     // Enable disabled exercise in library
    case disableExercise    // Disable enabled exercise in library
    case removeExercise     // Remove exercise from library (legacy, prefer removeExerciseFromLibrary)

    // Future actions (v50+)
    // case rescheduleWorkout
    // case editProgram
    // case markExerciseDone
}

// MARK: - Entity Context

/// Context describing an entity and its state for action determination
struct EntityDescriptor {
    let entityType: Entity
    let entityId: String
    let status: String              // Badge text (e.g., "Draft", "Active", "Scheduled")
    let userRole: UserRole
    let parentContext: ParentContext?

    init(
        entityType: Entity,
        entityId: String,
        status: String,
        userRole: UserRole,
        parentContext: ParentContext? = nil
    ) {
        self.entityType = entityType
        self.entityId = entityId
        self.status = status
        self.userRole = userRole
        self.parentContext = parentContext
    }
}

/// Parent entity IDs for hierarchical context
/// Enables context-aware actions (e.g., "View in Plan" requires planId)
struct ParentContext {
    let planId: String?
    let programId: String?
    let workoutId: String?

    init(planId: String? = nil, programId: String? = nil, workoutId: String? = nil) {
        self.planId = planId
        self.programId = programId
        self.workoutId = workoutId
    }
}

// MARK: - Action Model

/// Represents a single action available for an entity
struct EntityAction: Identifiable {
    let id: String
    let type: EntityActionType
    let title: String
    let icon: String
    let isDestructive: Bool
    let confirmationMessage: String?
    let requiresRole: UserRole?     // If set, action only available to this role

    init(
        type: EntityActionType,
        title: String,
        icon: String,
        isDestructive: Bool = false,
        confirmationMessage: String? = nil,
        requiresRole: UserRole? = nil
    ) {
        self.id = UUID().uuidString
        self.type = type
        self.title = title
        self.icon = icon
        self.isDestructive = isDestructive
        self.confirmationMessage = confirmationMessage
        self.requiresRole = requiresRole
    }
}

// MARK: - Execution Result

/// Result of executing an action
enum ActionResult {
    case success(message: String?, navigationIntent: NavigationIntent?)
    case failure(error: Error)
    case cancelled
}

/// Post-execution navigation instructions
enum NavigationIntent {
    case popToRoot(injectedMessage: String? = nil)  // Return to ChatView, optionally inject system message
    case popOne                                      // Back one level
    case none                                        // Stay in current view
    case navigateToChat(injectCard: Bool, injectedMessage: String? = nil)  // Go to chat, optionally inject card/message
}

// MARK: - Action Execution Context

/// Context in which action is being executed
/// Determines post-execution behavior (e.g., chat vs detail view handling)
enum ActionExecutionContext {
    case chatCard                   // Long-press in chat card list
    case detailView                 // Toolbar menu in detail view
}
