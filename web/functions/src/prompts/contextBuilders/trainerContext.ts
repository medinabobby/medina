/**
 * Trainer Context Builder
 *
 * v2: Migrated from iOS TrainerContextBuilder.swift
 * Builds trainer-specific context including member roster and instructions
 */

import { capitalize, formatGoal } from '../shared/formatters';

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
 * Build trainer-specific instructions (compressed)
 */
function buildTrainerInstructions(): string {
  return `
## Trainer Mode - Instructions

**Selected Member:** If "Currently Selected Member" section exists, use that member for all operations.
**No Selection:** Ask which member before proceeding.

**Plans:** Use \`forMemberId\` parameter. Use roster data as defaults (don't re-ask).
**Messages:** Types: encouragement, planUpdate, checkIn, reminder, general`;
}

/**
 * Build context for currently selected member (compressed)
 */
function buildSelectedMemberContext(member: SelectedMember): string {
  let output = `
## Currently Selected Member: ${member.name} (ID: ${member.id})
Use \`forMemberId: "${member.id}"\` for all operations.

**Profile:**`;

  if (member.experienceLevel) output += ` ${capitalize(member.experienceLevel)}`;
  if (member.fitnessGoal) output += ` | ${formatGoal(member.fitnessGoal)}`;
  if (member.sessionDuration) output += ` | ${member.sessionDuration}min`;
  if (member.schedule?.length) output += ` | ${member.schedule.join(', ')}`;
  if (member.emphasizedMuscles?.length) output += ` | Focus: ${member.emphasizedMuscles.join(', ')}`;

  if (member.planProgress) {
    const p = member.planProgress;
    output += `\n**Active Plan:** ${p.planName} (${p.completedWorkouts}/${p.totalWorkouts} done)`;
  } else {
    output += '\n**No active plan.**';
  }

  return output;
}

