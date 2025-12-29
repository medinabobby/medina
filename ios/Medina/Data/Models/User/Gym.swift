//
// Gym.swift
// Medina
//
// Last reviewed: October 2025
// v80.2: Added id to MembershipTier for subscription linking
//

import Foundation

// MARK: - Gym Model

struct Gym: Identifiable, Codable {
    let id: String
    var name: String
    var address: String
    var neighborhood: String
    var city: String
    var state: String
    var zipCode: String
    var phone: String?
    var email: String
    var website: String?
    var hours: GymHours
    var facility: GymFacility
    var services: [String]
    var amenities: [String]
    var membershipTiers: [MembershipTier]
    var foundedDate: Date
    var memberCapacity: Int
    var activeMembers: Int
}

// MARK: - Supporting Structures

struct GymHours: Codable {
    let monday: String
    let tuesday: String
    let wednesday: String
    let thursday: String
    let friday: String
    let saturday: String
    let sunday: String

    /// Get formatted hours for a specific day
    func hours(for day: String) -> String {
        switch day.lowercased() {
        case "monday": return monday
        case "tuesday": return tuesday
        case "wednesday": return wednesday
        case "thursday": return thursday
        case "friday": return friday
        case "saturday": return saturday
        case "sunday": return sunday
        default: return "Closed"
        }
    }
}

struct GymFacility: Codable {
    let type: String
    let squareFeet: Int
    let levels: Int
    let description: String
}

/// v80.2: Membership tier with unique ID for subscription linking
/// v99: Added classCredits for Classes Module credit tracking
struct MembershipTier: Codable, Identifiable {
    let id: String          // Unique tier ID (e.g., "core", "core_plus", "ultimate")
    let name: String        // Display name (e.g., "Core", "Core+", "Ultimate")
    let price: Int          // Monthly price in dollars
    let benefits: [String]  // Feature list
    let classCredits: Int   // v99: Monthly class credits (Int.max for unlimited)

    var priceDisplay: String {
        return "$\(price)/month"
    }

    /// v99: Display string for class credits
    var classCreditsDisplay: String {
        classCredits == Int.max ? "Unlimited" : "\(classCredits)"
    }

    /// v80.2: CodingKeys for backwards compatibility (id defaults to lowercased name)
    enum CodingKeys: String, CodingKey {
        case id, name, price, benefits, classCredits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        price = try container.decode(Int.self, forKey: .price)
        benefits = try container.decode([String].self, forKey: .benefits)
        // v80.2: Default id from name if not present (backwards compatibility)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? name.lowercased().replacingOccurrences(of: "+", with: "_plus").replacingOccurrences(of: " ", with: "_")
        // v99: Default to 2 credits if not specified (backwards compatibility)
        classCredits = try container.decodeIfPresent(Int.self, forKey: .classCredits) ?? 2
    }

    init(id: String, name: String, price: Int, benefits: [String], classCredits: Int = 2) {
        self.id = id
        self.name = name
        self.price = price
        self.benefits = benefits
        self.classCredits = classCredits
    }
}

