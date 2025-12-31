/**
 * User Context Builder
 *
 * v2: Enhanced from Firebase systemPrompt.ts + iOS UserContextBuilder.swift
 * Builds comprehensive user profile context for AI
 */

import { UserProfile } from '../../types/chat';
import { capitalize, formatGoal } from '../shared/formatters';

export interface WorkoutContext {
  todayWorkout?: { id: string; name: string };
  nextWorkout?: { id: string; name: string; date: string };
  activeSession?: { id: string; name: string; progress: string };
  missedWorkouts?: Array<{ id: string; name: string; date: string }>;
}

export interface PlanContext {
  activePlan?: {
    id: string;
    name: string;
    week: number;
    totalWeeks: number;
    goal: string;
    completedWorkouts: number;
    totalWorkouts: number;
  };
  draftPlan?: { id: string; name: string };
}

/**
 * Build user information section
 */
export function buildUserInfo(user: UserProfile): string {
  const name = user.displayName || user.email?.split('@')[0] || 'User';

  let ageInfo = 'unknown';
  if (user.birthdate) {
    const birthDate = new Date(user.birthdate);
    const today = new Date();
    const age = today.getFullYear() - birthDate.getFullYear();
    ageInfo = String(age);
  }

  return `## User Information
- Name: ${name}
- Age: ${ageInfo}`;
}

/**
 * Build member profile section
 */
export function buildProfileInfo(user: UserProfile): string {
  const profile = user.profile;
  if (!profile) return '';

  const lines: string[] = [];
  lines.push('\n## User Profile');

  if (profile.experienceLevel) {
    lines.push(`- Experience Level: ${capitalize(profile.experienceLevel)}`);
  }

  if (profile.fitnessGoal) {
    lines.push(`- Primary Goal: ${formatGoal(profile.fitnessGoal)}`);
  }

  if (profile.sessionDuration) {
    lines.push(`- Session Duration: ${profile.sessionDuration} minutes`);
  }

  if (profile.trainingLocation) {
    lines.push(`- Training Location: ${capitalize(profile.trainingLocation)}`);
  }

  // Home equipment
  if (profile.homeEquipment && profile.homeEquipment.length > 0) {
    lines.push(`- Home Equipment: ${profile.homeEquipment.join(', ')}`);
  } else {
    lines.push('- Home Equipment: Not configured (only ask if user EXPLICITLY requests home workout)');
  }

  // Weekly schedule
  if (profile.preferredDays && profile.preferredDays.length > 0) {
    lines.push(`- Weekly Schedule: ${profile.preferredDays.map(capitalize).join(', ')}`);
  }

  // Muscle focus
  if (profile.emphasizedMuscles && profile.emphasizedMuscles.length > 0) {
    lines.push(`- Muscle Focus: Emphasize ${profile.emphasizedMuscles.join(', ')}`);
  }

  if (profile.excludedMuscles && profile.excludedMuscles.length > 0) {
    lines.push(`- Avoid: ${profile.excludedMuscles.join(', ')}`);
  }

  // Weight info
  if (profile.currentWeight) {
    lines.push(`- Current Weight: ${Math.round(profile.currentWeight)} lbs`);
  }

  if (profile.goalWeight) {
    lines.push(`- Goal Weight: ${Math.round(profile.goalWeight)} lbs`);
  }

  // Personal motivation
  if (profile.personalMotivation) {
    lines.push(`- Personal Motivation: "${profile.personalMotivation}"`);
  }

  return lines.join('\n');
}

/**
 * Build current context section with workout status
 */
export function buildCurrentContext(workoutContext?: WorkoutContext): string {
  const today = new Date().toISOString().slice(0, 10);
  const lines: string[] = [];

  lines.push('## Current Context');
  lines.push(`- Today's date: ${today}`);

  if (!workoutContext) {
    lines.push('- No workout data loaded');
    return lines.join('\n');
  }

  // Today's workout
  if (workoutContext.todayWorkout) {
    const w = workoutContext.todayWorkout;
    lines.push(`- Today's Workout: ${w.name} (ID: ${w.id})`);
    lines.push(`  -> If user says "start my workout", call start_workout(workoutId: "${w.id}")`);
  } else if (workoutContext.nextWorkout) {
    const w = workoutContext.nextWorkout;
    lines.push(`- Next Scheduled Workout: ${w.name} on ${w.date} (ID: ${w.id})`);
    lines.push('  -> No workout today. User can start this early or wait.');
  }

  // Active session
  if (workoutContext.activeSession) {
    const s = workoutContext.activeSession;
    lines.push(`- ACTIVE SESSION: ${s.name} (ID: ${s.id})`);
    lines.push(`  -> Progress: ${s.progress}`);
    lines.push(`  -> If user says "continue", call start_workout(workoutId: "${s.id}")`);
  } else {
    lines.push('- NO WORKOUT IN PROGRESS');
    lines.push('  -> If user says "continue workout", explain nothing to continue');
    lines.push('  -> DO NOT call start_workout with a guessed ID');
  }

  // Missed workouts
  if (workoutContext.missedWorkouts && workoutContext.missedWorkouts.length > 0) {
    lines.push('- Missed Workouts:');
    for (const m of workoutContext.missedWorkouts.slice(0, 3)) {
      lines.push(`  - ${m.name} from ${m.date} (ID: ${m.id})`);
    }
    lines.push('  -> Offer to catch up or skip');
  }

  return lines.join('\n');
}

/**
 * Build active plan context
 */
export function buildActivePlanContext(planContext?: PlanContext): string {
  if (!planContext) return '';

  const lines: string[] = [];

  if (planContext.activePlan) {
    const p = planContext.activePlan;
    lines.push('## Active Training Plan');
    lines.push(`- Plan: ${p.name} (ID: ${p.id})`);
    lines.push(`- Progress: Week ${p.week} of ${p.totalWeeks}`);
    lines.push(`- Goal: ${p.goal}`);
    lines.push(`- Workouts: ${p.completedWorkouts}/${p.totalWorkouts} completed`);
  }

  if (planContext.draftPlan) {
    const d = planContext.draftPlan;
    lines.push(`\n- Draft Plan: ${d.name} (ID: ${d.id}) - pending activation`);
  }

  return lines.length > 0 ? lines.join('\n') : '';
}

/**
 * Build complete user context
 */
export function buildFullUserContext(
  user: UserProfile,
  workoutContext?: WorkoutContext,
  planContext?: PlanContext
): string {
  const sections = [
    buildUserInfo(user),
    buildProfileInfo(user),
    buildCurrentContext(workoutContext),
    buildActivePlanContext(planContext),
  ].filter(s => s.length > 0);

  return sections.join('\n\n');
}

