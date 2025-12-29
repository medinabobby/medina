//
//  SidebarFilterSection.swift
//  Medina
//
//  v105: Filter section at TOP of sidebar for trainer/admin roles
//  v105.1: Collapsible member list + expandable trainer drill-down
//  v187: Removed admin/gymOwner filters (deferred for beta)
//  v190: Member list truncation with "+ X more members..." modal
//
//  Renders filter options for trainer role:
//  - Trainer: All Members (collapsible) + assigned members (truncated)
//

import SwiftUI

/// Filter selection section displayed at TOP of sidebar
struct SidebarFilterSection: View {
    @ObservedObject var context: SidebarContext
    let onShowAll: (String, EntityListData) -> Void  // v190: For member modal

    // v105.1: Expansion states
    // v187: Removed isTrainersExpanded (admin UI deferred)
    @State private var isMembersExpanded = true

    // v190: Member display limit
    private let sidebarMemberLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            filterOptions

            Divider()
                .padding(.vertical, 8)
        }
    }

    // v187: Simplified to trainer-only filters (admin/gymOwner deferred for beta)
    @ViewBuilder
    private var filterOptions: some View {
        if context.currentUser.hasRole(.trainer) {
            trainerFilters
        } else {
            EmptyView()
        }
    }

    // MARK: - Trainer Filters

    private var trainerFilters: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "All Members" option - collapsible
            FilterRowView(
                icon: "person.2.fill",
                title: "All Members",
                isActive: context.filter == .allMembers,
                count: assignedMembers.count,
                isExpandable: true,
                isExpanded: isMembersExpanded
            ) {
                // Tap toggles expansion AND sets filter
                withAnimation(.easeInOut(duration: 0.2)) {
                    isMembersExpanded.toggle()
                }
                context.clearFilter()
            }

            // Individual member rows (collapsible, truncated to limit)
            if isMembersExpanded {
                // v190: Show first N members
                ForEach(assignedMembers.prefix(sidebarMemberLimit), id: \.id) { member in
                    FilterRowView(
                        icon: "person.fill",
                        title: member.name,
                        isActive: context.filter == .member(member.id),
                        indent: true
                    ) {
                        context.selectMember(member.id)
                    }
                }

                // v190: "+ X more members..." link to modal
                if assignedMembers.count > sidebarMemberLimit {
                    SidebarMoreButton(
                        remainingCount: assignedMembers.count - sidebarMemberLimit,
                        label: "members"
                    ) {
                        // v190: Use .memberFilter for selection behavior (not .users for navigation)
                        onShowAll("All Members", .memberFilter(assignedMembers))
                    }
                }
            }
        }
    }

    // v187: Removed gymManagerFilters (admin/gymOwner UI deferred for beta)

    // MARK: - Data

    private var assignedMembers: [UnifiedUser] {
        let members = UserDataStore.members(assignedToTrainer: context.currentUser.id)
        // v191: Sort by recency so recently-selected members appear in top 3
        return MemberRecencyStore.sortedByRecency(members, trainerId: context.currentUser.id)
    }

    // v187: Removed gymMembers, gymTrainers (admin UI deferred for beta)
}
