/**
 * Trainer Context Builder
 *
 * v2: Migrated from iOS TrainerContextBuilder.swift
 * Builds trainer-specific context including member roster and instructions
 */

export interface MemberInfo {
  id: string;
  name: string;
  firstName: string;
  experienceLevel?: string;
  fitnessGoal?: string;
  sessionDuration?: number;
  schedule?: string[];
  activePlan?: string;
  emphasizedMuscles?: string[];
}

export interface SelectedMember extends MemberInfo {
  planProgress?: {
    planName: string;
    goal: string;
    structure: string;
    completedWorkouts: number;
    totalWorkouts: number;
  };
}

/**
 * Check if user is a trainer
 */
export function isTrainer(roles?: string[]): boolean {
  return roles?.includes('trainer') ?? false;
}

/**
 * Build trainer mode context
 */
export function buildTrainerContext(
  members: MemberInfo[],
  selectedMember?: SelectedMember
): string {
  const sections: string[] = [];

  sections.push(buildMemberRosterSection(members));
  sections.push(buildTrainerInstructions());

  if (selectedMember) {
    sections.push(buildSelectedMemberContext(selectedMember));
  }

  return sections.filter(s => s.length > 0).join('\n');
}

/**
 * Build member roster section
 */
function buildMemberRosterSection(members: MemberInfo[]): string {
  if (!members || members.length === 0) {
    return `
## Trainer Mode - Member Roster
No members currently assigned. New members can be assigned through the gym admin.`;
  }

  let output = `
## Trainer Mode - Member Roster
You are a trainer with ${members.length} assigned member(s). Use these member IDs when creating plans.

**Your Members:**`;

  for (const member of members) {
    output += `\n- **${member.name}** (ID: \`${member.id}\`)`;

    if (member.experienceLevel) {
      output += `\n  - Experience: ${capitalize(member.experienceLevel)}`;
    }
    if (member.fitnessGoal) {
      output += `\n  - Goal: ${formatGoal(member.fitnessGoal)}`;
    }
    if (member.sessionDuration) {
      output += `\n  - Duration: ${member.sessionDuration} min`;
    }
    if (member.schedule && member.schedule.length > 0) {
      output += `\n  - Schedule: ${member.schedule.join(', ')} (${member.schedule.length} days/week)`;
    }

    const planStatus = member.activePlan
      ? `Active plan: ${member.activePlan}`
      : 'No active plan';
    output += `\n  - Status: ${planStatus}`;
  }

  return output;
}

/**
 * Build trainer-specific instructions
 */
function buildTrainerInstructions(): string {
  return `
## Trainer Mode - Special Instructions

### Selected Member Behavior
Check for "Currently Selected Member" section above.

**IF a member IS selected:**
- "Create a plan" -> Proceed with selected member (don't ask which)
- "Send a message" -> Send to selected member (don't ask which)
- Use their profile data for defaults (don't ask for info)

**IF NO member selected:**
- Ask which member before proceeding

### Creating Plans for Members
When creating plans for a member:
1. Use \`forMemberId\` parameter with the member's ID
2. The plan will be accessible to both you and the member

**USE MEMBER PROFILE DATA - DON'T ASK FOR IT:**
The Member Roster above shows each member's full profile.
- USE this data as defaults when creating plans
- DON'T ask for information already shown in the roster
- Trainer can override defaults if they provide new values

**IMPORTANT - Confirmation Required:**
1. Present ONE summary using member's profile data from roster
2. Ask "Should I create a plan with these settings?" and STOP
3. WAIT for explicit user confirmation
4. Only call create_plan AFTER user confirms

### Available Trainer Tools
- \`get_my_members\` - Get list of your assigned members
- \`get_member_progress\` - Get detailed progress for a member
- \`create_plan\` with \`forMemberId\` - Create a plan for a member
- \`send_message\` - Send a message to a member

### Sending Messages to Members
Message types: encouragement, planUpdate, checkIn, reminder, general
The message appears in the member's Messages folder.`;
}

/**
 * Build context for currently selected member
 */
function buildSelectedMemberContext(member: SelectedMember): string {
  let output = `
## Currently Selected Member: ${member.name}
USE THIS MEMBER FOR ALL OPERATIONS - do NOT ask which member.

When trainer says:
- "Create a plan" -> Create for ${member.firstName} (don't ask which member)
- "Send a message" -> Send to ${member.firstName} (don't ask which member)
- "Show progress" -> Show ${member.firstName}'s progress

**Member Profile:**`;

  if (member.experienceLevel) {
    output += `\n- Experience: ${capitalize(member.experienceLevel)}`;
  }
  if (member.fitnessGoal) {
    output += `\n- Goal: ${formatGoal(member.fitnessGoal)}`;
  }
  if (member.sessionDuration) {
    output += `\n- Preferred Duration: ${member.sessionDuration} min`;
  }
  if (member.schedule && member.schedule.length > 0) {
    output += `\n- Schedule: ${member.schedule.join(', ')}`;
  }
  if (member.emphasizedMuscles && member.emphasizedMuscles.length > 0) {
    output += `\n- Muscle Focus: ${member.emphasizedMuscles.join(', ')}`;
  }

  // Add active plan info
  if (member.planProgress) {
    const p = member.planProgress;
    output += `\n\n**Active Plan:** ${p.planName}`;
    output += `\n- Goal: ${p.goal}`;
    output += `\n- Structure: ${p.structure}`;
    output += `\n- Progress: ${p.completedWorkouts}/${p.totalWorkouts} workouts completed`;
  } else {
    output += '\n\n**No active plan.** Consider creating a plan for this member.';
  }

  output += `

**IMPORTANT:** When creating plans or workouts for ${member.firstName}, use:
- \`forMemberId: "${member.id}"\` in create_plan
This ensures the content is created for ${member.firstName}, not for you.`;

  return output;
}

// ============================================================================
// Helpers
// ============================================================================

function capitalize(str: string): string {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

function formatGoal(goal: string): string {
  const goalMap: Record<string, string> = {
    strength: 'Build Strength',
    muscleGain: 'Build Muscle',
    fatLoss: 'Lose Fat',
    endurance: 'Improve Endurance',
    generalFitness: 'General Fitness',
    athleticPerformance: 'Athletic Performance',
  };
  return goalMap[goal] || goal;
}
