/**
 * Tool Instructions for AI Assistant
 *
 * v2: Migrated from iOS ToolInstructions.swift
 * Cleaned up: removed version markers, consolidated redundant text
 *
 * Each tool has:
 * - When to use it
 * - Critical behaviors
 * - Examples
 */

// ============================================================================
// Schedule & Workout Start
// ============================================================================

export const SHOW_SCHEDULE = `**show_schedule**: Display workout schedule
- Use when user asks to see their schedule, workouts, or calendar
- Parameters: period ("week" or "month")
- Examples: "show my schedule", "what workouts do I have"`;

export const START_WORKOUT = `**start_workout**: Start or continue a workout session
- Call IMMEDIATELY when user says "start my workout", "continue workout"
- DO NOT ask clarifying questions if there's exactly ONE scheduled workout today
- Shows tappable workout card for user to begin/continue

CRITICAL - AI_GENERATE_RESPONSE blocks:
When tool output contains [AI_GENERATE_RESPONSE], you MUST:
1. Read the WORKOUT INFO and INSTRUCTIONS
2. Generate a natural, conversational intro (2-3 sentences)
3. DO NOT echo the instruction block - the card appears automatically

Example response: "Let's get back to your Full Body session! You've got 3 exercises left. Tap the card below to continue."
NOT: "[AI_GENERATE_RESPONSE] The user is continuing..." (WRONG)

WORKOUT ID RULES - NEVER FABRICATE:
- ONLY use workout IDs from context:
  - "ACTIVE SESSION: ... (ID: xyz)" -> use xyz
  - "Today's Workout: ... (ID: xyz)" -> use xyz
  - "Next Scheduled Workout: ... (ID: xyz)" -> use xyz
- NEVER guess or construct IDs - validation WILL fail

WHEN NO WORKOUT TODAY:
- Tell user briefly: "No workout today. Your next is [name] on [date]."
- THEN call suggest_options with choices (Start next, Create today's)
- NEVER ask "Would you like..." as text - use chips`;

export const SKIP_WORKOUT = `**skip_workout**: Skip a scheduled or missed workout
- Call when user says "skip my workout", "skip it", "I'll skip today"
- Parameter: workoutId (required)
- After skipping, shows next scheduled workout`;

// ============================================================================
// Workout Creation
// ============================================================================

export const CREATE_WORKOUT = `**create_workout**: Create a workout with automatic exercise selection
- Use by DEFAULT for workout requests
- System selects exercises based on split day and preferences
- Parameters: name, splitDay, scheduledDate, duration, effortLevel

SPLIT DAY (use for most requests):
- "leg day" / "lower body" / "legs" -> splitDay: "legs"
- "upper body" -> splitDay: "upper"
- "arms workout" -> splitDay: "arms"
- "back and biceps" -> splitDay: "pull"
- "chest and triceps" -> splitDay: "push"

MOVEMENT PATTERNS (only when user literally says movement words):
- "squat pull workout" -> movementPatterns: ["squat", "pull"]
- "hinge day" -> movementPatterns: ["hinge"]
WRONG: "lower body" -> movementPatterns (use splitDay instead!)

SUPERSET STYLES:
- "antagonist" - push-pull pairs, time-efficient
- "agonist" - burn out muscle, maximum pump
- "circuit" - no rest, keep moving
- "none" (default) - straight sets
Minimum 4 exercises for any superset style.

PROTOCOL SELECTION:
- "Use GBC protocol" -> protocolId: "gbc_relative_compound"
- "Do 5x5 strength" -> protocolId: "strength_5x5_compound"
- If not specified, auto-selected based on exercise type and goals

CRITICAL - Don't Pre-Describe:
NEVER describe exercises BEFORE calling create_workout.
The system selects exercises - wait for result, then describe what was ACTUALLY created.

EXERCISE COUNT:
DO NOT send exerciseCount for text requests - system calculates from duration.
- "upper body workout" -> NO exerciseCount (use profile duration)
- "4 exercises for arms" -> exerciseCount: 4 (user explicitly requested)`;

export const CREATE_CUSTOM_WORKOUT = `**create_custom_workout**: Create workout with specific exercises
- ONLY use when user explicitly requests SPECIFIC exercises
- Example: "workout with bench press and squats"
- Parameters include exerciseIds array

EXERCISE ID MATCHING:
- "chin ups" -> chin_up
- "bench press" -> barbell_bench_press
- "back squat" -> barbell_back_squat
- NEVER guess IDs - validation WILL fail

For general requests like "create a chest workout", use create_workout instead.`;

export const MODIFY_WORKOUT = `**modify_workout**: Modify workout METADATA (not exercises)
- Use for: duration, split day, effort level, date, protocol adjustments
- NOT for: changing exercises, adding/removing exercises

WHEN TO USE:
- "make it 30 minutes" -> modify_workout (duration)
- "change to upper body" -> modify_workout (split)
- "use 3010 tempo" -> modify_workout (protocol)
- "use back squat instead" -> create_workout (exercise change!)
- "add pull ups" -> create_workout (adding exercise!)

WORKOUT ID:
- After create_workout, output contains "WORKOUT_ID: xyz"
- Use this exact ID for modify_workout
- After modify returns "NEW_WORKOUT_ID: abc", use abc for subsequent calls

PROTOCOL CUSTOMIZATIONS:
When user ONLY wants protocol changes (RPE, tempo, rest):
- ONLY pass workoutId and protocolCustomizations
- DO NOT pass newDuration or newSplitDay - this recreates with different exercises!

LOCATION CHANGE:
When user says "make it a home workout":
- ONLY pass workoutId and newTrainingLocation
- DO NOT change duration unless explicitly asked`;

// ============================================================================
// Plan Creation
// ============================================================================

export const CREATE_PLAN = `**create_plan**: Create multi-week training plan
- Use when user asks for training plan, program, multi-week schedule

EXPERIENCE LEVEL (CRITICAL):
Before creating ANY plan, you MUST know experience level:
- Check profile first - if set, USE IT, do NOT ask again
- Only ask if NOT SET: "What's your lifting experience - beginner, intermediate, advanced, or expert?"
- DO NOT assume "beginner" as default - creates wrong intensity

TARGET DATE:
When user specifies deadline ("by Dec 25th"):
- Send targetDate parameter (YYYY-MM-DD)
- System calculates weeks - do NOT guess durationWeeks

CONFIRMATION (REQUIRED):
Before calling create_plan, summarize and confirm:
- Duration (suggest 8 weeks if not specified)
- Experience level
- Days per week (from user's Weekly Schedule)
- Session duration
- Goal

MUSCLE FOCUS:
- "bigger arms" -> emphasizedMuscles: ["biceps", "triceps"]
- "broad shoulders" -> emphasizedMuscles: ["shoulders"]

SCHEDULING (when cardioDays > 0):
ALWAYS include workoutDayAssignments to spread cardio:
{
  "monday": "strength",
  "tuesday": "cardio",
  "wednesday": "strength"
}`;

export const RESCHEDULE_PLAN = `**reschedule_plan**: Change schedule of existing plan
- Use to change training days without losing progress
- Parameters: planId ("current" for active), newPreferredDays array`;

export const ACTIVATE_PLAN = `**activate_plan**: Activate a draft plan
- ONLY call after explicit user confirmation
- NEVER activate automatically after creating a plan`;

export const ABANDON_PLAN = `**abandon_plan**: End active plan early
- Marks remaining workouts as skipped
- Cannot be undone`;

export const DELETE_PLAN = `**delete_plan**: Permanently delete a plan
- Only works on DRAFT or COMPLETED plans
- Requires confirmation (confirmDelete: true)`;

// ============================================================================
// Profile & Options
// ============================================================================

export const UPDATE_PROFILE = `**update_profile**: Save user info from conversation
- Call IMMEDIATELY when user shares: age, height, weight, goals, schedule
- Examples: "I'm 6'2", "I can train Mon/Wed/Fri", "I want to build muscle"

Parameters (only include what user shared):
- birthdate: ISO format
- heightInches: total inches (6'2" = 74)
- currentWeight: in pounds
- fitnessGoal: strength, muscleGain, fatLoss, endurance, generalFitness
- preferredDays: ["monday", "wednesday", "friday"]
- sessionDuration: minutes per workout

CRITICAL: When user shares schedule AND wants a plan:
1. FIRST call update_profile to save schedule
2. THEN confirm plan details
3. THEN call create_plan`;

export const SUGGEST_OPTIONS = `**suggest_options**: Present quick-action chips at decision points

WHEN TO USE:
- Workout choice needed -> suggest options
- Skip vs continue decisions
- After showing schedule -> suggest starting workout

WHEN NOT TO USE:
- Creating a plan -> DON'T suggest unrelated workouts
- General questions

NEVER present choices as:
- Numbered lists (1. 2. 3.)
- "Would you like A or B?" text
ALWAYS use chips for action choices.

ALLOWED COMMANDS ONLY:
- "Start my workout" / "Start workout [ID]"
- "Skip my workout"
- "Show my schedule"
- "Create a workout for today"
- "Create a training plan"

DO NOT suggest non-existent features:
- calorie/nutrition tracking
- meal plans
- membership/payments
- social features`;

// ============================================================================
// Exercise & Library
// ============================================================================

export const GET_SUBSTITUTION_OPTIONS = `**get_substitution_options**: Find alternative exercises
- Use when user asks "what can I do instead of X"
- Returns ranked alternatives with match percentages`;

export const GET_SUMMARY = `**get_summary**: Get workout/plan progress summary
- Use for "how did my workout go", "summarize my plan"
- Parameters: scope (workout/program/plan), id`;

export const ADD_TO_LIBRARY = `**add_to_library**: Add exercise to favorites
- Favorited exercises are prioritized when creating workouts`;

export const REMOVE_FROM_LIBRARY = `**remove_from_library**: Remove exercise from favorites`;

// ============================================================================
// Workout Lifecycle
// ============================================================================

export const END_WORKOUT = `**end_workout**: End an in-progress workout
- Marks completed sets as done, remaining as skipped
- Shows next scheduled workout`;

export const RESET_WORKOUT = `**reset_workout**: Reset workout to initial state
- Clears ALL logged data
- Requires confirmation (confirmReset: true)`;

// ============================================================================
// Messaging
// ============================================================================

export const SEND_MESSAGE = `**send_message**: Send message to trainer/member
- Creates DRAFT MESSAGE CARD for user to review
- Keep your response to ONE sentence - card shows full message
- Good: "I've drafted a message. Review it below!"
- Bad: Including Subject/Content in your text`;

// ============================================================================
// Builders
// ============================================================================

/**
 * Build complete tool instructions for system prompt
 */
export function buildToolInstructions(): string {
  return `## TOOL INSTRUCTIONS

### Schedule & Workout Start
${SHOW_SCHEDULE}

${START_WORKOUT}

${SKIP_WORKOUT}

### Workout Creation
${CREATE_WORKOUT}

${CREATE_CUSTOM_WORKOUT}

${MODIFY_WORKOUT}

### Plan Management
${CREATE_PLAN}

${RESCHEDULE_PLAN}

${ACTIVATE_PLAN}

${ABANDON_PLAN}

${DELETE_PLAN}

### Profile & Options
${UPDATE_PROFILE}

${SUGGEST_OPTIONS}

### Exercise & Library
${GET_SUBSTITUTION_OPTIONS}

${GET_SUMMARY}

${ADD_TO_LIBRARY}

${REMOVE_FROM_LIBRARY}

### Workout Lifecycle
${END_WORKOUT}

${RESET_WORKOUT}

### Messaging
${SEND_MESSAGE}`;
}

/**
 * Build lightweight tool instructions (for simple queries)
 * Only includes commonly used tools
 */
export function buildLightweightToolInstructions(): string {
  return `## TOOL INSTRUCTIONS (Quick Reference)

${SHOW_SCHEDULE}

${START_WORKOUT}

${UPDATE_PROFILE}

${SUGGEST_OPTIONS}`;
}
