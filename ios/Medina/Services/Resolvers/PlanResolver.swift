//
// PlanResolver.swift
// Medina
//
// v90.0: Added trainer-aware queries and permission checks
// Last reviewed: December 2025
//

import Foundation

enum PlanResolver {

    // MARK: - Member Queries

    static func activePlan(for memberId: String) -> Plan? {
        PlanDataStore.activePlan(for: memberId)
    }

    // MARK: - v90.0: Trainer Queries

    /// Get all plans for trainer's assigned members
    static func plansForTrainer(_ trainerId: String) -> [Plan] {
        PlanDataStore.plansForTrainer(trainerId)
    }

    /// Get plans grouped by member (for trainer dashboard)
    static func plansByMember(forTrainer trainerId: String) -> [String: [Plan]] {
        PlanDataStore.plansByMember(forTrainer: trainerId)
    }

    /// Get active plans across all trainer's members
    static func activePlansForTrainer(_ trainerId: String) -> [Plan] {
        PlanDataStore.activePlansForTrainer(trainerId)
    }

    // MARK: - v90.0: Permission Checks

    /// Check if a user can access a specific plan
    /// - Member: can only access their own plans
    /// - Trainer: can access plans for assigned members
    /// - Admin/GymOwner: can access plans for users in their gym
    static func canAccess(plan: Plan, userId: String) -> Bool {
        let role = UserRoleService.getHighestRole(userId: userId)

        switch role {
        case .member:
            // Members can only access their own plans
            return plan.memberId == userId

        case .trainer:
            // Trainer created/has access to this plan
            if plan.trainerId == userId { return true }

            // Trainer's assigned member owns this plan
            if let member = TestDataManager.shared.users[plan.memberId],
               member.memberProfile?.trainerId == userId {
                return true
            }
            return false

        case .admin, .gymOwner:
            // Admin/GymOwner can access plans for users in their gym
            guard let viewer = TestDataManager.shared.users[userId],
                  let member = TestDataManager.shared.users[plan.memberId] else {
                return false
            }
            return viewer.gymId == member.gymId
        }
    }

    /// Filter plans to only those accessible by a user
    static func accessiblePlans(_ plans: [Plan], for userId: String) -> [Plan] {
        return plans.filter { canAccess(plan: $0, userId: userId) }
    }

    // MARK: - Original Methods

    static func mostRecentPlan(for memberId: String) -> Plan? {
        allPlans(for: memberId).first
    }

    static func allPlans(for memberId: String) -> [Plan] {
        // v54.7: Show all plans including completed/abandoned
        PlanDataStore.allPlans(for: memberId)
    }

    /// Get archived plans (completed)
    /// Used for "show archived plans" queries
    /// v46.1: Archived plans are hidden from default view
    /// v172: Simplified - only completed (removed abandoned)
    static func archivedPlans(for memberId: String) -> [Plan] {
        PlanDataStore.allPlans(for: memberId)
            .filter { $0.status == .completed }
    }

    static func plan(for memberId: String, status: PlanStatus?) -> Plan? {
        guard let status = status else {
            return activePlan(for: memberId) ?? mostRecentPlan(for: memberId)
        }

        switch status {
        case .active:
            return activePlan(for: memberId) ?? mostRecentPlan(for: memberId)
        case .completed:
            return lastCompletedPlan(for: memberId)
        case .draft:
            return draftPlans(for: memberId).first
        }
    }

    static func plan(for memberId: String, status: PlanStatus?, rawText: String?) -> Plan? {
        // Handle special keyword filtering using StatusFilteringService
        if let filtered = StatusFilteringService.handleSpecialKeywords(
            in: rawText,
            fallbackFilter: {
                if let plan = plan(for: memberId, status: status) {
                    return [plan]
                } else {
                    return []
                }
            },
            keywordHandlers: [
                "draft": { draftPlans(for: memberId) }
            ]
        ) {
            return filtered.first
        }

        // Otherwise use normal status filtering
        return plan(for: memberId, status: status)
    }

    static func plans(for memberId: String, status: PlanStatus?) -> [Plan] {
        // v46.1: Get ALL plans (bypasses default filter) for explicit status queries
        let allPlans = PlanDataStore.allPlans(for: memberId)

        guard let status = status else {
            // v46.1: Default behavior - show active + draft only (hide archived)
            // v172: Completed plans require explicit "show archived plans"
            return allPlans.filter { $0.status != .completed }
        }

        switch status {
        case .active:
            return allPlans.filter(planIsActive)
        case .completed:
            return completedPlans(for: memberId)
        case .draft:
            return draftPlans(for: memberId)
        }
    }

    static func plans(for memberId: String, status: PlanStatus?, rawText: String?) -> [Plan] {
        // Handle special keyword filtering using StatusFilteringService
        if let filtered = StatusFilteringService.handleSpecialKeywords(
            in: rawText,
            fallbackFilter: { plans(for: memberId, status: status) },
            keywordHandlers: [
                "draft": { draftPlans(for: memberId) }
            ]
        ) {
            return filtered
        }

        // Otherwise use normal status filtering
        return plans(for: memberId, status: status)
    }

    static func draftPlans(for memberId: String) -> [Plan] {
        // v46.1: Bypass default filter to get drafts
        return PlanDataStore.allPlans(for: memberId).filter { plan in
            plan.effectiveStatus == .draft
        }
    }

    static func completedPlans(for memberId: String) -> [Plan] {
        // v46.1: Bypass default filter to get completed plans
        return PlanDataStore.allPlans(for: memberId).filter { plan in
            plan.effectiveStatus == .completed
        }
    }

    static func upcomingPlans(for memberId: String) -> [Plan] {
        return allPlans(for: memberId).filter { plan in
            plan.isUpcoming
        }
    }

    static func lastCompletedPlan(for memberId: String) -> Plan? {
        completedPlans(for: memberId).first
    }

    private static func planIsActive(_ plan: Plan) -> Bool {
        return plan.isEffectivelyActive
    }

    // MARK: - Standard Filtering Context Support
    // NOTE: StandardFilteringContext methods removed - that struct still uses legacy StatusSlot
    // which has been deleted. StandardFilteringContext needs to be updated separately to use
    // entity-specific status enums before these methods can be restored.
}
