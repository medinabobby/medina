//
// EntityActionCoordinator.swift
// Medina
//
// v49: Centralized action execution coordinator
// Created: November 2025
//
// Purpose: Handles execution of entity actions with:
// - Confirmation alerts for destructive actions
// - Routing to existing handlers/services
// - Post-execution navigation (pop to root, navigate to chat)
// - Result handling (success/failure)
//
// Replaces: Scattered execution logic in ChatView.handleContextAction/executeAction
//

import Foundation
import SwiftUI

@MainActor
class EntityActionCoordinator: ObservableObject {

    // MARK: - Properties

    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var alertError: String?

    private var pendingAction: PendingActionExecution?

    // MARK: - Execution

    /// Execute an action for the given entity
    /// - Parameters:
    ///   - actionType: Type of action to execute
    ///   - descriptor: Entity context
    ///   - context: Execution context (chat vs detail view)
    ///   - navigationModel: Optional navigation model for detail view actions
    ///   - chatViewModel: Optional chat view model for chat actions
    ///   - userId: User ID for handler context
    func execute(
        actionType: EntityActionType,
        descriptor: EntityDescriptor,
        context: ActionExecutionContext,
        navigationModel: NavigationModel? = nil,
        chatViewModel: ChatViewModel? = nil,
        userId: String? = nil
    ) async -> ActionResult {

        Logger.log(.info, component: "EntityActionCoordinator",
                  message: "Executing \(actionType) for \(descriptor.entityType) \(descriptor.entityId)")

        // Store pending action for confirmation flow
        pendingAction = PendingActionExecution(
            actionType: actionType,
            descriptor: descriptor,
            context: context,
            navigationModel: navigationModel,
            chatViewModel: chatViewModel
        )

        // Check if action requires confirmation
        let action = EntityActionProvider.actions(for: descriptor)
            .first { $0.type == actionType }

        if let confirmationMessage = action?.confirmationMessage {
            // Show confirmation alert - actual execution happens in confirmAction()
            showConfirmation(title: action?.title ?? "Confirm", message: confirmationMessage)
            return .cancelled  // Will resume if user confirms
        } else {
            // Execute immediately (no confirmation needed)
            return await performAction()
        }
    }

    /// Show confirmation alert
    private func showConfirmation(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    /// Called when user confirms action from alert
    func confirmAction() async {
        Logger.log(.debug, component: "EntityActionCoordinator", message: "Action confirmed by user")
        let _ = await performAction()
        showAlert = false
    }

    /// Cancel pending action
    func cancelAction() {
        Logger.log(.debug, component: "EntityActionCoordinator", message: "Action cancelled by user")
        pendingAction = nil
        showAlert = false
    }

    // MARK: - Execution Logic

    private func performAction() async -> ActionResult {
        guard let pending = pendingAction else {
            Logger.log(.warning, component: "EntityActionCoordinator", message: "performAction called but no pending action")
            return .cancelled
        }

        defer { pendingAction = nil }

        do {
            let result: ActionResult

            switch pending.actionType {
            // Plan actions
            case .activatePlan:
                result = try await executePlanActivation(entityId: pending.descriptor.entityId)

            case .abandonPlan:
                result = try await executePlanAbandon(entityId: pending.descriptor.entityId)

            case .deletePlan:
                result = try await executePlanDelete(entityId: pending.descriptor.entityId)

            // Workout actions
            // v55.0: Guided-only workout execution
            case .startWorkout, .startGuidedWorkout, .continueWorkout:
                result = try await executeWorkoutStart(entityId: pending.descriptor.entityId)

            case .skipWorkout:
                result = try await executeWorkoutSkip(entityId: pending.descriptor.entityId)

            // Complete/Reset/Refresh workout (intercepted in WorkoutDetailView, shouldn't reach here)
            case .completeWorkout, .resetWorkout, .refreshExercises:
                result = .failure(error: NSError(domain: "Workout", code: 500, userInfo: [NSLocalizedDescriptionKey: "Action should be intercepted by WorkoutDetailView"]))

            // Protocol actions (v51.0)
            case .enableProtocol:
                result = try await executeProtocolEnable(entityId: pending.descriptor.entityId, userId: pending.chatViewModel?.user.id)

            case .disableProtocol:
                result = try await executeProtocolDisable(entityId: pending.descriptor.entityId, userId: pending.chatViewModel?.user.id)

            case .removeProtocol:
                result = try await executeProtocolRemove(entityId: pending.descriptor.entityId, userId: pending.chatViewModel?.user.id)

            // Exercise actions (v70.0)
            case .addExerciseToLibrary:
                result = try await executeExerciseAdd(entityId: pending.descriptor.entityId, userId: pending.chatViewModel?.user.id)

            case .removeExerciseFromLibrary, .removeExercise:
                result = try await executeExerciseRemove(entityId: pending.descriptor.entityId, userId: pending.chatViewModel?.user.id)

            // Legacy exercise actions (not implemented)
            case .enableExercise, .disableExercise:
                result = .failure(error: NSError(domain: "Exercise", code: 501, userInfo: [NSLocalizedDescriptionKey: "Exercise enable/disable not yet implemented"]))
            }

            // Handle post-execution navigation
            if case .success(_, let navigationIntent) = result {
                await handleNavigation(intent: navigationIntent, context: pending.context, navigationModel: pending.navigationModel, chatViewModel: pending.chatViewModel)
            }

            return result

        } catch let error as PlanActivationError {
            return .failure(error: NSError(domain: "PlanActivation", code: 1, userInfo: [NSLocalizedDescriptionKey: error.userMessage]))
        } catch let error as PlanAbandonmentError {
            return .failure(error: NSError(domain: "PlanAbandon", code: 1, userInfo: [NSLocalizedDescriptionKey: error.errorDescription ?? "Failed"]))
        } catch let error as PlanDeletionError {
            return .failure(error: NSError(domain: "PlanDeletion", code: 1, userInfo: [NSLocalizedDescriptionKey: error.userMessage]))
        } catch let error as WorkoutSkipError {
            return .failure(error: NSError(domain: "WorkoutSkip", code: 1, userInfo: [NSLocalizedDescriptionKey: error.userMessage]))
        } catch {
            return .failure(error: error)
        }
    }

    // MARK: - Plan Actions

    private func executePlanActivation(entityId: String) async throws -> ActionResult {
        guard let plan = LocalDataStore.shared.plans.values.first(where: { $0.id == entityId }) else {
            return .failure(error: NSError(domain: "Plan", code: 404, userInfo: [NSLocalizedDescriptionKey: "Plan not found"]))
        }

        let activatedPlan = try await PlanActivationService.activate(plan: plan)
        let message = "'\(activatedPlan.name)' is now active!"

        Logger.log(.info, component: "EntityActionCoordinator", message: "Plan activated: \(activatedPlan.id)")

        // Navigate to chat and show message (card injection handled separately)
        return .success(message: nil, navigationIntent: .navigateToChat(injectCard: true, injectedMessage: message))
    }

    private func executePlanAbandon(entityId: String) async throws -> ActionResult {
        guard let plan = LocalDataStore.shared.plans.values.first(where: { $0.id == entityId }) else {
            return .failure(error: NSError(domain: "Plan", code: 404, userInfo: [NSLocalizedDescriptionKey: "Plan not found"]))
        }

        let abandonedPlan = try await PlanAbandonmentService.abandon(plan: plan)
        let message = "'\(abandonedPlan.name)' has been abandoned."

        Logger.log(.info, component: "EntityActionCoordinator", message: "Plan abandoned: \(abandonedPlan.id)")

        // Navigate to chat and show message (card injection handled separately)
        return .success(message: nil, navigationIntent: .navigateToChat(injectCard: true, injectedMessage: message))
    }

    private func executePlanDelete(entityId: String) async throws -> ActionResult {
        guard let plan = LocalDataStore.shared.plans.values.first(where: { $0.id == entityId }) else {
            return .failure(error: NSError(domain: "Plan", code: 404, userInfo: [NSLocalizedDescriptionKey: "Plan not found"]))
        }

        let planName = plan.name
        try await PlanDeletionService.delete(plan: plan)
        let message = "'\(planName)' has been deleted."

        Logger.log(.info, component: "EntityActionCoordinator", message: "Plan deleted: \(entityId)")

        // Navigate to root and show message (plan no longer exists)
        return .success(message: nil, navigationIntent: .popToRoot(injectedMessage: message))
    }

    // MARK: - Workout Actions

    // v55.0: Guided-only (removed mode parameter)
    private func executeWorkoutStart(entityId: String) async throws -> ActionResult {
        guard let workout = LocalDataStore.shared.workouts.values.first(where: { $0.id == entityId }) else {
            return .failure(error: NSError(domain: "Workout", code: 404, userInfo: [NSLocalizedDescriptionKey: "Workout not found"]))
        }

        // Check if workout belongs to draft plan
        if let program = LocalDataStore.shared.programs[workout.programId],
           let plan = LocalDataStore.shared.plans[program.planId],
           plan.status == .draft {
            let message = "Cannot start workout from draft plan. Activate '\(plan.name)' first."
            return .failure(error: NSError(domain: "Workout", code: 400, userInfo: [NSLocalizedDescriptionKey: message]))
        }

        Logger.log(.info, component: "EntityActionCoordinator", message: "Starting workout (guided mode): \(workout.id)")

        // v49: Navigate to chat and inject instruction message
        // v50: Will inject WorkoutStartCard directly via SessionStartHandler
        // v55.0: Guided-only mode
        let workoutName = workout.name
        let message = "Return to chat and say 'start \(workoutName)' to begin"
        return .success(message: nil, navigationIntent: .popToRoot(injectedMessage: message))
    }

    private func executeWorkoutSkip(entityId: String) async throws -> ActionResult {
        guard let workout = LocalDataStore.shared.workouts.values.first(where: { $0.id == entityId }) else {
            return .failure(error: NSError(domain: "Workout", code: 404, userInfo: [NSLocalizedDescriptionKey: "Workout not found"]))
        }

        // Mark workout as skipped
        var updatedWorkout = workout
        updatedWorkout.status = .skipped
        LocalDataStore.shared.workouts[workout.id] = updatedWorkout

        // v167: Save to DeltaStore for sync/audit consistency (matches handler pattern)
        let delta = DeltaStore.WorkoutDelta(
            workoutId: workout.id,
            scheduledDate: nil,
            completion: .skipped
        )
        DeltaStore.shared.saveWorkoutDelta(delta)

        // v206: Sync to Firestore (fire-and-forget)
        if let program = LocalDataStore.shared.programs[workout.programId],
           let plan = LocalDataStore.shared.plans[program.planId] {
            Task {
                do {
                    try await FirestoreWorkoutRepository.shared.saveWorkout(updatedWorkout, memberId: plan.memberId)
                } catch {
                    Logger.log(.warning, component: "EntityActionCoordinator",
                              message: "⚠️ Firestore sync failed for skipped workout: \(error)")
                }
            }
        }

        Logger.log(.info, component: "EntityActionCoordinator", message: "Skipped workout: \(workout.id)")

        // v167: Post notification so sidebar refreshes (matches handler pattern)
        NotificationCenter.default.post(name: .workoutStatusDidChange, object: nil)

        let message = "'\(workout.name)' skipped"
        return .success(message: message, navigationIntent: nil)
    }

    // MARK: - Protocol Actions

    private func executeProtocolEnable(entityId: String, userId: String?) async throws -> ActionResult {
        guard let userId = userId else {
            return .failure(error: NSError(domain: "Protocol", code: 401, userInfo: [NSLocalizedDescriptionKey: "User ID required"]))
        }

        guard var library = LocalDataStore.shared.libraries[userId] else {
            return .failure(error: NSError(domain: "Protocol", code: 404, userInfo: [NSLocalizedDescriptionKey: "Library not found"]))
        }

        guard let index = library.protocols.firstIndex(where: { $0.protocolConfigId == entityId }) else {
            return .failure(error: NSError(domain: "Protocol", code: 404, userInfo: [NSLocalizedDescriptionKey: "Protocol not found in library"]))
        }

        // Enable the protocol
        library.protocols[index].isEnabled = true
        library.lastModified = Date()
        LocalDataStore.shared.libraries[userId] = library

        // Persist
        try LibraryPersistenceService.save(library)

        let protocolName = LocalDataStore.shared.protocolConfigs[entityId]?.variantName ?? "Protocol"
        Logger.log(.info, component: "EntityActionCoordinator", message: "Protocol enabled: \(entityId)")

        return .success(message: "'\(protocolName)' enabled", navigationIntent: nil)
    }

    private func executeProtocolDisable(entityId: String, userId: String?) async throws -> ActionResult {
        guard let userId = userId else {
            return .failure(error: NSError(domain: "Protocol", code: 401, userInfo: [NSLocalizedDescriptionKey: "User ID required"]))
        }

        guard var library = LocalDataStore.shared.libraries[userId] else {
            return .failure(error: NSError(domain: "Protocol", code: 404, userInfo: [NSLocalizedDescriptionKey: "Library not found"]))
        }

        guard let index = library.protocols.firstIndex(where: { $0.protocolConfigId == entityId }) else {
            return .failure(error: NSError(domain: "Protocol", code: 404, userInfo: [NSLocalizedDescriptionKey: "Protocol not found in library"]))
        }

        // Disable the protocol
        library.protocols[index].isEnabled = false
        library.lastModified = Date()
        LocalDataStore.shared.libraries[userId] = library

        // Persist
        try LibraryPersistenceService.save(library)

        let protocolName = LocalDataStore.shared.protocolConfigs[entityId]?.variantName ?? "Protocol"
        Logger.log(.info, component: "EntityActionCoordinator", message: "Protocol disabled: \(entityId)")

        return .success(message: "'\(protocolName)' disabled", navigationIntent: nil)
    }

    private func executeProtocolRemove(entityId: String, userId: String?) async throws -> ActionResult {
        guard let userId = userId else {
            return .failure(error: NSError(domain: "Protocol", code: 401, userInfo: [NSLocalizedDescriptionKey: "User ID required"]))
        }

        guard var library = LocalDataStore.shared.libraries[userId] else {
            return .failure(error: NSError(domain: "Protocol", code: 404, userInfo: [NSLocalizedDescriptionKey: "Library not found"]))
        }

        guard let index = library.protocols.firstIndex(where: { $0.protocolConfigId == entityId }) else {
            return .failure(error: NSError(domain: "Protocol", code: 404, userInfo: [NSLocalizedDescriptionKey: "Protocol not found in library"]))
        }

        let protocolName = LocalDataStore.shared.protocolConfigs[entityId]?.variantName ?? "Protocol"

        // Remove the protocol
        library.protocols.remove(at: index)
        library.lastModified = Date()
        LocalDataStore.shared.libraries[userId] = library

        // Persist
        try LibraryPersistenceService.save(library)

        Logger.log(.info, component: "EntityActionCoordinator", message: "Protocol removed: \(entityId)")

        return .success(message: "'\(protocolName)' removed from library", navigationIntent: .popOne)
    }

    // MARK: - Exercise Actions (v70.0)

    private func executeExerciseAdd(entityId: String, userId: String?) async throws -> ActionResult {
        guard let userId = userId else {
            return .failure(error: NSError(domain: "Exercise", code: 401, userInfo: [NSLocalizedDescriptionKey: "User ID required"]))
        }

        // Get exercise name for user feedback
        let exerciseName = LocalDataStore.shared.exercises[entityId]?.name ?? "Exercise"

        // Add to library
        try LibraryPersistenceService.addExercise(entityId, userId: userId)

        Logger.log(.info, component: "EntityActionCoordinator", message: "Exercise added to library: \(entityId)")

        return .success(message: "'\(exerciseName)' added to library", navigationIntent: nil)
    }

    private func executeExerciseRemove(entityId: String, userId: String?) async throws -> ActionResult {
        guard let userId = userId else {
            return .failure(error: NSError(domain: "Exercise", code: 401, userInfo: [NSLocalizedDescriptionKey: "User ID required"]))
        }

        // Get exercise name for user feedback
        let exerciseName = LocalDataStore.shared.exercises[entityId]?.name ?? "Exercise"

        // Remove from library
        try LibraryPersistenceService.removeExercise(entityId, userId: userId)

        Logger.log(.info, component: "EntityActionCoordinator", message: "Exercise removed from library: \(entityId)")

        return .success(message: "'\(exerciseName)' removed from library", navigationIntent: nil)
    }

    // MARK: - Navigation Handling

    private func handleNavigation(
        intent: NavigationIntent?,
        context: ActionExecutionContext,
        navigationModel: NavigationModel?,
        chatViewModel: ChatViewModel?
    ) async {
        guard let intent = intent else { return }

        switch intent {
        case .popToRoot(let injectedMessage):
            // Pop to root (ChatView)
            if let navigationModel = navigationModel {
                navigationModel.popToRoot()
            }

            // Inject system message after navigation completes
            if let message = injectedMessage {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    Logger.log(.debug, component: "EntityActionCoordinator", message: "Injecting message: \(message)")
                    NotificationCenter.default.post(
                        name: NSNotification.Name("AddChatMessage"),
                        object: nil,
                        userInfo: ["message": Message(content: message, isUser: false)]
                    )
                }
            }

        case .popOne:
            // Pop one level back
            if let navigationModel = navigationModel {
                navigationModel.pop()
            }

        case .none:
            // Stay in current view
            break

        case .navigateToChat(_, let injectedMessage):
            // Navigate to chat
            if context == .detailView, let navigationModel = navigationModel {
                navigationModel.popToRoot()
            }

            // Inject system message after navigation completes
            if let message = injectedMessage {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    Logger.log(.debug, component: "EntityActionCoordinator", message: "Injecting message: \(message)")
                    NotificationCenter.default.post(
                        name: NSNotification.Name("AddChatMessage"),
                        object: nil,
                        userInfo: ["message": Message(content: message, isUser: false)]
                    )
                }
            }

            // Card injection will be handled by caller (ChatView)
            // This coordinator doesn't create cards - that's the view's responsibility
        }
    }
}

// MARK: - Supporting Types

private struct PendingActionExecution {
    let actionType: EntityActionType
    let descriptor: EntityDescriptor
    let context: ActionExecutionContext
    let navigationModel: NavigationModel?
    let chatViewModel: ChatViewModel?
}
