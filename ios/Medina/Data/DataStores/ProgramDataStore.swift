//
// ProgramDataStore.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

enum ProgramDataStore {

    private static var manager: LocalDataStore { LocalDataStore.shared }

    static func allPrograms(for memberId: String) -> [Program] {
        let planIds = Set(PlanDataStore.allPlans(for: memberId).map { $0.id })
        guard !planIds.isEmpty else { return [] }

        return manager.programs.values
            .filter { planIds.contains($0.planId) }
            .sorted { $0.startDate > $1.startDate }
    }

    static func programs(for planId: String) -> [Program] {
        manager.programs.values
            .filter { $0.planId == planId }
            .sorted { $0.startDate > $1.startDate }
    }
}
