//
// UserRole.swift
// Medina
//
// Last reviewed: October 2025
//

//
//  UserRole.swift
//  Medina
//
//  Created by Claude Code on 10/6/25.
//

// Last reviewed: October 2025

import Foundation

// MARK: - User Role System

/// User roles for B2B gym management with query permissions
enum UserRole: String, CaseIterable, Codable {
    case member = "member"           // Regular gym member - sees personal data only
    case trainer = "trainer"         // Personal trainer - sees assigned members + public resources
    case admin = "admin"            // Gym admin/owner - sees all gym entities
    case gymOwner = "gymOwner"      // Multi-gym owner - sees all owned gym data

    var displayName: String {
        switch self {
        case .member: return "Member"
        case .trainer: return "Trainer"
        case .admin: return "Admin"
        case .gymOwner: return "Gym Manager"  // v99.9: Renamed from "Gym Owner"
        }
    }

    var permissions: Set<QueryPermission> {
        switch self {
        case .member:
            return [.viewPersonalData, .viewPublicResources]
        case .trainer:
            return [.viewPersonalData, .viewPublicResources, .viewAssignedMembers, .viewGymClasses, .viewGymTrainers]
        case .admin:
            // District gym admin: can manage gym operations (address, hours, amenities) and see all gym data
            return [.viewPersonalData, .viewPublicResources, .viewAllMembers, .viewGymClasses, .viewGymTrainers, .viewGymData, .manageGymOperations]
        case .gymOwner:
            // Medina admin: platform-level control including cross-gym analytics and business management
            return [.viewPersonalData, .viewPublicResources, .viewAllMembers, .viewGymClasses, .viewGymTrainers, .viewGymData, .manageGymOperations, .managePlatform, .viewCrossGymData]
        }
    }

    /// Whether this role can view other members
    var canViewOtherMembers: Bool {
        return permissions.contains(.viewAssignedMembers) || permissions.contains(.viewAllMembers)
    }

    /// Whether this role can view all gym data
    var canViewAllGymData: Bool {
        return permissions.contains(.viewGymData)
    }

    /// Whether this role can manage gym operations (legacy)
    var canManageGym: Bool {
        return permissions.contains(.manageGym)
    }

    /// Whether this role can manage gym operations (District admin)
    var canManageGymOperations: Bool {
        return permissions.contains(.manageGymOperations)
    }

    /// Whether this role can manage platform operations (Medina admin)
    var canManagePlatform: Bool {
        return permissions.contains(.managePlatform)
    }

    /// Whether this role can view cross-gym analytics (Medina admin)
    var canViewCrossGymData: Bool {
        return permissions.contains(.viewCrossGymData)
    }
}

// MARK: - Query Permissions

/// Specific permissions for data access in queries
enum QueryPermission: String, CaseIterable {
    case viewPersonalData = "view_personal_data"
    case viewPublicResources = "view_public_resources"
    case viewAssignedMembers = "view_assigned_members"
    case viewAllMembers = "view_all_members"
    case viewGymClasses = "view_gym_classes"
    case viewGymTrainers = "view_gym_trainers"
    case viewGymData = "view_gym_data"
    case manageGym = "manage_gym"                    // Legacy - being replaced
    case viewMultiGymData = "view_multi_gym_data"    // Legacy - being replaced

    // Enhanced gym management permissions (v15.0)
    case manageGymOperations = "manage_gym_operations"  // District admin: edit gym details, hours, amenities
    case managePlatform = "manage_platform"             // Medina admin: business relationship, billing
    case viewCrossGymData = "view_cross_gym_data"       // Medina admin: platform-level analytics
}


// MARK: - V11+ User Context for Semantic Frames

/// Universal user context for FrameSlots - replaces simple member string
/// Enables role-based queries with proper permission validation
struct UserContext {
    let userId: String
    let userRole: UserRole
    let permissions: Set<QueryPermission>

    init(userId: String) {
        self.userId = userId
        // Use UnifiedUser system directly
        if let user = LocalDataStore.shared.users[userId] {
            self.userRole = user.primaryRole ?? .member
        } else {
            self.userRole = .member
        }
        self.permissions = userRole.permissions
    }

    /// Direct initialization with known role (for performance)
    init(userId: String, userRole: UserRole) {
        self.userId = userId
        self.userRole = userRole
        self.permissions = userRole.permissions
    }

    /// Whether this user can view other members
    var canViewOtherMembers: Bool {
        return userRole.canViewOtherMembers
    }

    /// Whether this user can view all gym data
    var canViewAllGymData: Bool {
        return userRole.canViewAllGymData
    }

    /// Whether this user can manage gym operations
    var canManageGym: Bool {
        return userRole.canManageGym
    }

    /// Whether this user has a specific permission
    func hasPermission(_ permission: QueryPermission) -> Bool {
        return permissions.contains(permission)
    }


    /// Get all gyms visible to this user
    func getVisibleGyms() -> [Gym] {
        let allGyms = Array(LocalDataStore.shared.gyms.values)

        switch userRole {
        case .member, .trainer, .admin:
            // Members, trainers, and admins can see their gym
            if let user = LocalDataStore.shared.users[userId],
               let userGymId = user.gymId,
               let gym = LocalDataStore.shared.gyms[userGymId] {
                return [gym]
            }
            return allGyms // Fallback to all gyms

        case .gymOwner:
            // Gym owners can see all gyms they own/manage
            return allGyms // For now, return all gyms
        }
    }

    /// Whether this user can view a specific member
    func canViewMember(_ memberId: String) -> Bool {
        // Users can always view themselves
        if userId == memberId {
            return true
        }

        switch userRole {
        case .member:
            return false // Members cannot view other members

        case .trainer:
            // Trainers can view assigned members
            if let targetUser = LocalDataStore.shared.users[memberId],
               let viewerUser = LocalDataStore.shared.users[userId],
               targetUser.hasRole(.member),
               viewerUser.hasRole(.trainer) {
                return targetUser.memberProfile?.trainerId == viewerUser.id
            }
            return false

        case .admin, .gymOwner:
            // Admins can view members in their gym
            if let targetUser = LocalDataStore.shared.users[memberId],
               let viewerUser = LocalDataStore.shared.users[userId] {
                return targetUser.gymId == viewerUser.gymId
            }
            return false
        }
    }

    /// Logging prefix for debugging multi-user flows
    var logPrefix: String {
        
        return "[\(userId):\(userRole.rawValue)]"
    }
}

// MARK: - UserContext Equatable & Hashable

extension UserContext: Equatable {
    static func == (lhs: UserContext, rhs: UserContext) -> Bool {
        return lhs.userId == rhs.userId && lhs.userRole == rhs.userRole
    }
}

extension UserContext: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(userId)
        hasher.combine(userRole)
    }
}

// MARK: - Role-Based Query Context

/// Context for role-based queries (legacy - consider migrating to UserContext)
struct RoleQueryContext {
    let userId: String
    let userRole: UserRole
    let permissions: Set<QueryPermission>
    let visibleGymIds: Set<String>

    init(userId: String) {
        self.userId = userId
        // Use UnifiedUser system directly
        if let user = LocalDataStore.shared.users[userId] {
            self.userRole = user.primaryRole ?? .member
        } else {
            self.userRole = .member
        }
        self.permissions = userRole.permissions

        // Determine visible gym IDs based on role
        let userContext = UserContext(userId: userId, userRole: userRole)
        let visibleGyms = userContext.getVisibleGyms()
        self.visibleGymIds = Set(visibleGyms.map { $0.id })
    }

    /// Whether this context can access data from a specific gym
    func canAccessGym(_ gymId: String) -> Bool {
        return visibleGymIds.contains(gymId)
    }

    /// Whether this context can view a specific member
    func canViewMember(_ memberId: String) -> Bool {
        let userContext = UserContext(userId: userId, userRole: userRole)
        return userContext.canViewMember(memberId)
    }

    /// Logging prefix for debugging multi-user flows
    var logPrefix: String {
        
        return "[\(userId):\(userRole.rawValue)]"
    }
}
