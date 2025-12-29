//
// Plan.swift
// Medina
//
// v90.0: Added trainerId and createdBy for Trainer Mode
// v172: Removed abandon() - simplified to draft/active/completed
// Last reviewed: December 2025
//

import Foundation

struct Plan: Identifiable, Codable {
    // Identity
    let id: String
    let memberId: String

    // v90.0: Trainer Mode - Shared Ownership
    /// Trainer who has access to this plan (nil = member-only plan)
    var trainerId: String?
    /// User ID who created this plan (member or trainer)
    var createdBy: String?

    // v58.3: Single workout flag - distinguishes quick workouts from multi-week programs
    // Single workouts have 1-day duration with no intensity progression
    var isSingleWorkout: Bool

    // Status
    var status: PlanStatus

    // Basic Info
    var name: String
    var description: String  // Simple description, no rationales
    var goal: FitnessGoal

    // Training Structure
    var weightliftingDays: Int
    var cardioDays: Int
    var splitType: SplitType  // v16.7: Changed from String to typed enum
    var splitRecommendationReasoning: String?  // v51.4: Explanation for computed split choice
    var targetSessionDuration: Int
    var trainingLocation: TrainingLocation  // v51.3: Location (District/Home for equipment filtering)

    // Training Strategy
    var compoundTimeAllocation: Double
    var isolationApproach: IsolationApproach

    // Schedule
    var preferredDays: Set<DayOfWeek>
    var startDate: Date
    var endDate: Date

    // Customization
    var emphasizedMuscleGroups: Set<MuscleGroup>?
    var excludedMuscleGroups: Set<MuscleGroup>?
    var goalWeight: Double?
    var contextualGoals: String?

    // v58.5: Per-workout experience level override (nil = use profile default)
    var experienceLevel: ExperienceLevel?

    // v80.3: Override equipment for AI-generated home workouts
    // When set, takes precedence over memberProfile.availableEquipment
    var availableEquipment: Set<Equipment>?

    // MARK: - Codable (with backward-compatible defaults)

    private enum CodingKeys: String, CodingKey {
        case id, memberId, trainerId, createdBy  // v90.0: Added trainer mode fields
        case isSingleWorkout, status, name, description, goal
        case weightliftingDays, cardioDays, splitType, splitRecommendationReasoning
        case targetSessionDuration, trainingLocation
        case compoundTimeAllocation, isolationApproach
        case preferredDays, startDate, endDate
        case emphasizedMuscleGroups, excludedMuscleGroups, goalWeight, contextualGoals
        case experienceLevel, availableEquipment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        memberId = try container.decode(String.self, forKey: .memberId)

        // v90.0: Trainer mode fields with backward compatibility
        trainerId = try container.decodeIfPresent(String.self, forKey: .trainerId)
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)

        isSingleWorkout = try container.decodeIfPresent(Bool.self, forKey: .isSingleWorkout) ?? false
        status = try container.decode(PlanStatus.self, forKey: .status)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        goal = try container.decode(FitnessGoal.self, forKey: .goal)
        weightliftingDays = try container.decode(Int.self, forKey: .weightliftingDays)
        cardioDays = try container.decode(Int.self, forKey: .cardioDays)
        splitType = try container.decode(SplitType.self, forKey: .splitType)
        splitRecommendationReasoning = try container.decodeIfPresent(String.self, forKey: .splitRecommendationReasoning)
        targetSessionDuration = try container.decode(Int.self, forKey: .targetSessionDuration)
        trainingLocation = try container.decode(TrainingLocation.self, forKey: .trainingLocation)
        compoundTimeAllocation = try container.decode(Double.self, forKey: .compoundTimeAllocation)
        isolationApproach = try container.decode(IsolationApproach.self, forKey: .isolationApproach)
        preferredDays = try container.decode(Set<DayOfWeek>.self, forKey: .preferredDays)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        emphasizedMuscleGroups = try container.decodeIfPresent(Set<MuscleGroup>.self, forKey: .emphasizedMuscleGroups)
        excludedMuscleGroups = try container.decodeIfPresent(Set<MuscleGroup>.self, forKey: .excludedMuscleGroups)
        goalWeight = try container.decodeIfPresent(Double.self, forKey: .goalWeight)
        contextualGoals = try container.decodeIfPresent(String.self, forKey: .contextualGoals)
        experienceLevel = try container.decodeIfPresent(ExperienceLevel.self, forKey: .experienceLevel)
        availableEquipment = try container.decodeIfPresent(Set<Equipment>.self, forKey: .availableEquipment)
    }

    // Memberwise init for programmatic creation
    init(
        id: String,
        memberId: String,
        trainerId: String? = nil,          // v90.0: Trainer with access
        createdBy: String? = nil,          // v90.0: Who created this plan
        isSingleWorkout: Bool = false,
        status: PlanStatus,
        name: String,
        description: String,
        goal: FitnessGoal,
        weightliftingDays: Int,
        cardioDays: Int,
        splitType: SplitType,
        splitRecommendationReasoning: String? = nil,
        targetSessionDuration: Int,
        trainingLocation: TrainingLocation,
        compoundTimeAllocation: Double,
        isolationApproach: IsolationApproach,
        preferredDays: Set<DayOfWeek>,
        startDate: Date,
        endDate: Date,
        emphasizedMuscleGroups: Set<MuscleGroup>? = nil,
        excludedMuscleGroups: Set<MuscleGroup>? = nil,
        goalWeight: Double? = nil,
        contextualGoals: String? = nil,
        experienceLevel: ExperienceLevel? = nil,
        availableEquipment: Set<Equipment>? = nil
    ) {
        self.id = id
        self.memberId = memberId
        self.trainerId = trainerId
        self.createdBy = createdBy
        self.isSingleWorkout = isSingleWorkout
        self.status = status
        self.name = name
        self.description = description
        self.goal = goal
        self.weightliftingDays = weightliftingDays
        self.cardioDays = cardioDays
        self.splitType = splitType
        self.splitRecommendationReasoning = splitRecommendationReasoning
        self.targetSessionDuration = targetSessionDuration
        self.trainingLocation = trainingLocation
        self.compoundTimeAllocation = compoundTimeAllocation
        self.isolationApproach = isolationApproach
        self.preferredDays = preferredDays
        self.startDate = startDate
        self.endDate = endDate
        self.emphasizedMuscleGroups = emphasizedMuscleGroups
        self.excludedMuscleGroups = excludedMuscleGroups
        self.goalWeight = goalWeight
        self.contextualGoals = contextualGoals
        self.experienceLevel = experienceLevel
        self.availableEquipment = availableEquipment
    }
}

// MARK: - Plan Lifecycle Management

extension Plan {

    /// Computed status that combines stored status with date-based logic
    /// Use this for queries and UI display instead of raw `status`
    ///
    /// v46.1: Respects manual activation even for future plans
    /// v172: Simplified - no more abandoned status
    /// Once activated, plan stays active until endDate passes (auto-complete)
    var effectiveStatus: PlanStatus {
        let now = Date()

        // Manual completion override
        if status == .completed {
            return status  // Always respect manual completion
        }

        // For draft plans, check if they should auto-activate based on dates
        if status == .draft {
            if startDate > now { return .draft }  // Future draft (not started yet)
            if endDate < now { return .completed }  // Past draft (never activated, auto-complete)
            return .draft  // Current draft (waiting for manual activation)
        }

        // For active plans, check if they should auto-complete
        if status == .active {
            if endDate < now { return .completed }  // Auto-complete when plan ends
            return .active  // Still active (respects manual activation even if startDate is future)
        }

        return status  // Fallback (shouldn't reach here)
    }

    /// Whether this plan can be manually activated
    var canBeActivated: Bool {
        return status == .draft && startDate <= Date()
    }

    /// Whether this plan is currently the effective active plan
    var isEffectivelyActive: Bool {
        return effectiveStatus == .active
    }

    /// Whether this plan is in the future and ready for planning
    var isUpcoming: Bool {
        return effectiveStatus == .draft && startDate > Date()
    }

    /// Whether this plan has finished (v172: simplified to just completed)
    var isFinished: Bool {
        return effectiveStatus == .completed
    }

    /// User-friendly status description combining stored and computed status
    var statusDescription: String {
        if status != effectiveStatus {
            // Show when stored status differs from computed
            switch (status, effectiveStatus) {
            case (.active, .completed):
                return "Completed (was active)"
            case (.active, .draft):
                return "Scheduled (marked active)"
            default:
                return "\(effectiveStatus.displayName) (\(status.displayName))"
            }
        }
        return effectiveStatus.displayName
    }

    // MARK: - Lifecycle Transitions

    /// Manually complete this plan (v172: handles both normal and early completion)
    mutating func complete() {
        status = .completed
    }

    /// Complete this plan early (for injury, life changes, etc.)
    /// v172: Replaced abandon() - now sets to completed instead of abandoned
    mutating func completeEarly() {
        status = .completed
    }

    /// Activate a draft plan (if valid)
    mutating func activate() throws {
        guard canBeActivated else {
            throw PlanError.cannotActivate("Plan must be draft and start date must be reached")
        }
        status = .active
    }

    /// Check if plan dates overlap with another plan
    func overlaps(with other: Plan) -> Bool {
        return !(endDate < other.startDate || startDate > other.endDate)
    }

    /// Intelligently generated plan summary based on plan properties
    /// v19.3.1: Comprehensive format with all personalized fields and educational context
    var dynamicDescription: String {
        let sessionFrequency = weightliftingDays + cardioDays

        var lines: [String] = []

        // Line 1: Frequency and split breakdown
        var frequencyLine = "\(sessionFrequency)-day a week"
        if weightliftingDays > 0 && cardioDays > 0 {
            frequencyLine += " (\(weightliftingDays) weightlifting, \(cardioDays) cardio)"
        } else if weightliftingDays > 0 {
            frequencyLine += " (weightlifting focus)"
        } else if cardioDays > 0 {
            frequencyLine += " (cardio focus)"
        }

        // Add split type
        frequencyLine += ", featuring \(splitType.displayName)"

        // Add target session duration
        let hours = targetSessionDuration / 60
        let minutes = targetSessionDuration % 60
        if hours > 0 && minutes > 0 {
            frequencyLine += " with \(hours)hr \(minutes)min sessions"
        } else if hours > 0 {
            frequencyLine += " with \(hours)hr sessions"
        } else {
            frequencyLine += " with \(minutes)min sessions"
        }

        lines.append(frequencyLine)

        // Line 2: Goal
        if let contextGoals = contextualGoals, !contextGoals.isEmpty {
            lines.append("Designed to accomplish \(contextGoals.lowercased()).")
        } else {
            lines.append("Designed to accomplish \(goal.displayName.lowercased()).")
        }

        // Line 3: Educational description about split type
        lines.append(splitType.educationalDescription)

        return lines.joined(separator: " ")
    }
}

// MARK: - Plan Lifecycle Errors

enum PlanError: Error, LocalizedError {
    case cannotActivate(String)
    case planConflict(String)

    var errorDescription: String? {
        switch self {
        case .cannotActivate(let reason):
            return "Cannot activate plan: \(reason)"
        case .planConflict(let reason):
            return "Plan conflict: \(reason)"
        }
    }
}
