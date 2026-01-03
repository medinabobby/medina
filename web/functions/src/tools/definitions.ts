/**
 * Tool Definitions for OpenAI Responses API
 *
 * v197: Ported from iOS AIToolDefinitions.swift
 * v268: Extracted shared constants to reduce token usage
 * All 22 tools for passthrough mode (server streams tool calls → iOS executes)
 */

import {ToolDefinition} from '../types/chat';

// ============================================================================
// Shared Constants (v268: Reduce duplication)
// ============================================================================

/** Shared splitDay enum for workout tools */
const SPLIT_DAY_ENUM = ['upper', 'lower', 'push', 'pull', 'legs', 'fullBody', 'chest', 'back', 'shoulders', 'arms', 'notApplicable'] as const;

/** Shared effort level enum */
const EFFORT_LEVEL_ENUM = ['recovery', 'standard', 'push'] as const;

/** Shared training location enum */
const TRAINING_LOCATION_ENUM = ['gym', 'home', 'outdoor'] as const;

/** Shared protocol ID description */
const PROTOCOL_ID_DESC = `Protocol ID. Common: 'gbc_relative_compound' (GBC - 12 reps, 30s rest, 3010 tempo), 'strength_5x5_compound' (5x5), 'hypertrophy_3x10_compound' (3x10).`;

/** Shared protocolCustomizations schema */
const PROTOCOL_CUSTOMIZATION_SCHEMA = {
  type: 'array' as const,
  items: {
    type: 'object' as const,
    properties: {
      exercisePosition: {type: 'integer' as const, description: 'Position in exercise array (0-indexed)'},
      setsAdjustment: {type: 'integer' as const, minimum: -2, maximum: 2, description: 'Adjust sets: -2 to +2'},
      repsAdjustment: {type: 'integer' as const, minimum: -10, maximum: 10, description: 'Adjust reps: -10 to +10. GBC needs +7'},
      restAdjustment: {type: 'integer' as const, minimum: -60, maximum: 60, description: 'Adjust rest seconds: -60 to +60. GBC needs -60'},
      tempoOverride: {type: 'string' as const, description: "Tempo: '3010' (GBC), '2010', '4020'"},
      rpeOverride: {type: 'number' as const, minimum: 6, maximum: 10, description: 'RPE 6-10. GBC uses 8.0'},
      rationale: {type: 'string' as const, description: 'Why customizing'},
    },
  },
  description: "Customize protocols. For GBC: repsAdjustment=+7, restAdjustment=-60, tempoOverride='3010', rpeOverride=8.0",
};

// ============================================================================
// Schedule & Calendar
// ============================================================================

/**
 * Show user's workout schedule
 * v248: Smart responses based on query type
 */
export const showSchedule: ToolDefinition = {
  type: 'function',
  name: 'show_schedule',
  description: `Show user's workout schedule. Supports different query types:
- "Show my schedule" → full week view with calendar card
- "When is leg day?" → short answer like "Tuesday" or "No leg day scheduled"
- "What's my next workout?" → just the next upcoming workout

Use query_type to control response format. Always shows FUTURE dates (today forward).`,
  parameters: {
    type: 'object',
    properties: {
      period: {
        type: 'string',
        enum: ['week', 'month'],
        description: 'Time period to show schedule for (week or month). Default: week.',
      },
      query_type: {
        type: 'string',
        enum: ['full', 'next_workout', 'specific_day'],
        description: `Response format:
- 'full': Show complete schedule with calendar card (default for "show my schedule")
- 'next_workout': Just the next upcoming workout (for "what's my next workout?")
- 'specific_day': Find a specific split day (for "when is leg day?")`,
      },
      day_query: {
        type: 'string',
        description: "For query_type='specific_day': The split/day to find (e.g., 'legs', 'push', 'upper', 'Monday')",
      },
    },
    required: [],
  },
};

// ============================================================================
// Workout Creation
// ============================================================================

/**
 * Create workout with auto-selected exercises (fast path)
 * v81.0: AI-first - AI selects exerciseIds from provided context, Swift validates
 */
export const createWorkout: ToolDefinition = {
  type: 'function',
  name: 'create_workout',
  description: `Create a workout. ONLY call when user says "create/make/build workout" or split day like "push day", "legs".
❌ NOT FOR: greetings, questions, "show schedule", "my 1RM is", "skip workout"
Exercise count: 30min→3, 45min→4, 60min→5. Use IDs from EXERCISE OPTIONS context.`,
  parameters: {
    type: 'object',
    properties: {
      name: {
        type: 'string',
        description: "Workout name (e.g., 'Upper Body - Chest Focus', 'Full Body Strength', '30 Min Cardio')",
      },
      splitDay: {
        type: 'string',
        enum: [...SPLIT_DAY_ENUM],
        description: "Split type. Use 'notApplicable' for cardio.",
      },
      scheduledDate: {
        type: 'string',
        description: "ISO8601 date string (YYYY-MM-DD, e.g., '2025-11-25')",
      },
      duration: {
        type: 'integer',
        minimum: 15,
        maximum: 120,
        description: "Target duration in minutes (15-120). Use the user's requested duration. Default to 45 if not specified.",
      },
      effortLevel: {
        type: 'string',
        enum: [...EFFORT_LEVEL_ENUM],
        description: "Effort: recovery=light, standard=balanced (default), push=high.",
      },
      sessionType: {
        type: 'string',
        enum: ['strength', 'cardio'],
        description: `Type of workout session. Default: 'strength'.

- 'strength': Traditional weightlifting workout with reps/sets
- 'cardio': Duration-based cardio session (treadmill, bike, rower, etc.)

Use 'cardio' when user requests cardio/running/cycling workouts.
When sessionType='cardio': Use cardio exerciseIds, set splitDay to 'notApplicable'.`,
      },
      exerciseIds: {
        type: 'array',
        items: {type: 'string'},
        description: 'REQUIRED: Array of exercise IDs selected from your EXERCISE OPTIONS context. Must match exercise count for duration. Include favorites when muscle groups match.',
      },
      selectionReasoning: {
        type: 'string',
        description: "Brief explanation of why you chose these exercises (e.g., 'Included 2 favorites, plus recent exercises with high completion')",
      },
      trainingLocation: {
        type: 'string',
        enum: [...TRAINING_LOCATION_ENUM],
        description: "Where training. Default 'gym'. Use 'home' if user mentions home/no gym.",
      },
      availableEquipment: {
        type: 'array',
        items: {type: 'string'},
        description: "For home workouts: Check user profile first. If 'Home Equipment: Not configured', ASK user before calling. Values: 'bodyweight', 'dumbbells', 'barbell', 'kettlebell', 'resistance_band', 'pullup_bar', 'bench', 'cable_machine'.",
      },
      protocolCustomizations: PROTOCOL_CUSTOMIZATION_SCHEMA,
      movementPatterns: {
        type: 'array',
        items: {type: 'string'},
        description: `Filter exercises by movement pattern. Use for movement-based requests like 'squat pull', 'hinge day'.

Values: squat, hinge, push, pull, horizontal_press, vertical_press, horizontal_pull, vertical_pull, lunge, carry.

Examples: 'squat pull workout' → ["squat", "pull"], 'hinge day' → ["hinge"]`,
      },
      protocolId: {
        type: 'string',
        description: PROTOCOL_ID_DESC,
      },
      supersetStyle: {
        type: 'string',
        enum: ['none', 'antagonist', 'agonist', 'compound_isolation', 'circuit', 'explicit'],
        description: "Superset structure. 'none'=traditional (default), 'antagonist'=push-pull pairs, 'agonist'=same muscle, 'compound_isolation'=compound+isolation pairs, 'circuit'=all exercises flow, 'explicit'=use supersetGroups for custom pairings.",
      },
      supersetGroups: {
        type: 'array',
        description: "Required when supersetStyle='explicit'. User-defined superset groupings with custom rest times.",
        items: {
          type: 'object',
          properties: {
            positions: {type: 'array', items: {type: 'integer'}, description: 'Exercise positions (0-indexed) to pair'},
            restBetween: {type: 'integer', description: 'Rest in seconds between exercises in this group'},
            restAfter: {type: 'integer', description: 'Rest in seconds after completing full rotation'},
          },
          required: ['positions', 'restBetween', 'restAfter'],
        },
      },
      exerciseCount: {
        type: 'integer',
        minimum: 3,
        maximum: 12,
        description: "ONLY use when: (1) extracting from an image with visible exercises, OR (2) user explicitly says a number like 'give me 4 exercises'. Do NOT use for text requests - let the system calculate from duration.",
      },
    },
    required: ['name', 'splitDay', 'scheduledDate', 'duration', 'effortLevel', 'exerciseIds'],
  },
};

// v267: Removed create_custom_workout - consolidated into create_workout
// Both tools used the same handler. Now create_workout handles both:
// - General requests (system picks exercises)
// - Specific exercises (user passes exerciseIds)

/**
 * Modify recently created workouts (delete + recreate)
 */
export const modifyWorkout: ToolDefinition = {
  type: 'function',
  name: 'modify_workout',
  description: "Modify a workout. STRUCTURAL (duration/split): may replace exercises. PROTOCOL-ONLY (reps/tempo/RPE): pass ONLY protocolCustomizations to preserve exercises.",
  parameters: {
    type: 'object',
    properties: {
      workoutId: {
        type: 'string',
        description: 'The ID of the workout to modify (from create_workout response)',
      },
      newDuration: {
        type: 'integer',
        minimum: 15,
        maximum: 120,
        description: 'New target duration in minutes (15-120, optional)',
      },
      newSplitDay: {
        type: 'string',
        enum: [...SPLIT_DAY_ENUM],
        description: "New split type (optional).",
      },
      newEffortLevel: {
        type: 'string',
        enum: [...EFFORT_LEVEL_ENUM],
        description: 'New effort level (optional)',
      },
      newSessionType: {
        type: 'string',
        enum: ['strength', 'cardio'],
        description: "Change workout type. Use 'cardio' when user wants to convert to a cardio workout.",
      },
      newName: {
        type: 'string',
        description: 'New workout name (optional)',
      },
      newTrainingLocation: {
        type: 'string',
        enum: [...TRAINING_LOCATION_ENUM],
        description: "Change location. Replaces exercises with equipment-appropriate alternatives.",
      },
      protocolCustomizations: PROTOCOL_CUSTOMIZATION_SCHEMA,
    },
    required: ['workoutId'],
  },
};

// ============================================================================
// Protocol Management
// ============================================================================

/**
 * Data-driven protocol change tool - PREFERRED for protocol changes
 */
export const changeProtocol: ToolDefinition = {
  type: 'function',
  name: 'change_protocol',
  description: "Change workout protocol. Use INSTEAD of modify_workout for protocol changes. Never loses exercises.",
  parameters: {
    type: 'object',
    properties: {
      workoutId: {
        type: 'string',
        description: 'Workout ID (optional if changing the most recently created workout)',
      },
      namedProtocol: {
        type: 'string',
        description: "Protocol name: 'gbc', 'hypertrophy', 'strength', '5x5', 'drop set', 'rest pause', 'waves', 'pyramid', 'myo', 'wendler'.",
      },
      targetReps: {
        type: 'integer',
        minimum: 1,
        maximum: 20,
        description: 'Target reps. Can override namedProtocol value.',
      },
      targetSets: {
        type: 'integer',
        minimum: 1,
        maximum: 10,
        description: 'Number of sets. Can override namedProtocol value.',
      },
      restBetweenSets: {
        type: 'integer',
        minimum: 15,
        maximum: 300,
        description: "Rest in seconds. Can override namedProtocol value (e.g., 'GBC with 45s rest').",
      },
      tempo: {
        type: 'string',
        description: "Tempo (e.g., '3010', '4020'). Can override namedProtocol value.",
      },
      targetRPE: {
        type: 'number',
        minimum: 6,
        maximum: 10,
        description: "RPE target. Can override namedProtocol value (e.g., 'GBC but with RPE 9').",
      },
    },
    required: [],
  },
};

// ============================================================================
// Plan Management
// ============================================================================

/**
 * Create multi-week training plan
 */
export const createPlan: ToolDefinition = {
  type: 'function',
  name: 'create_plan',
  description: `Create multi-week training plan. Auto-structured into phases (Foundation→Development→Peak→Deload).
VISION: If [Extracted from attached image] has exercises, MUST pass as exerciseIds.`,
  parameters: {
    type: 'object',
    properties: {
      name: {
        type: 'string',
        description: "Plan name (e.g., 'Summer Strength Program', '8-Week Hypertrophy Plan')",
      },
      durationWeeks: {
        type: 'integer',
        minimum: 1,
        maximum: 52,
        description: "Plan duration in weeks (1-52). Use the user's requested duration. Default to 8 if not specified.",
      },
      goal: {
        type: 'string',
        enum: ['strength', 'muscleGain', 'fatLoss', 'endurance', 'generalFitness', 'athleticPerformance'],
        description: 'Primary fitness goal for this plan',
      },
      daysPerWeek: {
        type: 'integer',
        minimum: 2,
        maximum: 6,
        description: 'Number of training days per week. Default to 4 if not specified.',
      },
      sessionDuration: {
        type: 'integer',
        minimum: 15,
        maximum: 120,
        description: 'Target duration per workout in minutes (15-120). Default to 45 if not specified.',
      },
      preferredDays: {
        type: 'array',
        items: {type: 'string'},
        description: "Preferred training days (e.g., ['monday', 'tuesday', 'thursday', 'friday']). If not specified, system will auto-select based on daysPerWeek.",
      },
      startDate: {
        type: 'string',
        description: 'ISO8601 date string (YYYY-MM-DD) for plan start. Default to today if not specified.',
      },
      targetDate: {
        type: 'string',
        description: "ISO8601 date string (YYYY-MM-DD) for user's goal deadline. CRITICAL: When user says 'by Dec 25th' or 'by end of 2026', YOU MUST send this parameter.",
      },
      goalWeightChange: {
        type: 'number',
        description: "Target weight change in lbs (positive = gain, negative = lose). Extract from user input like 'gain 15lbs' or 'lose 20lbs'.",
      },
      splitType: {
        type: 'string',
        enum: ['fullBody', 'upperLower', 'pushPull', 'pushPullLegs', 'bodyPart'],
        description: "Training split type. Use when user explicitly requests a specific split (e.g., 'I want push/pull' → 'pushPull').",
      },
      trainingLocation: {
        type: 'string',
        enum: [...TRAINING_LOCATION_ENUM],
        description: "Where training. Use when user mentions location.",
      },
      experienceLevel: {
        type: 'string',
        enum: ['beginner', 'intermediate', 'advanced', 'expert'],
        description: "User's training experience. Use when user mentions experience (e.g., 'I'm a beginner' → 'beginner').",
      },
      emphasizedMuscles: {
        type: 'array',
        items: {type: 'string'},
        description: "Muscle groups to emphasize (e.g., ['chest', 'shoulders']). Use when user wants focus on specific muscles.",
      },
      excludedMuscles: {
        type: 'array',
        items: {type: 'string'},
        description: "Muscle groups to avoid (e.g., ['back'] if injured). Use when user mentions injuries or avoidances.",
      },
      cardioDaysPerWeek: {
        type: 'integer',
        minimum: 0,
        maximum: 5,
        description: "Number of cardio sessions per week. Use when user explicitly requests cardio days (e.g., 'add 2 days of cardio' → 2).",
      },
      periodizationStyle: {
        type: 'string',
        enum: ['auto', 'linear', 'block', 'undulating', 'none'],
        description: "How to structure training phases. 'auto' (default) lets AI decide. 'linear' = Foundation→Development→Peak. 'block' = focused blocks. 'undulating' = varied intensity. 'none' = no phases.",
      },
      includeDeloads: {
        type: 'boolean',
        description: "Whether to include deload (recovery) weeks. Default: true for plans > 4 weeks. Set false if user says 'no deloads'.",
      },
      deloadFrequency: {
        type: 'integer',
        minimum: 3,
        maximum: 8,
        description: "Weeks between deload weeks (typically 4-6). Only used if includeDeloads is true.",
      },
      workoutDayAssignments: {
        type: 'object',
        description: "Optimal mapping of days to workout types. Keys: lowercase day names (monday-sunday). Values: 'strength' or 'cardio'.",
        additionalProperties: {type: 'string', enum: ['strength', 'cardio']},
      },
      intensityStart: {
        type: 'number',
        minimum: 0.40,
        maximum: 0.95,
        description: "Starting intensity as decimal (e.g., 0.60 for 60%). Use when user specifies intensity range.",
      },
      intensityEnd: {
        type: 'number',
        minimum: 0.40,
        maximum: 0.95,
        description: 'Ending intensity as decimal (e.g., 0.80 for 80%). Must be >= intensityStart.',
      },
      forMemberId: {
        type: 'string',
        description: "TRAINER ONLY: Member ID to create plan for. Use when trainer says 'create plan for Bobby'.",
      },
      exerciseIds: {
        type: 'array',
        items: {type: 'string'},
        description: "REQUIRED if vision extracted exercises. Pass exercise names - system auto-matches to IDs.",
      },
      protocolId: {
        type: 'string',
        description: PROTOCOL_ID_DESC + " Also: 'drop_set', 'rest_pause'.",
      },
    },
    required: ['name', 'goal'],
  },
};

/**
 * Activate a plan to start tracking workouts
 */
export const activatePlan: ToolDefinition = {
  type: 'function',
  name: 'activate_plan',
  description: "Activate a plan to begin tracking workouts. IMPORTANT: Only call this tool when user EXPLICITLY says 'yes', 'activate', 'start it', 'let's go', or similar confirmation. Do NOT call automatically after create_plan or change_protocol - always ASK user first and wait for their confirmation. If another plan is already active, this will automatically deactivate it.",
  parameters: {
    type: 'object',
    properties: {
      planId: {
        type: 'string',
        description: 'The ID of the plan to activate (from create_plan response or schedule)',
      },
      confirmOverlap: {
        type: 'boolean',
        description: 'If true, confirms user wants to replace existing active plan. Set to true only if user has already confirmed.',
      },
    },
    required: ['planId'],
  },
};

/**
 * Reschedule an existing plan's training days
 */
export const reschedulePlan: ToolDefinition = {
  type: 'function',
  name: 'reschedule_plan',
  description: "Change the schedule of an existing plan (draft or active). Use when user wants to change training days or cardio/strength distribution without recreating the entire plan. Preserves completed workout progress for active plans. Examples: 'Change my schedule to Mon/Wed/Fri', 'Move cardio to weekends', 'I can only train 3 days now'.",
  parameters: {
    type: 'object',
    properties: {
      planId: {
        type: 'string',
        description: "ID of plan to reschedule. Use 'current' for active plan or 'draft' for current draft plan.",
      },
      newPreferredDays: {
        type: 'array',
        items: {type: 'string'},
        description: "New training days as lowercase day names (e.g., ['monday', 'wednesday', 'friday'])",
      },
      newDaysPerWeek: {
        type: 'integer',
        minimum: 2,
        maximum: 6,
        description: 'New total training days per week. Optional - inferred from newPreferredDays if not provided.',
      },
      newCardioDays: {
        type: 'integer',
        minimum: 0,
        maximum: 5,
        description: 'New number of cardio days per week. Optional - keeps existing if not provided.',
      },
      workoutDayAssignments: {
        type: 'object',
        description: "Optional: explicit day→type mapping. Keys: lowercase day names. Values: 'strength' or 'cardio'.",
        additionalProperties: {type: 'string', enum: ['strength', 'cardio']},
      },
    },
    required: ['planId', 'newPreferredDays'],
  },
};

/**
 * Abandon an active plan (end early)
 */
export const abandonPlan: ToolDefinition = {
  type: 'function',
  name: 'abandon_plan',
  description: `End an active plan early. Marks all remaining scheduled workouts as skipped.
Use when user says:
- "abandon my plan"
- "end my plan early"
- "stop this plan"
- "I want to quit my current plan"

Only works on ACTIVE plans. For draft plans, suggest delete_plan instead.`,
  parameters: {
    type: 'object',
    properties: {
      planId: {
        type: 'string',
        description: "Plan ID to abandon. Use 'current' or 'active' to abandon the user's active plan.",
      },
    },
    required: ['planId'],
  },
};

/**
 * Delete a draft or completed plan permanently
 */
export const deletePlan: ToolDefinition = {
  type: 'function',
  name: 'delete_plan',
  description: `Permanently delete a plan and all its workouts.
Use when user says:
- "delete my draft plan"
- "remove this plan"
- "delete the plan"

Only works on DRAFT or COMPLETED plans. For active plans, suggest abandon_plan first.
Requires confirmation before deletion (confirmDelete=true).`,
  parameters: {
    type: 'object',
    properties: {
      planId: {
        type: 'string',
        description: "Plan ID to delete. Use 'draft' to delete the user's draft plan.",
      },
      confirmDelete: {
        type: 'boolean',
        description: 'Set to true to confirm deletion. Without confirmation, returns a warning first.',
      },
    },
    required: ['planId'],
  },
};

// ============================================================================
// Workout Execution
// ============================================================================

/**
 * Start a workout session
 */
export const startWorkout: ToolDefinition = {
  type: 'function',
  name: 'start_workout',
  description: "Start a workout session for guided execution. Use this when user asks to start their workout, begin their workout, or says they're ready to train. Validates that the plan is active and no other workout is in progress.",
  parameters: {
    type: 'object',
    properties: {
      workoutId: {
        type: 'string',
        description: 'The ID of the workout to start (from schedule or plan)',
      },
    },
    required: ['workoutId'],
  },
};

/**
 * Skip a scheduled workout
 */
export const skipWorkout: ToolDefinition = {
  type: 'function',
  name: 'skip_workout',
  description: `Skip a scheduled or missed workout. Use when user says:
- "skip my workout"
- "skip it"
- "I'll skip today"
- "mark it as skipped"

After skipping, shows the NEXT scheduled workout with date context
(e.g., "See you tomorrow!" or "Next workout is Monday").

IMPORTANT: Only use workout IDs from context - never fabricate IDs.`,
  parameters: {
    type: 'object',
    properties: {
      workoutId: {
        type: 'string',
        description: "The ID of the workout to skip (from schedule, Today's Workout, or Missed Workouts context)",
      },
    },
    required: ['workoutId'],
  },
};

/**
 * End an in-progress workout
 */
export const endWorkout: ToolDefinition = {
  type: 'function',
  name: 'end_workout',
  description: `End an in-progress workout. Marks completed sets as done, skips remaining sets.
Use when user says:
- "end my workout"
- "finish my workout"
- "I'm done with my workout"
- "stop my workout"

Returns a summary of completed vs skipped sets and shows the next scheduled workout.`,
  parameters: {
    type: 'object',
    properties: {
      workoutId: {
        type: 'string',
        description: "Workout ID to end. Optional - defaults to current active session's workout.",
      },
    },
    required: [],
  },
};

/**
 * Reset a workout to initial state
 */
export const resetWorkout: ToolDefinition = {
  type: 'function',
  name: 'reset_workout',
  description: `Reset a workout to its initial state. Clears all logged data (weights, reps, completion).
Use when user says:
- "reset my workout"
- "start this workout over"
- "clear my workout data"
- "redo this workout from scratch"

Requires confirmation before reset (confirmReset=true).
Works on any workout status (scheduled, in-progress, completed, skipped).`,
  parameters: {
    type: 'object',
    properties: {
      workoutId: {
        type: 'string',
        description: 'Workout ID to reset.',
      },
      confirmReset: {
        type: 'boolean',
        description: 'Set to true to confirm reset. Without confirmation, returns a warning about data loss.',
      },
    },
    required: ['workoutId'],
  },
};

// ============================================================================
// Utilities
// ============================================================================

/**
 * Find alternative exercises for substitution
 */
export const getSubstitutionOptions: ToolDefinition = {
  type: 'function',
  name: 'get_substitution_options',
  description: "Find alternative exercises that can substitute for a given exercise. Use this when the user asks 'what can I do instead of X', 'I don't have equipment for Y', or wants to swap an exercise in their workout.",
  parameters: {
    type: 'object',
    properties: {
      exerciseId: {
        type: 'string',
        description: 'The ID of the exercise to find alternatives for (from exercise library)',
      },
      workoutId: {
        type: 'string',
        description: 'Optional: The workout ID for context (helps determine equipment availability)',
      },
    },
    required: ['exerciseId'],
  },
};

/**
 * Get workout/program/plan progress summary
 */
export const getSummary: ToolDefinition = {
  type: 'function',
  name: 'get_summary',
  description: "Get workout, program, or plan progress summary with completion metrics. Use this when the user asks 'how did my workout go', 'summarize my workout', 'how is my plan going', or asks about their progress.",
  parameters: {
    type: 'object',
    properties: {
      scope: {
        type: 'string',
        enum: ['workout', 'program', 'plan'],
        description: "What to summarize: 'workout' for single workout, 'program' for program progress, 'plan' for full plan progress",
      },
      id: {
        type: 'string',
        description: 'The ID of the workout, program, or plan to summarize',
      },
    },
    required: ['scope', 'id'],
  },
};

/**
 * Update user's 1RM or working weight
 */
export const updateExerciseTarget: ToolDefinition = {
  type: 'function',
  name: 'update_exercise_target',
  description: "⚠️ MUST CALL when user shares ANY strength number. Saves their 1RM or working weight to the database. Triggers: 'my 1RM is', 'my max is', 'I can bench/squat X', 'my PR is'. Do NOT just acknowledge - you MUST call this tool to actually save the data.",
  parameters: {
    type: 'object',
    properties: {
      exercise_id: {
        type: 'string',
        description: "Exercise ID from the database (e.g., 'barbell_bench_press', 'dumbbell_bicep_curl'). Use snake_case format.",
      },
      weight_lbs: {
        type: 'number',
        description: 'Weight in pounds (convert from kg if needed: kg * 2.2)',
      },
      weight_type: {
        type: 'string',
        enum: ['1rm', 'working'],
        description: "Type of weight: '1rm' if user stated their max, 'working' if user mentioned typical training weight",
      },
      reps: {
        type: 'integer',
        description: "Number of reps (REQUIRED if weight_type is 'working'). Used to calculate 1RM via Brzycki formula.",
      },
    },
    required: ['exercise_id', 'weight_lbs', 'weight_type'],
  },
};

/**
 * Analyze historical training data
 */
export const analyzeTrainingData: ToolDefinition = {
  type: 'function',
  name: 'analyze_training_data',
  description: `Analyze user's historical training data. Use this when the user asks about:
- Progress over time ("How am I tracking Jan-Dec?")
- Exercise progression ("Show my bench press progress")
- Strength trends ("Am I getting stronger? What's regressing?")
- Period comparisons ("Compare October vs November")

This tool queries the ACTUAL workout data (sets, reps, weights) - NOT just scheduled workouts.
Always use date ranges to scope the analysis appropriately.`,
  parameters: {
    type: 'object',
    properties: {
      analysisType: {
        type: 'string',
        enum: ['period_summary', 'exercise_progression', 'strength_trends', 'period_comparison'],
        description: `Type of analysis to perform:
- period_summary: Overall stats for a time period (volume, adherence, muscle breakdown)
- exercise_progression: Track a specific exercise's progression over time (weight/reps trends)
- strength_trends: Identify which exercises are improving, maintaining, or regressing
- period_comparison: Compare two time periods side by side`,
      },
      dateRange: {
        type: 'object',
        description: 'Time period to analyze. For exercise_progression, ALWAYS use 1 full year (365 days back from today) so the chart can show time-frame filters.',
        properties: {
          start: {
            type: 'string',
            description: 'Start date in YYYY-MM-DD format.',
          },
          end: {
            type: 'string',
            description: 'End date in YYYY-MM-DD format (typically today)',
          },
        },
        required: ['start', 'end'],
      },
      comparisonDateRange: {
        type: 'object',
        description: 'Second time period for period_comparison analysis type',
        properties: {
          start: {
            type: 'string',
            description: 'Start date in YYYY-MM-DD format',
          },
          end: {
            type: 'string',
            description: 'End date in YYYY-MM-DD format',
          },
        },
        required: ['start', 'end'],
      },
      exerciseId: {
        type: 'string',
        description: "Specific exercise ID for exercise_progression analysis (e.g., 'barbell_bench_press')",
      },
      exerciseName: {
        type: 'string',
        description: "Exercise name if ID unknown - will fuzzy match (e.g., 'bench press')",
      },
      muscleGroup: {
        type: 'string',
        enum: ['chest', 'back', 'shoulders', 'biceps', 'triceps', 'forearms', 'core', 'quads', 'hamstrings', 'glutes', 'calves', 'fullBody'],
        description: 'Filter analysis to specific muscle group',
      },
      includeDetails: {
        type: 'boolean',
        description: 'Include detailed weekly breakdown (default: false, use for deep dives)',
      },
    },
    required: ['analysisType'],
  },
};

// ============================================================================
// User Profile
// ============================================================================

/**
 * Update user profile from conversation
 */
export const updateProfile: ToolDefinition = {
  type: 'function',
  name: 'update_profile',
  description: "Update the user's profile with information they shared in conversation. Use when user mentions their age, birthdate, height, weight, fitness goal, schedule, or other profile information. Call this IMMEDIATELY when user shares any personal or fitness-related details.",
  parameters: {
    type: 'object',
    properties: {
      birthdate: {
        type: 'string',
        description: "User's birthdate in ISO format (YYYY-MM-DD). Extract from age ('I'm 13' → calculate), grade level ('7th grade' → ~12-13yo), or explicit date.",
      },
      heightInches: {
        type: 'number',
        description: "User's height in total inches. Convert from feet/inches (e.g., 6'2\" = 74 inches, 5'10\" = 70 inches)",
      },
      currentWeight: {
        type: 'number',
        description: "User's current weight in pounds",
      },
      fitnessGoal: {
        type: 'string',
        enum: ['strength', 'muscleGain', 'fatLoss', 'endurance', 'generalFitness', 'athleticPerformance'],
        description: "User's primary fitness goal. Infer from context: basketball/vertical/sports → athleticPerformance, bigger/muscle → muscleGain, lose weight → fatLoss",
      },
      personalMotivation: {
        type: 'string',
        description: "User's 'why' - their motivation for training (e.g., 'increase vertical jump for basketball', 'look good for summer')",
      },
      preferredDays: {
        type: 'array',
        items: {
          type: 'string',
          enum: ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'],
        },
        description: "Days user can work out (e.g., ['monday', 'wednesday', 'friday'])",
      },
      sessionDuration: {
        type: 'integer',
        description: 'Preferred session duration in minutes (e.g., 30, 45, 60)',
      },
      gender: {
        type: 'string',
        enum: ['male', 'female', 'other', 'prefer_not_to_say'],
        description: "User's gender. Extract from 'I'm male/female/etc.' or 'I am a man/woman'.",
      },
      experienceLevel: {
        type: 'string',
        enum: ['beginner', 'intermediate', 'advanced', 'expert'],
        description: "User's lifting/training experience level. Extract from 'I'm a beginner', 'expert lifter', '5+ years experience', etc.",
      },
    },
    required: [],
  },
};

// ============================================================================
// Messaging
// ============================================================================

/**
 * Send a message to trainer or member
 */
export const sendMessage: ToolDefinition = {
  type: 'function',
  name: 'send_message',
  description: `Send a message to your trainer (if you're a member) or to a member (if you're a trainer).
Creates a new thread or replies to an existing thread.

TRAINERS: 'send Bobby a message', 'tell Sarah good job', 'remind Alex about leg day'
MEMBERS: 'send Nick a message', 'tell my trainer about my schedule', 'reply to Nick's message'

Messages appear in the Messages folder in the sidebar and are grouped by conversation thread.`,
  parameters: {
    type: 'object',
    properties: {
      recipientId: {
        type: 'string',
        description: 'User ID to send message to. For trainers: member ID from roster. For members: trainer ID from profile.',
      },
      content: {
        type: 'string',
        description: 'Message content. Keep it natural and conversational. Will be delivered as-is.',
      },
      subject: {
        type: 'string',
        description: "Thread subject (REQUIRED for new threads). Examples: 'Training Schedule Update', 'Great workout today!'. Not needed when replying to existing thread.",
      },
      threadId: {
        type: 'string',
        description: "Existing thread ID to reply to. Omit to start a new thread. Use when user says 'reply to...' or 'respond to that message'.",
      },
      messageType: {
        type: 'string',
        enum: ['encouragement', 'planUpdate', 'checkIn', 'reminder', 'general'],
        description: "Category of message: 'encouragement' for praise/motivation, 'planUpdate' for plan-related updates, 'checkIn' for wellness checks, 'reminder' for workout reminders, 'general' for everything else.",
      },
    },
    required: ['recipientId', 'content'],
  },
};

// ============================================================================
// Quick Actions
// ============================================================================

/**
 * Present quick-action chips to user
 */
export const suggestOptions: ToolDefinition = {
  type: 'function',
  name: 'suggest_options',
  description: `Present quick-action chips to user at decision points.
Use when presenting 2-4 options the user can tap instead of typing.

CRITICAL: Only use workout IDs from context - NEVER fabricate IDs.

ALLOWED COMMANDS ONLY - only suggest these existing features:
- "Start my workout" / "Start workout [ID]"
- "Skip my workout" / "Skip workout [ID]"
- "Show my schedule"
- "Create a workout for today"
- "Create a training plan"
- "Analyze my progress"
- "Send a message to my trainer"
- "Continue workout" (for paused workouts)

Do NOT suggest non-existent features like calorie/nutrition tracking, meal plans, payments, etc.`,
  parameters: {
    type: 'object',
    properties: {
      options: {
        type: 'array',
        description: '2-4 quick-action options for user to tap',
        items: {
          type: 'object',
          properties: {
            label: {
              type: 'string',
              description: 'Short button text (2-4 words)',
            },
            command: {
              type: 'string',
              description: 'Message to send when tapped (from ALLOWED COMMANDS list)',
            },
          },
          required: ['label', 'command'],
        },
        minItems: 2,
        maxItems: 4,
      },
    },
    required: ['options'],
  },
};

// ============================================================================
// Exercise Library
// ============================================================================

/**
 * Add an exercise to user's library (favorites)
 */
export const addToLibrary: ToolDefinition = {
  type: 'function',
  name: 'add_to_library',
  description: `Add an exercise to the user's favorites library.
Favorited exercises are prioritized when creating workouts.
Use when user says:
- "add bench press to my library"
- "favorite this exercise"
- "save squats to my favorites"
- "add this to my library"`,
  parameters: {
    type: 'object',
    properties: {
      exerciseId: {
        type: 'string',
        description: "Exercise ID to add (e.g., 'barbell_bench_press', 'dumbbell_curl'). Supports fuzzy matching if exact ID unknown.",
      },
    },
    required: ['exerciseId'],
  },
};

/**
 * Remove an exercise from user's library (favorites)
 */
export const removeFromLibrary: ToolDefinition = {
  type: 'function',
  name: 'remove_from_library',
  description: `Remove an exercise from the user's favorites library.
Use when user says:
- "remove bench press from my library"
- "unfavorite this exercise"
- "remove this from my favorites"`,
  parameters: {
    type: 'object',
    properties: {
      exerciseId: {
        type: 'string',
        description: "Exercise ID to remove (e.g., 'barbell_bench_press'). Supports fuzzy matching.",
      },
    },
    required: ['exerciseId'],
  },
};

// ============================================================================
// Tool Collections
// ============================================================================

/**
 * All 22 tools for passthrough mode
 * In passthrough mode, server streams tool calls to iOS, iOS executes and sends results back
 */
export const allTools: ToolDefinition[] = [
  // Schedule
  showSchedule,
  // Workout Creation
  createWorkout,
  // v267: Removed createCustomWorkout - consolidated into createWorkout
  modifyWorkout,
  // Protocol
  changeProtocol,
  // Plan Management
  createPlan,
  activatePlan,
  reschedulePlan,
  abandonPlan,
  deletePlan,
  // Workout Execution
  startWorkout,
  skipWorkout,
  endWorkout,
  resetWorkout,
  // Utilities
  getSubstitutionOptions,
  getSummary,
  updateExerciseTarget,
  analyzeTrainingData,
  // Profile
  updateProfile,
  // Messaging
  sendMessage,
  // Quick Actions
  suggestOptions,
  // Library
  addToLibrary,
  removeFromLibrary,
];

/**
 * Get all tool definitions in OpenAI format
 * v197: Returns all 22 tools for passthrough mode
 */
export function getToolDefinitions(): ToolDefinition[] {
  return allTools;
}
