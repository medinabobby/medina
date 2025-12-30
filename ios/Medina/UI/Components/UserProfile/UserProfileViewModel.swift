//
// UserProfileViewModel.swift
// Medina
//
// v93.7: Extracted state management from UserProfileView
// Manages edit state, form validation, and save operations
//

import SwiftUI

/// ViewModel managing user profile edit state and save operations
@MainActor
final class UserProfileViewModel: ObservableObject {

    // MARK: - Edit Form State

    @Published var fullName: String = ""
    @Published var phoneNumber: String = ""
    @Published var birthdate: Date = Date()
    @Published var birthdateIsSet: Bool = false
    @Published var gender: Gender = .preferNotToSay
    @Published var heightFeet: Int = 0
    @Published var heightInches: Int = 0
    @Published var currentWeight: String = ""
    @Published var showHeightPicker = false

    // MARK: - UI State

    @Published var showDeleteConfirmation = false
    @Published var isSaving = false

    // MARK: - User Context

    let userId: String
    let mode: ProfileViewMode

    init(userId: String, mode: ProfileViewMode) {
        self.userId = userId
        self.mode = mode
    }

    // MARK: - User Access

    var user: UnifiedUser? {
        LocalDataStore.shared.users[userId]
    }

    // MARK: - Computed Properties

    var calculatedAge: Int {
        Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year ?? 0
    }

    var totalHeightInches: Double {
        Double(heightFeet * 12 + heightInches)
    }

    var heightDisplayString: String {
        if heightFeet == 0 && heightInches == 0 {
            return "Not set"
        }
        return "\(heightFeet)'\(heightInches)\""
    }

    var hasChanges: Bool {
        guard let user = user else { return false }

        if fullName != user.name { return true }
        if phoneNumber != (user.phoneNumber ?? "") { return true }
        if gender != user.gender { return true }

        let profile = user.memberProfile
        if totalHeightInches != (profile?.height ?? 0) { return true }
        if Double(currentWeight) != profile?.currentWeight { return true }

        let userHasBirthdate = user.birthdate != nil
        if birthdateIsSet != userHasBirthdate { return true }
        if birthdateIsSet, let existingBirthdate = user.birthdate, birthdate != existingBirthdate { return true }

        return false
    }

    // MARK: - Initialization

    func initializeEditState() {
        guard let user = user else { return }

        fullName = user.name
        phoneNumber = user.phoneNumber ?? ""
        gender = user.gender

        if let existingBirthdate = user.birthdate {
            birthdate = existingBirthdate
            birthdateIsSet = true
        } else {
            birthdate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
            birthdateIsSet = false
        }

        let profile = user.memberProfile
        let totalInches = Int(profile?.height ?? 0)
        heightFeet = totalInches / 12
        heightInches = totalInches % 12
        currentWeight = profile?.currentWeight.map { String(Int($0)) } ?? ""
    }

    // MARK: - Save Operations

    func saveProfile(onSave: ((UnifiedUser) -> Void)?, onComplete: @escaping () -> Void) {
        guard hasChanges, var updatedUser = user else { return }
        isSaving = true

        updatedUser.name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedUser.phoneNumber = trimmedPhone.isEmpty ? nil : trimmedPhone

        updatedUser.birthdate = birthdateIsSet ? birthdate : nil
        updatedUser.gender = gender

        var profile = updatedUser.memberProfile ?? MemberProfile(
            fitnessGoal: .strength,
            experienceLevel: .intermediate,
            preferredSessionDuration: 60,
            membershipStatus: .active,
            memberSince: Date()
        )

        profile.height = totalHeightInches > 0 ? totalHeightInches : nil
        profile.currentWeight = Double(currentWeight)

        updatedUser.memberProfile = profile
        LocalDataStore.shared.users[userId] = updatedUser

        // v206: Sync to Firestore (fire-and-forget)
        Task {
            do {
                try await FirestoreUserRepository.shared.saveUser(updatedUser)
                Logger.log(.info, component: "UserProfileView", message: "☁️ Profile synced to Firestore")
            } catch {
                Logger.log(.warning, component: "UserProfileView", message: "⚠️ Firestore sync failed: \(error)")
            }
        }

        isSaving = false
        onSave?(updatedUser)
        onComplete()
    }

    // MARK: - Navigation Title

    func navigationTitle() -> String {
        guard let user = user else { return "Profile" }

        if mode == .edit {
            return "Profile"
        }
        if user.hasRole(.trainer) {
            return "Trainer"
        }
        return "Member"
    }
}
