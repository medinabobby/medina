//
// UserProfileView.swift
// Medina
//
// v93.7: Refactored from 1,053 lines to ~280 lines
// Extracted components:
//   - UserProfileViewModel.swift (state management + save logic)
//   - UserProfileComponents.swift (ProfileSection, ProfileCard, edit rows, FlowLayout)
//   - UserProfileTrainerSections.swift (bio, specialties, certifications, contact)
//   - UserProfileMemberSections.swift (training prefs, plan, workouts, stats, edit fields)
//

import SwiftUI

// MARK: - View Mode

enum ProfileViewMode {
    case view  // Read-only (viewing another user)
    case edit  // Editable (own profile in settings)
}

// MARK: - Main View

struct UserProfileView: View {
    let userId: String
    let mode: ProfileViewMode

    // Edit mode callbacks (only used when mode == .edit)
    var onSave: ((UnifiedUser) -> Void)?
    var onDeleteAccount: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigationModel: NavigationModel

    @StateObject private var viewModel: UserProfileViewModel

    init(userId: String, mode: ProfileViewMode, onSave: ((UnifiedUser) -> Void)? = nil, onDeleteAccount: (() -> Void)? = nil) {
        self.userId = userId
        self.mode = mode
        self.onSave = onSave
        self.onDeleteAccount = onDeleteAccount
        self._viewModel = StateObject(wrappedValue: UserProfileViewModel(userId: userId, mode: mode))
    }

    private var user: UnifiedUser? {
        LocalDataStore.shared.users[userId]
    }

    private var coordinator: NavigationCoordinator {
        NavigationCoordinator(navigationModel: navigationModel)
    }

    var body: some View {
        Group {
            if let user = user {
                ScrollView {
                    VStack(spacing: 24) {
                        // Profile header
                        profileHeader(user)

                        // Role-specific content
                        if user.hasRole(.trainer) {
                            TrainerContentSections(user: user, mode: mode)
                        }

                        if user.hasRole(.member) || mode == .edit {
                            memberContent(user)
                        }

                        // Edit mode footer
                        if mode == .edit {
                            MemberEditModeFooter(
                                viewModel: viewModel,
                                onSave: onSave,
                                onDeleteAccount: onDeleteAccount,
                                onDismiss: { dismiss() }
                            )
                        }
                    }
                    .padding(20)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle(viewModel.navigationTitle())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if mode == .view {
                        ToolbarItem(placement: .primaryAction) {
                            viewModeToolbar(user)
                        }
                    }
                }
                .onAppear {
                    if mode == .edit {
                        viewModel.initializeEditState()
                    }
                }
            } else {
                userNotFoundView
            }
        }
        .alert("Delete Account", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDeleteAccount?() }
        } message: {
            Text("This action cannot be undone. All your data will be permanently removed.")
        }
    }

    // MARK: - Profile Header

    @ViewBuilder
    private func profileHeader(_ user: UnifiedUser) -> some View {
        if user.hasRole(.trainer) {
            TrainerProfileHeader(user: user)
        } else {
            MemberProfileHeader(user: user, mode: mode)
        }
    }

    // MARK: - Member Content

    @ViewBuilder
    private func memberContent(_ user: UnifiedUser) -> some View {
        if mode == .edit {
            // Edit mode: Show editable fields
            MemberEditableFields(user: user, viewModel: viewModel)
        } else {
            // View mode: Show training data
            MemberTrainingPreferencesSection(user: user)
            MemberActivePlanSection(
                userId: userId,
                userFirstName: user.firstName,
                coordinator: coordinator
            )
            MemberRecentWorkoutsSection(userId: userId, coordinator: coordinator)
            MemberStatsSection(userId: userId)
        }
    }

    // MARK: - View Mode Toolbar

    @ViewBuilder
    private func viewModeToolbar(_ user: UnifiedUser) -> some View {
        // Only show menu for member profiles (trainer viewing member)
        if user.hasRole(.member) && !user.hasRole(.trainer) {
            Menu {
                Button(action: {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SetFocusMember"),
                        object: nil,
                        userInfo: ["memberId": userId]
                    )
                    navigationModel.popToRoot()
                }) {
                    Label("Make Focus Member", systemImage: "person.fill.checkmark")
                }

                Divider()

                Button(action: {
                    // TODO: v91+ - Message member
                }) {
                    Label("Send Message", systemImage: "message")
                }
                .disabled(true)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
            }
        }
    }

    // MARK: - User Not Found

    @ViewBuilder
    private var userNotFoundView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("User Not Found")
                .font(.headline)
            Text("This user could not be loaded.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview("Member View Mode") {
    NavigationStack {
        UserProfileView(userId: "bobby_tulsiani", mode: .view)
            .environmentObject(NavigationModel())
    }
}

#Preview("Trainer View Mode") {
    NavigationStack {
        UserProfileView(userId: "nick_vargas", mode: .view)
            .environmentObject(NavigationModel())
    }
}

#Preview("Edit Mode") {
    NavigationStack {
        UserProfileView(userId: "bobby_tulsiani", mode: .edit, onSave: { _ in }, onDeleteAccount: {})
            .environmentObject(NavigationModel())
    }
}
