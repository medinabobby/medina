//
// OnboardingState.swift
// Medina
//
// Track onboarding state and reminder timing for new users
// v65.2: Keys are now user-specific to prevent state leakage between accounts

import Foundation

/// Manages onboarding flow state using UserDefaults
/// Tracks whether user has dismissed onboarding and when to show reminders
enum OnboardingState {

    // MARK: - Keys

    private static let reminderIntervalDays = 3

    /// Generate user-specific key for dismissed state
    private static func dismissedKey(for userId: String) -> String {
        "medina.onboarding.dismissed.\(userId)"
    }

    /// Generate user-specific key for last reminder
    private static func reminderKey(for userId: String) -> String {
        "medina.onboarding.lastReminder.\(userId)"
    }

    // MARK: - State Properties

    /// User has explicitly dismissed onboarding (clicked "Skip for now")
    static func wasDismissed(for userId: String) -> Bool {
        UserDefaults.standard.bool(forKey: dismissedKey(for: userId))
    }

    /// Set dismissed state for specific user
    static func setDismissed(_ value: Bool, for userId: String) {
        UserDefaults.standard.set(value, forKey: dismissedKey(for: userId))
    }

    /// Should show reminder (dismissed but enough time passed)
    static func shouldShowReminder(for userId: String) -> Bool {
        guard wasDismissed(for: userId) else { return false }

        let lastReminder = UserDefaults.standard.object(forKey: reminderKey(for: userId)) as? Date ?? .distantPast
        let daysSince = Calendar.current.dateComponents([.day], from: lastReminder, to: Date()).day ?? 0

        return daysSince >= reminderIntervalDays
    }

    // MARK: - Actions

    /// Mark reminder as shown (resets the reminder timer)
    static func markReminderShown(for userId: String) {
        UserDefaults.standard.set(Date(), forKey: reminderKey(for: userId))
    }

    /// Reset onboarding state for specific user (for testing via /reset-deltas)
    static func reset(for userId: String) {
        UserDefaults.standard.removeObject(forKey: dismissedKey(for: userId))
        UserDefaults.standard.removeObject(forKey: reminderKey(for: userId))
    }
}
