//
// HomeEquipmentListView.swift
// Medina
//
// v74.1: Extracted from SettingsModal.swift
// Created: December 1, 2025
//

import SwiftUI

/// Home equipment list with checkmarks
struct HomeEquipmentListView: View {
    @Binding var user: UnifiedUser

    private let homeEquipment: [Equipment] = [
        .dumbbells, .kettlebell, .resistanceBand, .bodyweight,
        .pullupBar, .bench, .trx, .barbell
    ]

    var body: some View {
        List {
            Section {
                ForEach(homeEquipment, id: \.self) { item in
                    let isSelected = user.memberProfile?.availableEquipment?.contains(item) ?? false
                    Button {
                        toggleEquipment(item)
                    } label: {
                        HStack {
                            Text(item.displayName)
                                .font(.system(size: 17))
                                .foregroundColor(.primary)

                            Spacer()

                            if isSelected {
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
                Text("Select equipment you have at home")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Home Equipment")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggleEquipment(_ item: Equipment) {
        var profile = user.memberProfile ?? defaultProfile()
        var equipment = profile.availableEquipment ?? []

        if equipment.contains(item) {
            equipment.remove(item)
        } else {
            equipment.insert(item)
        }

        profile.availableEquipment = equipment.isEmpty ? nil : equipment
        user.memberProfile = profile

        // Persist to TestDataManager
        TestDataManager.shared.users[user.id] = user

        // v206: Sync to Firestore (fire-and-forget)
        Task {
            do {
                try await FirestoreUserRepository.shared.saveUser(user)
                Logger.log(.info, component: "HomeEquipmentListView", message: "☁️ Equipment saved: \(equipment.count) items")
            } catch {
                Logger.log(.warning, component: "HomeEquipmentListView", message: "⚠️ Firestore sync failed: \(error)")
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
