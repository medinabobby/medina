//
// AuthorizationService.swift
// Medina
//
// v94.0: Centralized authorization checks for trainer/member data access
// Provides consistent validation across tool handlers and view models
//

import Foundation

/// Centralized authorization service for trainer/member access control
enum AuthorizationService {

    // MARK: - Trainer/Member Access

    /// Check if trainer can access member's data
    /// Returns true if the member is assigned to this trainer
    static func canTrainerAccessMember(trainerId: String, memberId: String) -> Bool {
        guard let member = LocalDataStore.shared.users[memberId] else {
            return false
        }
        return member.memberProfile?.trainerId == trainerId
    }

    /// Check if user can modify an entity owned by another user
    /// Returns true if:
    /// - User is the owner (same ID)
    /// - User is a trainer and target is their assigned member
    static func canModifyEntity(actorId: String, ownerId: String) -> Bool {
        // Same user can always modify their own entities
        if actorId == ownerId { return true }

        // Trainer can modify assigned member's entities
        guard let actor = LocalDataStore.shared.users[actorId],
              actor.hasRole(.trainer) else {
            return false
        }

        return canTrainerAccessMember(trainerId: actorId, memberId: ownerId)
    }

    // MARK: - Tool Handler Helpers

    /// Validate forMemberId parameter in tool calls
    /// Returns the target user and whether access was authorized
    ///
    /// Usage in tool handlers:
    /// ```
    /// let (targetUser, authorized) = AuthorizationService.resolveTargetUser(
    ///     forMemberId: args["forMemberId"] as? String,
    ///     actorUser: context.user
    /// )
    /// guard authorized else { return "ERROR: Unauthorized access" }
    /// ```
    static func resolveTargetUser(
        forMemberId: String?,
        actorUser: UnifiedUser
    ) -> (user: UnifiedUser, authorized: Bool) {
        // No forMemberId specified - use actor (current user)
        guard let memberId = forMemberId,
              let member = LocalDataStore.shared.users[memberId] else {
            return (actorUser, true)
        }

        // Verify trainer access to this member
        guard canTrainerAccessMember(trainerId: actorUser.id, memberId: memberId) else {
            Logger.log(.warning, component: "AuthorizationService",
                      message: "⚠️ Unauthorized access attempt: trainer \(actorUser.id) → member \(memberId)")
            return (actorUser, false)
        }

        Logger.log(.info, component: "AuthorizationService",
                  message: "✅ Authorized: trainer \(actorUser.id) → member \(memberId)")
        return (member, true)
    }

    // MARK: - View Model Helpers

    /// Validate that a selectedMemberId is accessible by the trainer
    /// Returns nil if unauthorized, or the validated memberId if authorized
    static func validateMemberSelection(trainerId: String, memberId: String?) -> String? {
        guard let memberId = memberId else {
            return nil
        }

        guard canTrainerAccessMember(trainerId: trainerId, memberId: memberId) else {
            Logger.log(.warning, component: "AuthorizationService",
                      message: "⚠️ Invalid member selection: trainer \(trainerId) cannot access \(memberId)")
            return nil
        }

        return memberId
    }
}
