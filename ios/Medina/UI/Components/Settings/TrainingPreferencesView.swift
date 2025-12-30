//
// TrainingPreferencesView.swift
// Medina
//
// v58.2: Cleaned up - removed unused picker sub-views after SettingsModal redesign
// v79.2: Added TrainingPreferencesView for drill-down Settings navigation
// v80.2: Removed COACHING section (moved to UploadModal → COACHING section)
//

import SwiftUI

// MARK: - Training Preferences (Drill-Down from Settings)

/// v79.2: All training preferences in dedicated view (Anthropic-style settings drill-down)
struct TrainingPreferencesView: View {
    @Binding var user: UnifiedUser
    let onSave: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                goalsSection
                scheduleSection
                equipmentSection
                // v80.2: COACHING section removed - now in UploadModal → COACHING section
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Goals Section

    @ViewBuilder
    private var goalsSection: some View {
        SettingsSection(title: "GOALS") {
            // Fitness Goal
            SettingsMenuRow(title: "Fitness Goal", selection: user.memberProfile?.fitnessGoal.displayName ?? "Strength") {
                ForEach(FitnessGoal.allCases, id: \.self) { goal in
                    Button {
                        updateProfile { $0.fitnessGoal = goal }
                    } label: {
                        HStack {
                            Text(goal.displayName)
                            if user.memberProfile?.fitnessGoal == goal {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            SettingsDivider()

            // Muscle Focus
            NavigationLink {
                MuscleFocusListView(user: $user)
            } label: {
                SettingsNavigationRow(title: "Muscle Focus", value: muscleFocusSummary)
            }
        }
    }

    // MARK: - Schedule Section

    @ViewBuilder
    private var scheduleSection: some View {
        SettingsSection(title: "SCHEDULE") {
            // Experience Level
            SettingsMenuRow(title: "Experience Level", selection: user.memberProfile?.experienceLevel.displayName ?? "Intermediate") {
                ForEach(ExperienceLevel.allCases, id: \.self) { level in
                    Button {
                        updateProfile { $0.experienceLevel = level }
                    } label: {
                        HStack {
                            Text(level.displayName)
                            if user.memberProfile?.experienceLevel == level {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            SettingsDivider()

            // Schedule
            NavigationLink {
                SchedulePickerView(user: $user)
            } label: {
                SettingsNavigationRow(title: "Workout Days", value: "\(user.memberProfile?.preferredWorkoutDays?.count ?? 0) days/week")
            }

            SettingsDivider()

            // Split Type
            SettingsMenuRow(title: "Split Type", selection: user.memberProfile?.preferredSplitType?.displayName ?? "Auto") {
                Button {
                    updateProfile { $0.preferredSplitType = nil }
                } label: {
                    HStack {
                        Text("Auto")
                        if user.memberProfile?.preferredSplitType == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Divider()
                ForEach(SplitType.allCases, id: \.self) { split in
                    Button {
                        updateProfile { $0.preferredSplitType = split }
                    } label: {
                        HStack {
                            Text(split.displayName)
                            if user.memberProfile?.preferredSplitType == split {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            SettingsDivider()

            // Cardio Days
            SettingsMenuRow(title: "Cardio Days", selection: formatCardioDays(user.memberProfile?.preferredCardioDays)) {
                Button {
                    updateProfile { $0.preferredCardioDays = nil }
                } label: {
                    HStack {
                        Text("Auto")
                        if user.memberProfile?.preferredCardioDays == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Divider()
                ForEach(0..<8, id: \.self) { days in
                    Button {
                        updateProfile { $0.preferredCardioDays = days }
                    } label: {
                        HStack {
                            Text("\(days) per week")
                            if user.memberProfile?.preferredCardioDays == days {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            SettingsDivider()

            // Session Duration
            SettingsMenuRow(title: "Session Duration", selection: "\(user.memberProfile?.preferredSessionDuration ?? 60) min") {
                ForEach([30, 45, 60, 75, 90, 105, 120], id: \.self) { mins in
                    Button {
                        updateProfile { $0.preferredSessionDuration = mins }
                    } label: {
                        HStack {
                            Text("\(mins) minutes")
                            if user.memberProfile?.preferredSessionDuration == mins {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Equipment Section

    @ViewBuilder
    private var equipmentSection: some View {
        SettingsSection(title: "EQUIPMENT") {
            NavigationLink {
                HomeEquipmentListView(user: $user)
            } label: {
                SettingsNavigationRow(title: "Home Equipment", value: homeEquipmentSummary)
            }
        }
    }

    // v80.2: COACHING section removed - now in UploadModal → COACHING section

    // MARK: - Helpers

    private var homeEquipmentSummary: String {
        let count = user.memberProfile?.availableEquipment?.count ?? 0
        return count == 0 ? "None" : "\(count) items"
    }

    private var muscleFocusSummary: String {
        let emphasizedGroups = user.memberProfile?.emphasizedMuscleGroups ?? []
        let avoidedGroups = user.memberProfile?.excludedMuscleGroups ?? []

        var emphasizedCount = 0
        var avoidedCount = 0

        for muscle in MuscleGroup.simplifiedGroups {
            if !muscle.groups.isDisjoint(with: emphasizedGroups) {
                emphasizedCount += 1
            } else if !muscle.groups.isDisjoint(with: avoidedGroups) {
                avoidedCount += 1
            }
        }

        if emphasizedCount == 0 && avoidedCount == 0 { return "Balanced" }
        var parts: [String] = []
        if emphasizedCount > 0 { parts.append("\(emphasizedCount) focus") }
        if avoidedCount > 0 { parts.append("\(avoidedCount) avoid") }
        return parts.joined(separator: ", ")
    }

    private func formatCardioDays(_ days: Int?) -> String {
        guard let days = days else { return "Auto" }
        return "\(days) per week"
    }

    private func updateProfile(_ update: (inout MemberProfile) -> Void) {
        var profile = user.memberProfile ?? MemberProfile(
            fitnessGoal: .strength,
            experienceLevel: .intermediate,
            preferredSessionDuration: 60,
            membershipStatus: .active,
            memberSince: Date()
        )
        update(&profile)
        user.memberProfile = profile
        saveUser()
    }

    private func saveUser() {
        LocalDataStore.shared.users[user.id] = user

        // v206: Sync to Firestore (fire-and-forget)
        Task {
            do {
                try await FirestoreUserRepository.shared.saveUser(user)
            } catch {
                Logger.log(.warning, component: "TrainingPreferencesView", message: "⚠️ Firestore sync failed: \(error)")
            }
        }
        onSave()
    }
}

// MARK: - Schedule Picker (List with checkmarks)

struct SchedulePickerView: View {
    @Binding var user: UnifiedUser

    @State private var selectedDays: Set<DayOfWeek>

    init(user: Binding<UnifiedUser>) {
        self._user = user
        _selectedDays = State(initialValue: user.wrappedValue.memberProfile?.preferredWorkoutDays ?? [.monday, .tuesday, .thursday, .friday])
    }

    var body: some View {
        List {
            Section {
                ForEach(DayOfWeek.allCases, id: \.self) { day in
                    Button {
                        toggleDay(day)
                    } label: {
                        HStack {
                            Text(day.displayName)
                                .font(.system(size: 17))
                                .foregroundColor(.primary)

                            Spacer()

                            if selectedDays.contains(day) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("\(selectedDays.count) days selected")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            saveChanges()
        }
    }

    private func toggleDay(_ day: DayOfWeek) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }

    private func saveChanges() {
        var profile = user.memberProfile ?? MemberProfile(
            fitnessGoal: .strength,
            experienceLevel: .intermediate,
            preferredWorkoutDays: selectedDays,
            preferredSessionDuration: 60,
            membershipStatus: .active,
            memberSince: Date()
        )
        profile.preferredWorkoutDays = selectedDays
        user.memberProfile = profile

        // Persist to LocalDataStore
        LocalDataStore.shared.users[user.id] = user

        // v206: Sync to Firestore (fire-and-forget)
        Task {
            do {
                try await FirestoreUserRepository.shared.saveUser(user)
                Logger.log(.info, component: "SchedulePickerView", message: "☁️ Schedule saved: \(selectedDays.count) days")
            } catch {
                Logger.log(.warning, component: "SchedulePickerView", message: "⚠️ Firestore sync failed: \(error)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        SchedulePickerView(
            user: .constant(UnifiedUser(
                id: "test",
                firebaseUID: "test",
                authProvider: .email,
                name: "Bobby Tulsiani",
                birthdate: Date(),
                gender: .male,
                roles: [.member],
                memberProfile: MemberProfile(
                    fitnessGoal: .strength,
                    experienceLevel: .intermediate,
                    preferredWorkoutDays: [.monday, .wednesday, .friday],
                    preferredSessionDuration: 60,
                    membershipStatus: .active,
                    memberSince: Date()
                )
            ))
        )
    }
}
