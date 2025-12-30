//
// TrainerSidebarSections.swift
// Medina
//
// v90.0: Trainer-specific sidebar sections (My Members, My Plans)
// Created: December 2025
//

import SwiftUI

// MARK: - My Members Folder

/// Trainer sidebar section showing assigned members
/// Tapping a member navigates to MemberDetailView
struct MyMembersFolder: View {
    let trainerId: String
    let isExpanded: Binding<Bool>
    let onNavigate: (String, Entity) -> Void
    let onDismiss: () -> Void

    private let sidebarItemLimit = 5

    private var members: [UnifiedUser] {
        UserDataStore.members(assignedToTrainer: trainerId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            folderHeader(
                icon: "person.2.fill",
                title: "My Members",
                count: members.count,
                isExpanded: isExpanded
            )

            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 0) {
                    if members.isEmpty {
                        emptyState
                    } else {
                        ForEach(members.prefix(sidebarItemLimit), id: \.id) { member in
                            memberButton(member)
                        }

                        if members.count > sidebarItemLimit {
                            showAllButton
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Text("No assigned members")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.leading, 44)
            .padding(.trailing, 20)
            .padding(.vertical, 10)
    }

    // MARK: - Member Button

    private func memberButton(_ member: UnifiedUser) -> some View {
        Button(action: {
            onNavigate(member.id, .member)
            onDismiss()
        }) {
            HStack {
                Text(member.name)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                // Status dot (membership status)
                // Blue = active membership, Grey = inactive/pending
                StatusDot(membershipStatus: member.memberProfile?.membershipStatus)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.leading, 44)
        .padding(.trailing, 20)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.01))
        .contentShape(Rectangle())
    }

    // MARK: - Show All Button

    private var showAllButton: some View {
        Button(action: {
            // TODO: v90.0 - Implement Show All Members modal
        }) {
            HStack(spacing: 8) {
                Text("Show All Members")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)

                Spacer()

                Text("(\(members.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.leading, 44)
        .padding(.trailing, 20)
        .padding(.vertical, 12)
        .padding(.top, 4)
        .background(Color.white.opacity(0.01))
        .contentShape(Rectangle())
    }

    // MARK: - Folder Header

    private func folderHeader(
        icon: String,
        title: String,
        count: Int,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.wrappedValue.toggle()
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 12)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 20)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("(\(count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.01))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - My Plans Folder

/// Trainer sidebar section showing plans for assigned members
/// Groups plans by member name for easy navigation
struct MyPlansFolder: View {
    let trainerId: String
    let isExpanded: Binding<Bool>
    let onNavigate: (String, Entity) -> Void
    let onDismiss: () -> Void

    private let sidebarItemLimit = 5

    private var plansByMember: [String: [Plan]] {
        PlanDataStore.plansByMember(forTrainer: trainerId)
    }

    private var allPlans: [Plan] {
        PlanDataStore.plansForTrainer(trainerId)
    }

    /// Plans with member names for display (sorted by recency - most recent first)
    private var plansWithMembers: [(plan: Plan, memberName: String)] {
        allPlans.compactMap { plan in
            guard let member = LocalDataStore.shared.users[plan.memberId] else {
                return nil
            }
            return (plan, member.name)
        }
        .sorted { $0.plan.startDate > $1.plan.startDate }  // Recency: most recent first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            folderHeader(
                icon: "list.clipboard",
                title: "My Plans",
                count: allPlans.count,
                isExpanded: isExpanded
            )

            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 0) {
                    if plansWithMembers.isEmpty {
                        emptyState
                    } else {
                        ForEach(plansWithMembers.prefix(sidebarItemLimit), id: \.plan.id) { item in
                            planButton(item.plan, memberName: item.memberName)
                        }

                        if plansWithMembers.count > sidebarItemLimit {
                            showAllButton
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Text("No plans for members")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.leading, 44)
            .padding(.trailing, 20)
            .padding(.vertical, 10)
    }

    // MARK: - Plan Button

    private func planButton(_ plan: Plan, memberName: String) -> some View {
        Button(action: {
            onNavigate(plan.id, .plan)
            onDismiss()
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stripPlanSuffix(plan.name))
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(memberName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Status dot: Blue = active, Grey = draft
                StatusDot(planStatus: plan.effectiveStatus)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.leading, 44)
        .padding(.trailing, 20)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.01))
        .contentShape(Rectangle())
    }

    // MARK: - Show All Button

    private var showAllButton: some View {
        Button(action: {
            // TODO: v90.0 - Implement Show All Plans modal
        }) {
            HStack(spacing: 8) {
                Text("Show All Plans")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)

                Spacer()

                Text("(\(allPlans.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.leading, 44)
        .padding(.trailing, 20)
        .padding(.vertical, 12)
        .padding(.top, 4)
        .background(Color.white.opacity(0.01))
        .contentShape(Rectangle())
    }

    // MARK: - Helper Functions

    private func stripPlanSuffix(_ planName: String) -> String {
        var simplified = planName
        // Remove " Plan" suffix
        if simplified.hasSuffix(" Plan") {
            simplified = String(simplified.dropLast(5))
        }
        // Remove date ranges (e.g., "Nov 10-28")
        let datePattern = #"\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d+-\d+"#
        if let range = simplified.range(of: datePattern, options: .regularExpression) {
            simplified = String(simplified[..<range.lowerBound])
        }
        return simplified.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Folder Header

    private func folderHeader(
        icon: String,
        title: String,
        count: Int,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.wrappedValue.toggle()
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 12)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 20)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("(\(count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.01))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
