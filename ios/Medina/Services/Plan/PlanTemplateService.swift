//
// PlanTemplateService.swift
// Medina
//
// Created: November 2025
// v51.2 - Plan Creation MVP Simplification
// v69.0 - Multi-program periodization support
// v74.7 - Custom intensity range support
//
// Template-based plan generation service (replaces AI-powered PlanCreationService)
// Generates plan structure (Plan + Programs + Workouts) using rule-based templates
//

import Foundation

/// Result of plan generation containing plan and programs
struct GeneratedPlan {
    let plan: Plan
    let programs: [Program]
}

/// Service for template-based plan creation (no AI dependency)
/// v51.2: Simplified MVP approach with goal-based templates
enum PlanTemplateService {

    // MARK: - Public Interface

    /// Generate complete plan structure from user inputs using templates
    /// Returns Plan + Programs + Workouts (fully structured, ready for exercise assignment)
    /// v69.0: Added periodization parameters for multi-program generation
    static func createPlan(
        memberId: String,
        name: String,                    // User-entered plan name
        startDate: Date,
        durationDays: Int,               // Required (1 day to 364 days = 52 weeks)
        goal: FitnessGoal,               // Required
        liftingDays: Int,                // Required (2-6 days)
        experienceLevel: ExperienceLevel,  // v51.4: NEW (replaces splitType parameter)
        cardioDays: Int,                 // Required (0-7 days per v66)
        targetSessionDuration: Int,      // Required (45-90 min)
        preferredDays: Set<DayOfWeek>,   // Required (must match liftingDays + cardioDays)
        trainingLocation: TrainingLocation,  // v51.3: Location for equipment filtering
        emphasizedMuscleGroups: Set<MuscleGroup>? = nil,  // v65.2: User muscle focus
        excludedMuscleGroups: Set<MuscleGroup>? = nil,    // v65.2: User muscle avoidance
        preferredSplitType: SplitType? = nil,             // v66: User's preferred split (nil = auto-recommend)
        periodizationStyle: PeriodizationStyle = .auto,   // v69.0: How to structure phases
        includeDeloads: Bool = true,                      // v69.0: Include deload weeks
        deloadFrequency: Int = 5,                         // v69.0: Weeks between deloads
        intensityStart: Double? = nil,                    // v74.7: Custom start intensity (0.40-0.95)
        intensityEnd: Double? = nil,                      // v74.7: Custom end intensity (0.40-0.95)
        trainerId: String? = nil,                         // v188.3: Trainer with access (for trainer mode)
        createdBy: String? = nil                          // v188.3: Who created this plan
    ) -> GeneratedPlan {

        // Calculate plan end date
        let endDate = Calendar.current.date(
            byAdding: .day,
            value: durationDays,
            to: startDate
        ) ?? startDate

        // v66: Use user's preferred split type if set, otherwise auto-recommend
        let (splitType, splitReasoning): (SplitType, String)
        if let userSplit = preferredSplitType {
            // User has explicitly chosen a split type
            splitType = userSplit
            splitReasoning = "Using your preferred \(userSplit.displayName) split."
        } else {
            // v51.4: Compute optimal split based on experience + days + goal
            (splitType, splitReasoning) = recommendSplit(
                liftingDays: liftingDays,
                experience: experienceLevel,
                goal: goal
            )
        }

        // Get template-based strategy parameters
        let strategy = getDefaultParameters(goal: goal, liftingDays: liftingDays)

        // Build plan entity
        let plan = Plan(
            id: "plan_\(memberId)_\(UUID().uuidString.prefix(8))",
            memberId: memberId,
            trainerId: trainerId,    // v188.3: Trainer with access
            createdBy: createdBy,    // v188.3: Who created this plan
            status: .draft,
            name: name,  // User-provided name
            description: strategy.description,  // Template-based description
            goal: goal,
            weightliftingDays: liftingDays,
            cardioDays: cardioDays,
            splitType: splitType,
            splitRecommendationReasoning: splitReasoning,  // v51.4: Store reasoning for user display
            targetSessionDuration: targetSessionDuration,
            trainingLocation: trainingLocation,  // v51.3
            compoundTimeAllocation: strategy.compoundTimeAllocation,
            isolationApproach: strategy.isolationApproach,
            preferredDays: preferredDays,
            startDate: startDate,
            endDate: endDate,
            // v65.2: User preferences override strategy defaults
            emphasizedMuscleGroups: emphasizedMuscleGroups ?? strategy.emphasizedMuscleGroups,
            excludedMuscleGroups: excludedMuscleGroups,
            goalWeight: nil,
            contextualGoals: nil
        )

        // v69.0: Build programs using periodization engine
        // v74.7: Pass custom intensity range if provided
        let durationWeeks = max(1, durationDays / 7)
        let programs = buildPrograms(
            planId: plan.id,
            planName: name,
            startDate: startDate,
            endDate: endDate,
            goal: goal,
            durationWeeks: durationWeeks,
            periodizationStyle: periodizationStyle,
            includeDeloads: includeDeloads,
            deloadFrequency: deloadFrequency,
            customIntensityStart: intensityStart,
            customIntensityEnd: intensityEnd
        )

        return GeneratedPlan(plan: plan, programs: programs)
    }

    // MARK: - Split Recommendation (v51.4)

    /// Recommends optimal split type based on training frequency, experience, and goal
    /// - Parameters:
    ///   - liftingDays: Number of lifting days per week (2-6, per validation constraints)
    ///   - experience: User's training experience level (beginner/intermediate/advanced/expert)
    ///   - goal: Primary fitness goal
    /// - Returns: Recommended SplitType with reasoning text for user display
    private static func recommendSplit(
        liftingDays: Int,
        experience: ExperienceLevel,
        goal: FitnessGoal
    ) -> (split: SplitType, reasoning: String) {

        // Note: liftingDays is capped at 2-6 per createPlan validation
        switch (liftingDays, experience, goal) {

        // 2-3 days: Always Full Body (insufficient frequency for body part splits)
        case (2...3, _, _):
            return (.fullBody,
                    "Full Body split is optimal for 2-3 training days, hitting all muscle groups multiple times per week.")

        // 4 days: Beginner/Intermediate → Upper/Lower
        case (4, .beginner, _), (4, .intermediate, _):
            return (.upperLower,
                    "Upper/Lower split is ideal for 4 days per week at your experience level, allowing 2x frequency per muscle group with proper recovery.")

        // 4 days: Advanced/Expert + Strength goal → Full Body (high frequency benefits)
        case (4, .advanced, .strength), (4, .expert, .strength):
            return (.fullBody,
                    "Advanced strength training benefits from higher frequency. Full Body 4x/week allows practicing each lift multiple times per week.")

        // 4 days: Advanced/Expert + other goals → Upper/Lower
        case (4, .advanced, _), (4, .expert, _):
            return (.upperLower,
                    "Upper/Lower split provides optimal volume distribution for your experience level with 4 training days.")

        // 5 days: Upper/Lower with optional 5th day
        case (5, _, _):
            return (.upperLower,
                    "5 training days works well with Upper/Lower split plus a flexible 5th day for weak points or extra volume.")

        // 6 days: Push/Pull/Legs (classic PPL requires 6 days for 2x frequency)
        case (6, _, _):
            return (.pushPullLegs,
                    "Push/Pull/Legs split is optimal for 6 training days, running each workout 2x per week for high frequency and targeted volume.")

        // Fallback for edge cases (should rarely trigger given 2-6 constraint)
        default:
            return (.fullBody,
                    "Full Body split provides a balanced approach for your training schedule.")
        }
    }

    // MARK: - Template Strategy

    /// Template strategy parameters for a specific goal
    private struct TemplateStrategy {
        let description: String
        let compoundTimeAllocation: Double
        let isolationApproach: IsolationApproach
        let emphasizedMuscleGroups: Set<MuscleGroup>?
        let programFocus: TrainingFocus
        let startingIntensity: Double
        let endingIntensity: Double
        let progressionType: ProgressionType
        let programRationale: String
    }

    /// Get default strategy parameters based on goal and training frequency
    /// MVP: Simple goal-based templates with sensible defaults
    private static func getDefaultParameters(
        goal: FitnessGoal,
        liftingDays: Int
    ) -> TemplateStrategy {

        switch goal {

        case .strength:
            return TemplateStrategy(
                description: "Build maximal strength through progressive overload with compound movements",
                compoundTimeAllocation: 0.75,  // 75% compound, 25% isolation
                isolationApproach: .minimal,
                emphasizedMuscleGroups: nil,  // Balanced approach
                programFocus: .development,  // Progressive development phase
                startingIntensity: 0.70,  // 70% intensity
                endingIntensity: 0.85,    // 85% intensity
                progressionType: .linear,
                programRationale: "Progressive strength development with linear progression focusing on core compound lifts. Intensity increases from 70% to 85% to build maximal strength while managing fatigue."
            )

        case .muscleGain:
            return TemplateStrategy(
                description: "Maximize muscle growth through volume and metabolic stress",
                compoundTimeAllocation: 0.65,  // 65% compound, 35% isolation
                isolationApproach: .volumeAccumulation,  // Maximum isolation volume for growth
                emphasizedMuscleGroups: nil,  // Balanced approach
                programFocus: .development,  // Progressive development phase
                startingIntensity: 0.65,  // 65% intensity
                endingIntensity: 0.80,    // 80% intensity
                progressionType: .linear,
                programRationale: "Volume-focused muscle building with balanced compound and isolation work. Moderate intensity range (65-80%) optimizes hypertrophy while allowing sufficient volume."
            )

        case .fatLoss:
            return TemplateStrategy(
                description: "Burn calories and maintain muscle through circuit training and conditioning",
                compoundTimeAllocation: 0.60,  // 60% compound, 40% isolation
                isolationApproach: .postExhaust,  // Post-exhaust for muscle retention
                emphasizedMuscleGroups: nil,  // Full body approach
                programFocus: .development,  // Progressive development phase
                startingIntensity: 0.60,  // 60% intensity
                endingIntensity: 0.75,    // 75% intensity
                progressionType: .linear,
                programRationale: "Fat loss-optimized training with circuit and superset approach. Moderate-high reps (12-15) and steady intensity (60-75%) maximize calorie burn while preserving muscle."
            )

        case .endurance:
            return TemplateStrategy(
                description: "Build muscular endurance and work capacity",
                compoundTimeAllocation: 0.55,  // 55% compound, 45% isolation
                isolationApproach: .volumeAccumulation,  // Volume for work capacity
                emphasizedMuscleGroups: nil,  // Full body approach
                programFocus: .foundation,  // Foundation phase for work capacity
                startingIntensity: 0.50,  // 50% intensity
                endingIntensity: 0.70,    // 70% intensity
                progressionType: .linear,
                programRationale: "Endurance-focused training with higher rep ranges (15-20) and lower intensity (50-70%). Builds work capacity and muscular stamina over strength."
            )

        case .generalFitness:
            return TemplateStrategy(
                description: "Balanced training for overall health and fitness",
                compoundTimeAllocation: 0.70,  // 70% compound, 30% isolation
                isolationApproach: .minimal,
                emphasizedMuscleGroups: nil,  // Balanced approach
                programFocus: .maintenance,  // Maintenance phase for general fitness
                startingIntensity: 0.65,  // 65% intensity
                endingIntensity: 0.75,    // 75% intensity
                progressionType: .linear,
                programRationale: "Well-rounded training combining strength, hypertrophy, and conditioning elements. Moderate intensity (65-75%) and balanced programming for sustainable general fitness."
            )

        // Additional goal types (use sensible defaults based on primary goals above)
        case .powerlifting, .bodybuilding, .strengthConditioning:
            // Use strength template for powerlifting/strength-focused goals
            return getDefaultParameters(goal: .strength, liftingDays: liftingDays)

        case .athleticPerformance, .sportSpecific:
            // Use general fitness template for athletic performance
            return getDefaultParameters(goal: .generalFitness, liftingDays: liftingDays)

        case .mobility, .yoga, .rehabilitative:
            // Use endurance template for mobility/recovery-focused goals
            return getDefaultParameters(goal: .endurance, liftingDays: liftingDays)

        case .weightManagement:
            // Use fat loss template for weight management
            return getDefaultParameters(goal: .fatLoss, liftingDays: liftingDays)

        case .enduranceTraining:
            // Use endurance template
            return getDefaultParameters(goal: .endurance, liftingDays: liftingDays)

        case .personalTraining, .nutrition, .specialPopulations:
            // Use general fitness template for general training goals
            return getDefaultParameters(goal: .generalFitness, liftingDays: liftingDays)
        }
    }

    // MARK: - Program Building (v69.0: Multi-Program)

    /// v69.0: Build multiple programs using periodization engine
    /// v74.7: Added custom intensity range support
    /// Generates phase structure based on goal, duration, and style
    private static func buildPrograms(
        planId: String,
        planName: String,
        startDate: Date,
        endDate: Date,
        goal: FitnessGoal,
        durationWeeks: Int,
        periodizationStyle: PeriodizationStyle,
        includeDeloads: Bool,
        deloadFrequency: Int,
        customIntensityStart: Double? = nil,
        customIntensityEnd: Double? = nil
    ) -> [Program] {

        // Get phases from periodization engine
        // v74.7: Pass custom intensity if user specified
        let phases = PeriodizationEngine.calculatePhases(
            goal: goal,
            weeks: durationWeeks,
            style: periodizationStyle,
            includeDeloads: includeDeloads,
            deloadFrequency: deloadFrequency,
            customIntensityStart: customIntensityStart,
            customIntensityEnd: customIntensityEnd
        )

        var programs: [Program] = []
        var currentDate = startDate

        for (index, phase) in phases.enumerated() {
            // Calculate phase end date
            let phaseEndDate = Calendar.current.date(
                byAdding: .weekOfYear,
                value: phase.weeks,
                to: currentDate
            ) ?? endDate

            // Ensure we don't exceed plan end date
            let clampedEndDate = min(phaseEndDate, endDate)

            // Program name: Short, phase-first for better list display
            // e.g., "Phase 1: Foundation" or "Deload Week 1"
            let programName: String
            if phase.focus == .deload {
                // Count deload weeks for numbering
                let deloadCount = programs.filter { $0.focus == .deload }.count + 1
                programName = "Deload Week \(deloadCount)"
            } else {
                // Count non-deload phases for numbering
                let phaseCount = programs.filter { $0.focus != .deload }.count + 1
                programName = "Phase \(phaseCount): \(phase.focus.displayName)"
            }

            let program = Program(
                id: "prog_\(planId)_\(index + 1)",
                planId: planId,
                name: programName,
                focus: phase.focus,
                rationale: phase.rationale,
                startDate: currentDate,
                endDate: clampedEndDate,
                startingIntensity: phase.intensityRange.lowerBound,
                endingIntensity: phase.intensityRange.upperBound,
                progressionType: phase.progressionType,
                status: .draft
            )

            programs.append(program)
            currentDate = clampedEndDate
        }

        return programs
    }
}
