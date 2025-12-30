//
//  SidebarContext.swift
//  Medina
//
//  v105: Unified context model for sidebar filtering
//  v114: Added plan/program filter state for hierarchical filtering
//  v116: Added sidebarPlans (max 1), hasMorePlans, auto-select current plan
//  v170: Smart 3-plan display (active, draft/future, recent completed)
//  v187: Removed admin/gymOwner checks (deferred for beta)
//
//  Single source of truth for:
//  - What content to show in sidebar
//  - What context to send to AI
//  - How to label sections (context-aware)
//  - Plan/Program filtering for workouts
//

import SwiftUI

/// Observable context for sidebar filtering across trainer and admin roles
@MainActor
final class SidebarContext: ObservableObject {

    // MARK: - Published State

    @Published var filter: SidebarFilter = .allMembers

    /// v114: Selected plan ID for filtering workouts (nil = all plans or active plan)
    @Published var selectedPlanId: String? = nil

    /// v114: Selected program ID for filtering workouts (nil = all programs in plan)
    @Published var selectedProgramId: String? = nil

    // MARK: - Properties

    let currentUser: UnifiedUser

    // MARK: - Init

    init(user: UnifiedUser) {
        self.currentUser = user
        // v116: Auto-select current plan on init
        selectCurrentPlanIfNone()
    }

    // MARK: - v170: Smart 3-Plan Display

    /// Plans to show in sidebar (max 3: active, draft/future, recent completed)
    /// v170: Simplified from nested programs to flat list with status badges
    /// Logic:
    /// 1. Active plan (always shown if exists)
    /// 2. Draft or future-dated plan (if exists)
    /// 3. Most recent completed or abandoned (if exists)
    var sidebarPlans: [Plan] {
        var result: [Plan] = []
        var usedIds = Set<String>()

        // 1. Active plan (most important)
        if let activePlan = availablePlans.first(where: { $0.effectiveStatus == .active }) {
            result.append(activePlan)
            usedIds.insert(activePlan.id)
        }

        // 2. Draft or future-dated plan
        let draftOrFuture = availablePlans.first { plan in
            !usedIds.contains(plan.id) && (
                plan.effectiveStatus == .draft ||
                (plan.startDate ?? .distantPast) > Date()
            )
        }
        if let plan = draftOrFuture {
            result.append(plan)
            usedIds.insert(plan.id)
        }

        // 3. Most recent completed
        // v172: Removed abandoned - plans are now draft/active/completed only
        let recentCompleted = availablePlans
            .filter { !usedIds.contains($0.id) }
            .first { $0.effectiveStatus == .completed }
        if let plan = recentCompleted {
            result.append(plan)
            usedIds.insert(plan.id)
        }

        // If we have fewer than 3 and more plans exist, fill with remaining
        if result.count < 3 {
            for plan in availablePlans where !usedIds.contains(plan.id) {
                result.append(plan)
                usedIds.insert(plan.id)
                if result.count >= 3 { break }
            }
        }

        return result
    }

    /// Whether there are more plans than shown in sidebar
    var hasMorePlans: Bool {
        availablePlans.count > sidebarPlans.count
    }

    /// Count of additional plans not shown in sidebar
    var morePlansCount: Int {
        max(0, availablePlans.count - sidebarPlans.count)
    }

    /// Auto-select current plan if nothing selected
    func selectCurrentPlanIfNone() {
        guard selectedPlanId == nil else { return }
        if let activePlan = availablePlans.first(where: { $0.effectiveStatus == .active }) {
            selectedPlanId = activePlan.id
        } else if let firstPlan = availablePlans.first {
            selectedPlanId = firstPlan.id
        }
    }

    // MARK: - Plan/Program Computed Properties (v114)

    /// The currently selected plan (if any)
    var selectedPlan: Plan? {
        guard let planId = selectedPlanId else { return nil }
        return LocalDataStore.shared.plans[planId]
    }

    /// The currently selected program (if any)
    var selectedProgram: Program? {
        guard let programId = selectedProgramId else { return nil }
        return LocalDataStore.shared.programs[programId]
    }

    /// Effective member ID for data queries
    /// For members: their own ID
    /// For trainers: selected member ID (if any)
    /// v187: Removed admin/gymOwner checks (deferred for beta)
    var effectiveMemberId: String? {
        if let memberId = selectedMemberId {
            return memberId
        }
        // For member role, use their own ID
        if currentUser.hasRole(.member) && !currentUser.hasRole(.trainer) {
            return currentUser.id
        }
        return nil
    }

    /// Available plans for the effective member (for plan dropdown)
    /// v189: When no member selected (All Members), returns all plans for trainer's members
    var availablePlans: [Plan] {
        if let memberId = effectiveMemberId {
            // Specific member selected - show their plans
            return PlanDataStore.allPlans(for: memberId)
                .filter { !$0.isSingleWorkout }
                .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        }

        // v189: All Members view - show all members' plans for trainer
        if currentUser.hasRole(.trainer) {
            let members = UserDataStore.members(assignedToTrainer: currentUser.id)
            var allPlans: [Plan] = []
            for member in members {
                let memberPlans = PlanDataStore.allPlans(for: member.id)
                    .filter { !$0.isSingleWorkout }
                allPlans.append(contentsOf: memberPlans)
            }
            return allPlans.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        }

        return []
    }

    /// Available programs for the selected plan (for program dropdown)
    var availablePrograms: [Program] {
        guard let planId = selectedPlanId else { return [] }
        return ProgramDataStore.programs(for: planId)
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    // MARK: - Plan/Program Actions (v114)

    /// Select a plan (cascades: clears program selection)
    func selectPlan(_ planId: String?) {
        selectedPlanId = planId
        selectedProgramId = nil  // Cascade: clear program when plan changes
    }

    /// Select a program within the current plan
    func selectProgram(_ programId: String?) {
        selectedProgramId = programId
    }

    /// Clear plan and program filters
    func clearPlanFilters() {
        selectedPlanId = nil
        selectedProgramId = nil
    }

    // MARK: - AI Integration

    /// Selected member ID for AI context (nil = aggregate view)
    /// Used by ChatViewModel to set ResponsesManager.selectedMemberId
    var selectedMemberId: String? {
        switch filter {
        case .member(let id):
            return id
        case .trainerMember(_, let memberId):
            return memberId
        default:
            return nil
        }
    }

    /// Selected trainer ID (for gym manager drill-down)
    var selectedTrainerId: String? {
        switch filter {
        case .trainer(let id):
            return id
        case .trainerMember(let trainerId, _):
            return trainerId
        default:
            return nil
        }
    }

    // MARK: - Context-Aware Labels

    /// Plans folder label - "All Plans", "Plans" or "Bobby's Plans"
    /// v189: "All Plans" when trainer in All Members view
    func plansLabel() -> String {
        if let memberId = selectedMemberId {
            return "\(firstName(memberId))'s Plans"
        }
        // v189: Trainer with no member selected = All Plans
        if currentUser.hasRole(.trainer) {
            return "All Plans"
        }
        return "Plans"
    }

    /// Workouts folder label - "Workouts" or "Bobby's Workouts"
    func workoutsLabel() -> String {
        guard let memberId = selectedMemberId else { return "Workouts" }
        return "\(firstName(memberId))'s Workouts"
    }

    /// Exercises folder label - "Exercises" or "Bobby's Exercises"
    func exercisesLabel() -> String {
        guard let memberId = selectedMemberId else { return "Exercises" }
        return "\(firstName(memberId))'s Exercises"
    }

    /// Protocols folder label - "Protocols" or "Bobby's Protocols"
    func protocolsLabel() -> String {
        guard let memberId = selectedMemberId else { return "Protocols" }
        return "\(firstName(memberId))'s Protocols"
    }

    /// Classes folder label - "Classes" or "Bobby's Classes"
    func classesLabel() -> String {
        guard let memberId = selectedMemberId else { return "Classes" }
        return "\(firstName(memberId))'s Classes"
    }

    /// v190: Library folder label - "Library", "All Libraries" or "Bobby's Library"
    func libraryLabel() -> String {
        if let memberId = selectedMemberId {
            return "\(firstName(memberId))'s Library"
        }
        if currentUser.hasRole(.trainer) {
            return "All Libraries"
        }
        return "Library"
    }

    /// Current filter display title (for header if needed)
    var filterTitle: String {
        switch filter {
        case .allMembers:
            return "All Members"
        case .allTrainers:
            return "All Trainers"
        case .classSchedule:
            return "Class Schedule"
        case .member(let id):
            return memberName(id)
        case .trainer(let id):
            return trainerName(id)
        case .trainerMember(_, let memberId):
            return memberName(memberId)
        }
    }

    // MARK: - Filter Actions

    /// Select a specific member (trainer use case)
    /// v114: Also clears plan/program filters when member changes
    /// v116: Auto-selects their current plan
    /// v191: Records recency for sidebar ordering
    func selectMember(_ memberId: String) {
        // v191: Track recency for sidebar ordering
        MemberRecencyStore.recordAccess(memberId: memberId, trainerId: currentUser.id)

        filter = .member(memberId)
        clearPlanFilters()  // Cascade: clear plan/program when member changes
        selectCurrentPlanIfNone()  // v116: Auto-select their current plan
    }

    /// Select a specific trainer (manager drill-down)
    func selectTrainer(_ trainerId: String) {
        filter = .trainer(trainerId)
        clearPlanFilters()  // Cascade: clear plan/program
    }

    /// Select a trainer's member (manager full drill-down)
    /// v114: Also clears plan/program filters when member changes
    func selectTrainerMember(trainerId: String, memberId: String) {
        filter = .trainerMember(trainerId, memberId)
        clearPlanFilters()  // Cascade: clear plan/program when member changes
    }

    /// Clear filter to default aggregate view
    /// v114: Also clears plan/program filters
    func clearFilter() {
        filter = .allMembers
        clearPlanFilters()  // Cascade: clear all filters
    }

    /// Check if a filter is currently active
    func isActive(_ otherFilter: SidebarFilter) -> Bool {
        filter == otherFilter
    }

    // MARK: - Helpers

    private func memberName(_ id: String) -> String {
        LocalDataStore.shared.users[id]?.name ?? "Member"
    }

    private func trainerName(_ id: String) -> String {
        LocalDataStore.shared.users[id]?.name ?? "Trainer"
    }

    private func firstName(_ id: String) -> String {
        guard let name = LocalDataStore.shared.users[id]?.name else { return "Member" }
        return name.components(separatedBy: " ").first ?? name
    }
}
