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

export const SKIP_WORKOUT = `**skip_workout**: User wants to skip a workout
TRIGGERS: "skip my workout", "skip today", "can't make it today"
Returns next scheduled workout automatically`;

// ============================================================================
// Workout Creation
// ============================================================================

export const CREATE_WORKOUT = `**create_workout** (user asks to CREATE/MAKE/BUILD a workout)
TRIGGERS: "create/make/build a workout", "give me a [split] day", "create a GBC workout"
NOT FOR: questions, greetings, schedule requests, profile updates
SPLIT MAPPING: legs/lower→"legs", upper→"upper", back+biceps→"pull", chest+triceps→"push"

⚠️ LOW STAKES - EXECUTE IMMEDIATELY with profile defaults (duration, location, date)
DON'T ASK: duration/day/location questions. Just create, then offer to adjust.
❌ WRONG: Ask 3 questions before creating
✅ RIGHT: Execute immediately, then "Created! Want me to change anything?"`;

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

export const CREATE_PLAN = `**create_plan**: Multi-week training program
TRIGGERS: "create a plan/program", "X-week program"
EXPERIENCE: Check profile first. Only ask if NOT SET.
TARGET DATE: User deadline → send targetDate, system calculates weeks
MUSCLE FOCUS: "bigger arms"→emphasizedMuscles: ["biceps", "triceps"]
PROTOCOL: GBC/5x5/drop sets → pass as protocolId
⚠️ VISION/IMAGE: If exercises in image, MUST pass as exerciseIds parameter (system auto-matches)

⚠️ HIGH STAKES - CONFIRM THEN EXECUTE:
Multi-week plan = confirm key params (weeks, days/week, goal) before executing
✅ RIGHT: "I'll create 12-week plan, 4 days/week. Sound good?" → User confirms → Execute`;

export const RESCHEDULE_PLAN = `**reschedule_plan**: Change training days without losing progress`;

export const ACTIVATE_PLAN = `**activate_plan**: ONLY after explicit user confirmation`;

export const ABANDON_PLAN = `**abandon_plan**: End plan early (cannot be undone)`;

export const DELETE_PLAN = `**delete_plan**: Only DRAFT/COMPLETED plans, requires confirmDelete: true`;

// ============================================================================
// Profile & Options
// ============================================================================

export const UPDATE_PROFILE = `**update_profile**: Save user preferences and profile info
IMMEDIATE: "I want to train X days", "update my weight", explicit save requests
ASK FIRST: Personal info ("I'm 5'11", "I weigh 180") - confirm before saving
Height: 6'2" = 74 inches | Goals: strength, muscleGain, fatLoss, endurance
AFTER UPDATE: Confirm "Done! Updated your profile with [change]."`;

export const SUGGEST_OPTIONS = `**suggest_options**: Present action chips (NOT numbered lists)
WHEN: Workout choice, skip/continue decisions, after schedule
NOT WHEN: Creating a plan, general questions
ALLOWED: "Start my workout", "Skip my workout", "Show my schedule", "Create a workout", "Create a training plan"
NO: nutrition tracking, meal plans, payments, social features`;

// ============================================================================
// Exercise & Library
// ============================================================================

export const GET_SUBSTITUTION_OPTIONS = `**get_substitution_options**: User wants exercise alternatives
TRIGGERS: "swap/replace/substitute X", "alternative to X"
Returns ranked alternatives based on equipment and muscle groups`;

export const GET_SUMMARY = `**get_summary**: "how did my workout go" → scope: workout/program/plan`;

export const ADD_TO_LIBRARY = `**add_to_library**: Add exercise to library/favorites
TRIGGERS: "add X to library/favorites", "save X", "favorite X"
EXERCISE MAPPING: "bench press"→barbell_bench_press, "squat"→back_squat
Favorites prioritized in workout creation`;

export const REMOVE_FROM_LIBRARY = `**remove_from_library**: Remove from favorites`;

export const UPDATE_EXERCISE_TARGET = `**update_exercise_target**: User shares 1RM or working weight
⚠️ MUST CALL this tool - don't just acknowledge in text
TRIGGERS: "my 1RM/max/PR is", "my bench/squat/deadlift is X lbs"
PARAMS: exercise_id, weight_lbs, weight_type ("1rm" or "working")
❌ WRONG: Acknowledge without calling | ✅ RIGHT: Call tool, then confirm saved`;

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
