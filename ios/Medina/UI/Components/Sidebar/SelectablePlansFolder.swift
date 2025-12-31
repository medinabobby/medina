//
//  SelectablePlansFolder.swift
//  Medina
//
//  v115: Plans folder with highlight-selection pattern
//  v116: Uses sidebarPlans (max 1), adds "+N more plans" link
//  v170: Simplified - flat plan list, no nested programs
//  v170.1: Status dots instead of text labels
//  v173: Removed folder icon next to plans (no longer showing nested programs)
//

import SwiftUI

/// Plans folder - flat list with status dots (v170: removed nested programs)
/// v170.1: Shows up to 3 plans (active, draft, completed) with colored status dots
struct SelectablePlansFolder: View {
    @ObservedObject var context: SidebarContext
    let contextLabel: String  // "Plans" or "Bobby's Plans"
    @Binding var isExpanded: Bool
    let onNavigate: (String, Entity) -> Void
    let onShowAll: (String, EntityListData) -> Void
    let onDismiss: () -> Void

    var body: some View {
        SidebarFolderView(
            icon: "list.clipboard",
            title: contextLabel,
            count: context.availablePlans.count,
            isExpanded: $isExpanded
        ) {
            if context.sidebarPlans.isEmpty {
                SidebarEmptyState("No plans")
            } else {
                // v170: Flat plan list with status badges (no nested programs)
                ForEach(context.sidebarPlans) { plan in
                    SimplePlanRow(
                        plan: plan,
                        onNavigate: onNavigate,
                        onDismiss: onDismiss
                    )
                }

                // "+N more plans" link if more exist
                if context.hasMorePlans {
                    MorePlansLink(
                        count: context.morePlansCount,
                        contextLabel: contextLabel,
                        allPlans: context.availablePlans,
                        onShowAll: onShowAll
                    )
                }
            }
        }
    }
}

// MARK: - More Plans Link (v116)

/// Link to show all plans in modal
struct MorePlansLink: View {
    let count: Int
    let contextLabel: String
    let allPlans: [Plan]
    let onShowAll: (String, EntityListData) -> Void

    var body: some View {
        Button {
            onShowAll(contextLabel, .plans(allPlans))
        } label: {
            HStack(spacing: 8) {
                Text("+ \(count) more plans...")
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                    .fontWeight(.medium)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .padding(.leading, 56)  // Align with plan names
            .padding(.trailing, 20)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.01))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Simple Plan Row (v170)

/// A simplified plan row with status badge (no nested programs)
/// v170: Clean, flat design - click navigates to PlanDetailView
struct SimplePlanRow: View {
    let plan: Plan
    let onNavigate: (String, Entity) -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button {
            onNavigate(plan.id, .plan)
            onDismiss()
        } label: {
            HStack(spacing: 8) {
                // v173: Removed folder icon (no longer showing nested programs)

                // Plan name
                Text(stripPlanSuffix(plan.name))
                    .font(.subheadline)
                    .foregroundColor(Color("PrimaryText"))
                    .lineLimit(1)

                Spacer()

                // Status dot (v170.1: colored dot)
                PlanStatusDot(status: plan.effectiveStatus)
            }
            .padding(.leading, 56)  // Aligned with folder content
            .padding(.trailing, 20)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.01))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Strip common suffixes for cleaner display
    private func stripPlanSuffix(_ name: String) -> String {
        var simplified = name
        if simplified.hasSuffix(" Plan") {
            simplified = String(simplified.dropLast(5))
        }
        return simplified.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Plan Status Dot (v170.1)

/// Colored dot showing plan status
/// v170.1: Simple dots for plan status
/// v172: Removed abandoned - plans are now draft/active/completed only
/// v190.1: Fixed colors to match StatusHelpers canonical scheme
struct PlanStatusDot: View {
    let status: PlanStatus

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
    }

    /// Colors from StatusHelpers.swift (canonical source)
    /// v235: Fixed to match StatusHelpers - active=blue, completed=green
    private var dotColor: Color {
        switch status {
        case .draft:
            return Color("SecondaryText")  // Grey - not yet started
        case .active:
            return .accentColor  // Blue - currently running (only 1 at a time)
        case .completed:
            return .green  // Green - finished successfully
        }
    }
}

// MARK: - Preview

struct SelectablePlansFolder_Previews: PreviewProvider {
    static var previews: some View {
        SelectablePlansFolderPreview()
            .frame(width: 300)
            .background(Color("Background"))
    }
}

private struct SelectablePlansFolderPreview: View {
    @State private var isExpanded = true

    var body: some View {
        let user = UnifiedUser(
            id: "bobby",
            firebaseUID: "test",
            authProvider: .email,
            email: "bobby@test.com",
            name: "Bobby Tulsiani",
            birthdate: Date(),
            gender: .male,
            roles: [.member],
            gymId: "district_brooklyn",
            memberProfile: nil
        )
        let context = SidebarContext(user: user)

        SelectablePlansFolder(
            context: context,
            contextLabel: "Plans",
            isExpanded: $isExpanded,
            onNavigate: { _, _ in },
            onShowAll: { _, _ in },
            onDismiss: { }
        )
    }
}
