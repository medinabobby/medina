//
// UserProfileMemberSections.swift
// Medina
//
// v93.7: Member-specific content sections for UserProfileView
// Training preferences, active plan, recent workouts, stats, edit fields
//

import SwiftUI

// MARK: - Member Profile Header

struct MemberProfileHeader: View {
    let user: UnifiedUser
    let mode: ProfileViewMode

    private func statusColor(for status: MembershipStatus) -> Color {
        switch status {
        case .active: return .green
        case .pending: return .yellow
        case .expired, .cancelled: return .red
        case .suspended: return .orange
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Smaller avatar - 48px in edit mode, 80px in view mode
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: mode == .edit ? 48 : 80, height: mode == .edit ? 48 : 80)

                Text(user.firstName.prefix(1).uppercased())
                    .font(.system(size: mode == .edit ? 20 : 32, weight: .semibold))
                    .foregroundColor(.blue)
            }

            // Name
            Text(user.name)
                .font(mode == .edit ? .headline : .title2)
                .fontWeight(.semibold)

            // Only show status and member since in view mode
            if mode == .view {
                // Membership status
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(for: user.memberProfile?.membershipStatus ?? .active))
                        .frame(width: 8, height: 8)

                    Text(user.memberProfile?.membershipStatus.displayName ?? "Active")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Member since
                if let memberSince = user.memberProfile?.memberSince {
                    Text("Member since \(memberSince.formatted(.dateTime.month().year()))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(mode == .edit ? 16 : 24)
        // Only show card background in view mode
        .background(mode == .view ? Color(.systemBackground) : Color.clear)
        .cornerRadius(mode == .view ? 16 : 0)
    }
}

// MARK: - Training Preferences Section

struct MemberTrainingPreferencesSection: View {
    let user: UnifiedUser

    var body: some View {
        ProfileSection(title: "Training Preferences", icon: "dumbbell.fill") {
            if let profile = user.memberProfile {
                VStack(spacing: 12) {
                    ProfilePreferenceRow(label: "Goal", value: profile.fitnessGoal.displayName, icon: "target")
                    ProfilePreferenceRow(label: "Experience", value: profile.experienceLevel.displayName, icon: "chart.bar.fill")
                    ProfilePreferenceRow(label: "Duration", value: "\(profile.preferredSessionDuration) min", icon: "clock")

                    if let days = profile.preferredWorkoutDays, !days.isEmpty {
                        ProfilePreferenceRow(
                            label: "Schedule",
                            value: days.sorted { $0.rawValue < $1.rawValue }.map { $0.shortName }.joined(separator: ", "),
                            icon: "calendar"
                        )
                    }

                    if let location = profile.trainingLocation {
                        ProfilePreferenceRow(label: "Location", value: location.displayName, icon: "location.fill")
                    }
                }
            } else {
                Text("No training preferences set")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Active Plan Section

struct MemberActivePlanSection: View {
    let userId: String
    let userFirstName: String
    let coordinator: NavigationCoordinator

    private var activePlan: Plan? {
        PlanResolver.activePlan(for: userId)
    }

    var body: some View {
        ProfileSection(title: "Active Plan", icon: activePlan != nil ? "list.clipboard.fill" : "list.clipboard") {
            if let plan = activePlan {
                Button(action: {
                    coordinator.navigateToPlan(id: plan.id)
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)

                            Text("\(plan.weightliftingDays)x/week • \(plan.splitType.displayName)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if let endDate = plan.endDate as Date? {
                                Text("Ends \(endDate.formatted(.dateTime.month().day()))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 12) {
                    Text("No active plan")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button(action: {
                        // TODO: Navigate to chat with pre-filled member context
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Create Plan for \(userFirstName)")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
        }
    }
}

// MARK: - Recent Workouts Section

struct MemberRecentWorkoutsSection: View {
    let userId: String
    let coordinator: NavigationCoordinator

    private var recentWorkouts: [Workout] {
        WorkoutResolver.workouts(
            for: userId,
            temporal: .past,
            status: .completed,
            modality: .unspecified,
            splitDay: nil,
            source: nil,
            plan: nil,
            program: nil,
            dateInterval: nil
        ).prefix(5).map { $0 }
    }

    var body: some View {
        ProfileSection(title: "Recent Workouts", icon: "figure.strengthtraining.traditional") {
            if recentWorkouts.isEmpty {
                Text("No completed workouts yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    ForEach(recentWorkouts) { workout in
                        MemberWorkoutRow(workout: workout, coordinator: coordinator)
                    }
                }
            }
        }
    }
}

// MARK: - Workout Row

struct MemberWorkoutRow: View {
    let workout: Workout
    let coordinator: NavigationCoordinator

    var body: some View {
        Button(action: {
            coordinator.navigateToWorkout(id: workout.id)
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.splitDay?.displayName ?? workout.type.displayName)
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    if let date = workout.completedDate ?? workout.scheduledDate {
                        Text(date.formatted(.dateTime.month().day()))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if workout.status == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stats Section

struct MemberStatsSection: View {
    let userId: String

    private var completedCount: Int {
        WorkoutResolver.workouts(
            for: userId,
            temporal: .past,
            status: .completed,
            modality: .unspecified,
            splitDay: nil,
            source: nil,
            plan: nil,
            program: nil,
            dateInterval: nil
        ).count
    }

    private var planCount: Int {
        PlanResolver.allPlans(for: userId).count
    }

    var body: some View {
        ProfileSection(title: "Quick Stats", icon: "chart.bar.fill") {
            HStack(spacing: 16) {
                ProfileStatCard(value: "\(completedCount)", label: "Workouts", icon: "dumbbell.fill")
                ProfileStatCard(value: "\(planCount)", label: "Plans", icon: "list.clipboard")
            }
        }
    }
}

// MARK: - Editable Profile Fields

struct MemberEditableFields: View {
    let user: UnifiedUser
    @ObservedObject var viewModel: UserProfileViewModel

    var body: some View {
        // Basic Info Card
        ProfileCard {
            ProfileEditRow(label: "Name", value: $viewModel.fullName)
            ProfileDivider()

            if let email = user.email {
                HStack {
                    Text("Email")
                        .font(.system(size: 17))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(email)
                        .font(.system(size: 17))
                        .foregroundColor(Color("SecondaryText"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                ProfileDivider()
            }

            ProfileEditRow(label: "Phone", value: $viewModel.phoneNumber, keyboardType: .phonePad, placeholder: "Optional")
            ProfileDivider()

            ProfilePickerRow(label: "Age", value: viewModel.birthdateIsSet ? "\(viewModel.calculatedAge) years" : "Not set") {
                DatePicker("", selection: $viewModel.birthdate, displayedComponents: .date)
                    .labelsHidden()
                    .onChange(of: viewModel.birthdate) { _ in
                        viewModel.birthdateIsSet = true
                    }
            }
            ProfileDivider()

            ProfileMenuRow(label: "Gender", selection: viewModel.gender.displayName) {
                ForEach(Gender.allCases, id: \.self) { g in
                    Button(g.displayName) { viewModel.gender = g }
                }
            }
        }

        // Physical Stats Card
        ProfileCard {
            Button(action: { viewModel.showHeightPicker.toggle() }) {
                HStack {
                    Text("Height")
                        .font(.system(size: 17))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(viewModel.heightDisplayString)
                        .font(.system(size: 17))
                        .foregroundColor(Color("SecondaryText"))
                    Image(systemName: viewModel.showHeightPicker ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(Color("SecondaryText").opacity(0.6))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            if viewModel.showHeightPicker {
                HStack(spacing: 0) {
                    Picker("Feet", selection: $viewModel.heightFeet) {
                        ForEach(4...7, id: \.self) { ft in
                            Text("\(ft) ft").tag(ft)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)

                    Picker("Inches", selection: $viewModel.heightInches) {
                        ForEach(0...11, id: \.self) { inch in
                            Text("\(inch) in").tag(inch)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                }
                .padding(.horizontal, 8)
            }

            ProfileDivider()
            ProfileEditRow(label: "Weight", value: $viewModel.currentWeight, suffix: "lbs", keyboardType: .numberPad, placeholder: "Optional")
        }
    }
}

// MARK: - Edit Mode Footer

struct MemberEditModeFooter: View {
    @ObservedObject var viewModel: UserProfileViewModel
    let onSave: ((UnifiedUser) -> Void)?
    let onDeleteAccount: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        // Save Button
        Button(action: {
            viewModel.saveProfile(onSave: onSave, onComplete: onDismiss)
        }) {
            HStack {
                Spacer()
                if viewModel.isSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Save Changes")
                        .font(.system(size: 17, weight: .semibold))
                }
                Spacer()
            }
            .padding(.vertical, 14)
            .background(viewModel.hasChanges ? Color.blue : Color.gray.opacity(0.3))
            .foregroundColor(viewModel.hasChanges ? .white : .gray)
            .cornerRadius(12)
        }
        .disabled(!viewModel.hasChanges || viewModel.isSaving)

        // Delete Account
        Button(action: { viewModel.showDeleteConfirmation = true }) {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                Text("Delete Account")
            }
            .font(.system(size: 15))
            .foregroundColor(.red)
        }
        .padding(.top, 8)
    }
}
