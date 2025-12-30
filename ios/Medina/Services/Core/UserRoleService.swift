//
// UserRoleService.swift
// Medina
//
// Last reviewed: October 2025
// v187: Admin/gymOwner UI deferred for beta - service kept for data model compatibility
//

import Foundation

// MARK: - User Role Service

/// Service for determining user roles and permissions in the user system
/// Supports multiple roles per user and role-based data filtering
class UserRoleService {

    // MARK: - Data Access

    private static var allUsers: [String: UnifiedUser] {
        return LocalDataStore.shared.users
    }

    // MARK: - Role Detection

    /// Get the primary role for a given user ID
    /// Returns the highest permission role if user has multiple roles
    static func getUserRole(userId: String) -> UserRole {
        if let user = allUsers[userId] {
            return user.primaryRole ?? .member
        }

        // Fallback to default role for unknown users
        return .member
    }

    /// Get all roles for a given user ID
    static func getUserRoles(userId: String) -> [UserRole] {
        if let user = allUsers[userId] {
            return user.roles
        }

        // Fallback to default role for unknown users
        return [.member]
    }

    /// Get the highest permission role for a user
    /// Used for determining maximum access level
    static func getHighestRole(userId: String) -> UserRole {
        let roles = getUserRoles(userId: userId)

        // Role hierarchy: gymOwner > admin > trainer > member
        if roles.contains(.gymOwner) { return .gymOwner }
        if roles.contains(.admin) { return .admin }
        if roles.contains(.trainer) { return .trainer }
        return .member
    }

    /// Check if a user has a specific role
    static func hasRole(userId: String, role: UserRole) -> Bool {
        let userRoles = getUserRoles(userId: userId)
        return userRoles.contains(role)
    }

    /// Check if a user has any admin-level role
    static func isAdmin(userId: String) -> Bool {
        return hasRole(userId: userId, role: .admin) || hasRole(userId: userId, role: .gymOwner)
    }

    // MARK: - Permission Checking

    /// Check if a user has a specific permission
    /// Considers all roles the user has and returns true if any role grants the permission
    static func hasPermission(userId: String, permission: QueryPermission) -> Bool {
        let roles = getUserRoles(userId: userId)
        return roles.contains { role in
            role.permissions.contains(permission)
        }
    }

    /// Get all permissions for a user (union of all roles)
    static func getAllPermissions(userId: String) -> Set<QueryPermission> {
        let roles = getUserRoles(userId: userId)
        return roles.reduce(Set<QueryPermission>()) { result, role in
            result.union(role.permissions)
        }
    }

    // MARK: - Visibility Methods

    /// Get all users visible to a given user based on their roles
    static func getVisibleUsers(forUserId userId: String) -> [UnifiedUser] {
        let role = getHighestRole(userId: userId)
        let allUsersList = Array(allUsers.values)

        Logger.log(.debug, component: "UserRoleService", message: "[\(userId):\(role.rawValue)] getVisibleUsers: \(allUsersList.count) total users in system")

        switch role {
        case .member:
            // Members can see themselves and their assigned trainer
            guard let currentUser = allUsers[userId] else {
                return []
            }

            return allUsersList.filter { user in
                // Include self
                if user.id == userId { return true }

                // Include assigned trainer (if current user is member with trainer)
                if user.hasRole(.trainer),
                   let memberProfile = currentUser.memberProfile,
                   let trainerId = memberProfile.trainerId,
                   user.id == trainerId {
                    return true
                }

                return false
            }

        case .trainer:
            // Trainers can see their assigned members + other trainers at their gym
            guard let currentUser = allUsers[userId],
                  let gymId = currentUser.gymId else {
                return []
            }

            return allUsersList.filter { user in
                // Include self
                if user.id == userId { return true }

                // Include assigned members (if current user is trainer)
                if user.hasRole(.member),
                   let memberProfile = user.memberProfile,
                   memberProfile.trainerId == userId {
                    return true
                }

                // Include other trainers/admins at same gym
                if (user.hasRole(.trainer) || user.hasRole(.admin)) && user.gymId == gymId {
                    return true
                }

                return false
            }

        case .admin, .gymOwner:
            // Admins can see all users in their gym(s)
            guard let currentUser = allUsers[userId],
                  let gymId = currentUser.gymId else {
                return allUsersList // Fallback to all users
            }

            return allUsersList.filter { user in
                user.gymId == gymId
            }
        }
    }

    /// Get all members visible to a given user based on their roles
    static func getVisibleMembers(forUserId userId: String) -> [UnifiedUser] {
        let visibleUsers = getVisibleUsers(forUserId: userId)
        return visibleUsers.filter { $0.hasRole(.member) }
    }

    /// Get all trainers visible to a given user based on their roles
    static func getVisibleTrainers(forUserId userId: String) -> [UnifiedUser] {
        let visibleUsers = getVisibleUsers(forUserId: userId)
        return visibleUsers.filter { $0.hasRole(.trainer) }
    }

    /// Get all gyms visible to a given user based on their roles
    static func getVisibleGyms(forUserId userId: String) -> [Gym] {
        let role = getHighestRole(userId: userId)
        let allGyms = Array(LocalDataStore.shared.gyms.values)

        switch role {
        case .member, .trainer, .admin:
            // Members, trainers, and admins can see their gym
            if let user = allUsers[userId],
               let gymId = user.gymId,
               let gym = LocalDataStore.shared.gyms[gymId] {
                return [gym]
            }
            return allGyms // Fallback to all gyms

        case .gymOwner:
            // Gym owners can see all gyms they own/manage
            return allGyms // For now, return all gyms
        }
    }

    // MARK: - Access Control

    /// Check if a user can view specific user data
    static func canViewUser(viewerId: String, targetUserId: String) -> Bool {
        // Users can always view themselves
        if viewerId == targetUserId {
            return true
        }

        let viewerRole = getHighestRole(userId: viewerId)
        guard let targetUser = allUsers[targetUserId] else {
            return false
        }

        switch viewerRole {
        case .member:
            // Members can view their assigned trainer
            guard let viewerUser = allUsers[viewerId] else {
                return false
            }

            // Check if target is assigned trainer
            if targetUser.hasRole(.trainer),
               let memberProfile = viewerUser.memberProfile,
               let trainerId = memberProfile.trainerId,
               targetUser.id == trainerId {
                return true
            }

            return false // Members cannot view other users

        case .trainer:
            // Trainers can view:
            // 1. Their assigned members
            // 2. Other trainers/admins at their gym
            guard let viewerUser = allUsers[viewerId] else {
                return false
            }

            // Check if target is assigned member
            if targetUser.hasRole(.member),
               let memberProfile = targetUser.memberProfile,
               memberProfile.trainerId == viewerId {
                return true
            }

            // Check if target is trainer/admin at same gym
            if (targetUser.hasRole(.trainer) || targetUser.hasRole(.admin)) &&
               targetUser.gymId == viewerUser.gymId {
                return true
            }

            return false

        case .admin, .gymOwner:
            // Admins can view users in their gym
            guard let viewerUser = allUsers[viewerId] else {
                return false
            }
            return targetUser.gymId == viewerUser.gymId
        }
    }

    /// Check if a user can view specific member data
    static func canViewMember(viewerId: String, targetMemberId: String) -> Bool {
        guard let targetUser = allUsers[targetMemberId],
              targetUser.hasRole(.member) else {
            return false
        }
        return canViewUser(viewerId: viewerId, targetUserId: targetMemberId)
    }

    /// Check if a user can view specific trainer data
    static func canViewTrainer(viewerId: String, targetTrainerId: String) -> Bool {
        guard let targetUser = allUsers[targetTrainerId],
              targetUser.hasRole(.trainer) else {
            return false
        }
        return canViewUser(viewerId: viewerId, targetUserId: targetTrainerId)
    }

    // MARK: - Role-Based Filtering

    /// Filter users by role and visibility
    static func filterUsers(_ users: [UnifiedUser], forViewerId viewerId: String, withRole role: UserRole? = nil) -> [UnifiedUser] {
        var filtered = users

        // Filter by role if specified
        if let role = role {
            filtered = filtered.filter { $0.hasRole(role) }
        }

        // Filter by visibility permissions
        filtered = filtered.filter { user in
            canViewUser(viewerId: viewerId, targetUserId: user.id)
        }

        return filtered
    }

    /// Get users with specific role visible to viewer
    static func getUsersWithRole(viewerId: String, role: UserRole) -> [UnifiedUser] {
        let allUsersList = Array(allUsers.values)
        return filterUsers(allUsersList, forViewerId: viewerId, withRole: role)
    }

}

// MARK: - Enhanced User Context

/// Updated UserContext for unified user system
extension UserContext {

    /// Initialize with unified user system
    init(unifiedUserId: String) {
        self.userId = unifiedUserId
        self.userRole = UserRoleService.getHighestRole(userId: unifiedUserId)
        self.permissions = UserRoleService.getAllPermissions(userId: unifiedUserId)
    }

    /// Get all unified users visible to this context
    func getVisibleUnifiedUsers() -> [UnifiedUser] {
        return UserRoleService.getVisibleUsers(forUserId: userId)
    }

    /// Get unified users with specific role
    func getUnifiedUsersWithRole(_ role: UserRole) -> [UnifiedUser] {
        return UserRoleService.getUsersWithRole(viewerId: userId, role: role)
    }

    /// Whether this context can view a specific unified user
    func canViewUnifiedUser(_ userId: String) -> Bool {
        return UserRoleService.canViewUser(viewerId: self.userId, targetUserId: userId)
    }

}