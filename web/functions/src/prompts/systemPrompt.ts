/**
 * System Prompt Builder for OpenAI Responses API
 *
 * v2: Complete rewrite - migrated from iOS with full feature parity
 *
 * Modules:
 * - coreRules.ts - Behavioral rules (confirmation, profile-aware, experience)
 * - toolInstructions.ts - All 22 tool instructions
 * - contextBuilders/* - User, training data, trainer context
 */

import { UserProfile } from '../types/chat';
import { buildCoreRules, buildExamples, buildWarnings } from './coreRules';
import { buildToolInstructions } from './toolInstructions';
import {
  buildFullUserContext,
  WorkoutContext,
  PlanContext,
} from './contextBuilders/userContext';
import { buildTrainingDataContext, StrengthTarget, ExerciseAffinity } from './contextBuilders/trainingDataContext';
import { buildTrainerContext, isTrainer, MemberInfo, SelectedMember } from './contextBuilders/trainerContext';

// ============================================================================
// Main Entry Point
// ============================================================================

export interface SystemPromptOptions {
  user: UserProfile;
  workoutContext?: WorkoutContext;
  planContext?: PlanContext;
  strengthTargets?: StrengthTarget[];
  exerciseAffinity?: ExerciseAffinity;
  trainerMembers?: MemberInfo[];
  selectedMember?: SelectedMember;
}

/**
 * Build complete system prompt for the AI assistant
 *
 * @param options - User profile and optional context data
 * @returns Complete system prompt string
 */
export function buildSystemPrompt(options: SystemPromptOptions | UserProfile): string {
  // Handle both old signature (UserProfile) and new signature (options)
  const opts: SystemPromptOptions = 'user' in options ? options : { user: options };
  const { user, workoutContext, planContext, strengthTargets, exerciseAffinity, trainerMembers, selectedMember } = opts;

  const currentDate = new Date().toISOString().slice(0, 10);

  // Build sections
  const sections: string[] = [];

  // 1. Base identity (always)
  sections.push(BASE_IDENTITY);

  // 2. User context
  sections.push(buildFullUserContext(user, workoutContext, planContext));

  // 3. Training data (if available)
  const trainingData = buildTrainingDataContext(strengthTargets, exerciseAffinity);
  if (trainingData) {
    sections.push(trainingData);
  }

  // 4. Trainer context (if trainer)
  if (isTrainer(user.roles)) {
    sections.push(buildTrainerContext(trainerMembers || [], selectedMember));
  }

  // 5. Core behavioral rules
  sections.push(buildCoreRules());

  // 6. Tool instructions
  sections.push(buildToolInstructions());

  // 7. Action examples
  sections.push(buildExamples());

  // 8. Fitness warnings
  sections.push(buildWarnings());

  // 9. Current date
  sections.push(`## Current Date
Today is ${currentDate}`);

  return sections.filter(s => s && s.length > 0).join('\n\n');
}

/**
 * Build lightweight system prompt for simple queries
 * Uses less tokens for basic operations (schedule views, profile updates)
 */
export function buildLightweightPrompt(user: UserProfile): string {
  const currentDate = new Date().toISOString().slice(0, 10);

  return `${BASE_IDENTITY}

## About the User
Name: ${user.displayName || user.email?.split('@')[0] || 'User'}
${user.profile?.experienceLevel ? `Experience: ${capitalize(user.profile.experienceLevel)}` : ''}
${user.profile?.fitnessGoal ? `Goal: ${formatGoal(user.profile.fitnessGoal)}` : ''}

## Quick Reference
- Use show_schedule for schedule/calendar requests
- Use update_profile when user shares personal info
- Use suggest_options to present action choices (not numbered lists)

## Current Date
Today is ${currentDate}`;
}

// ============================================================================
// Base Identity
// ============================================================================

const BASE_IDENTITY = `You are Medina, a personal fitness coach and training companion.

## Your Role
You help members with:
- Creating custom workouts and training plans
- Answering questions about exercises, techniques, and programming
- Providing motivation and guidance throughout their fitness journey
- Explaining training concepts in simple, practical terms

## Communication Style
- Be conversational, friendly, and encouraging
- Use clear, simple language - avoid excessive jargon
- Keep responses concise (2-3 paragraphs max for explanations)
- When creating workouts, be specific about exercises, sets, reps, and rest periods
- Always prioritize safety and proper form

## Important Guidelines
1. **Safety First**: Never recommend dangerous exercises without proper supervision
2. **Progressive Overload**: Respect the user's experience level
3. **Personalization**: Consider their goals, schedule, and preferences
4. **Practical**: Focus on actionable advice they can use immediately`;

// ============================================================================
// Helpers
// ============================================================================

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

function capitalize(str: string): string {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

// ============================================================================
// Re-exports for convenience
// ============================================================================

export { WorkoutContext, PlanContext } from './contextBuilders/userContext';
export { StrengthTarget, ExerciseAffinity } from './contextBuilders/trainingDataContext';
export { MemberInfo, SelectedMember, isTrainer } from './contextBuilders/trainerContext';
