//
// VoiceCoachingView.swift
// Medina
//
// v82.3: Voice coaching preferences with verbosity dial and announcement toggles
// v95.1: Simplified - removed granular toggles, verbosity now controls workout voice
// v106.2: Simplified further - removed verbosity dial, added brief announcements toggle
// Controls workout voice cues only (AI adapts to context automatically)
// Created: December 4, 2025
//

import SwiftUI

// MARK: - Voice Coaching View

struct VoiceCoachingView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var user: UnifiedUser

    @State private var voiceSettings: VoiceSettings

    init(user: Binding<UnifiedUser>) {
        self._user = user
        // Initialize from user's saved preference, or use defaults
        _voiceSettings = State(initialValue: user.wrappedValue.memberProfile?.voiceSettings ?? .default)
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Workout Audio Section
                Section {
                    Toggle("Voice Coaching", isOn: $voiceSettings.isEnabled)

                    if voiceSettings.isEnabled {
                        // v95.0: Voice Gender picker
                        HStack {
                            Text("Voice")
                            Spacer()
                            Picker("Voice", selection: $voiceSettings.voiceGender) {
                                ForEach(VoiceGender.allCases) { gender in
                                    Text(gender.displayName).tag(gender)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 150)
                        }

                        // v106.2: Simplified toggle replaces 5-level slider
                        Toggle("Brief Announcements", isOn: $voiceSettings.briefAnnouncements)
                    }
                } header: {
                    Text("WORKOUT AUDIO")
                } footer: {
                    if voiceSettings.isEnabled {
                        Text(voiceSettings.briefAnnouncements
                            ? "Short confirmations: \"Set 1. 5 at 150.\""
                            : "Full detail: \"Bench Press. Set 1 of 3. 5 reps at 150 pounds.\"")
                    } else {
                        Text("Voice coaching during workout execution. Confirms logged sets and announces next targets.")
                    }
                }
            }
            .navigationTitle("Workout Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveSettings()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Persistence

    private func saveSettings() {
        var profile = user.memberProfile ?? MemberProfile(
            fitnessGoal: .strength,
            experienceLevel: .intermediate,
            preferredSessionDuration: 60,
            membershipStatus: .active,
            memberSince: Date()
        )
        profile.voiceSettings = voiceSettings

        // v85.1: Create updated user copy to ensure consistent save
        var updatedUser = user
        updatedUser.memberProfile = profile

        // v85.1: Save to LocalDataStore FIRST (in-memory source of truth for AI)
        LocalDataStore.shared.users[user.id] = updatedUser
        Logger.log(.debug, component: "VoiceCoachingView",
                  message: "Saved to LocalDataStore: id=\(user.id), brief=\(voiceSettings.briefAnnouncements)")

        // Update binding (for UI consistency)
        user.memberProfile = profile

        // v206: Sync to Firestore (fire-and-forget)
        Task {
            do {
                try await FirestoreUserRepository.shared.saveUser(updatedUser)
                Logger.log(.info, component: "VoiceCoachingView", message: "☁️ Voice settings saved: brief=\(voiceSettings.briefAnnouncements), enabled=\(voiceSettings.isEnabled)")
            } catch {
                Logger.log(.warning, component: "VoiceCoachingView", message: "⚠️ Firestore sync failed: \(error)")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VoiceCoachingView(
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
                preferredSessionDuration: 60,
                voiceSettings: VoiceSettings.default,
                membershipStatus: .active,
                memberSince: Date()
            )
        ))
    )
}
