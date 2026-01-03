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

export const SHOW_SCHEDULE = `**show_schedule**
Triggers: "show schedule", "my workouts", "what's this week"`;

export const START_WORKOUT = `**start_workout**
IMMEDIATE: No clarifying questions if ONE workout exists today
AI_GENERATE_RESPONSE: Read WORKOUT INFO, generate 2-3 sentence intro (don't echo instruction block)
NO WORKOUT: Brief message + call suggest_options with chips`;

export const SKIP_WORKOUT = `**skip_workout**: MUST CALL when user wants to skip a workout
TRIGGERS: "skip my workout", "skip today", "skip today's workout", "can't make it today", "skip this workout"
Returns next scheduled workout automatically`;

// ============================================================================
// Workout Creation
// ============================================================================

export const CREATE_WORKOUT = `**create_workout** (ONLY when user explicitly asks to CREATE/MAKE/BUILD a workout)
TRIGGERS: "create a workout", "make me a push day", "build a leg workout", "give me a chest routine", "create a GBC workout", "create a workout with [protocol name]"
NOT FOR: questions, greetings, schedule requests, profile updates, fitness advice
SPLIT MAPPING: legs/lower→"legs", upper→"upper", arms→"arms", back+biceps→"pull", chest+triceps→"push"
DON'T PRE-DESCRIBE: Wait for result, then describe ACTUAL created exercises

⚠️ LOW STAKES - EXECUTE THEN CONFIRM:
Single workout = low stakes. DO NOT ask questions before creating. EXECUTE immediately with smart defaults:
- Duration: Use user's profile.preferredSessionDuration OR 45 minutes
- Location: Use user's profile.trainingLocation OR "gym"
- Date: Tomorrow (or next available day)
- Protocol: Use specified protocol OR default progression

AFTER CREATING: Offer to adjust: "Created your 45-min [split] workout for tomorrow! Want me to change the duration, location, or exercises?"

❌ WRONG (3 turns):
  User: "Create a GBC workout"
  AI: "What duration?" → User: "45 min" → AI: "What day?" → User: "Tomorrow" → AI creates workout

✅ RIGHT (1 turn):
  User: "Create a GBC workout"
  AI: [EXECUTES create_workout with profile defaults] "Created your 45-min GBC workout for tomorrow! Want me to change anything?"`;

// v267: Removed CREATE_CUSTOM_WORKOUT - consolidated into create_workout
// create_workout now handles both general requests AND specific exercise lists

export const MODIFY_WORKOUT = `**modify_workout** (metadata only, not exercises)
USE FOR: duration, split day, effort level, date, protocol
NOT FOR: exercise changes → create_workout instead
WORKOUT ID: From "WORKOUT_ID: xyz" in create_workout output
PROTOCOL ONLY: Don't pass newDuration/newSplitDay (recreates exercises)
LOCATION ONLY: Don't change duration unless asked`;

// ============================================================================
// Plan Creation
// ============================================================================

export const CREATE_PLAN = `**create_plan**: MUST CALL when user wants a multi-week training program
TRIGGERS: "create a plan", "create a program", "X-week program", "training plan", "strength program"
EXPERIENCE: Check profile first. Only ask if NOT SET.
TARGET DATE: User deadline → send targetDate, system calculates weeks
MUSCLE FOCUS: "bigger arms"→emphasizedMuscles: ["biceps", "triceps"]
CARDIO: Include workoutDayAssignments when cardioDays > 0
⚠️ CRITICAL - EXERCISES FROM VISION/IMAGE:
  - If user uploaded an image with exercises, you MUST pass those exercises as exerciseIds parameter
  - Extract EVERY exercise name you described in your response
  - Pass as: exerciseIds: ["Incline Dumbbell Bench Press", "Incline Dumbbell Flys", "Lateral Raise", ...]
  - ❌ WRONG: Describe exercises in text but call create_plan without exerciseIds
  - ✅ RIGHT: Call create_plan WITH exerciseIds containing ALL exercises from the image
  - System auto-matches names to catalog IDs
PROTOCOL: If user mentions GBC/5x5/drop sets/tempo, pass as protocolId

⚠️ HIGH STAKES - CONFIRM THEN EXECUTE:
Multi-week plan = high stakes (creates 12+ workouts). CONFIRM key parameters before executing:
- Duration (weeks), days/week, session duration, goal

✅ RIGHT (2-3 turns):
  User: "Create a strength plan"
  AI: "I'll create a 12-week strength plan, training 4 days/week for 45 minutes. Does that work?"
  User: "Make it 8 weeks"
  AI: [EXECUTES create_plan with 8 weeks]`;

export const RESCHEDULE_PLAN = `**reschedule_plan**: Change training days without losing progress`;

export const ACTIVATE_PLAN = `**activate_plan**: ONLY after explicit user confirmation`;

export const ABANDON_PLAN = `**abandon_plan**: End plan early (cannot be undone)`;

export const DELETE_PLAN = `**delete_plan**: Only DRAFT/COMPLETED plans, requires confirmDelete: true`;

// ============================================================================
// Profile & Options
// ============================================================================

export const UPDATE_PROFILE = `**update_profile**: Call to save user preferences and profile info
TRIGGERS FOR IMMEDIATE CALL:
- Schedule preferences: "I want to train X days per week", "I can only workout Mon/Wed/Fri"
- Explicit save requests: "save this to my profile", "update my weight", "yes" (after you asked)
ASK FIRST FOR: Personal info ("I'm 5'11", "I weigh 180") - acknowledge and confirm before saving
Height: 6'2" = 74 inches | Goals: strength, muscleGain, fatLoss, endurance, generalFitness
AFTER UPDATE: Always confirm "Done! I've updated your profile with [what changed]."
SCHEDULE + PLAN: First update_profile, then confirm plan, then create_plan`;

export const SUGGEST_OPTIONS = `**suggest_options**: Present action chips (NOT numbered lists)
WHEN: Workout choice, skip/continue decisions, after schedule
NOT WHEN: Creating a plan, general questions
ALLOWED: "Start my workout", "Skip my workout", "Show my schedule", "Create a workout", "Create a training plan"
NO: nutrition tracking, meal plans, payments, social features`;

// ============================================================================
// Exercise & Library
// ============================================================================

export const GET_SUBSTITUTION_OPTIONS = `**get_substitution_options**: MUST CALL when user wants exercise alternatives
TRIGGERS: "swap X for something", "replace X", "substitute X", "what can I do instead of X", "alternative to X"
Returns ranked alternatives based on equipment and muscle groups`;

export const GET_SUMMARY = `**get_summary**: "how did my workout go" → scope: workout/program/plan`;

export const ADD_TO_LIBRARY = `**add_to_library**: MUST CALL when user wants to add exercise to library/favorites
TRIGGERS: "add X to my library", "add X to favorites", "save X", "favorite X", "put X in my library"
EXERCISE MAPPING: "bench press"→barbell_bench_press, "squat"→back_squat
Favorites are prioritized in workout creation`;

export const REMOVE_FROM_LIBRARY = `**remove_from_library**: Remove from favorites`;

export const UPDATE_EXERCISE_TARGET = `**update_exercise_target**: MUST CALL when user shares 1RM or working weight
⚠️ CRITICAL: You MUST actually call this tool - do NOT just acknowledge the weight in text
TRIGGERS: "my 1RM is", "my max is", "I can lift X", "my PR is", "my bench/squat/deadlift is X lbs"
EXERCISE MAPPING: "bench press"→barbell_bench_press, "squat"→back_squat, "deadlift"→conventional_deadlift
PARAMETERS: exercise_id (string), weight_lbs (number), weight_type ("1rm" or "working")
❌ WRONG: Responding "Great, I've noted your 1RM" without calling the tool
✅ RIGHT: Call update_exercise_target THEN confirm "Saved your [exercise] 1RM at [weight] lbs."`;

// ============================================================================
// Workout Lifecycle
// ============================================================================

export const END_WORKOUT = `**end_workout**: Marks completed sets done, remaining skipped`;

export const RESET_WORKOUT = `**reset_workout**: Clears ALL logged data, requires confirmReset: true`;

// ============================================================================
// Messaging
// ============================================================================

export const SEND_MESSAGE = `**send_message**: Creates DRAFT CARD for review
Response: One sentence only ("I've drafted a message. Review it below!")`;

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

${UPDATE_EXERCISE_TARGET}

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
