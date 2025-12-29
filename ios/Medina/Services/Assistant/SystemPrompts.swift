//
//  SystemPrompts.swift
//  Medina
//
//  Created by Bobby Tulsiani on 2025-11-24.
//  v59.1 - Basic System Prompt Generation
//  v69.4 - AI-optimized scheduling instructions + reschedule_plan tool
//  v74.2 - Decomposed into Prompts/ sub-files (~802 → ~80 lines)
//  v79.6 - Added active plan context for AI plan awareness
//  v81.0 - AI-first exercise context with preferences
//  v82.3 - Added confirmation behavior guidelines
//  v106.2 - Removed verbosity from AI prompts (AI adapts to context naturally)
//  v182 - Removed coaching style (TrainingStyle) - using default Medina personality
//  v87.2 - Added off-topic handling for B2B fitness focus
//  v87.4 - Added transparent assumptions and protocol experience defaults
//  v90.0 - Added trainer context for trainer mode
//  v96.0 - Flywheel data integration, prompt tiering, core rules consolidation
//  v111 - Added missed workout handling guideline for smart scheduling
//  v111.1 - Added class name accuracy guideline to fix booking failures
//

import Foundation

/// Generates system prompts for OpenAI Assistants API
/// v59.1: Basic personalized prompts
/// v74.2: Decomposed into BaseSystemPrompt, UserContextBuilder, ToolInstructions, FitnessWarnings, ResponseGuidelines
/// v96.0: Added flywheel data (1RMs, completion rates), prompt tiering, core rules
struct SystemPrompts {

    /// Generate fitness assistant system prompt (full tier - legacy)
    /// - Parameter user: The user to generate prompt for
    /// - Returns: System prompt string
    static func fitnessAssistant(for user: UnifiedUser) -> String {
        // Default to full tier for backwards compatibility
        return fitnessAssistant(for: user, message: nil)
    }

    /// Generate fitness assistant system prompt with tier detection
    /// - Parameters:
    ///   - user: The user to generate prompt for
    ///   - message: The user's message (for tier detection)
    /// - Returns: System prompt string optimized for the request complexity
    static func fitnessAssistant(for user: UnifiedUser, message: String?) -> String {
        let currentDate = String(ISO8601DateFormatter().string(from: Date()).prefix(10))

        // Detect prompt tier based on message complexity
        let tier = message.map { TierDetector.detect(message: $0, user: user) } ?? .full
        let config = PromptTierConfiguration(tier: tier)

        // Build user context sections (always included)
        let userInfo = UserContextBuilder.buildUserInfo(for: user)
        let profileInfo = UserContextBuilder.buildProfileInfo(for: user)
        let currentContext = UserContextBuilder.buildCurrentContext(for: user)

        // v96.0: Flywheel training data (strength baselines, exercise affinity)
        let trainingData = config.includeTrainingData
            ? TrainingDataContextBuilder.buildAllFlyweelData(for: user.id)
            : ""

        // Conditional sections based on tier
        let trainerContext = config.includeTrainerContext
            ? TrainerContextBuilder.buildTrainerContext(for: user)
            : ""

        let activePlanContext = config.includePlanRules
            ? UserContextBuilder.buildActivePlanContext(for: user)
            : ""

        // v81.0: AI-first exercise context with preferences
        // v96.0: Compact mode for standard tier
        let exerciseContext = config.includeExerciseContext
            ? ExerciseContextBuilder.buildExerciseContext(
                for: user,
                trainingLocation: user.memberProfile?.trainingLocation,
                compact: config.useCompactExerciseFormat
            )
            : ""

        // Build prompt based on tier
        switch tier {
        case .lightweight:
            return buildLightweightPrompt(
                userInfo: userInfo,
                profileInfo: profileInfo,
                currentContext: currentContext,
                currentDate: currentDate
            )

        case .standard:
            return buildStandardPrompt(
                userInfo: userInfo,
                profileInfo: profileInfo,
                currentContext: currentContext,
                trainingData: trainingData,
                exerciseContext: exerciseContext,
                currentDate: currentDate
            )

        case .full:
            return buildFullPrompt(
                userInfo: userInfo,
                profileInfo: profileInfo,
                trainerContext: trainerContext,
                currentContext: currentContext,
                activePlanContext: activePlanContext,
                trainingData: trainingData,
                exerciseContext: exerciseContext,
                currentDate: currentDate
            )
        }
    }

    // MARK: - Tiered Prompt Builders

    /// Lightweight prompt (~1,500 tokens) for simple queries
    /// v111: Added missed workout handling guideline
    private static func buildLightweightPrompt(
        userInfo: String,
        profileInfo: String,
        currentContext: String,
        currentDate: String
    ) -> String {
        """
        \(BaseSystemPrompt.build())

        \(userInfo)\(profileInfo)

        \(CoreRules.offTopic)

        \(ResponseGuidelines.actionOrientedEndings)

        \(ResponseGuidelines.missedWorkoutHandling)

        \(currentContext)

        \(BaseSystemPrompt.currentLimitations)
        """
    }

    /// Standard prompt (~4,000 tokens) for workout creation
    /// v102.4: Added workoutImageCreation guideline for image-based workout creation
    /// v104: Added age-aware programming and AI transparency guidelines
    /// v110: Added action-oriented endings
    /// v111: Added missed workout handling guideline
    /// v111.1: Added class name accuracy guideline
    private static func buildStandardPrompt(
        userInfo: String,
        profileInfo: String,
        currentContext: String,
        trainingData: String,
        exerciseContext: String,
        currentDate: String
    ) -> String {
        """
        \(BaseSystemPrompt.build())

        \(userInfo)\(profileInfo)

        \(trainingData)

        \(CoreRules.offTopic)

        \(ResponseGuidelines.actionOrientedEndings)

        \(ResponseGuidelines.missedWorkoutHandling)

        \(ResponseGuidelines.classNameAccuracy)

        \(currentContext)

        \(CoreRules.confirmation)

        \(ResponseGuidelines.workoutImageCreation)

        \(ResponseGuidelines.ageAwareProgramming)

        \(ResponseGuidelines.aiTransparencyGuidelines)

        \(CoreRules.profileAware)

        \(CoreRules.experienceDefaults)

        \(CoreRules.equipment)

        \(ToolInstructions.build())

        \(CoreRules.workoutExamples)

        \(FitnessWarnings.timelineCalculation(currentDate: currentDate))

        \(exerciseContext)

        \(BaseSystemPrompt.currentLimitations)
        """
    }

    /// Full prompt (~8,000 tokens) for plan creation and trainer mode
    /// v104: Added age-aware programming and AI transparency guidelines
    /// v110: Added action-oriented endings
    /// v111: Added missed workout handling guideline
    /// v111.1: Added class name accuracy guideline
    private static func buildFullPrompt(
        userInfo: String,
        profileInfo: String,
        trainerContext: String,
        currentContext: String,
        activePlanContext: String,
        trainingData: String,
        exerciseContext: String,
        currentDate: String
    ) -> String {
        """
        \(BaseSystemPrompt.build())

        \(userInfo)\(profileInfo)

        \(trainingData)

        \(trainerContext)

        \(ResponseGuidelines.offTopicHandling)

        \(ResponseGuidelines.actionOrientedEndings)

        \(ResponseGuidelines.missedWorkoutHandling)

        \(ResponseGuidelines.classNameAccuracy)

        \(currentContext)

        \(activePlanContext)

        \(BaseSystemPrompt.importantGuidelines)

        \(FitnessWarnings.timelineCalculation(currentDate: currentDate))

        \(FitnessWarnings.allWarnings)

        \(ResponseGuidelines.conversationalOnboarding)

        \(ResponseGuidelines.noTextBasedPlans)

        \(ResponseGuidelines.profileAwareBehavior)

        \(ResponseGuidelines.confirmationBehavior)

        \(ToolInstructions.build())

        \(ResponseGuidelines.voiceFirstProtocol)

        \(ResponseGuidelines.workoutCreationGuidelines)

        \(ResponseGuidelines.protocolCustomizationGuidelines)

        \(ResponseGuidelines.mutuallyExclusiveTools)

        \(ResponseGuidelines.transparentAssumptions)

        \(ResponseGuidelines.protocolExperienceDefaults)

        \(ResponseGuidelines.imageTargetExtraction)

        \(ResponseGuidelines.workoutImageCreation)

        \(ResponseGuidelines.ageAwareProgramming)

        \(ResponseGuidelines.aiTransparencyGuidelines)

        \(exerciseContext)

        \(BaseSystemPrompt.currentLimitations)
        """
    }

    /// Generate workout creation system prompt (v59.6+)
    /// v59.1: Not implemented yet, placeholder for future use
    static func workoutCreation(for user: UnifiedUser, context: String) -> String {
        return """
        [Workout creation prompts will be added in v59.6]

        For now, use the basic fitness assistant prompt.
        """
    }

    /// Generate proactive coaching prompt (v60.0+)
    /// v59.1: Not implemented yet, placeholder for future use
    static func proactiveCoach(for user: UnifiedUser, analysis: String) -> String {
        return """
        [Proactive coaching prompts will be added in v60.0+]

        For now, use the basic fitness assistant prompt.
        """
    }
}
