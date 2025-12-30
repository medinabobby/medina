//
// AuthenticationService.swift
// Medina
//
// Beta authentication system - v57.0
// Created: November 2025
//
// Purpose: Simple JSON-based authentication for beta testing
// Post-beta: Migrate to Firebase/Cloud auth with bcrypt hashing
//

import Foundation

/// Beta authentication service using local JSON storage
/// ⚠️ Security Note: Uses plain text passwords for beta only
/// Post-beta migration: Firebase Auth + bcrypt + KeyChain
@MainActor
class AuthenticationService {
    static let shared = AuthenticationService()

    private init() {}

    // MARK: - Login/Logout

    /// Authenticate user with username (email or name) and password
    /// - Parameters:
    ///   - username: User's email or name (case-insensitive)
    ///   - password: User's password (beta: plain text comparison)
    /// - Returns: UnifiedUser if credentials valid, nil if invalid
    func login(username: String, password: String) -> UnifiedUser? {
        let allUsers = Array(LocalDataStore.shared.users.values)

        // Find user by email OR name (flexible for better UX)
        guard let user = allUsers.first(where: { user in
            user.email?.lowercased() == username.lowercased() ||
            user.name.lowercased() == username.lowercased()
        }) else {
            Logger.log(.warning, component: "Auth",
                      message: "User not found: \(username)")
            return nil
        }

        // Validate password (beta: simple string comparison)
        guard let storedPassword = user.passwordHash,
              storedPassword == password else {
            Logger.log(.warning, component: "Auth",
                      message: "Invalid password for: \(username)")
            return nil
        }

        Logger.log(.info, component: "Auth",
                  message: "Login successful: \(user.name)")
        return user
    }

    /// Logout current user and clear session
    func logout() {
        LocalDataStore.shared.currentUserId = nil
        clearSession()
        Logger.log(.info, component: "Auth", message: "User logged out")
    }

    // MARK: - Session Persistence

    private let sessionUserIdKey = "medina.beta.lastLoggedInUserId"
    private let stayLoggedInKey = "medina.beta.stayLoggedIn"

    /// Save session for "stay logged in" functionality
    /// - Parameters:
    ///   - userId: User ID to persist
    ///   - stayLoggedIn: Whether to enable auto-login on app restart
    func saveSession(userId: String, stayLoggedIn: Bool) {
        UserDefaults.standard.set(userId, forKey: sessionUserIdKey)
        UserDefaults.standard.set(stayLoggedIn, forKey: stayLoggedInKey)
        Logger.log(.debug, component: "Auth",
                  message: "Session saved: \(userId), stay=\(stayLoggedIn)")
    }

    /// Get current session if "stay logged in" is enabled
    /// - Returns: Saved user ID if auto-login enabled, nil otherwise
    func getCurrentSession() -> String? {
        let stayLoggedIn = UserDefaults.standard.bool(forKey: stayLoggedInKey)
        guard stayLoggedIn else {
            Logger.log(.debug, component: "Auth", message: "Stay logged in disabled")
            return nil
        }

        let userId = UserDefaults.standard.string(forKey: sessionUserIdKey)
        if let userId = userId {
            Logger.log(.debug, component: "Auth", message: "Found saved session: \(userId)")
        }
        return userId
    }

    /// Clear saved session (called on logout)
    func clearSession() {
        UserDefaults.standard.removeObject(forKey: sessionUserIdKey)
        UserDefaults.standard.removeObject(forKey: stayLoggedInKey)
        Logger.log(.debug, component: "Auth", message: "Session cleared")
    }

    // MARK: - Signup Validation

    /// Check if username (email or name) already exists
    /// - Parameter username: Email or name to check
    /// - Returns: true if username exists, false if available
    func usernameExists(_ username: String) -> Bool {
        let allUsers = Array(LocalDataStore.shared.users.values)
        let exists = allUsers.contains { user in
            user.email?.lowercased() == username.lowercased() ||
            user.name.lowercased() == username.lowercased()
        }

        if exists {
            Logger.log(.debug, component: "Auth",
                      message: "Username already exists: \(username)")
        }
        return exists
    }

    /// Validate password meets minimum requirements
    /// - Parameter password: Password to validate
    /// - Returns: nil if valid, error message if invalid
    func validatePassword(_ password: String) -> String? {
        // Beta: Simple validation (6+ characters)
        if password.count < 6 {
            return "Password must be at least 6 characters"
        }
        return nil
    }

    /// Validate email format
    /// - Parameter email: Email to validate
    /// - Returns: true if valid email format
    func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}
