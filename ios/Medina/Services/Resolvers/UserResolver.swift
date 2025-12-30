//
// UserResolver.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

enum UserResolver {

    // MARK: - User Resolution

    /// Get all users visible to the user (permission-filtered)
    static func allUsers(for userContext: UserContext) -> [UnifiedUser] {
        return UserRoleService.getVisibleUsers(forUserId: userContext.userId)
    }

    /// Get a specific user by ID if visible to the context user
    static func user(id: String, for userContext: UserContext) -> UnifiedUser? {
        let visibleUsers = allUsers(for: userContext)
        return visibleUsers.first { $0.id == id }
    }

    /// Get users with specific role
    static func users(for userContext: UserContext, withRole role: UserRole) -> [UnifiedUser] {
        return UserRoleService.getUsersWithRole(viewerId: userContext.userId, role: role)
    }

    /// Get users filtered by status
    static func users(for userContext: UserContext, status: UserStatus?, role: UserRole? = nil) -> [UnifiedUser] {
        var users: [UnifiedUser]

        if let role = role {
            users = self.users(for: userContext, withRole: role)
        } else {
            users = allUsers(for: userContext)
        }

        guard let status = status else {
            return users
        }

        switch status {
        case .active:
            return users.filter { user in
                if user.hasRole(.member), let memberProfile = user.memberProfile {
                    return memberProfile.membershipStatus == .active
                }
                if user.hasRole(.trainer) {
                    // Active trainers have assigned members
                    let assignedMembers = allUsers(for: userContext)
                        .filter { $0.hasRole(.member) }
                        .filter { $0.memberProfile?.trainerId == user.id }
                    return !assignedMembers.isEmpty
                }
                return true // Default to active for other roles
            }
        case .expired:
            return users.filter { user in
                if user.hasRole(.member), let memberProfile = user.memberProfile {
                    return memberProfile.membershipStatus == .expired || memberProfile.membershipStatus == .cancelled
                }
                return false
            }
        case .pending:
            return users.filter { user in
                if user.hasRole(.member), let memberProfile = user.memberProfile {
                    return memberProfile.membershipStatus == .pending
                }
                return false
            }
        case .inactive:
            return users.filter { user in
                if user.hasRole(.member), let memberProfile = user.memberProfile {
                    // Map UserStatus.inactive to MembershipStatus.suspended
                    // (MembershipStatus doesn't have .inactive case)
                    return memberProfile.membershipStatus == .suspended
                }
                return false
            }
        }
    }

    /// Get a single user by status and optional role
    static func user(for userContext: UserContext, status: UserStatus?, role: UserRole? = nil) -> UnifiedUser? {
        return users(for: userContext, status: status, role: role).first
    }

    // MARK: - Member-Specific Methods

    /// Get all members visible to the user (permission-filtered)
    static func allMembers(for userContext: UserContext) -> [UnifiedUser] {
        return users(for: userContext, withRole: .member)
    }

    /// Get a specific member by ID if visible to the user
    static func member(id: String, for userContext: UserContext) -> UnifiedUser? {
        let members = allMembers(for: userContext)
        return members.first { $0.id == id }
    }

    /// Get members filtered by status
    static func members(for userContext: UserContext, status: UserStatus?) -> [UnifiedUser] {
        return users(for: userContext, status: status, role: .member)
    }

    /// Get a single member by status
    static func member(for userContext: UserContext, status: UserStatus?) -> UnifiedUser? {
        return members(for: userContext, status: status).first
    }

    // MARK: - Trainer-Specific Methods

    /// Get all trainers visible to the user (permission-filtered)
    static func allTrainers(for userContext: UserContext) -> [UnifiedUser] {
        let users = self.users(for: userContext, withRole: .trainer)

        // Log permission filtering results
        let totalTrainers = Array(LocalDataStore.shared.users.values).filter { $0.hasRole(.trainer) }
        Logger.log(.debug, component: "UserResolver", userContext: userContext,
                   message: "Permission filtering: \(users.count) of \(totalTrainers.count) trainers visible")

        return users
    }

    /// Get a specific trainer by ID if visible to the user
    static func trainer(id: String, for userContext: UserContext) -> UnifiedUser? {
        let trainers = allTrainers(for: userContext)
        return trainers.first { $0.id == id }
    }

    /// Get trainers filtered by status
    static func trainers(for userContext: UserContext, status: UserStatus?) -> [UnifiedUser] {
        return users(for: userContext, status: status, role: .trainer)
    }

    /// Get a single trainer by status
    static func trainer(for userContext: UserContext, status: UserStatus?) -> UnifiedUser? {
        return trainers(for: userContext, status: status).first
    }

    // MARK: - Admin-Specific Methods

    /// Get all admins visible to the user
    static func allAdmins(for userContext: UserContext) -> [UnifiedUser] {
        return users(for: userContext, withRole: .admin)
    }

    /// Get gym owners visible to the user
    static func allGymOwners(for userContext: UserContext) -> [UnifiedUser] {
        return users(for: userContext, withRole: .gymOwner)
    }

    // MARK: - Gym-Specific Methods

    /// Get all users for a specific gym
    static func usersForGym(gymId: String, userContext: UserContext) -> [UnifiedUser] {
        let visibleUsers = allUsers(for: userContext)
        return visibleUsers.filter { $0.gymId == gymId }
    }

    /// Get members for a specific gym
    static func membersForGym(gymId: String, userContext: UserContext) -> [UnifiedUser] {
        let gymUsers = usersForGym(gymId: gymId, userContext: userContext)
        return gymUsers.filter { $0.hasRole(.member) }
    }

    /// Get trainers for a specific gym
    static func trainersForGym(gymId: String, userContext: UserContext) -> [UnifiedUser] {
        let gymUsers = usersForGym(gymId: gymId, userContext: userContext)
        return gymUsers.filter { $0.hasRole(.trainer) }
    }

    // MARK: - Trainer Assignment Methods

    /// Get members assigned to a specific trainer
    static func membersForTrainer(trainerId: String, userContext: UserContext) -> [UnifiedUser] {
        let visibleMembers = allMembers(for: userContext)
        return visibleMembers.filter { member in
            member.memberProfile?.trainerId == trainerId
        }
    }

    /// Get the trainer assigned to a specific member
    static func trainerForMember(memberId: String, userContext: UserContext) -> UnifiedUser? {
        guard let member = member(id: memberId, for: userContext),
              let trainerId = member.memberProfile?.trainerId else {
            return nil
        }
        return trainer(id: trainerId, for: userContext)
    }

    // MARK: - Search Methods

    /// Search users by name
    static func searchUsers(query: String, userContext: UserContext, role: UserRole? = nil) -> [UnifiedUser] {
        var users: [UnifiedUser]

        if let role = role {
            users = self.users(for: userContext, withRole: role)
        } else {
            users = allUsers(for: userContext)
        }

        let lowercaseQuery = query.lowercased()
        return users.filter { user in
            user.name.lowercased().contains(lowercaseQuery) ||
            user.email?.lowercased().contains(lowercaseQuery) == true
        }
    }

    /// Search members by name
    static func searchMembers(query: String, userContext: UserContext) -> [UnifiedUser] {
        return searchUsers(query: query, userContext: userContext, role: .member)
    }

    /// Search trainers by name
    static func searchTrainers(query: String, userContext: UserContext) -> [UnifiedUser] {
        return searchUsers(query: query, userContext: userContext, role: .trainer)
    }


    // MARK: - Role Transition Helpers

    /// Check if unified user system is available
    static func isUnifiedSystemAvailable() -> Bool {
        return true // Unified system is always available now
    }

    /// Get user statistics for a gym
    static func gymUserStats(gymId: String, userContext: UserContext) -> GymUserStats {
        let gymUsers = usersForGym(gymId: gymId, userContext: userContext)

        let memberCount = gymUsers.filter { $0.hasRole(.member) }.count
        let trainerCount = gymUsers.filter { $0.hasRole(.trainer) }.count
        let adminCount = gymUsers.filter { $0.hasRole(.admin) }.count
        let multiRoleCount = gymUsers.filter { $0.roles.count > 1 }.count

        return GymUserStats(
            totalUsers: gymUsers.count,
            memberCount: memberCount,
            trainerCount: trainerCount,
            adminCount: adminCount,
            multiRoleCount: multiRoleCount
        )
    }
}

// MARK: - Supporting Types

struct GymUserStats {
    let totalUsers: Int
    let memberCount: Int
    let trainerCount: Int
    let adminCount: Int
    let multiRoleCount: Int

    var summary: String {
        return """
        Gym User Statistics:
        • Total Users: \(totalUsers)
        • Members: \(memberCount)
        • Trainers: \(trainerCount)
        • Admins: \(adminCount)
        • Multi-role Users: \(multiRoleCount)
        """
    }
}