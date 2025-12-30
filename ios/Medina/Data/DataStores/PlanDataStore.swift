//
// PlanDataStore.swift
// Medina
//
// v90.0: Added trainer-aware queries for Trainer Mode
// Last reviewed: December 2025
//

import Foundation

enum PlanDataStore {

    private static var manager: LocalDataStore { LocalDataStore.shared }

    // MARK: - Member Queries

    static func activePlan(for memberId: String) -> Plan? {
        return allPlans(for: memberId).first(where: { $0.isEffectivelyActive })
    }

    static func allPlans(for memberId: String) -> [Plan] {
        manager.plans.values
            .filter { $0.memberId == memberId }
            .sorted { $0.startDate > $1.startDate }
    }

    // MARK: - v90.0: Trainer Queries

    /// Get all plans for a trainer's assigned members
    /// Returns plans where:
    /// - trainerId matches the trainer, OR
    /// - memberId belongs to a currently assigned member
    static func plansForTrainer(_ trainerId: String) -> [Plan] {
        let assignedMemberIds = Set(UserDataStore.members(assignedToTrainer: trainerId).map { $0.id })

        return manager.plans.values
            .filter { plan in
                // Plan was created/assigned to this trainer
                plan.trainerId == trainerId ||
                // OR plan belongs to a currently assigned member
                assignedMemberIds.contains(plan.memberId)
            }
            .sorted { $0.startDate > $1.startDate }
    }

    /// Get plans grouped by member (for trainer dashboard)
    static func plansByMember(forTrainer trainerId: String) -> [String: [Plan]] {
        let plans = plansForTrainer(trainerId)
        return Dictionary(grouping: plans) { $0.memberId }
    }

    /// Get active plans for all of a trainer's members
    static func activePlansForTrainer(_ trainerId: String) -> [Plan] {
        return plansForTrainer(trainerId).filter { $0.isEffectivelyActive }
    }
}
