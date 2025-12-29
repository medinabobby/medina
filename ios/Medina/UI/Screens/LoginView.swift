//
// LoginView.swift
// Medina
//
// v213: Complete redesign - Claude-style login
// - Social buttons (Google/Apple) prominent at top
// - Magic link email auth (passwordless)
// - Removed insecure beta email/password
//

import SwiftUI
import AuthenticationServices
import GoogleSignIn
import FirebaseAuth

struct LoginView: View {
    // Auth state
    @State private var email: String = ""
    @State private var isLoading = false
    @State private var loginError: String?
    @State private var showChat = false
    @State private var showMagicLinkSent = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background - warm off-white like Claude
                Color("BackgroundPrimary")
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Logo and tagline
                    VStack(spacing: 16) {
                        Image("LoginIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)

                        Text("District")
                            .font(.system(size: 36, weight: .bold, design: .default))
                            .foregroundColor(Color("PrimaryText"))

                        Text("Your AI-powered fitness coach")
                            .font(.title3)
                            .foregroundColor(Color("SecondaryText"))
                    }
                    .padding(.bottom, 48)

                    // Auth buttons
                    VStack(spacing: 12) {
                        // Google Sign-In (most common)
                        Button {
                            Task { await handleGoogleSignIn() }
                        } label: {
                            HStack(spacing: 12) {
                                Image("GoogleLogo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                Text("Continue with Google")
                                    .font(.body)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color("PrimaryText"))
                            .foregroundColor(Color("BackgroundPrimary"))
                            .cornerRadius(27)
                        }
                        .disabled(isLoading)

                        // Apple Sign-In (required by App Store)
                        SignInWithAppleButton(.continue) { request in
                            let appleRequest = FirebaseAuthService.shared.createAppleIDRequest()
                            request.requestedScopes = appleRequest.requestedScopes
                            request.nonce = appleRequest.nonce
                        } onCompletion: { result in
                            Task { await handleAppleSignIn(result: result) }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 54)
                        .cornerRadius(27)
                    }
                    .padding(.horizontal, 32)

                    // OR divider
                    HStack(spacing: 16) {
                        Rectangle()
                            .fill(Color("SecondaryText").opacity(0.3))
                            .frame(height: 1)
                        Text("OR")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(Color("SecondaryText"))
                        Rectangle()
                            .fill(Color("SecondaryText").opacity(0.3))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)

                    // Email magic link
                    VStack(spacing: 12) {
                        TextField("Personal or work email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(Color("BackgroundSecondary"))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color("SecondaryText").opacity(0.2), lineWidth: 1)
                            )

                        Button {
                            Task { await sendMagicLink() }
                        } label: {
                            Text("Continue with Email")
                                .font(.body)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(email.isEmpty ? Color("SecondaryText").opacity(0.3) : Color.accentColor)
                                .foregroundColor(email.isEmpty ? Color("SecondaryText") : .white)
                                .cornerRadius(12)
                        }
                        .disabled(email.isEmpty || isLoading)
                    }
                    .padding(.horizontal, 32)

                    // Error message
                    if let loginError {
                        Text(loginError)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.top, 12)
                            .padding(.horizontal, 32)
                            .multilineTextAlignment(.center)
                    }

                    Spacer()

                    // Terms and privacy
                    VStack(spacing: 4) {
                        Text("By continuing, you agree to our")
                            .font(.caption)
                            .foregroundColor(Color("SecondaryText"))
                        HStack(spacing: 4) {
                            Link("Terms of Service", destination: URL(string: "https://district.fitness/terms")!)
                                .font(.caption)
                            Text("and")
                                .font(.caption)
                                .foregroundColor(Color("SecondaryText"))
                            Link("Privacy Policy", destination: URL(string: "https://district.fitness/privacy")!)
                                .font(.caption)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
            .fullScreenCover(isPresented: $showChat) {
                if let userId = TestDataManager.shared.currentUserId,
                   let user = TestDataManager.shared.users[userId] {
                    ChatView(user: user)
                }
            }
            .alert("Check Your Email", isPresented: $showMagicLinkSent) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("We sent a sign-in link to \(email). Click the link in the email to sign in.")
            }
            .overlay {
                if isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
        }
    }

    // MARK: - Auth Methods

    /// Send magic link to email (passwordless sign-in)
    @MainActor
    private func sendMagicLink() async {
        guard !email.isEmpty else { return }

        isLoading = true
        loginError = nil

        do {
            try await FirebaseAuthService.shared.sendMagicLink(to: email)
            showMagicLinkSent = true
            Logger.log(.info, component: "LoginView", message: "Magic link sent to: \(email)")
        } catch {
            loginError = "Failed to send sign-in link: \(error.localizedDescription)"
            Logger.log(.error, component: "LoginView", message: "Magic link failed: \(error)")
        }

        isLoading = false
    }

    /// Handle Sign in with Apple result
    @MainActor
    private func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        isLoading = true
        loginError = nil

        switch result {
        case .success(let authorization):
            do {
                try await FirebaseAuthService.shared.signInWithApple(authorization: authorization)
                await completeFirebaseLogin()
            } catch {
                loginError = "Apple Sign-In failed: \(error.localizedDescription)"
                Logger.log(.error, component: "LoginView", message: "Apple Sign-In failed: \(error)")
            }
        case .failure(let error):
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                Logger.log(.info, component: "LoginView", message: "Apple Sign-In cancelled")
            } else {
                loginError = "Apple Sign-In error: \(error.localizedDescription)"
                Logger.log(.error, component: "LoginView", message: "Apple Sign-In error: \(error)")
            }
        }

        isLoading = false
    }

    /// Handle Sign in with Google result
    @MainActor
    private func handleGoogleSignIn() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            loginError = "Unable to present sign-in"
            return
        }

        isLoading = true
        loginError = nil

        do {
            try await FirebaseAuthService.shared.signInWithGoogle(presenting: rootViewController)
            await completeFirebaseLogin()
        } catch FirebaseAuthError.cancelled {
            Logger.log(.info, component: "LoginView", message: "Google Sign-In cancelled")
        } catch {
            loginError = "Google Sign-In failed: \(error.localizedDescription)"
            Logger.log(.error, component: "LoginView", message: "Google Sign-In failed: \(error)")
        }

        isLoading = false
    }

    /// Complete login after Firebase auth succeeds
    @MainActor
    private func completeFirebaseLogin() async {
        guard let firebaseUser = Auth.auth().currentUser else {
            loginError = "Sign-in succeeded but no user returned"
            return
        }

        // Get or create local user
        let user = TestDataManager.shared.getOrCreateUser(
            firebaseUID: firebaseUser.uid,
            email: firebaseUser.email ?? "",
            displayName: firebaseUser.displayName
        )

        TestDataManager.shared.currentUserId = user.id

        // Load data from Firestore
        await LocalDataLoader.loadReferenceDataFromFirestore()
        await LocalDataLoader.loadUserDataFromFirestore(userId: user.id)

        Logger.log(.info, component: "LoginView", message: "Login complete: \(user.name)")
        showChat = true
    }
}
