//
// MemberContextSelector.swift
// Medina
//
// v91.0: Header dropdown for trainer member context selection
// Single source of truth for sidebar filtering and AI context
//

import SwiftUI

/// Header dropdown showing current member context
/// Trainer can switch between "All Members" (aggregate view) and individual members
struct MemberContextSelector: View {
    let trainerId: String
    @Binding var selectedMemberId: String?
    @Binding var showPicker: Bool

    private var members: [UnifiedUser] {
        UserDataStore.members(assignedToTrainer: trainerId)
    }

    private var selectedMemberName: String {
        if let memberId = selectedMemberId,
           let member = members.first(where: { $0.id == memberId }) {
            return member.name.components(separatedBy: " ").first ?? member.name
        }
        return "All Members"
    }

    private var isFiltered: Bool {
        selectedMemberId != nil
    }

    var body: some View {
        Button(action: { showPicker = true }) {
            HStack(spacing: 4) {
                Text(selectedMemberName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isFiltered ? .accentColor : .secondary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isFiltered ? .accentColor : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isFiltered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // All Members selected
        MemberContextSelector(
            trainerId: "trainer-nick",
            selectedMemberId: .constant(nil),
            showPicker: .constant(false)
        )

        // Specific member selected
        MemberContextSelector(
            trainerId: "trainer-nick",
            selectedMemberId: .constant("member-bobby"),
            showPicker: .constant(false)
        )
    }
    .padding()
}
