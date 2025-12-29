//
// UserEnums.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

enum AuthProvider: String, Codable {
    case email = "email"
    case google = "google"
    case apple = "apple"
    
    var displayName: String {
        rawValue.capitalized
    }
}

enum Gender: String, Codable, CaseIterable {
    case male = "male"
    case female = "female"
    case other = "other"
    case preferNotToSay = "prefer_not_to_say"
    
    var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .other: return "Other"
        case .preferNotToSay: return "Prefer not to say"
        }
    }
}

enum TrainingLocation: String, Codable, CaseIterable {
    case home = "home"
    case gym = "gym"
    case hybrid = "hybrid"
    case outdoor = "outdoor"
    
    var displayName: String {
        switch self {
        case .home: return "Home"
        case .gym: return "Gym"
        case .hybrid: return "Home & Gym"
        case .outdoor: return "Outdoor"
        }
    }
}

enum MembershipStatus: String, Codable {
    case active = "active"
    case pending = "pending"
    case expired = "expired"
    case suspended = "suspended"
    case cancelled = "cancelled"

    var displayName: String {
        rawValue.capitalized
    }

    var isActive: Bool {
        switch self {
        case .active:
            return true
        default:
            return false
        }
    }
}

enum FitnessGoal: String, Codable, CaseIterable {
    case muscleGain = "muscle_gain"
    case fatLoss = "fat_loss"
    case strength = "strength"
    case endurance = "endurance"
    case mobility = "mobility"
    case generalFitness = "general_fitness"
    case powerlifting = "powerlifting"
    case bodybuilding = "bodybuilding"
    case athleticPerformance = "athletic_performance"
    case weightManagement = "weight_management"
    case personalTraining = "personal_training"
    case strengthConditioning = "strength_conditioning"
    case enduranceTraining = "endurance_training"
    case nutrition = "nutrition"
    case rehabilitative = "rehabilitative"
    case specialPopulations = "special_populations"
    case sportSpecific = "sport_specific"
    case yoga = "yoga"

    var displayName: String {
        switch self {
        case .muscleGain: return "Muscle Gain"
        case .fatLoss: return "Fat Loss"
        case .strength: return "Strength"
        case .endurance: return "Endurance"
        case .mobility: return "Mobility"
        case .generalFitness: return "General Fitness"
        case .powerlifting: return "Powerlifting"
        case .bodybuilding: return "Bodybuilding"
        case .athleticPerformance: return "Athletic Performance"
        case .weightManagement: return "Weight Management"
        case .personalTraining: return "Personal Training"
        case .strengthConditioning: return "Strength & Conditioning"
        case .enduranceTraining: return "Endurance Training"
        case .nutrition: return "Nutrition"
        case .rehabilitative: return "Rehabilitative"
        case .specialPopulations: return "Special Populations"
        case .sportSpecific: return "Sport Specific"
        case .yoga: return "Yoga"
        }
    }

    var educationalDescription: String {
        switch self {
        case .muscleGain:
            return "This focuses on hypertrophy through progressive overload, optimal volume, and muscle protein synthesis to build lean tissue."
        case .fatLoss:
            return "This emphasizes caloric deficit through metabolic training, strength preservation, and sustainable habits for body composition changes."
        case .strength:
            return "This develops maximal force production through heavy loading, progressive overload, and neuromuscular adaptations."
        case .endurance:
            return "This builds cardiovascular and muscular endurance through sustained activity and progressive volume increases."
        case .mobility:
            return "This improves joint range of motion, movement quality, and functional patterns through targeted flexibility work."
        case .generalFitness:
            return "This develops well-rounded fitness across strength, endurance, and mobility for overall health and wellness."
        case .powerlifting:
            return "This specializes in maximal squat, bench press, and deadlift performance through competition-specific training."
        case .bodybuilding:
            return "This focuses on muscle size, symmetry, and definition through targeted hypertrophy and physique development."
        case .athleticPerformance:
            return "This enhances sport-specific power, speed, agility, and movement patterns for competitive advantage."
        case .weightManagement:
            return "This focuses on sustainable weight control through balanced nutrition guidance, metabolic health, and lifestyle coaching."
        case .personalTraining:
            return "This provides one-on-one individualized training programs tailored to personal goals and fitness levels."
        case .strengthConditioning:
            return "This develops power, strength, and conditioning through systematic progressive training methods."
        case .enduranceTraining:
            return "This builds cardiovascular efficiency and stamina through aerobic and anaerobic conditioning protocols."
        case .nutrition:
            return "This provides dietary guidance, meal planning, and nutritional strategies to support fitness and health goals."
        case .rehabilitative:
            return "This focuses on injury recovery, movement restoration, and therapeutic exercise for optimal healing."
        case .specialPopulations:
            return "This serves specific groups like seniors, youth, or individuals with medical conditions requiring specialized care."
        case .sportSpecific:
            return "This develops skills, techniques, and conditioning specific to particular sports and athletic competitions."
        case .yoga:
            return "This teaches mindful movement, flexibility, balance, and stress reduction through traditional yoga practices."
        }
    }
}

enum ExperienceLevel: String, Codable, CaseIterable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"
    case expert = "expert"

    var displayName: String {
        rawValue.capitalized
    }

    var yearsRange: String {
        switch self {
        case .beginner: return "0-1 years"
        case .intermediate: return "1-3 years"
        case .advanced: return "3-5 years"
        case .expert: return "5+ years"
        }
    }
}

enum TrainerSpecialty: String, Codable, CaseIterable {
    case personalTraining = "personal_training"
    case strengthConditioning = "strength_conditioning"
    case weightLoss = "weight_loss"
    case weightManagement = "weight_management"
    case sportSpecific = "sport_specific"
    case rehabilitation = "rehabilitation"
    case rehabilitative = "rehabilitative"
    case groupFitness = "group_fitness"
    case nutrition = "nutrition"
    case yoga = "yoga"
    case pilates = "pilates"
    case crossfit = "crossfit"
    case enduranceTraining = "endurance_training"
    case mobility = "mobility"
    case powerlifting = "powerlifting"
    case specialPopulations = "special_populations"

    var displayName: String {
        switch self {
        case .personalTraining: return "Personal Training"
        case .strengthConditioning: return "Strength & Conditioning"
        case .weightLoss: return "Weight Loss"
        case .weightManagement: return "Weight Management"
        case .sportSpecific: return "Sport-Specific Training"
        case .rehabilitation: return "Injury Rehabilitation"
        case .rehabilitative: return "Rehabilitative"
        case .groupFitness: return "Group Fitness"
        case .nutrition: return "Nutrition Coaching"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .crossfit: return "CrossFit"
        case .enduranceTraining: return "Endurance Training"
        case .mobility: return "Mobility"
        case .powerlifting: return "Powerlifting"
        case .specialPopulations: return "Special Populations"
        }
    }
}

// v182: TrainingStyle enum removed - feature removed for beta simplicity
// Users can adjust AI tone via natural language in chat ("be more encouraging", "just give me the data")
