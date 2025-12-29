//
// LoginView.swift
// Medina
//
// Last reviewed: October 2025
//

import SwiftUI
import AuthenticationServices
import GoogleSignIn
import FirebaseAuth

struct LoginView: View {
    // v57.0: Username/password authentication
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var showPassword: Bool = false
    @State private var stayLoggedIn: Bool = true
    @State private var loginError: String?
    @State private var showChat = false
    @State private var showResetConfirmation = false
    @State private var resetMessage: String?


    // v47: Sign-up flow state
    @State private var showSignUpSheet = false
    @State private var signUpEmail: String = ""
    @State private var signUpPassword: String = ""
    @State private var signUpName: String = ""
    @State private var signUpError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                // v57.2: App-consistent background color
                Color("BackgroundPrimary")
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Centered app icon and branding
                    VStack(spacing: 16) {
                        Image("LoginIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)

                        Text("DISTRICT")
                            .font(.system(size: 48, weight: .heavy, design: .default))
                            .tracking(3)
                            .fontWeight(.black)
                            .foregroundColor(Color("PrimaryText"))
                    }
                    .padding(.bottom, 60)

                    // v57.2: Login form with refined styling
                    VStack(spacing: 20) {
                        // Username field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username or Email")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(Color("SecondaryText"))

                            TextField("Email or username", text: $username)
                                .textContentType(.username)
                                .autocapitalization(.none)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color("BackgroundSecondary"))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color("SecondaryText").opacity(0.2), lineWidth: 1)
                                )
                                .submitLabel(.next)
                                .onChange(of: username) { _ in
                                    // Force state update for AutoFill compatibility
                                }
                        }

                        // Password field with show/hide toggle
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(Color("SecondaryText"))

                            HStack(spacing: 0) {
                                Group {
                                    if showPassword {
                                        TextField("Password", text: $password)
                                            .textContentType(.password)
                                    } else {
                                        SecureField("Password", text: $password)
                                            .textContentType(.password)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .submitLabel(.go)
                                .onSubmit { login() }
                                .onChange(of: password) { _ in
                                    // Force state update for AutoFill compatibility
                                }

                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(Color("SecondaryText"))
                                        .frame(width: 44, height: 44)
                                }
                                .padding(.trailing, 4)
                            }
                            .background(Color("BackgroundSecondary"))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color("SecondaryText").opacity(0.2), lineWidth: 1)
                            )
                        }

                        // Stay logged in toggle
                        HStack {
                            Text("Stay logged in")
                                .font(.subheadline)
                                .foregroundColor(Color("PrimaryText"))
                            Spacer()
                            Toggle("", isOn: $stayLoggedIn)
                                .labelsHidden()
                        }
                        .padding(.top, 4)

                        // Error message
                        if let loginError {
                            Text(loginError)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.top, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 32)

                    // Login button
                    Button(action: login) {
                        Text("Continue")
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(username.isEmpty || password.isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                            .foregroundColor(username.isEmpty || password.isEmpty ? Color("SecondaryText") : .white)
                            .cornerRadius(12)
                    }
                    .disabled(username.isEmpty || password.isEmpty)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)

                    // Sign-up button
                    Button(action: { showSignUpSheet = true }) {
                        Text("New user? Sign up")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                    }
                    .padding(.top, 16)

                    // v188: Sign in with Apple (Firebase Auth)
                    SignInWithAppleButton(.signIn) { request in
                        let appleRequest = FirebaseAuthService.shared.createAppleIDRequest()
                        request.requestedScopes = appleRequest.requestedScopes
                        request.nonce = appleRequest.nonce
                    } onCompletion: { result in
                        Task {
                            await handleAppleSignIn(result: result)
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(12)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)

                    // v209: Sign in with Google (Firebase Auth)
                    Button {
                        Task {
                            await handleGoogleSignIn()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            // Google "G" logo - using text as fallback
                            // For production: add GoogleLogo.png to Assets.xcassets
                            Text("G")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.blue)
                            Text("Sign in with Google")
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)

                    if let resetMessage {
                        Text(resetMessage)
                            .font(.footnote)
                            .foregroundColor(.green)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                    }

                    Spacer()

                    // v57.3: Beta testing utilities
                    VStack(spacing: 8) {
                        Button(action: { showResetConfirmation = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.caption)
                                Text("Reset Workout Progress")
                                    .font(.caption)
                            }
                            .foregroundColor(Color("SecondaryText"))
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
            // v48.2: Changed from .navigationDestination to .fullScreenCover
            // This prevents back button from appearing in ChatView (was pushing ChatView onto LoginView's stack)
            // Now ChatView is presented as modal root, not pushed view
            .fullScreenCover(isPresented: $showChat) {
                // v57.0: Use currentUserId after login
                if let userId = TestDataManager.shared.currentUserId,
                   let user = TestDataManager.shared.users[userId] {
                    ChatView(user: user)
                }
            }
            .alert("Reset Workout Progress?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    resetWorkoutProgress()
                }
            } message: {
                Text("This will clear all workout completion status and set results. Your plans will remain, but all workouts will show as 'not started'. Useful for re-testing a training week.")
            }
            .task {
                await loadDataIfNeeded()
            }
            .sheet(isPresented: $showSignUpSheet) {
                signUpSheet
            }
        }
    }

    // v47: Sign-up sheet view
    // v57.2: Updated to match app design aesthetic
    private var signUpSheet: some View {
        NavigationStack {
            ZStack {
                Color("BackgroundPrimary")
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Account Details Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("ACCOUNT DETAILS")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(Color("SecondaryText"))
                                .padding(.horizontal, 20)

                            VStack(spacing: 0) {
                                // Email field
                                VStack(alignment: .leading, spacing: 0) {
                                    TextField("Email", text: $signUpEmail)
                                        .textContentType(.emailAddress)
                                        .autocapitalization(.none)
                                        .keyboardType(.emailAddress)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 16)
                                        .background(Color("BackgroundSecondary"))
                                }

                                Divider()
                                    .padding(.leading, 20)

                                // Password field
                                VStack(alignment: .leading, spacing: 0) {
                                    SecureField("Password", text: $signUpPassword)
                                        .textContentType(.newPassword)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 16)
                                        .background(Color("BackgroundSecondary"))
                                }
                            }
                            .background(Color("BackgroundSecondary"))
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                        }

                        // Profile Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("PROFILE")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(Color("SecondaryText"))
                                .padding(.horizontal, 20)

                            VStack(spacing: 0) {
                                TextField("Display Name", text: $signUpName)
                                    .textContentType(.name)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                    .background(Color("BackgroundSecondary"))
                            }
                            .background(Color("BackgroundSecondary"))
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                        }

                        // Create Account Button
                        Button(action: signUp) {
                            Text("Create Account")
                                .font(.body)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(signUpEmail.isEmpty || signUpPassword.isEmpty || signUpName.isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                                .foregroundColor(signUpEmail.isEmpty || signUpPassword.isEmpty || signUpName.isEmpty ? Color("SecondaryText") : .white)
                                .cornerRadius(12)
                        }
                        .disabled(signUpEmail.isEmpty || signUpPassword.isEmpty || signUpName.isEmpty)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .padding(.top, 24)
                }
            }
            .navigationTitle("Sign Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showSignUpSheet = false
                        signUpEmail = ""
                        signUpPassword = ""
                        signUpName = ""
                    }
                }
            }
        }
    }

    // v57.0: Removed filteredUsers and userSummary - no longer using picker

    private func login() {
        loginError = nil

        // v57.0: Authenticate with username/password
        guard let user = AuthenticationService.shared.login(
            username: username,
            password: password
        ) else {
            loginError = "Invalid username or password"
            return
        }

        // Set current user
        TestDataManager.shared.currentUserId = user.id

        // Save session for "stay logged in"
        AuthenticationService.shared.saveSession(
            userId: user.id,
            stayLoggedIn: stayLoggedIn
        )

        // v195: Load user data from Firestore (cloud-only)
        Task {
            await LocalDataLoader.loadUserDataFromFirestore(userId: user.id)
        }

        // Navigate to chat
        showChat = true
    }

    // v47: Create new user account
    private func signUp() {
        guard !signUpEmail.isEmpty && !signUpPassword.isEmpty && !signUpName.isEmpty else { return }

        // Generate unique user ID
        let userId = "user_\(UUID().uuidString.prefix(8))"

        // v57.0: Create minimal UnifiedUser skeleton with password
        let newUser = UnifiedUser(
            id: userId,
            firebaseUID: userId, // Placeholder until Firebase integration
            authProvider: .email,
            email: signUpEmail,
            phoneNumber: nil,
            name: signUpName, // Name from sign-up form
            photoURL: nil,
            providerUID: nil,
            emailVerified: false,
            birthdate: nil, // v65.2: nil until user sets it (don't send default to AI)
            gender: .preferNotToSay,
            roles: [.member], // Default to member role
            gymId: "district_brooklyn", // Default gym
            passwordHash: signUpPassword, // v57.0: Save password (plain text for beta)
            memberProfile: MemberProfile(
                height: nil,
                currentWeight: nil,
                goalWeight: nil,
                goalDate: nil,
                startingWeight: nil,
                fitnessGoal: .generalFitness,
                experienceLevel: .beginner,
                preferredWorkoutDays: [], // Empty array = onboarding complete, no name capture needed
                preferredSessionDuration: 60,
                emphasizedMuscleGroups: nil,
                excludedMuscleGroups: nil,
                trainingLocation: nil,
                availableEquipment: nil,
                maxTargetExercises: nil,
                voiceSettings: nil,
                trainerId: nil,
                membershipStatus: .active,
                memberSince: Date()
            ),
            trainerProfile: nil
        )

        // Add to TestDataManager
        TestDataManager.shared.users[userId] = newUser

        // v206: Sync to Firestore (fire-and-forget)
        Task {
            do {
                try await FirestoreUserRepository.shared.saveUser(newUser)
                Logger.log(.info, component: "LoginView", message: "☁️ Created new user: \(userId)")
            } catch {
                Logger.log(.warning, component: "LoginView", message: "⚠️ Firestore sync failed: \(error)")
            }
        }

        Logger.log(.info, component: "LoginView", message: "Created new user: \(userId)")

        // v57.0: Set current user and save session
        TestDataManager.shared.currentUserId = userId
        AuthenticationService.shared.saveSession(
            userId: userId,
            stayLoggedIn: true // Auto-enable for new users
        )

        // v78.1: REMOVED loadUserData() call - new users should start with EMPTY library
        // Exercise selection draws from global 100+ pool when library is empty
        // Exercises are auto-added to library on plan activation

        // Close sheet
        showSignUpSheet = false

        // Clear form
        signUpEmail = ""
        signUpPassword = ""
        signUpName = ""

        // Navigate to chat
        showChat = true
    }

    // v188: Handle Sign in with Apple result
    @MainActor
    private func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            do {
                try await FirebaseAuthService.shared.signInWithApple(authorization: authorization)

                // Get Firebase user credentials
                guard let firebaseUser = FirebaseAuthService.shared.currentUser else {
                    loginError = "Firebase sign-in succeeded but no user returned"
                    return
                }

                // Get or create local user from Firebase credentials
                let user = TestDataManager.shared.getOrCreateUser(
                    firebaseUID: firebaseUser.uid,
                    email: firebaseUser.email ?? "",
                    displayName: firebaseUser.displayName
                )

                // Set as current user
                TestDataManager.shared.currentUserId = user.id

                // Save session for auto-login
                AuthenticationService.shared.saveSession(
                    userId: user.id,
                    stayLoggedIn: true
                )

                // v196: Load reference data (exercises, protocols, gyms) then user data
                await LocalDataLoader.loadReferenceDataFromFirestore()
                await LocalDataLoader.loadUserDataFromFirestore(userId: user.id)

                Logger.log(.info, component: "LoginView", message: "Firebase login complete: \(user.name)")

                // Navigate to ChatView
                showChat = true

            } catch {
                loginError = "Sign-in failed: \(error.localizedDescription)"
                Logger.log(.error, component: "LoginView", message: "Apple Sign-In failed: \(error)")
            }
        case .failure(let error):
            // User cancelled or error occurred
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                Logger.log(.info, component: "LoginView", message: "Apple Sign-In cancelled by user")
            } else {
                loginError = "Apple Sign-In error: \(error.localizedDescription)"
                Logger.log(.error, component: "LoginView", message: "Apple Sign-In error: \(error)")
            }
        }
    }

    // v209: Handle Sign in with Google result
    @MainActor
    private func handleGoogleSignIn() async {
        // Get the root view controller for presenting Google Sign-In
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            loginError = "Unable to get root view controller"
            return
        }

        do {
            try await FirebaseAuthService.shared.signInWithGoogle(presenting: rootViewController)

            // Get Firebase user credentials
            guard let firebaseUser = Auth.auth().currentUser else {
                loginError = "Google sign-in succeeded but no user returned"
                return
            }

            // Get or create local user from Firebase credentials
            let user = TestDataManager.shared.getOrCreateUser(
                firebaseUID: firebaseUser.uid,
                email: firebaseUser.email ?? "",
                displayName: firebaseUser.displayName
            )

            // Set as current user
            TestDataManager.shared.currentUserId = user.id

            // Save session for auto-login
            AuthenticationService.shared.saveSession(
                userId: user.id,
                stayLoggedIn: true
            )

            // v196: Load reference data (exercises, protocols, gyms) then user data
            await LocalDataLoader.loadReferenceDataFromFirestore()
            await LocalDataLoader.loadUserDataFromFirestore(userId: user.id)

            Logger.log(.info, component: "LoginView", message: "Google login complete: \(user.name)")

            // Navigate to ChatView
            showChat = true

        } catch FirebaseAuthError.cancelled {
            // User cancelled - no error message needed
            Logger.log(.info, component: "LoginView", message: "Google Sign-In cancelled by user")
        } catch {
            loginError = "Google Sign-In failed: \(error.localizedDescription)"
            Logger.log(.error, component: "LoginView", message: "Google Sign-In failed: \(error)")
        }
    }

    // v57.3: Reset workout progress (clears deltas but keeps plans)
    // v206: Removed legacy file deletion - Firestore is source of truth
    // v57.6: Clear active sessions
    private func resetWorkoutProgress() {
        // Clear all persisted deltas from UserDefaults
        DeltaStore.shared.clearAllDeltas()

        // v206: Removed legacy file deletion - Firestore is source of truth
        // Reset is now handled by clearing in-memory data and reloading from Firestore

        // v57.6: Clear active sessions (prevents stale session state)
        TestDataManager.shared.sessions.removeAll()

        // Force reload data from JSON
        TestDataManager.shared.isDataLoaded = false

        // Show success message
        resetMessage = "✓ Workout progress reset. All workouts marked as 'not started'."
        loginError = nil

        // Reload data
        Task {
            await loadDataIfNeeded()

            // Clear success message after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            resetMessage = nil
        }

        Logger.log(.info, component: "LoginView", message: "User reset workout progress (cleared deltas)")
    }

    @MainActor
    private func loadDataIfNeeded() async {
        if !TestDataManager.shared.isDataLoaded {
            do {
                try LocalDataLoader.loadAll()

                // v16.4: Apply persisted deltas from UserDefaults
                let manager = TestDataManager.shared

                manager.workouts = DeltaStore.shared.applyWorkoutDeltas(to: manager.workouts)
                manager.exerciseSets = DeltaStore.shared.applySetDeltas(to: manager.exerciseSets)  // v17.1
                manager.exerciseInstances = DeltaStore.shared.applyInstanceDeltas(to: manager.exerciseInstances)  // v17.4

                Logger.log(.info, component: "LoginView", message: "Applied workout, set, and instance deltas from DeltaStore")
            } catch {
                Logger.log(.error, component: "LoginView", message: "Data loading failed", data: error)
                if let loadError = error as? LocalDataLoaderError {
                    switch loadError {
                    case .fileMissing(let fileName):
                        loginError = "Missing file: \(fileName)"
                    case .decodingFailed(let resource, let underlying):
                        loginError = "Failed to decode \(resource).json: \(underlying.localizedDescription)"
                    }
                } else {
                    loginError = error.localizedDescription
                }
                return
            }
        }

        // v57.0: No longer need to populate picker - removed user list initialization
    }
}

// NOTE: LocalDataLoader has been extracted to Services/LocalDataLoader.swift
// so that both app code and tests can access it
