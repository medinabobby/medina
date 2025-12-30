//
// MedinaApp.swift
// Medina
//
// Last reviewed: October 2025
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

@main
struct MedinaApp: App {
    @State private var isCheckingSession = true
    @State private var autoLoginUserId: String?

    init() {
        // v188: Initialize Firebase for auth and backend services
        FirebaseApp.configure()
        Logger.log(.info, component: "MedinaApp", message: "Firebase initialized")

        // V11.3: Removed SemanticFrameRouter - using direct SemanticParser for CRAWL phase
        Logger.log(.info, component: "MedinaApp", message: "V11.3 Direct semantic parsing initialized")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isCheckingSession {
                    // v57.0: Show loading state while checking for saved session
                    ProgressView("Loading...")
                        .task {
                            await checkSession()
                        }
                } else if let userId = autoLoginUserId {
                    // v57.0: Auto-login successful - go directly to ChatView
                    if let user = LocalDataStore.shared.users[userId] {
                        ChatView(user: user)
                            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserLogout"))) { _ in
                                handleLogout()
                            }
                    } else {
                        LoginView()
                    }
                } else {
                    // v57.0: No saved session - show login
                    LoginView()
                }
            }
            // v209: Handle Google Sign-In URL callback
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }

    // v57.1: Handle logout by clearing session and resetting state
    // v188: Also sign out of Firebase Auth
    private func handleLogout() {
        Logger.log(.info, component: "MedinaApp", message: "Logout requested - clearing session")

        // v188: Sign out of Firebase Auth
        do {
            try FirebaseAuthService.shared.signOut()
        } catch {
            Logger.log(.error, component: "MedinaApp", message: "Firebase sign-out failed: \(error)")
        }

        // Reset state to show login
        autoLoginUserId = nil
        isCheckingSession = false
    }

    // v57.0: Check for saved session on app launch
    // v188: Check Firebase auth first, then fall back to local session
    @MainActor
    private func checkSession() async {
        // Load data first
        if !LocalDataStore.shared.isDataLoaded {
            do {
                try LocalDataLoader.loadAll()

                // Apply persisted deltas
                let manager = LocalDataStore.shared
                manager.workouts = DeltaStore.shared.applyWorkoutDeltas(to: manager.workouts)
                manager.exerciseSets = DeltaStore.shared.applySetDeltas(to: manager.exerciseSets)
                manager.exerciseInstances = DeltaStore.shared.applyInstanceDeltas(to: manager.exerciseInstances)

                Logger.log(.info, component: "MedinaApp", message: "Data loaded and deltas applied")

                // Validate data integrity in DEBUG builds
                #if DEBUG
                MinimalDataValidator.validateDataOrCrash()
                #endif
            } catch {
                Logger.log(.error, component: "MedinaApp", message: "Data loading failed", data: error)
                isCheckingSession = false
                return
            }
        }

        // v188: Check Firebase auth first (Sign in with Apple session persists)
        // Note: Use Auth.auth().currentUser directly - FirebaseAuthService.isSignedIn
        // is set asynchronously by a listener and may not be ready yet
        if let firebaseUser = Auth.auth().currentUser {
            Logger.log(.info, component: "MedinaApp", message: "Firebase auto-login: \(firebaseUser.uid)")

            // Get or create local user from Firebase credentials
            let user = LocalDataStore.shared.getOrCreateUser(
                firebaseUID: firebaseUser.uid,
                email: firebaseUser.email ?? "",
                displayName: firebaseUser.displayName
            )

            // Set current user
            LocalDataStore.shared.currentUserId = user.id

            // v196: Load all reference data from Firestore (protocols, gyms, exercises)
            await LocalDataLoader.loadReferenceDataFromFirestore()

            // v195: Load all user data from Firestore (cloud-only)
            await LocalDataLoader.loadUserDataFromFirestore(userId: user.id)

            // Auto-login
            autoLoginUserId = user.id
            isCheckingSession = false
            return
        }

        // v195: No local fallback - require Firebase auth for cloud-only
        Logger.log(.info, component: "MedinaApp", message: "No Firebase session - showing login")
        isCheckingSession = false
    }
}
