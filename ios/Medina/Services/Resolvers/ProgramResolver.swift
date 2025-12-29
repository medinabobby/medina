//
// ProgramResolver.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

enum ProgramResolver {

    static func primaryProgram(for memberId: String) -> Program? {
        let programs = ProgramDataStore.allPrograms(for: memberId)
        guard !programs.isEmpty else { return nil }

        let now = Date()

        if let activePlan = PlanResolver.activePlan(for: memberId) {
            let planPrograms = programs
                .filter { $0.planId == activePlan.id }
                .sorted { $0.startDate < $1.startDate }
            Logger.log(.debug, component: "ProgramResolver", message: "Active plan \(activePlan.name) has \(planPrograms.count) programs")

            if let current = planPrograms.first(where: { $0.startDate <= now && $0.endDate >= now }) {
                Logger.log(.debug, component: "ProgramResolver", message: "Selecting current program \(current.name)")
                return current
            }

            if let upcoming = planPrograms.first(where: { $0.startDate > now }) {
                Logger.log(.debug, component: "ProgramResolver", message: "Selecting upcoming program \(upcoming.name)")
                return upcoming
            }

            if let mostRecent = planPrograms.last {
                Logger.log(.debug, component: "ProgramResolver", message: "Selecting most recent program \(mostRecent.name)")
                return mostRecent
            }
        }

        let activeProgramCandidates = activePrograms(programs)
        let activeCurrent = activeProgramCandidates.first
        if let current = activeCurrent {
            Logger.log(.debug, component: "ProgramResolver", message: "Selecting fallback active program \(current.name)")
            return current
        }

        let upcomingPrograms = programs
            .filter { $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
        if let upcoming = upcomingPrograms.first {
            Logger.log(.debug, component: "ProgramResolver", message: "Selecting fallback upcoming program \(upcoming.name)")
            return upcoming
        }

        let selected = programs.sorted { $0.startDate > $1.startDate }.first
        if let selected {
            Logger.log(.debug, component: "ProgramResolver", message: "Selecting fallback latest program \(selected.name)")
        }
        return selected
    }

    static func programs(for memberId: String, status: ProgramStatus?, temporal: TemporalSlot) -> [Program] {
        let programs = ProgramDataStore.allPrograms(for: memberId)

        if let status = status {
            return filter(programs: programs, byStatus: status)
        }

        if temporal != .unspecified {
            return filter(programs: programs, byTemporal: temporal)
        }

        // v42.0: Show ALL programs by default (including from draft plans)
        // Now that plan creation is a feature, draft plans are REAL plans waiting to start
        // User can filter explicitly: "show draft programs", "show active programs"
        return programs
    }

    // MARK: - Helpers

    private static func filter(programs: [Program], byStatus status: ProgramStatus) -> [Program] {
        // v21.2: Filter by program's stored status directly (not computed from dates)
        return programs.filter { $0.status == status }
    }

    private static func filter(programs: [Program], byTemporal temporal: TemporalSlot) -> [Program] {
        let now = Date()

        switch temporal {
        case .today, .thisWeek:
            return programs.filter { $0.startDate <= now && $0.endDate >= now }
        case .tomorrow:  // Added missing case
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
            return programs.filter { $0.startDate <= tomorrow && $0.endDate >= tomorrow }
        case .upcoming:
            return programs.filter { $0.startDate > now }
        case .past:
            return programs.filter { $0.endDate < now }
        case .unspecified:
            return programs
        }
    }

    private static func activePrograms(_ programs: [Program]) -> [Program] {
        let now = Date()
        return programs.filter { $0.startDate <= now && $0.endDate >= now }
    }

    // v23.0: Filter programs to only those within non-draft plans
    // Excludes theoretical programs (from draft plans = ideas not started)
    private static func programsFromNonDraftPlans(_ programs: [Program], memberId: String) -> [Program] {
        let realPlans = PlanDataStore.allPlans(for: memberId)
            .filter { $0.effectiveStatus != .draft }
        let realPlanIds = Set(realPlans.map { $0.id })
        return programs.filter { realPlanIds.contains($0.planId) }
    }

    private static func upcomingPrograms(_ programs: [Program]) -> [Program] {
        let now = Date()
        return programs.filter { $0.startDate > now }
    }

    private static func pastPrograms(_ programs: [Program]) -> [Program] {
        let now = Date()
        return programs.filter { $0.endDate < now }
    }

    // MARK: - Note on StandardFilteringContext
    // StandardFilteringContext support removed as it still references the deleted StatusSlot enum.
    // This will need to be updated separately when StandardFilteringContext is migrated to use
    // entity-specific status enums (WorkoutStatus, PlanStatus, UserStatus).

    /// Extended programs method with rawText support for special keywords
    static func programs(for memberId: String, status: ProgramStatus?, temporal: TemporalSlot, rawText: String?) -> [Program] {
        // Handle special keyword "draft"
        if let text = rawText?.lowercased(), text.contains("draft") {
            return draftPrograms(for: memberId)
        }

        // Otherwise use normal status/temporal filtering
        return programs(for: memberId, status: status, temporal: temporal)
    }

    static func draftPrograms(for memberId: String) -> [Program] {
        return ProgramDataStore.allPrograms(for: memberId).filter { program in
            // v21.2: Filter by stored status (not computed from dates)
            program.status == .draft
        }
    }
}
