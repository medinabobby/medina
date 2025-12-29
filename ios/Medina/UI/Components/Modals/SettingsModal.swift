//
// SettingsModal.swift
// Medina
//
// v48.1: Consolidated settings modal
// v58.0: Navigation-based redesign with Profile, Training Preferences, Billing sub-views
// v74.1: Extracted components and sub-views to Settings folder (~1081 → ~350 lines)
// v79.2: Drill-down navigation - Training Preferences moved to dedicated view
// v80.2: Consolidated Account section (Gym, Profile, Billing together)
// Created: November 4, 2025
//
// Settings modal with navigation to sub-screens (modeled after Claude/ChatGPT iOS apps)
//

import SwiftUI

struct SettingsModal: View {
    @Environment(\.dismiss) var dismiss
    let user: UnifiedUser
    let onLogout: () -> Void
    let onSave: () -> Void
    let onDeleteAccount: () -> Void
    let onProfileCompleted: (() -> Void)?

    @State private var currentUser: UnifiedUser
    @State private var showLogoutConfirmation = false
    @State private var wasIncomplete: Bool

    init(user: UnifiedUser, onLogout: @escaping () -> Void, onSave: @escaping () -> Void, onDeleteAccount: @escaping () -> Void = {}, onProfileCompleted: (() -> Void)? = nil) {
        self.user = user
        self.onLogout = onLogout
        self.onSave = onSave
        self.onDeleteAccount = onDeleteAccount
        self.onProfileCompleted = onProfileCompleted

        let freshUser = TestDataManager.shared.users[user.id] ?? user
        _currentUser = State(initialValue: freshUser)
        _wasIncomplete = State(initialValue: !freshUser.hasCompletedOnboarding)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // v80.2: Consolidated ACCOUNT section (Gym, Profile, Billing)
                    accountSection
                    trainingPreferencesSection
                    appInfoSection
                    resourcesSection
                    creditsSection
                    signOutButton
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Sign Out", isPresented: $showLogoutConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) { onLogout() }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }

    // MARK: - Sections
    // v80.2: Consolidated ACCOUNT section with Gym, Profile, and Billing

    @ViewBuilder
    private var accountSection: some View {
        SettingsSection(title: "ACCOUNT") {
            // Gym row (only show if user has a gym)
            if let gym = gymName {
                NavigationLink {
                    GymDetailView(user: $currentUser)
                } label: {
                    SettingsNavigationRow(icon: "building.2.fill", title: "Gym", value: gym)
                }

                SettingsDivider()
            }

            // v92.0: Unified user profile view (replaces ProfileEditView)
            // v90.0: Dynamic role display (Member, Trainer, Admin, Gym Owner) with email
            NavigationLink {
                UserProfileView(
                    userId: currentUser.id,
                    mode: .edit,
                    onSave: { updatedUser in
                        currentUser = updatedUser
                        onSave()
                    },
                    onDeleteAccount: onDeleteAccount
                )
            } label: {
                SettingsNavigationRow(icon: roleIcon, title: roleDisplayName, value: currentUser.email ?? currentUser.name)
            }

            // v92.0: Trainer row (only show if member has assigned trainer)
            if let trainer = assignedTrainer {
                SettingsDivider()

                NavigationLink {
                    UserProfileView(userId: trainer.id, mode: .view)
                } label: {
                    SettingsNavigationRow(icon: "figure.strengthtraining.traditional", title: "Trainer", value: trainer.name)
                }
            }

            SettingsDivider()

            // Billing row - v90.0: Show price instead of plan name
            NavigationLink {
                BillingView(user: currentUser)
            } label: {
                SettingsNavigationRow(icon: "creditcard.fill", title: "Plan", value: currentPlanPrice)
            }
        }
    }

    @ViewBuilder
    private var trainingPreferencesSection: some View {
        SettingsSection(title: "TRAINING") {
            NavigationLink {
                TrainingPreferencesView(user: $currentUser, onSave: onSave)
            } label: {
                SettingsNavigationRow(
                    icon: "figure.run",
                    title: "Preferences",
                    value: trainingSummary
                )
            }
        }
    }

    @ViewBuilder
    private var appInfoSection: some View {
        SettingsSection(title: "APP INFORMATION") {
            SettingsValueRow(icon: "app.badge", label: "Version", value: appVersionDisplay)
        }
    }

    @ViewBuilder
    private var resourcesSection: some View {
        SettingsSection(title: "LEGAL") {
            NavigationLink {
                TermsOfServiceView()
            } label: {
                SettingsNavigationRow(icon: "doc.text", title: "Terms of Service", value: nil)
            }

            SettingsDivider()

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                SettingsNavigationRow(icon: "hand.raised.fill", title: "Privacy Policy", value: nil)
            }
        }
    }

    @ViewBuilder
    private var creditsSection: some View {
        SettingsSection(title: "CREDITS") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Built with ❤️ by the Medina team")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                Text("© 2025 Medina. All rights reserved.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var signOutButton: some View {
        Button { showLogoutConfirmation = true } label: {
            HStack {
                Spacer()
                Text("Sign Out")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.red)
                Spacer()
            }
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    // MARK: - Helpers

    private var gymName: String? {
        guard let gymId = currentUser.gymId,
              let gym = TestDataManager.shared.gyms[gymId] else { return nil }
        return gym.name
    }

    /// v80.2: Get assigned trainer for member
    private var assignedTrainer: UnifiedUser? {
        guard let trainerId = currentUser.memberProfile?.trainerId else { return nil }
        return TestDataManager.shared.users[trainerId]
    }

    /// v80.2: Get current plan name from gym membership tiers
    private var currentPlanName: String {
        // Get the user's subscribed tier
        guard let tierIdRaw = currentUser.memberProfile?.subscriptionTierId,
              let gymId = currentUser.gymId,
              let gym = TestDataManager.shared.gyms[gymId] else {
            // Default to first tier name if no subscription set
            if let gymId = currentUser.gymId,
               let gym = TestDataManager.shared.gyms[gymId],
               let firstTier = gym.membershipTiers.first {
                return firstTier.name
            }
            return "Free"
        }

        // Find matching tier
        if let tier = gym.membershipTiers.first(where: { $0.id == tierIdRaw }) {
            return tier.name
        }

        return gym.membershipTiers.first?.name ?? "Free"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// Combined version string for display: "1.0 (Build 6)"
    private var appVersionDisplay: String {
        "\(appVersion) (Build \(appBuild))"
    }

    private var membershipStatusLabel: String {
        switch currentUser.memberProfile?.membershipStatus {
        case .active: return "Beta Member"
        case .pending: return "Pending"
        case .expired: return "Expired"
        case .suspended: return "Suspended"
        case .cancelled: return "Cancelled"
        case .none: return "Free"
        }
    }

    // v90.0: Dynamic role display based on user's highest role
    // v187: Simplified to trainer/member only (admin/gymOwner deferred for beta)
    private var roleDisplayName: String {
        if currentUser.hasRole(.trainer) { return "Trainer" }
        return "Member"
    }

    // v90.0: Role-specific icon
    // v187: Simplified to trainer/member only
    private var roleIcon: String {
        if currentUser.hasRole(.trainer) {
            return "person.badge.shield.checkmark.fill"
        }
        return "person.fill"
    }

    // v99.3: Show tier name and class credits (not price)
    // v187: Simplified to trainer/member only
    private var currentPlanPrice: String {
        // Trainers don't have member subscriptions
        if currentUser.hasRole(.trainer) {
            return "Staff"
        }

        guard let tierIdRaw = currentUser.memberProfile?.subscriptionTierId,
              let gymId = currentUser.gymId,
              let gym = TestDataManager.shared.gyms[gymId],
              let tier = gym.membershipTiers.first(where: { $0.id == tierIdRaw }) else {
            return "Free"
        }

        // Show tier name with class credits
        if tier.classCredits == Int.max {
            return "\(tier.name) • Unlimited"
        }
        return "\(tier.name) • \(tier.classCredits) classes/mo"
    }

    private var trainingSummary: String {
        let days = currentUser.memberProfile?.preferredWorkoutDays?.count ?? 0
        let duration = currentUser.memberProfile?.preferredSessionDuration ?? 60
        return "\(days) days, \(duration) min"
    }
}

#Preview {
    SettingsModal(
        user: UnifiedUser(
            id: "bobby",
            firebaseUID: "test",
            authProvider: .email,
            email: "bobby@medina.com",
            name: "Bobby Tulsiani",
            birthdate: Date(),
            gender: .male,
            roles: [.member],
            gymId: "district",
            memberProfile: MemberProfile(
                fitnessGoal: .strength,
                experienceLevel: .intermediate,
                preferredSessionDuration: 60,
                membershipStatus: .active,
                memberSince: Date()
            )
        ),
        onLogout: {},
        onSave: {},
        onDeleteAccount: {}
    )
}
