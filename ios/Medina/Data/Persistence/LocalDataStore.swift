//
// LocalDataStore.swift
// Medina
//
// v54.7: Made ObservableObject for reactive calendar updates
// v215: Renamed from LocalDataStore for clarity (this is production code)
// Last reviewed: December 2025
//

import Foundation
import SwiftUI
import Combine

class LocalDataStore: ObservableObject {
    static let shared = LocalDataStore()

    // Data Collections
    @Published var users: [String: UnifiedUser] = [:]
    @Published var exercises: [String: Exercise] = [:]
    @Published var protocolConfigs: [String: ProtocolConfig] = [:]
    @Published var plans: [String: Plan] = [:]
    @Published var programs: [String: Program] = [:]
    @Published var workouts: [String: Workout] = [:]
    @Published var targets: [String: ExerciseTarget] = [:]
    @Published var exerciseInstances: [String: ExerciseInstance] = [:]
    @Published var exerciseSets: [String: ExerciseSet] = [:]
    @Published var sessions: [String: Session] = [:]

    // B2B Collections
    @Published var gyms: [String: Gym] = [:]

    // v51.0: User Libraries
    @Published var libraries: [String: UserLibrary] = [:]  // userId -> UserLibrary

    // v81.0: User Exercise Preferences (AI-first selection)
    @Published var exercisePreferences: [String: UserExercisePreferences] = [:]  // userId -> preferences

    // v74.6: Imported Workout Data
    @Published var importedData: [String: [ImportedWorkoutData]] = [:]  // userId -> [imports]

    // v186: Removed class booking properties (deferred for beta)

    // v164: Removed legacy trainerMessages dictionary (superseded by messageThreads)

    // v93.1: Message Threads (two-way threaded messaging)
    // All threads indexed by thread ID
    @Published var messageThreads: [String: MessageThread] = [:]

    // Session State
    @Published var currentUserId: String?
    @Published var isDataLoaded = false

    // v54.7: Change tracker for triggering UI updates
    @Published var workoutsVersion: Int = 0

    private init() {}

    func reset() {
        users.removeAll()
        exercises.removeAll()
        protocolConfigs.removeAll()
        plans.removeAll()
        programs.removeAll()
        workouts.removeAll()
        targets.removeAll()
        exerciseInstances.removeAll()
        exerciseSets.removeAll()
        sessions.removeAll()
        gyms.removeAll()
        libraries.removeAll()
        exercisePreferences.removeAll()
        // v186: Removed class booking reset (deferred for beta)
        messageThreads.removeAll()
        isDataLoaded = false
        currentUserId = nil
    }

    /// Reset and reload all JSON data
    /// Use this in tests to start with a clean slate of base JSON data
    func resetAndReload() {
        reset()
        do {
            try LocalDataLoader.loadAll()
        } catch {
            print("FATAL: Failed to reload test data after reset: \(error)")
        }
    }

    // MARK: - Session Helpers

    /// Get the active session for a member (if any)
    func activeSession(for memberId: String) -> Session? {
        return sessions.values.first { session in
            session.memberId == memberId && session.status == .active
        }
    }

    // MARK: - Firebase User Management (v188)

    /// Get or create a user from Firebase credentials
    /// Used when user signs in with Apple/Google via Firebase Auth
    func getOrCreateUser(firebaseUID: String, email: String, displayName: String?) -> UnifiedUser {
        // Check if user already exists by firebaseUID
        if let existing = users.values.first(where: { $0.firebaseUID == firebaseUID }) {
            Logger.log(.info, component: "LocalDataStore", message: "Found existing user for Firebase UID: \(firebaseUID)")
            return existing
        }

        // Create new user with member role
        let userName = displayName ?? email.components(separatedBy: "@").first ?? "User"

        let newUser = UnifiedUser(
            id: firebaseUID,  // Use Firebase UID as user ID for consistency
            firebaseUID: firebaseUID,
            authProvider: .apple,  // Sign in with Apple
            email: email,
            name: userName,
            gender: .preferNotToSay,
            roles: [.member],
            gymId: "district_brooklyn",  // Default gym for now
            memberProfile: MemberProfile(
                fitnessGoal: .strength,
                experienceLevel: .intermediate,
                preferredSessionDuration: 60,
                membershipStatus: .active,
                memberSince: Date()
            )
        )

        // Add to users dictionary
        users[newUser.id] = newUser

        // v206: Save to Firestore only (removed legacy disk persistence)
        Task {
            do {
                try await FirestoreUserRepository.shared.saveUser(newUser)
                Logger.log(.info, component: "LocalDataStore", message: "Saved new user to Firestore")
            } catch {
                Logger.log(.warning, component: "LocalDataStore", message: "Failed to save user to Firestore: \(error)")
            }
        }

        Logger.log(.info, component: "LocalDataStore", message: "Created new user from Firebase: \(userName) (\(firebaseUID))")
        return newUser
    }

    // MARK: - Library Helpers (v2.0)

    /// Get user library (create if doesn't exist)
    func userLibrary(for userId: String) -> UserLibrary? {
        return libraries[userId]
    }

    // MARK: - Exercise Preferences (v81.0)

    /// Get user exercise preferences (migrate from library if needed)
    func userExercisePreferences(for userId: String) -> UserExercisePreferences {
        // Return existing preferences
        if let existing = exercisePreferences[userId] {
            return existing
        }

        // Migrate from UserLibrary if exists
        if let library = libraries[userId] {
            let migrated = UserExercisePreferences(migratingFrom: library)
            exercisePreferences[userId] = migrated
            return migrated
        }

        // Create fresh preferences
        let fresh = UserExercisePreferences(userId: userId)
        exercisePreferences[userId] = fresh
        return fresh
    }

    /// Update user exercise preferences
    func updateExercisePreferences(_ prefs: UserExercisePreferences) {
        exercisePreferences[prefs.id] = prefs
    }

    // v164: Removed legacy trainer message methods (messages(for:), addMessage(), etc.)
    // Use messageThreads and thread-based methods instead

    // MARK: - Message Threads (v93.1)

    /// Get all threads for a user (as participant)
    func threads(for userId: String) -> [MessageThread] {
        return messageThreads.values
            .filter { $0.participantIds.contains(userId) }
            .sorted()  // Most recent first (Comparable)
    }

    /// Get total unread count across all threads for a user
    func unreadThreadCount(for userId: String) -> Int {
        return threads(for: userId).reduce(0) { $0 + $1.unreadCount(for: userId) }
    }

    /// Get a specific thread by ID
    func thread(id: String) -> MessageThread? {
        return messageThreads[id]
    }

    /// Add or update a thread
    func saveThread(_ thread: MessageThread) {
        messageThreads[thread.id] = thread
    }

    /// Add a message to an existing thread
    func addMessageToThread(_ message: TrainerMessage) {
        guard var thread = messageThreads[message.threadId] else {
            // Create new thread from message
            let newThread = MessageThread.create(from: message)
            messageThreads[newThread.id] = newThread
            return
        }
        thread.addMessage(message)
        messageThreads[thread.id] = thread
    }

    /// Mark all messages in a thread as read for a user
    func markThreadAsRead(_ threadId: String, for userId: String) {
        guard var thread = messageThreads[threadId] else { return }
        thread.markAllAsRead(for: userId)
        messageThreads[threadId] = thread
    }

    /// Delete a thread
    func deleteThread(_ threadId: String) {
        messageThreads.removeValue(forKey: threadId)
    }
}
