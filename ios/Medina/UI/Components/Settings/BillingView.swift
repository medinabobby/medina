//
// BillingView.swift
// Medina
//
// v80.2: Netflix-style plan selection with gym membership tiers
// Settings sub-view for billing and subscription management
//

import SwiftUI

struct BillingView: View {
    @Environment(\.dismiss) var dismiss
    let user: UnifiedUser

    @State private var selectedTierId: String?
    @State private var showConfirmChange = false
    @State private var pendingTier: MembershipTier?

    private var gym: Gym? {
        guard let gymId = user.gymId else { return nil }
        return TestDataManager.shared.gyms[gymId]
    }

    private var currentTierId: String? {
        user.memberProfile?.subscriptionTierId
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Plan Cards
                if let gym = gym {
                    planCardsSection(gym: gym)
                } else {
                    noGymSection
                }

                // Member since
                memberSinceSection

                // Footer
                footerSection
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Initialize selected tier from user's current subscription
            selectedTierId = currentTierId ?? gym?.membershipTiers.first?.id
        }
        .alert("Change Plan", isPresented: $showConfirmChange) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm") {
                if let tier = pendingTier {
                    changePlan(to: tier)
                }
            }
        } message: {
            if let tier = pendingTier {
                Text("Switch to \(tier.name) plan at \(tier.priceDisplay)?")
            }
        }
    }

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 8) {
            if let gym = gym {
                Text(gym.name)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            Text("Choose Your Plan")
                .font(.title2)
                .fontWeight(.bold)

            Text("Select the membership that fits your fitness journey")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Plan Cards Section

    @ViewBuilder
    private func planCardsSection(gym: Gym) -> some View {
        VStack(spacing: 16) {
            ForEach(gym.membershipTiers) { tier in
                PlanCard(
                    tier: tier,
                    isSelected: selectedTierId == tier.id,
                    isCurrent: currentTierId == tier.id,
                    onSelect: {
                        if tier.id != currentTierId {
                            pendingTier = tier
                            showConfirmChange = true
                        }
                    }
                )
            }
        }
    }

    // MARK: - No Gym Section

    @ViewBuilder
    private var noGymSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Gym Associated")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Contact your gym to get set up with a membership plan.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    // MARK: - Member Since Section

    @ViewBuilder
    private var memberSinceSection: some View {
        if let memberSince = user.memberProfile?.memberSince {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.secondary)
                Text("Member since \(memberSince.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Footer Section

    @ViewBuilder
    private var footerSection: some View {
        VStack(spacing: 8) {
            Text("Plan changes take effect immediately.")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Contact \(gym?.name ?? "your gym") for billing questions.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func changePlan(to tier: MembershipTier) {
        // Update local state
        selectedTierId = tier.id

        // Update user's subscription tier
        var updatedUser = user
        var profile = updatedUser.memberProfile ?? MemberProfile(
            fitnessGoal: .strength,
            experienceLevel: .intermediate,
            preferredSessionDuration: 60,
            membershipStatus: .active,
            memberSince: Date()
        )
        profile.subscriptionTierId = tier.id
        updatedUser.memberProfile = profile

        // Persist changes
        TestDataManager.shared.users[user.id] = updatedUser

        // v206: Sync to Firestore (fire-and-forget)
        Task {
            do {
                try await FirestoreUserRepository.shared.saveUser(updatedUser)
                Logger.log(.info, component: "BillingView", message: "☁️ Plan changed to: \(tier.name)")
            } catch {
                Logger.log(.warning, component: "BillingView", message: "⚠️ Firestore sync failed: \(error)")
            }
        }
    }
}

// MARK: - Plan Card

private struct PlanCard: View {
    let tier: MembershipTier
    let isSelected: Bool
    let isCurrent: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 16) {
                // Header row
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(tier.name)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)

                            if isCurrent {
                                CurrentPlanBadge()
                            }
                        }

                        Text(tier.priceDisplay)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Selection indicator
                    ZStack {
                        Circle()
                            .stroke(isSelected ? Color.blue : Color(.systemGray4), lineWidth: 2)
                            .frame(width: 24, height: 24)

                        if isSelected {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 14, height: 14)
                        }
                    }
                }

                // Benefits list
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tier.benefits, id: \.self) { benefit in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.green)
                                .frame(width: 16)

                            Text(benefit)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Current Plan Badge

private struct CurrentPlanBadge: View {
    var body: some View {
        Text("Current")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue)
            .clipShape(Capsule())
    }
}

#Preview {
    NavigationStack {
        BillingView(
            user: UnifiedUser(
                id: "bobby",
                firebaseUID: "test",
                authProvider: .email,
                name: "Bobby Tulsiani",
                birthdate: Date(),
                gender: .male,
                roles: [.member],
                gymId: "district_brooklyn",
                memberProfile: MemberProfile(
                    fitnessGoal: .strength,
                    experienceLevel: .intermediate,
                    preferredSessionDuration: 60,
                    subscriptionTierId: "core",
                    membershipStatus: .active,
                    memberSince: Date()
                )
            )
        )
    }
}
