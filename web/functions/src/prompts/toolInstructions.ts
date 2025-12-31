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

export const SKIP_WORKOUT = `**skip_workout**
Triggers: "skip my workout", "skip today"
Returns next scheduled workout automatically`;

// ============================================================================
// Workout Creation
// ============================================================================

export const CREATE_WORKOUT = `**create_workout** (DEFAULT for workout requests)
SPLIT MAPPING: legs/lower→"legs", upper→"upper", arms→"arms", back+biceps→"pull", chest+triceps→"push"
MOVEMENT PATTERNS: Only when user says "squat pull workout", "hinge day" (not "lower body"!)
DON'T PRE-DESCRIBE: Wait for result, then describe ACTUAL created exercises
EXERCISE COUNT: Only when user explicitly says number (e.g., "4 exercises")`;

export const CREATE_CUSTOM_WORKOUT = `**create_custom_workout**
Only when user names SPECIFIC exercises: "bench press and squats"
ID mapping: "chin ups"→chin_up, "bench press"→barbell_bench_press
General requests ("chest workout") → use create_workout instead`;

export const MODIFY_WORKOUT = `**modify_workout** (metadata only, not exercises)
USE FOR: duration, split day, effort level, date, protocol
NOT FOR: exercise changes → create_workout instead
WORKOUT ID: From "WORKOUT_ID: xyz" in create_workout output
PROTOCOL ONLY: Don't pass newDuration/newSplitDay (recreates exercises)
LOCATION ONLY: Don't change duration unless asked`;

// ============================================================================
// Plan Creation
// ============================================================================

export const CREATE_PLAN = `**create_plan**
EXPERIENCE: Check profile first. Only ask if NOT SET.
TARGET DATE: User deadline → send targetDate, system calculates weeks
CONFIRM BEFORE: Duration, experience, days/week, session duration, goal
MUSCLE FOCUS: "bigger arms"→emphasizedMuscles: ["biceps", "triceps"]
CARDIO: Include workoutDayAssignments when cardioDays > 0`;

export const RESCHEDULE_PLAN = `**reschedule_plan**: Change training days without losing progress`;

export const ACTIVATE_PLAN = `**activate_plan**: ONLY after explicit user confirmation`;

export const ABANDON_PLAN = `**abandon_plan**: End plan early (cannot be undone)`;

export const DELETE_PLAN = `**delete_plan**: Only DRAFT/COMPLETED plans, requires confirmDelete: true`;

// ============================================================================
// Profile & Options
// ============================================================================

export const UPDATE_PROFILE = `**update_profile**: Call IMMEDIATELY when user shares personal info
Height: 6'2" = 74 inches | Goals: strength, muscleGain, fatLoss, endurance, generalFitness
SCHEDULE + PLAN: First update_profile, then confirm plan, then create_plan`;

export const SUGGEST_OPTIONS = `**suggest_options**: Present action chips (NOT numbered lists)
WHEN: Workout choice, skip/continue decisions, after schedule
NOT WHEN: Creating a plan, general questions
ALLOWED: "Start my workout", "Skip my workout", "Show my schedule", "Create a workout", "Create a training plan"
NO: nutrition tracking, meal plans, payments, social features`;

// ============================================================================
// Exercise & Library
// ============================================================================

export const GET_SUBSTITUTION_OPTIONS = `**get_substitution_options**: "what can I do instead of X" → ranked alternatives`;

export const GET_SUMMARY = `**get_summary**: "how did my workout go" → scope: workout/program/plan`;

export const ADD_TO_LIBRARY = `**add_to_library**: Favorites are prioritized in workout creation`;

export const REMOVE_FROM_LIBRARY = `**remove_from_library**: Remove from favorites`;

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
