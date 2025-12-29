/**
 * System Prompt Builder for OpenAI Responses API
 *
 * Ported from iOS SystemPrompts.swift and BaseSystemPrompt.swift
 * Phase 5: Simplified version with core identity and MVP tool instructions
 */

import { UserProfile } from '../types/chat';

/**
 * Build system prompt for the AI assistant
 *
 * @param user - User profile from Firestore
 * @returns Complete system prompt string
 */
export function buildSystemPrompt(user: UserProfile): string {
  const currentDate = new Date().toISOString().slice(0, 10);
  const userContext = buildUserContext(user);

  return `${BASE_IDENTITY}

${userContext}

${TOOL_INSTRUCTIONS}

${RESPONSE_GUIDELINES}

## Current Date
Today is ${currentDate}

${CURRENT_LIMITATIONS}`;
}

// ============================================================================
// Prompt Components
// ============================================================================

/**
 * Base identity and role description
 * Ported from BaseSystemPrompt.swift
 */
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
- Always prioritize safety and proper form`;

/**
 * Tool usage instructions
 */
const TOOL_INSTRUCTIONS = `## Tool Usage

### show_schedule
Use when user asks to see their schedule, workouts, or calendar.
- "Show my schedule" → show_schedule(period: "week")
- "What workouts do I have this month?" → show_schedule(period: "month")

### suggest_options
Present quick-action chips at decision points.
- Offer 2-4 tappable options instead of asking open-ended questions
- Keep labels short (2-4 words)
- Use specific commands that map to actions

### update_profile
**CRITICAL: You MUST call update_profile tool when user shares ANY of these:**
- Age or birthdate ("I'm 47", "born in 1978")
- Height ("I'm 6'2", "5 foot 10")
- Weight ("I weigh 150lbs", "180 pounds")
- Fitness goals ("I want to build muscle", "lose weight")
- Training schedule ("I can work out Mon/Wed/Fri")
- Experience level ("I'm a beginner", "been lifting 5 years")

**DO NOT just acknowledge the info conversationally - CALL THE TOOL FIRST.**
Example: User says "I'm 47 and weigh 150lbs"
→ Call update_profile(birthdate: "1978-01-01", currentWeight: 150)
→ THEN respond conversationally`;

/**
 * Response guidelines
 */
const RESPONSE_GUIDELINES = `## Response Guidelines

### Be Action-Oriented
- End responses with clear next steps or actionable suggestions
- Use suggest_options to present choices at decision points
- Don't leave users wondering "what next?"

### Handle Off-Topic Gracefully
- You're a fitness coach - redirect non-fitness questions politely
- "I'm here to help with your fitness journey! What training questions do you have?"

### Confirmation Behavior
- NEVER automatically activate plans or start workouts
- ASK before taking significant actions
- After creating something, ask if user wants to proceed`;

/**
 * Current limitations
 */
const CURRENT_LIMITATIONS = `## Current Limitations (Phase 5)
- You can show schedules and update profiles
- Workout creation, starting workouts, and plan management are handled by the app
- Some tools may forward to the mobile app for execution`;

// ============================================================================
// Context Builders
// ============================================================================

/**
 * Build user-specific context section
 */
function buildUserContext(user: UserProfile): string {
  const sections: string[] = [];

  // Basic info
  const name = user.displayName || user.email?.split('@')[0] || 'User';
  sections.push(`## About the User
Name: ${name}`);

  // Profile info
  if (user.profile) {
    const profileLines: string[] = [];

    if (user.profile.fitnessGoal) {
      profileLines.push(`Goal: ${formatGoal(user.profile.fitnessGoal)}`);
    }

    if (user.profile.experienceLevel) {
      profileLines.push(`Experience: ${capitalize(user.profile.experienceLevel)}`);
    }

    if (user.profile.sessionDuration) {
      profileLines.push(`Preferred Session: ${user.profile.sessionDuration} minutes`);
    }

    if (user.profile.preferredDays?.length) {
      profileLines.push(`Training Days: ${user.profile.preferredDays.map(capitalize).join(', ')}`);
    }

    if (profileLines.length > 0) {
      sections.push(profileLines.join('\n'));
    }
  }

  // Role info
  if (user.role && user.role !== 'member') {
    sections.push(`\nRole: ${capitalize(user.role)}`);
  }

  return sections.join('\n');
}

/**
 * Format fitness goal for display
 */
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

/**
 * Capitalize first letter of string
 */
function capitalize(str: string): string {
  return str.charAt(0).toUpperCase() + str.slice(1);
}
