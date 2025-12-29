//
// TrainerContextBuilder.swift
// Medina
//
// v90.0: Trainer Mode - AI context for trainers
// Provides member roster and trainer-specific instructions
// v92.0: Single confirmation pattern for plan creation
// v93.0: Added send_message tool instructions
//

import Foundation

/// Builds trainer-specific context sections for system prompts
struct TrainerContextBuilder {

    /// Build complete trainer context section
    /// Returns empty string if user is not a trainer
    static func buildTrainerContext(for user: UnifiedUser) -> String {
        guard user.hasRole(.trainer) else { return "" }

        var sections: [String] = []

        sections.append(buildMemberRosterSection(trainerId: user.id))
        sections.append(buildTrainerInstructions())

        return sections.joined(separator: "\n")
    }

    // MARK: - Member Roster

    /// Build section listing all assigned members with their status
    private static func buildMemberRosterSection(trainerId: String) -> String {
        let members = UserDataStore.members(assignedToTrainer: trainerId)

        if members.isEmpty {
            return """

            ## Trainer Mode - Member Roster
            No members currently assigned. New members can be assigned through the gym admin.
            """
        }

        var output = """

        ## Trainer Mode - Member Roster
        You are a trainer with \(members.count) assigned member(s). Use these member IDs when creating plans or querying member data.

        **Your Members:**
        """

        for member in members {
            let activePlan = PlanResolver.activePlan(for: member.id)
            let planStatus = activePlan != nil ? "Active plan: \(activePlan!.name)" : "No active plan"

            output += "\n- **\(member.name)** (ID: `\(member.id)`)"

            // v100.2: Include full profile so AI doesn't need to ask
            if let profile = member.memberProfile {
                output += "\n  - Experience: \(profile.experienceLevel.displayName)"
                output += "\n  - Goal: \(profile.fitnessGoal.displayName)"
                output += "\n  - Duration: \(profile.preferredSessionDuration) min"

                if let days = profile.preferredWorkoutDays, !days.isEmpty {
                    let dayNames = days.sorted { $0.rawValue < $1.rawValue }.map { $0.shortName }.joined(separator: ", ")
                    output += "\n  - Schedule: \(dayNames) (\(days.count) days/week)"
                }
            } else {
                output += "\n  - Profile: Not set up"
            }

            output += "\n  - Status: \(planStatus)"
        }

        return output
    }

    // MARK: - Trainer Instructions

    /// Build trainer-specific tool usage instructions
    private static func buildTrainerInstructions() -> String {
        return """

        ## Trainer Mode - Special Instructions

        ### CRITICAL: Selected Member Behavior (v100.2)
        Check for "Currently Selected Member" section above.

        **IF a member IS selected:**
        - ✅ "Create a plan" → Proceed with selected member (don't ask which)
        - ✅ "Send a message" → Send to selected member (don't ask which)
        - ✅ Use their profile data for defaults (don't ask for info)

        **IF NO member selected:**
        - Ask which member before proceeding

        ### Creating Plans for Members
        When creating plans for a member:
        1. Use `forMemberId` parameter with the member's ID
        2. The plan will be accessible to both you and the member

        **USE MEMBER PROFILE DATA - DON'T ASK FOR IT:**
        The Member Roster above shows each member's full profile (experience, goal, duration, schedule).
        - ✅ USE this data as defaults when creating plans
        - ❌ DON'T ask for information already shown in the roster
        - Trainer can override defaults if they provide new values

        **IMPORTANT - Confirmation Required Before Creating:**
        When trainer requests a plan for a member:
        1. Present ONE summary using the member's profile data from the roster
        2. Ask "Should I create a plan with these settings?" and STOP
        3. WAIT for explicit user confirmation (e.g., "Yes", "Go ahead", "Create it")
        4. Only call create_plan AFTER user confirms

        Do NOT call create_plan in the same response as presenting the profile. Present → Wait → Create.

        ### Available Trainer Tools
        - `get_my_members` - Get list of your assigned members with status
        - `get_member_progress` - Get detailed progress for a specific member
        - `create_plan` with `forMemberId` - Create a plan for a member
        - `send_message` - Send a message to a member (encouragement, updates, reminders)

        ### Sending Messages to Members
        When trainer wants to communicate with a member:
        - "Send Bobby a message saying great job" → `send_message(recipientId: "bobby_tulsiani", content: "Great job!", messageType: "encouragement")`
        - "Remind Sarah about leg day tomorrow" → `send_message(recipientId: "...", content: "...", messageType: "reminder")`
        - "Tell Alex his new plan is ready" → `send_message(recipientId: "...", content: "...", messageType: "planUpdate")`

        Message types: encouragement, planUpdate, checkIn, reminder, general
        The message appears in the member's Messages folder in their sidebar.

        ### Natural Language Examples
        - "Create plan for Bobby" → Resolve Bobby from roster, use forMemberId
        - "Which members are falling behind?" → Use get_my_members(status: "behind")
        - "Show Bobby's progress" → Use get_member_progress(memberId: "bobby_tulsiani")
        - "Send Bobby a message about his PR" → Use send_message with encouragement type
        """
    }

    // MARK: - Selected Member Context

    /// Build context for the currently selected member (if any)
    /// Used when trainer has a specific member selected in the picker
    static func buildSelectedMemberContext(memberId: String?, for user: UnifiedUser) -> String {
        guard user.hasRole(.trainer), let selectedId = memberId else { return "" }

        guard let member = TestDataManager.shared.users[selectedId] else {
            return """

            ## Selected Member
            ⚠️ Selected member not found. Please select a valid member from the picker.
            """
        }

        // Verify trainer has access to this member
        guard member.memberProfile?.trainerId == user.id else {
            return """

            ## Selected Member
            ⚠️ You do not have access to this member. Please select one of your assigned members.
            """
        }

        var output = """

        ## Currently Selected Member: \(member.name)
        ⚠️ USE THIS MEMBER FOR ALL OPERATIONS - do NOT ask which member.

        When trainer says:
        - "Create a plan" → Create for \(member.firstName) (don't ask which member)
        - "Send a message" → Send to \(member.firstName) (don't ask which member)
        - "Show progress" → Show \(member.firstName)'s progress

        **Member Profile:**
        """

        if let profile = member.memberProfile {
            output += "\n- Experience: \(profile.experienceLevel.displayName)"
            output += "\n- Goal: \(profile.fitnessGoal.displayName)"
            output += "\n- Preferred Duration: \(profile.preferredSessionDuration) min"

            if let days = profile.preferredWorkoutDays, !days.isEmpty {
                let dayNames = days.sorted { $0.rawValue < $1.rawValue }.map { $0.shortName }.joined(separator: ", ")
                output += "\n- Schedule: \(dayNames)"
            }

            if let emphasized = profile.emphasizedMuscleGroups, !emphasized.isEmpty {
                output += "\n- Muscle Focus: \(emphasized.map { $0.displayName }.joined(separator: ", "))"
            }
        }

        // Add active plan info
        if let plan = PlanResolver.activePlan(for: selectedId) {
            output += "\n\n**Active Plan:** \(plan.name)"
            output += "\n- Goal: \(plan.goal.displayName)"
            output += "\n- Structure: \(plan.splitType.displayName), \(plan.weightliftingDays)x/week"

            let workouts = WorkoutDataStore.workouts(forPlanId: plan.id)
            let completed = workouts.filter { $0.status == .completed }.count
            output += "\n- Progress: \(completed)/\(workouts.count) workouts completed"
        } else {
            output += "\n\n**No active plan.** Consider creating a plan for this member."
        }

        // v92.0: Explicit instruction for forMemberId usage
        output += """


        **IMPORTANT:** When creating plans or workouts for \(member.firstName), use:
        - `forMemberId: "\(selectedId)"` in create_plan
        This ensures the content is created for \(member.firstName), not for you.
        """

        return output
    }
}
