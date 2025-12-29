//
// MuscleFocusListView.swift
// Medina
//
// v74.1: Extracted from SettingsModal.swift
// Created: December 1, 2025
//

import SwiftUI

/// Tri-state muscle focus list (neutral → emphasize → avoid → neutral)
struct MuscleFocusListView: View {
    @Binding var user: UnifiedUser

    enum MuscleState {
        case neutral, emphasize, avoid

        var next: MuscleState {
            switch self {
            case .neutral: return .emphasize
            case .emphasize: return .avoid
            case .avoid: return .neutral
            }
        }
    }

    // Use shared simplified muscle groups from MuscleGroup enum
    private var simplifiedMuscles: [(name: String, groups: Set<MuscleGroup>)] {
        MuscleGroup.simplifiedGroups
    }

    var body: some View {
        List {
            Section {
                ForEach(simplifiedMuscles, id: \.name) { muscle in
                    let state = getState(for: muscle.groups)
                    Button {
                        cycleState(for: muscle.groups, current: state)
                    } label: {
                        HStack {
                            Text(muscle.name)
                                .font(.system(size: 17))
                                .foregroundColor(.primary)

                            Spacer()

                            stateIcon(state)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tap to cycle: Neutral → Emphasize → Avoid")
                    Text(summaryText)
                        .fontWeight(.medium)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Muscle Focus")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryText: String {
        var emphasizedCount = 0
        var avoidedCount = 0

        for muscle in simplifiedMuscles {
            let state = getState(for: muscle.groups)
            if state == .emphasize { emphasizedCount += 1 }
            else if state == .avoid { avoidedCount += 1 }
        }

        if emphasizedCount == 0 && avoidedCount == 0 {
            return "Current: Balanced"
        }
        var parts: [String] = []
        if emphasizedCount > 0 { parts.append("\(emphasizedCount) focus") }
        if avoidedCount > 0 { parts.append("\(avoidedCount) avoid") }
        return "Current: \(parts.joined(separator: ", "))"
    }

    @ViewBuilder
    private func stateIcon(_ state: MuscleState) -> some View {
        switch state {
        case .neutral:
            EmptyView()
        case .emphasize:
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.green)
        case .avoid:
            Image(systemName: "minus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.red)
        }
    }

    private func getState(for groups: Set<MuscleGroup>) -> MuscleState {
        let emphasized = user.memberProfile?.emphasizedMuscleGroups ?? []
        let avoided = user.memberProfile?.excludedMuscleGroups ?? []

        if !groups.isDisjoint(with: emphasized) {
            return .emphasize
        } else if !groups.isDisjoint(with: avoided) {
            return .avoid
        }
        return .neutral
    }

    private func cycleState(for groups: Set<MuscleGroup>, current: MuscleState) {
        var profile = user.memberProfile ?? defaultProfile()
        var emphasized = profile.emphasizedMuscleGroups ?? []
        var avoided = profile.excludedMuscleGroups ?? []

        // Remove from both first
        emphasized.subtract(groups)
        avoided.subtract(groups)

        // Add to new state
        switch current.next {
        case .neutral:
            break // Already removed
        case .emphasize:
            emphasized.formUnion(groups)
        case .avoid:
            avoided.formUnion(groups)
        }

        profile.emphasizedMuscleGroups = emphasized.isEmpty ? nil : emphasized
        profile.excludedMuscleGroups = avoided.isEmpty ? nil : avoided
        user.memberProfile = profile

        // Persist to TestDataManager
        TestDataManager.shared.users[user.id] = user

        // v206: Sync to Firestore (fire-and-forget)
        Task {
            do {
                try await FirestoreUserRepository.shared.saveUser(user)
                Logger.log(.info, component: "MuscleFocusListView", message: "☁️ Muscle focus saved")
            } catch {
                Logger.log(.warning, component: "MuscleFocusListView", message: "⚠️ Firestore sync failed: \(error)")
            }
        }
    }

    private func defaultProfile() -> MemberProfile {
        MemberProfile(
            fitnessGoal: .strength,
            experienceLevel: .intermediate,
            preferredSessionDuration: 60,
            membershipStatus: .active,
            memberSince: Date()
        )
    }
}
