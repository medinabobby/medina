//
// MemberPickerSheet.swift
// Medina
//
// v91.0: Bottom sheet for trainer member selection
// "All Members" clears context, individual members filter sidebar
//

import SwiftUI

/// Bottom sheet for selecting member context
/// Shows "All Members" option at top, then list of assigned members with status dots
struct MemberPickerSheet: View {
    let trainerId: String
    @Binding var selectedMemberId: String?
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    private var members: [UnifiedUser] {
        UserDataStore.members(assignedToTrainer: trainerId)
    }

    private var filteredMembers: [UnifiedUser] {
        if searchText.isEmpty {
            return members
        }
        return members.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var showSearchBar: Bool {
        members.count >= 10
    }

    var body: some View {
        NavigationStack {
            List {
                // "All Members" option (clears context)
                allMembersRow

                // Member list
                Section {
                    ForEach(filteredMembers, id: \.id) { member in
                        memberRow(member)
                    }
                } header: {
                    if !members.isEmpty {
                        Text("Assigned Members")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search members...")
            .navigationTitle("Select Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - All Members Row

    private var allMembersRow: some View {
        Button(action: {
            selectedMemberId = nil
            dismiss()
        }) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                    .frame(width: 32)

                Text("All Members")
                    .foregroundColor(.primary)

                Spacer()

                if selectedMemberId == nil {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
        .listRowBackground(selectedMemberId == nil ? Color.accentColor.opacity(0.1) : Color(.systemBackground))
    }

    // MARK: - Member Row

    private func memberRow(_ member: UnifiedUser) -> some View {
        Button(action: {
            selectedMemberId = member.id
            dismiss()
        }) {
            HStack {
                // Member name
                Text(member.name)
                    .foregroundColor(.primary)

                Spacer()

                // Status dot (membership status)
                StatusDot(membershipStatus: member.memberProfile?.membershipStatus)

                // Checkmark if selected
                if selectedMemberId == member.id {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
        .listRowBackground(selectedMemberId == member.id ? Color.accentColor.opacity(0.1) : Color(.systemBackground))
    }
}

// MARK: - Preview

#Preview {
    MemberPickerSheet(
        trainerId: "trainer-nick",
        selectedMemberId: .constant(nil)
    )
}
