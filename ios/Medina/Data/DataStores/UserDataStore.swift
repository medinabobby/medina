//
// UserDataStore.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

enum UserDataStore {

    private static var manager: LocalDataStore { LocalDataStore.shared }

    /// Get all users in the system (no permission filtering - handled in resolver)
    static func allUsers() -> [UnifiedUser] {
        return Array(manager.users.values)
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Get a specific user by ID
    static func user(id: String) -> UnifiedUser? {
        return manager.users[id]
    }

    /// Get users with specific role
    static func users(withRole role: UserRole) -> [UnifiedUser] {
        return manager.users.values
            .filter { $0.hasRole(role) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Get users for a specific gym
    static func users(forGym gymId: String) -> [UnifiedUser] {
        return manager.users.values
            .filter { $0.gymId == gymId }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Get members assigned to a specific trainer
    static func members(assignedToTrainer trainerId: String) -> [UnifiedUser] {
        return manager.users.values
            .filter { user in
                user.hasRole(.member) && user.memberProfile?.trainerId == trainerId
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Get trainer assigned to a specific member
    static func trainer(forMember memberId: String) -> UnifiedUser? {
        guard let member = user(id: memberId),
              let trainerId = member.memberProfile?.trainerId else {
            return nil
        }
        return user(id: trainerId)
    }

    /// Search users by name or email
    static func searchUsers(query: String, role: UserRole? = nil) -> [UnifiedUser] {
        var users = allUsers()

        if let role = role {
            users = users.filter { $0.hasRole(role) }
        }

        let lowercaseQuery = query.lowercased()
        return users.filter { user in
            user.name.lowercased().contains(lowercaseQuery) ||
            user.email?.lowercased().contains(lowercaseQuery) == true
        }
    }

    /// Get active users (those with active membership/engagement)
    static func activeUsers(role: UserRole? = nil) -> [UnifiedUser] {
        var users = allUsers()

        if let role = role {
            users = users.filter { $0.hasRole(role) }
        }

        return users.filter { user in
            if user.hasRole(.member), let memberProfile = user.memberProfile {
                return memberProfile.membershipStatus == .active
            }
            if user.hasRole(.trainer) {
                // Active trainers have assigned members
                let assignedMembers = members(assignedToTrainer: user.id)
                return !assignedMembers.isEmpty
            }
            return true // Default to active for other roles
        }
    }

    /// Get users by membership/engagement status
    static func users(withStatus status: MembershipStatus) -> [UnifiedUser] {
        return manager.users.values
            .filter { user in
                if user.hasRole(.member), let memberProfile = user.memberProfile {
                    return memberProfile.membershipStatus == status
                }
                return false
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // MARK: - Convenience Methods

    /// Get all members
    static func allMembers() -> [UnifiedUser] {
        return users(withRole: .member)
    }

    /// Get all trainers
    static func allTrainers() -> [UnifiedUser] {
        return users(withRole: .trainer)
    }

    /// Get all admins
    static func allAdmins() -> [UnifiedUser] {
        return users(withRole: .admin)
    }

    /// Get all gym owners
    static func allGymOwners() -> [UnifiedUser] {
        return users(withRole: .gymOwner)
    }

    /// Get user statistics for a gym
    static func userStats(forGym gymId: String) -> UserStats {
        let gymUsers = users(forGym: gymId)

        let memberCount = gymUsers.filter { $0.hasRole(.member) }.count
        let trainerCount = gymUsers.filter { $0.hasRole(.trainer) }.count
        let adminCount = gymUsers.filter { $0.hasRole(.admin) }.count
        let multiRoleCount = gymUsers.filter { $0.roles.count > 1 }.count

        return UserStats(
            totalUsers: gymUsers.count,
            memberCount: memberCount,
            trainerCount: trainerCount,
            adminCount: adminCount,
            multiRoleCount: multiRoleCount
        )
    }
}

// MARK: - Supporting Types

struct UserStats {
    let totalUsers: Int
    let memberCount: Int
    let trainerCount: Int
    let adminCount: Int
    let multiRoleCount: Int

    var summary: String {
        return """
        User Statistics:
        • Total Users: \(totalUsers)
        • Members: \(memberCount)
        • Trainers: \(trainerCount)
        • Admins: \(adminCount)
        • Multi-role Users: \(multiRoleCount)
        """
    }
}