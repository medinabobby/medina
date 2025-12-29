import Foundation
import FirebaseAuth
import FirebaseCore
import AuthenticationServices
import CryptoKit
import GoogleSignIn

/// Firebase Authentication service for Google Sign-In
/// Release 1.2: Validates iOS can authenticate with Firebase
@MainActor
class FirebaseAuthService: ObservableObject {

    // MARK: - Published State

    @Published var currentUser: User?
    @Published var isSignedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Singleton

    static let shared = FirebaseAuthService()

    // MARK: - Private Properties

    private var authStateHandler: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    // MARK: - Initialization

    private init() {
        setupAuthStateListener()
    }

    deinit {
        if let handler = authStateHandler {
            Auth.auth().removeStateDidChangeListener(handler)
        }
    }

    // MARK: - Auth State

    private func setupAuthStateListener() {
        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isSignedIn = user != nil

                if let user = user {
                    Logger.log(.info, component: "FirebaseAuth", message: "User signed in: \(user.uid)")
                    // Update FirebaseAPIClient with the ID token
                    await self?.refreshIDToken()
                } else {
                    Logger.log(.info, component: "FirebaseAuth", message: "User signed out")
                    await FirebaseAPIClient.shared.setAuthToken(nil)
                }
            }
        }
    }

    // MARK: - ID Token Management

    /// Get the current user's ID token for API calls
    func getIDToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw FirebaseAuthError.notSignedIn
        }

        return try await user.getIDToken()
    }

    /// Refresh and update the ID token in FirebaseAPIClient
    func refreshIDToken() async {
        do {
            let token = try await getIDToken()
            await FirebaseAPIClient.shared.setAuthToken(token)
            Logger.log(.debug, component: "FirebaseAuth", message: "ID token refreshed")
        } catch {
            Logger.log(.error, component: "FirebaseAuth", message: "Failed to refresh ID token: \(error)")
        }
    }

    // MARK: - Sign In with Apple (Recommended for iOS)

    /// Start Sign in with Apple flow
    /// Returns the ASAuthorizationAppleIDRequest for the ASAuthorizationController
    func createAppleIDRequest() -> ASAuthorizationAppleIDRequest {
        let nonce = randomNonceString()
        currentNonce = nonce

        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        return request
    }

    /// Complete Sign in with Apple after receiving authorization
    func signInWithApple(authorization: ASAuthorization) async throws {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let nonce = currentNonce,
              let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw FirebaseAuthError.invalidCredential
        }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )

        do {
            let result = try await Auth.auth().signIn(with: credential)
            Logger.log(.info, component: "FirebaseAuth", message: "Apple Sign-In successful: \(result.user.uid)")

            // Explicitly refresh the ID token BEFORE making API calls
            // (Don't rely on auth state listener - it runs in a separate Task)
            await refreshIDToken()

            // Fetch user profile from Firebase backend
            await fetchUserProfile()
        } catch {
            Logger.log(.error, component: "FirebaseAuth", message: "Apple Sign-In failed: \(error)")
            errorMessage = error.localizedDescription
            throw FirebaseAuthError.signInFailed(error)
        }
    }

    // MARK: - Sign In with Google

    /// Sign in with Google
    /// v209: Added for cross-platform account parity with web
    func signInWithGoogle(presenting: UIViewController) async throws {
        // Get client ID from Firebase config
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw FirebaseAuthError.missingClientID
        }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        // Configure Google Sign-In
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        do {
            // Present Google Sign-In
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)

            // Get ID token
            guard let idToken = result.user.idToken?.tokenString else {
                throw FirebaseAuthError.missingIDToken
            }

            // Create Firebase credential
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )

            // Sign in with Firebase
            let authResult = try await Auth.auth().signIn(with: credential)
            Logger.log(.info, component: "FirebaseAuth", message: "Google Sign-In successful: \(authResult.user.uid)")

            // Explicitly refresh the ID token BEFORE making API calls
            await refreshIDToken()

            // Fetch user profile from Firebase backend
            await fetchUserProfile()
        } catch let error as GIDSignInError where error.code == .canceled {
            Logger.log(.info, component: "FirebaseAuth", message: "Google Sign-In cancelled by user")
            throw FirebaseAuthError.cancelled
        } catch {
            Logger.log(.error, component: "FirebaseAuth", message: "Google Sign-In failed: \(error)")
            errorMessage = error.localizedDescription
            throw FirebaseAuthError.signInFailed(error)
        }
    }

    // MARK: - Magic Link (Email Link Sign-In)

    /// Send a magic link to the user's email for passwordless sign-in
    /// v213: Added for passwordless email authentication
    func sendMagicLink(to email: String) async throws {
        let actionCodeSettings = ActionCodeSettings()
        actionCodeSettings.url = URL(string: "https://medinaintelligence.web.app/auth")
        actionCodeSettings.handleCodeInApp = true
        actionCodeSettings.setIOSBundleID(Bundle.main.bundleIdentifier!)

        do {
            try await Auth.auth().sendSignInLink(toEmail: email, actionCodeSettings: actionCodeSettings)

            // Save email for later verification
            UserDefaults.standard.set(email, forKey: "pendingMagicLinkEmail")

            Logger.log(.info, component: "FirebaseAuth", message: "Magic link sent to: \(email)")
        } catch {
            Logger.log(.error, component: "FirebaseAuth", message: "Failed to send magic link: \(error)")
            throw FirebaseAuthError.magicLinkFailed(error)
        }
    }

    /// Handle incoming magic link URL
    /// v213: Called from MedinaApp when app receives deep link
    func handleMagicLink(_ url: URL) async throws {
        let link = url.absoluteString

        guard Auth.auth().isSignIn(withEmailLink: link) else {
            Logger.log(.warning, component: "FirebaseAuth", message: "URL is not a valid sign-in link")
            return
        }

        guard let email = UserDefaults.standard.string(forKey: "pendingMagicLinkEmail") else {
            throw FirebaseAuthError.missingEmail
        }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let result = try await Auth.auth().signIn(withEmail: email, link: link)
            Logger.log(.info, component: "FirebaseAuth", message: "Magic link sign-in successful: \(result.user.uid)")

            // Clear saved email
            UserDefaults.standard.removeObject(forKey: "pendingMagicLinkEmail")

            // Refresh token and fetch profile
            await refreshIDToken()
            await fetchUserProfile()
        } catch {
            Logger.log(.error, component: "FirebaseAuth", message: "Magic link sign-in failed: \(error)")
            errorMessage = error.localizedDescription
            throw FirebaseAuthError.signInFailed(error)
        }
    }

    // MARK: - Sign Out

    func signOut() throws {
        do {
            try Auth.auth().signOut()
            Logger.log(.info, component: "FirebaseAuth", message: "Sign out successful")
        } catch {
            Logger.log(.error, component: "FirebaseAuth", message: "Sign out failed: \(error)")
            throw FirebaseAuthError.signOutFailed(error)
        }
    }

    // MARK: - User Profile

    /// Fetch user profile from Firebase backend after sign-in
    private func fetchUserProfile() async {
        do {
            let userResponse = try await FirebaseAPIClient.shared.getUser()
            Logger.log(.info, component: "FirebaseAuth", message: "User profile fetched: \(userResponse.email ?? "no email")")
        } catch {
            Logger.log(.error, component: "FirebaseAuth", message: "Failed to fetch user profile: \(error)")
        }
    }

    // MARK: - Helper Methods

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }

        return String(nonce)
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()

        return hashString
    }
}

// MARK: - Errors

enum FirebaseAuthError: LocalizedError {
    case notSignedIn
    case invalidCredential
    case missingClientID
    case missingIDToken
    case missingEmail
    case cancelled
    case signInFailed(Error)
    case signOutFailed(Error)
    case magicLinkFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in. Please sign in first."
        case .invalidCredential:
            return "Invalid credentials received."
        case .missingClientID:
            return "Firebase client ID not configured."
        case .missingIDToken:
            return "Failed to get ID token from Google."
        case .missingEmail:
            return "Email address not found. Please try signing in again."
        case .cancelled:
            return "Sign in was cancelled."
        case .signInFailed(let error):
            return "Sign in failed: \(error.localizedDescription)"
        case .signOutFailed(let error):
            return "Sign out failed: \(error.localizedDescription)"
        case .magicLinkFailed(let error):
            return "Failed to send sign-in link: \(error.localizedDescription)"
        }
    }
}
