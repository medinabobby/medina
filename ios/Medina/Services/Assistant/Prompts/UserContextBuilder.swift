//
//  UserContextBuilder.swift
//  Medina
//
//  v74.2: Extracted from SystemPrompts.swift
//  v79.6: Added buildActivePlanContext() for AI plan awareness
//  v111: Added missed workout backlog context for smart scheduling
//  v137: Fixed buildTodayContext to filter by active plan only
//  v144: Added "Next Scheduled Workout" context to prevent AI ID fabrication
//  v157: Added active session context + "no workout in progress" handling
//  Created: December 1, 2025
//
//  Builds user-specific context sections for system prompts

import Foundation

/// Builds user profile and context sections
struct UserContextBuilder {

    /// Build user information section
    static func buildUserInfo(for user: UnifiedUser) -> String {
        let name = user.name
        // v65.2: Handle optional birthdate - don't assume age if unknown
        let ageInfo: String
        if let birthdate = user.birthdate {
            let ageYears = Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year ?? 0
            ageInfo = "\(ageYears)"
        } else {
            ageInfo = "unknown"
        }
        let gender = user.gender.displayName

        return """
        ## User Information
        - Name: \(name)
        - Age: \(ageInfo)
        - Gender: \(gender)
        """
    }

    /// Build member profile section if available
    static func buildProfileInfo(for user: UnifiedUser) -> String {
        guard let profile = user.memberProfile else { return "" }

        let experienceLevel = profile.experienceLevel.rawValue.capitalized
        let goal = profile.fitnessGoal.displayName

        var profileInfo = """

        ## User Profile
        - Experience Level: \(experienceLevel)
        - Primary Goal: \(goal)
        - Session Duration: \(profile.preferredSessionDuration) minutes
        """

        // Add training location if set
        if let location = profile.trainingLocation {
            profileInfo += "\n- Training Location: \(location.displayName)"
        }

        // v80.3: Add home equipment if set (critical for home workout creation)
        // v83.5: Clarified - only ask about equipment for explicitly requested home workouts
        if let homeEquipment = profile.availableEquipment, !homeEquipment.isEmpty {
            let equipmentNames = homeEquipment.map { $0.displayName }.joined(separator: ", ")
            profileInfo += "\n- Home Equipment: \(equipmentNames)"
        } else {
            profileInfo += "\n- Home Equipment: Not configured (only ask if user EXPLICITLY requests home workout - assume gym by default)"
        }

        // Add workout schedule if set
        if let workoutDays = profile.preferredWorkoutDays, !workoutDays.isEmpty {
            let days = workoutDays.sorted(by: { $0.rawValue < $1.rawValue }).map { $0.displayName }.joined(separator: ", ")
            profileInfo += "\n- Weekly Schedule: \(days)"
        }

        // Add muscle focus if set
        if let emphasized = profile.emphasizedMuscleGroups, !emphasized.isEmpty {
            let muscles = emphasized.map { $0.displayName }.joined(separator: ", ")
            profileInfo += "\n- Muscle Focus: Emphasize \(muscles)"
        }

        if let excluded = profile.excludedMuscleGroups, !excluded.isEmpty {
            let muscles = excluded.map { $0.displayName }.joined(separator: ", ")
            profileInfo += "\n- Avoid: \(muscles)"
        }

        // v65.2: Add weight context if set
        if let currentWeight = profile.currentWeight {
            profileInfo += "\n- Current Weight: \(Int(currentWeight)) lbs"
        }
        if let goalWeight = profile.goalWeight {
            profileInfo += "\n- Goal Weight: \(Int(goalWeight)) lbs"
        }

        // v65.2: Add personal motivation ("Your Why") for AI personalization
        if let motivation = profile.personalMotivation, !motivation.isEmpty {
            profileInfo += "\n- Personal Motivation: \"\(motivation)\""
        }

        // v182: trainingStyle removed - feature removed for beta simplicity
        // v106.2: Removed verbosity from AI context - AI adapts to context naturally

        return profileInfo
    }

    /// Build current context section with date and recent workouts
    /// v111: Added missed workout backlog and intensity recommendation for smart scheduling
    /// v186: Removed class credits context (deferred for beta)
    static func buildCurrentContext(for user: UnifiedUser) -> String {
        let recentWorkoutsInfo = buildRecentWorkouts(for: user)
        let todayContext = buildTodayContext(for: user)
        let missedWorkoutsContext = buildMissedWorkoutsContext(for: user)
        let intensityContext = buildIntensityRecommendationContext(for: user)

        return """
        ## Current Context
        - Today's date: \(ISO8601DateFormatter().string(from: Date()).prefix(10))
        \(todayContext)\(missedWorkoutsContext)\(intensityContext)\(recentWorkoutsInfo)
        """
    }

    // MARK: - v110: Today's Schedule Context

    /// Build context about today's scheduled activities
    private static func buildTodayContext(for user: UnifiedUser) -> String {
        var lines: [String] = []

        // Check for today's workout
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let todayInterval = DateInterval(start: today, end: tomorrow)

        // v137: Only show "Today's Workout" if there's an active plan
        // Fixes bug where AI would pick draft plan workout over active plan workout
        // When no active plan exists, don't show any scheduled workouts
        if let activePlan = PlanResolver.activePlan(for: user.id) {
            let todaysWorkouts = WorkoutDataStore.workouts(
                for: user.id,
                temporal: .upcoming,
                status: .scheduled,
                plan: activePlan,
                dateInterval: todayInterval
            )

            if let workout = todaysWorkouts.first {
                // v120.1: Add action directive for AI to call start_workout immediately
                lines.append("- Today's Workout: \(workout.name) (ID: \(workout.id))")
                lines.append("  → If user says \"start my workout\", call start_workout(workoutId: \"\(workout.id)\")")
            } else {
                // v144: Add "Next Scheduled Workout" when no workout today
                // This prevents AI from fabricating IDs when user says "start my workout"
                let futureWorkouts = WorkoutDataStore.workouts(
                    for: user.id,
                    temporal: .upcoming,
                    status: .scheduled,
                    plan: activePlan,
                    dateInterval: nil  // All future
                ).sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }

                if let nextWorkout = futureWorkouts.first, let nextDate = nextWorkout.scheduledDate {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "EEEE, MMM d"
                    let dateStr = dateFormatter.string(from: nextDate)
                    lines.append("- Next Scheduled Workout: \(nextWorkout.name) on \(dateStr) (ID: \(nextWorkout.id))")
                    lines.append("  → No workout today. User can start this early or wait.")
                }
            }
        }

        // v157: Check for active session FIRST (in-memory), then fall back to .inProgress status
        // This provides accurate context for "continue workout" requests
        var hasActiveWorkout = false

        if let activeSession = TestDataManager.shared.activeSession(for: user.id),
           let activeWorkout = TestDataManager.shared.workouts[activeSession.workoutId] {
            // Active session exists - show workout details
            let instances = InstanceDataStore.instances(forWorkout: activeWorkout.id)
            let completed = instances.filter { $0.status == .completed }.count
            lines.append("- 🏋️ ACTIVE SESSION: \(activeWorkout.name) (ID: \(activeWorkout.id))")
            lines.append("  → Progress: \(completed)/\(instances.count) exercises done")
            lines.append("  → If user says \"continue\", call start_workout(workoutId: \"\(activeWorkout.id)\")")
            hasActiveWorkout = true
        } else {
            // No active session - check for .inProgress workout status (persistence fallback)
            let allWorkouts = WorkoutDataStore.workouts(for: user.id, temporal: .unspecified, dateInterval: nil)
            if let inProgress = allWorkouts.first(where: { $0.status == .inProgress }) {
                let instances = InstanceDataStore.instances(forWorkout: inProgress.id)
                let completed = instances.filter { $0.status == .completed }.count
                lines.append("- In Progress: \(inProgress.name) (\(completed)/\(instances.count) exercises done)")
                hasActiveWorkout = true
            }
        }

        // v157: Explicit "no workout in progress" context to prevent AI from guessing IDs
        if !hasActiveWorkout {
            lines.append("- ⚠️ NO WORKOUT IN PROGRESS")
            lines.append("  → If user says \"continue workout\", explain there's nothing to continue")
            lines.append("  → DO NOT call start_workout with a guessed ID - respond with text instead")
        }

        if lines.isEmpty {
            return ""
        }

        return "\n" + lines.joined(separator: "\n")
    }

    // MARK: - v111: Missed Workouts Context

    /// Build context about missed workouts (scheduled but past due)
    /// This allows AI to ask user which workout they want to do when there's a backlog
    /// v142: Only include workouts from ACTIVE plan (not draft plans)
    private static func buildMissedWorkoutsContext(for user: UnifiedUser) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // v142: Only show missed workouts from active plan
        // Without this filter, AI could pick workouts from draft plans
        guard let activePlan = PlanResolver.activePlan(for: user.id) else {
            return ""  // No active plan = no missed workouts to show
        }

        // Get scheduled workouts from the past (missed)
        // Look back 14 days max to avoid overwhelming context
        guard let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: today) else {
            return ""
        }

        let missedInterval = DateInterval(start: twoWeeksAgo, end: today)
        let missedWorkouts = WorkoutDataStore.workouts(
            for: user.id,
            temporal: .past,
            plan: activePlan,  // v142: Filter by active plan only
            dateInterval: missedInterval
        ).filter { $0.status == .scheduled }
            .sorted { ($0.scheduledDate ?? .distantPast) < ($1.scheduledDate ?? .distantPast) }

        if missedWorkouts.isEmpty {
            return ""
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMM d"

        var lines: [String] = []
        lines.append("")
        lines.append("## ⚠️ Missed Workouts (Backlog)")
        lines.append("User has \(missedWorkouts.count) workout(s) still marked as 'scheduled' from past dates:")

        for workout in missedWorkouts.prefix(5) {
            let dateStr: String
            if let date = workout.scheduledDate {
                dateStr = dateFormatter.string(from: date)
            } else {
                dateStr = "Unknown date"
            }
            let splitInfo = workout.splitDay?.displayName ?? "Workout"
            lines.append("- \(dateStr): \(workout.name) (\(splitInfo)) - ID: \(workout.id)")
        }

        if missedWorkouts.count > 5 {
            lines.append("- ... and \(missedWorkouts.count - 5) more")
        }

        lines.append("")
        lines.append("**AI BEHAVIOR for missed workouts:**")
        lines.append("- If user says 'start my workout' and there IS a scheduled workout today → start TODAY's workout")
        lines.append("- Only mention missed workouts if user specifically asks about them")
        lines.append("- DO NOT block 'start my workout' by asking about missed workouts")

        return lines.joined(separator: "\n")
    }

    // MARK: - v111: Intensity Recommendation Context

    /// Build context about intensity recommendation based on workout completion
    /// This allows AI to recommend staying at previous intensity if user missed workouts
    private static func buildIntensityRecommendationContext(for user: UnifiedUser) -> String {
        // Get active plan and current program
        guard let plan = PlanResolver.activePlan(for: user.id) else {
            return ""
        }

        let programs = ProgramDataStore.programs(for: plan.id)
        let now = Date()
        guard let currentProgram = programs.first(where: { $0.startDate <= now && $0.endDate >= now }) else {
            return ""
        }

        // Get recommendation
        let recommendation = IntensityRecommendationService.calculateRecommendation(
            program: currentProgram,
            memberId: user.id
        )

        // Only show if there's an adjustment
        guard recommendation.hasAdjustment else {
            return ""
        }

        var lines: [String] = []
        lines.append("")
        lines.append("## Intensity Recommendation")
        lines.append("- Scheduled Intensity: \(recommendation.originalPercentage)")
        lines.append("- Recommended Intensity: \(recommendation.suggestedPercentage)")
        lines.append("- Reason: \(recommendation.reason)")
        lines.append("")
        lines.append("**AI BEHAVIOR**: When user starts a workout:")
        lines.append("1. MENTION the intensity recommendation: 'Based on your recent schedule, I'd recommend staying at \(recommendation.suggestedPercentage) instead of jumping to \(recommendation.originalPercentage).'")
        lines.append("2. ASK if they want to use the recommended intensity or the scheduled intensity")
        lines.append("3. User decides - don't auto-apply the recommendation")

        return lines.joined(separator: "\n")
    }

    /// v62.1: Build recent workouts context for get_summary tool
    /// AI needs this to resolve natural language queries like "Monday workout" to correct workout IDs
    /// v142: Only include workouts from ACTIVE plan (not draft plans)
    private static func buildRecentWorkouts(for user: UnifiedUser) -> String {
        // v142: Only show recent workouts from active plan
        // Without this filter, AI could reference workouts from draft plans
        guard let activePlan = PlanResolver.activePlan(for: user.id) else {
            return ""  // No active plan = no recent workouts to show
        }

        // Get workouts from last 14 days for this user
        guard let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) else {
            return ""
        }

        // Use WorkoutDataStore to get workouts for this member (via program/plan hierarchy)
        // Get all workouts and filter by date range
        let allUserWorkouts = WorkoutDataStore.workouts(
            for: user.id,
            temporal: .unspecified,  // All times
            plan: activePlan,  // v142: Filter by active plan only
            dateInterval: DateInterval(start: twoWeeksAgo, end: Date())
        )
        let recentWorkouts = allUserWorkouts
            .sorted { ($0.scheduledDate ?? Date()) > ($1.scheduledDate ?? Date()) }

        // If no recent workouts, return empty
        if recentWorkouts.isEmpty {
            return """

        ## Recent Workouts
        No workouts in the last 14 days.
        """
        }

        // Format for AI context
        var output = """

        ## Recent Workouts (for get_summary tool)
        When user asks about a workout (e.g., "Monday workout", "yesterday's workout"), use this list to find the correct workout ID.

        """

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMM d"

        for workout in recentWorkouts.prefix(10) {
            let dateStr: String
            if let date = workout.scheduledDate {
                dateStr = dateFormatter.string(from: date)
            } else {
                dateStr = "Unknown date"
            }
            let statusStr = workout.status.displayName
            output += "- **\(workout.id)**: \(workout.name) - \(dateStr) (\(statusStr))\n"
        }

        return output
    }

    /// Build exercise library section for system prompt
    /// v59.6.2: Critical fix - AI needs to know which exercise IDs exist
    static func buildExerciseLibrary(for user: UnifiedUser) -> String {
        // Get user's library (try to load, fall back to seed library)
        var userLibrary: UserLibrary?
        do {
            userLibrary = try LibraryPersistenceService.load(userId: user.id)
            if userLibrary == nil {
                // No saved library, use seed library
                userLibrary = try LibraryPersistenceService.loadSeedLibrary()
            }
        } catch {
            Logger.log(.error, component: "UserContextBuilder",
                      message: "Failed to load library for user \(user.id): \(error)")
            // Return empty section if we can't load library
            return """

            ### 3a. Available Exercises
            **ERROR:** Could not load exercise library. Please try again.
            """
        }

        guard let library = userLibrary else {
            return """

            ### 3a. Available Exercises
            **ERROR:** No exercise library found.
            """
        }

        // Get full exercise objects from TestDataManager
        let exerciseLibrary = TestDataManager.shared.exercises
        var compoundExercises: [(id: String, name: String, muscles: String)] = []
        var isolationExercises: [(id: String, name: String, muscles: String)] = []

        for exerciseId in library.exercises {
            guard let exercise = exerciseLibrary[exerciseId] else {
                Logger.log(.warning, component: "UserContextBuilder",
                          message: "Exercise ID '\(exerciseId)' in library but not found in database")
                continue
            }

            let muscleNames = exercise.muscleGroups.map { $0.displayName }.joined(separator: ", ")
            let entry = (id: exerciseId, name: exercise.name, muscles: muscleNames)

            if exercise.type == .compound {
                compoundExercises.append(entry)
            } else if exercise.type == .isolation {
                isolationExercises.append(entry)
            }
        }

        // Sort alphabetically by name
        compoundExercises.sort { $0.name < $1.name }
        isolationExercises.sort { $0.name < $1.name }

        // Build formatted output
        var output = """

        ### 3a. Available Exercises (CRITICAL)
        **You MUST ONLY use exercise IDs from this list.** Using any other exercise ID will cause validation errors.

        **Compound Exercises (use for main movements):**
        """

        for exercise in compoundExercises {
            output += "\n- **\(exercise.id)** - \(exercise.name) (\(exercise.muscles))"
        }

        output += """


        **Isolation Exercises (use for accessory work):**
        """

        for exercise in isolationExercises {
            output += "\n- **\(exercise.id)** - \(exercise.name) (\(exercise.muscles))"
        }

        output += """


        **Selection Strategy:**
        - Match exercises to split day muscle targets
        - Favor compounds for main work, isolations for accessories
        - Check muscle groups to match user's emphasized/avoided preferences
        - Total exercises: \(library.exercises.count) available
        """

        return output
    }

    // MARK: - v79.6: Active Plan Context

    /// Build active plan context section for AI awareness
    /// This allows the AI to know about the user's current plan and schedule status
    static func buildActivePlanContext(for user: UnifiedUser) -> String {
        // Check if user has an active plan
        guard let plan = PlanResolver.activePlan(for: user.id) else {
            return """

            ## Active Plan
            No active training plan. User may want to create a new plan or activate a draft.
            """
        }

        var lines: [String] = []
        lines.append("")
        lines.append("## Active Plan")
        lines.append("- Plan ID: `\(plan.id)` (use this for get_summary with scope='plan')")
        lines.append("- Plan Name: \(plan.name)")
        lines.append("- Status: \(plan.effectiveStatus.displayName)")
        lines.append("- Goal: \(plan.goal.displayName)")

        // Training structure
        let totalDays = plan.weightliftingDays + plan.cardioDays
        lines.append("- Structure: \(plan.splitType.displayName), \(totalDays) days/week, \(plan.targetSessionDuration) min sessions")

        // Preferred days
        if !plan.preferredDays.isEmpty {
            let days = plan.preferredDays.sorted { $0.rawValue < $1.rawValue }.map { $0.displayName }.joined(separator: ", ")
            lines.append("- Workout Days: \(days)")
        }

        // Date range
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"
        lines.append("- Start Date: \(dateFormatter.string(from: plan.startDate))")
        lines.append("- End Date: \(dateFormatter.string(from: plan.endDate))")

        // Get current program
        let programs = ProgramDataStore.programs(for: plan.id)
        let now = Date()
        if let currentProgram = programs.first(where: { $0.startDate <= now && $0.endDate >= now }) {
            lines.append("- Current Program: \(currentProgram.name) (ID: `\(currentProgram.id)`)")
        } else if let firstProgram = programs.first {
            lines.append("- Program: \(firstProgram.name) (ID: `\(firstProgram.id)`)")
        }

        // Get workout counts
        let allWorkouts = WorkoutDataStore.workouts(forPlanId: plan.id)
        let completedCount = allWorkouts.filter { $0.status == .completed }.count
        let totalCount = allWorkouts.count
        lines.append("- Workout Progress: \(completedCount)/\(totalCount) completed")

        // Schedule analysis
        let analysis = PlanScheduleAnalyzer.analyze(plan: plan, memberId: user.id)

        if analysis.isBehindSchedule {
            lines.append("")
            lines.append("⚠️ SCHEDULE STATUS: \(analysis.statusSummary)")
            lines.append("- Missed workouts: \(analysis.missedWorkouts)")
            lines.append("- Days behind: \(analysis.daysBehind)")

            if !analysis.suggestedActions.isEmpty {
                let actionNames = analysis.suggestedActions.prefix(3).map { $0.shortName }.joined(separator: ", ")
                lines.append("- Suggested actions: \(actionNames)")
            }

            lines.append("")
            lines.append("**IMPORTANT**: User is behind on their plan. Proactively acknowledge this and offer to help them get back on track. Suggest rescheduling, creating a new plan, or continuing from the next workout.")
        } else if analysis.completedWorkouts == 0 && totalCount > 0 {
            lines.append("")
            lines.append("📋 SCHEDULE STATUS: Ready to start")
            lines.append("- No workouts completed yet")
            lines.append("- Encourage user to begin their first workout")
        } else {
            lines.append("")
            lines.append("✅ SCHEDULE STATUS: On track")
        }

        return lines.joined(separator: "\n")
    }
}
