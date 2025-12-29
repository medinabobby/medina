//
// UnifiedUser.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

// MARK: - Unified User Model

/// V15.0 Unified User model supporting multiple roles and optional profiles
/// Replaces separate Member and Trainer models with consolidated approach
struct UnifiedUser: Identifiable, Codable {

    // MARK: - Identity & Authentication

    /// Unique identifier for the user
    let id: String

    /// Firebase authentication UID
    let firebaseUID: String

    /// Authentication provider (Google, Apple, email, etc.)
    let authProvider: AuthProvider

    // MARK: - Contact Information

    /// User's email address
    var email: String?

    /// User's phone number
    var phoneNumber: String?

    // MARK: - Profile Information

    /// User's display name
    var name: String

    /// Profile photo URL from OAuth provider
    var photoURL: String?

    /// Provider-specific user ID
    var providerUID: String?

    /// Whether email has been verified
    var emailVerified: Bool?

    /// User's birthdate for age calculation
    /// v65.2: Optional - nil means unknown (don't send default to AI)
    var birthdate: Date?

    /// User's gender
    var gender: Gender

    // MARK: - Role System

    /// User's roles within the system (can have multiple)
    var roles: [UserRole]

    /// Primary gym association
    var gymId: String?

    // MARK: - Authentication (Beta)

    /// Beta authentication: plain text password (temporary)
    /// Post-beta: will be migrated to bcrypt hash + cloud auth
    var passwordHash: String?

    // MARK: - Role-Specific Profiles

    /// Member-specific data (present if user has member role)
    var memberProfile: MemberProfile?

    /// Trainer-specific data (present if user has trainer role)
    var trainerProfile: TrainerProfile?

    // MARK: - Computed Properties

    /// Check if user has specific role
    func hasRole(_ role: UserRole) -> Bool {
        return roles.contains(role)
    }

    /// Get primary role (first role in array)
    var primaryRole: UserRole? {
        return roles.first
    }

    /// Check if user is admin (has admin or gymOwner role)
    var isAdmin: Bool {
        return hasRole(.admin) || hasRole(.gymOwner)
    }

    /// Check if user is trainer
    var isTrainer: Bool {
        return hasRole(.trainer)
    }

    /// Check if user is member
    var isMember: Bool {
        return hasRole(.member)
    }
}

// MARK: - Member Profile

/// Member-specific data separated from core user identity
struct MemberProfile: Codable {

    // MARK: - Physical Info

    /// User's height in inches
    var height: Double?

    // MARK: - Weight Management

    /// Current weight in pounds
    var currentWeight: Double?

    /// Target goal weight in pounds
    var goalWeight: Double?

    /// Target date for reaching goal weight
    var goalDate: Date?

    /// Starting weight when beginning program
    var startingWeight: Double?

    // MARK: - Personal Motivation

    /// User's personal motivation / "Your Why" for training
    /// Used by AI to personalize coaching and plan generation
    var personalMotivation: String?

    // MARK: - Fitness Preferences

    /// Primary fitness goal
    var fitnessGoal: FitnessGoal

    /// Experience level with training
    var experienceLevel: ExperienceLevel

    /// Preferred workout days of the week
    var preferredWorkoutDays: Set<DayOfWeek>?

    /// Preferred session duration in minutes
    var preferredSessionDuration: Int

    /// v66: Preferred split type (nil = let AI recommend based on days/experience/goal)
    var preferredSplitType: SplitType?

    /// v66: Preferred cardio days per week (nil = goal-based: fatLoss/endurance=2, else=0)
    var preferredCardioDays: Int?

    /// Muscle groups to emphasize in training
    var emphasizedMuscleGroups: Set<MuscleGroup>?

    /// Muscle groups to exclude from training
    var excludedMuscleGroups: Set<MuscleGroup>?

    // MARK: - Training Context

    /// Where member prefers to train
    var trainingLocation: TrainingLocation?

    /// Equipment available to member
    var availableEquipment: Set<Equipment>?

    // MARK: - Exercise Constraints

    /// Maximum target exercises for customization
    var maxTargetExercises: Set<String>?

    /// v51.0: Exercises excluded from library selection (injuries, preferences)
    /// Respected during plan creation via LibraryExerciseSelector
    var excludedExerciseIds: Set<String>?

    // MARK: - Coaching Preferences

    /// Voice coaching preferences (v47)
    /// - Migration: Nil voiceSettings → VoiceSettings.default
    var voiceSettings: VoiceSettings?

    // v182: trainingStyle removed - feature removed for beta simplicity

    // MARK: - Relationships

    /// Assigned trainer ID
    var trainerId: String?

    // MARK: - Subscription

    /// v80.2: Gym membership tier ID (e.g., "core", "core_plus", "ultimate")
    /// Links to gym.membershipTiers[].id for pricing and features
    /// nil = not yet selected (show plan picker)
    var subscriptionTierId: String?

    // MARK: - Status

    /// Current membership status
    var membershipStatus: MembershipStatus

    /// Date when member joined
    var memberSince: Date
}

// MARK: - Trainer Profile

/// Trainer-specific data separated from core user identity
struct TrainerProfile: Codable {

    // MARK: - Professional Info

    /// Trainer's professional bio
    var bio: String

    /// Areas of specialization
    var specialties: [TrainerSpecialty]

    // MARK: - Experience & Certifications

    /// Years of training experience
    var yearsExperience: Int?

    /// Professional certifications
    var certifications: [String]?

    // MARK: - Rates & Availability

    /// Hourly training rate
    var hourlyRate: Double?

    /// Available training times
    var availability: [String]?
}

// MARK: - User Extensions

extension UnifiedUser {

    /// Calculate user's age from birthdate
    /// v65.2: Returns nil if birthdate unknown
    var age: Int? {
        guard let birthdate = birthdate else { return nil }
        let now = Date()
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: birthdate, to: now)
        return ageComponents.year
    }

    /// Get display name for UI
    var displayName: String {
        return name.isEmpty ? "Unknown User" : name
    }

    /// Get first name from full name
    /// Example: "Bobby Tulsiani" → "Bobby"
    var firstName: String {
        let components = name.components(separatedBy: " ")
        return components.first ?? name
    }

    /// Check if user has complete profile information
    var hasCompleteProfile: Bool {
        return !name.isEmpty && email != nil
    }

    /// Get formatted contact info
    var contactInfo: String {
        var info: [String] = []
        if let email = email { info.append(email) }
        if let phone = phoneNumber { info.append(phone) }
        return info.joined(separator: " • ")
    }

    /// Get role descriptions for display
    var roleDescriptions: String {
        return roles.map { $0.displayName }.joined(separator: ", ")
    }

    /// Get highest permission level from all roles
    var maxPermissions: Set<QueryPermission> {
        return roles.reduce(Set<QueryPermission>()) { result, role in
            result.union(role.permissions)
        }
    }
}

// MARK: - Onboarding Detection

extension UnifiedUser {

    /// Check if user has completed core onboarding fields
    /// v65.2: Required: name, schedule, height, and valid birthdate
    /// (goal/experience have defaults, weight is optional/personal)
    var hasCompletedOnboarding: Bool {
        // Name must be set and not default
        guard !name.isEmpty, name != "Unknown User" else {
            return false
        }

        // Must have member profile
        guard let profile = memberProfile else {
            return false
        }

        // Schedule must be selected (goal and experience always have defaults)
        let hasSchedule = !(profile.preferredWorkoutDays?.isEmpty ?? true)

        // v65.2: Height is required (influences exercise selection)
        let hasHeight = profile.height != nil && profile.height! > 0

        // v65.2: Birthdate must be set (not nil) and in reasonable range
        guard let birthdate = birthdate else { return false }
        let calendar = Calendar.current
        let ageYears = calendar.dateComponents([.year], from: birthdate, to: Date()).year ?? 0
        let hasBirthdate = ageYears >= 13 && ageYears <= 100  // Reasonable age range

        return hasSchedule && hasHeight && hasBirthdate
    }

    /// List of missing onboarding fields for AI prompts
    var missingOnboardingFields: [String] {
        var missing: [String] = []

        if name.isEmpty || name == "Unknown User" {
            missing.append("name")
        }

        if memberProfile?.preferredWorkoutDays?.isEmpty ?? true {
            missing.append("workout schedule")
        }

        // v65.2: Check height
        if memberProfile?.height == nil || memberProfile?.height == 0 {
            missing.append("height")
        }

        // v65.2: Check birthdate - nil means not set
        if let birthdate = birthdate {
            let calendar = Calendar.current
            let ageYears = calendar.dateComponents([.year], from: birthdate, to: Date()).year ?? 0
            if ageYears < 13 || ageYears > 100 {
                missing.append("birthdate")
            }
        } else {
            missing.append("birthdate")
        }

        return missing
    }
}

// MARK: - Migration Helpers

