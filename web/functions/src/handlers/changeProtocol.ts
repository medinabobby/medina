/**
 * Change Protocol Handler
 *
 * Migrated from iOS: ChangeProtocolHandler.swift, ProtocolChangeService.swift
 * Handles change_protocol tool calls - changes workout protocol in place
 * No delete/recreate - direct modification of exercise instances
 */

import {HandlerContext, HandlerResult, SuggestionChip, WorkoutCardData} from "./index";

// ============================================================================
// Types
// ============================================================================

/**
 * Arguments for change_protocol tool
 */
interface ChangeProtocolArgs {
  workoutId?: string;
  namedProtocol?: string;
  targetReps?: number;
  targetSets?: number;
  restBetweenSets?: number;
  tempo?: string;
  targetRPE?: number;
}

/**
 * Workout status types
 */
type WorkoutStatus = "scheduled" | "inProgress" | "completed" | "skipped";

/**
 * Protocol configuration
 */
interface ProtocolConfig {
  id: string;
  name: string;
  reps: number;
  sets: number;
  rest: number;
  tempo: string;
  rpe: number;
}

// ============================================================================
// Protocol Definitions
// ============================================================================

/**
 * Named protocols mapping (simplified from iOS ProtocolResolver)
 * Maps aliases to protocol configurations
 */
const NAMED_PROTOCOLS: Record<string, ProtocolConfig> = {
  // GBC / German Body Comp
  gbc: {
    id: "gbc_standard",
    name: "German Body Comp",
    reps: 12,
    sets: 3,
    rest: 30,
    tempo: "3010",
    rpe: 8,
  },
  "german body comp": {
    id: "gbc_standard",
    name: "German Body Comp",
    reps: 12,
    sets: 3,
    rest: 30,
    tempo: "3010",
    rpe: 8,
  },

  // Drop Sets
  "drop sets": {
    id: "machine_drop_set",
    name: "Drop Sets",
    reps: 10,
    sets: 3,
    rest: 10,
    tempo: "2010",
    rpe: 9,
  },
  "drop set": {
    id: "machine_drop_set",
    name: "Drop Sets",
    reps: 10,
    sets: 3,
    rest: 10,
    tempo: "2010",
    rpe: 9,
  },

  // Myo Reps
  myo: {
    id: "myo_reps",
    name: "Myo Reps",
    reps: 15,
    sets: 4,
    rest: 20,
    tempo: "2010",
    rpe: 9,
  },
  "myo reps": {
    id: "myo_reps",
    name: "Myo Reps",
    reps: 15,
    sets: 4,
    rest: 20,
    tempo: "2010",
    rpe: 9,
  },

  // Waves
  waves: {
    id: "wave_loading",
    name: "Wave Loading",
    reps: 5,
    sets: 6,
    rest: 120,
    tempo: "3010",
    rpe: 8,
  },
  "wave loading": {
    id: "wave_loading",
    name: "Wave Loading",
    reps: 5,
    sets: 6,
    rest: 120,
    tempo: "3010",
    rpe: 8,
  },

  // Pyramid
  pyramid: {
    id: "pyramid",
    name: "Pyramid",
    reps: 10,
    sets: 4,
    rest: 90,
    tempo: "2010",
    rpe: 8,
  },

  // Strength (heavy)
  strength: {
    id: "strength_3x5_heavy",
    name: "Strength",
    reps: 5,
    sets: 3,
    rest: 180,
    tempo: "2010",
    rpe: 8,
  },
  heavy: {
    id: "strength_3x5_heavy",
    name: "Heavy Strength",
    reps: 5,
    sets: 3,
    rest: 180,
    tempo: "2010",
    rpe: 8,
  },

  // Hypertrophy
  hypertrophy: {
    id: "hypertrophy_3x10",
    name: "Hypertrophy",
    reps: 10,
    sets: 3,
    rest: 60,
    tempo: "3010",
    rpe: 8,
  },

  // Endurance
  endurance: {
    id: "endurance_high_rep",
    name: "Endurance",
    reps: 15,
    sets: 3,
    rest: 45,
    tempo: "2010",
    rpe: 7,
  },
};

/**
 * Resolve a protocol by name or ID
 */
function resolveProtocol(nameOrId: string): ProtocolConfig | null {
  const lower = nameOrId.toLowerCase().trim();

  // Check named protocols first
  if (NAMED_PROTOCOLS[lower]) {
    return NAMED_PROTOCOLS[lower];
  }

  // Check if it's a direct protocol ID
  for (const config of Object.values(NAMED_PROTOCOLS)) {
    if (config.id === nameOrId) {
      return config;
    }
  }

  return null;
}

// ============================================================================
// Main Handler
// ============================================================================

/**
 * Handle change_protocol tool call
 *
 * Flow:
 * 1. Validate workout exists and can be modified
 * 2. Resolve protocol (named or custom values)
 * 3. Update all exercise instances with new protocol
 * 4. Return result
 */
export async function changeProtocolHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;
  const {
    workoutId,
    namedProtocol,
    targetReps,
    targetSets,
    restBetweenSets,
    tempo,
    targetRPE,
  } = args as ChangeProtocolArgs;

  // Validate workout ID
  if (!workoutId) {
    return {
      output: "ERROR: Missing required parameter 'workoutId'. Please specify which workout to modify.",
    };
  }

  console.log(`[change_protocol] Changing protocol for workout ${workoutId}`);

  try {
    // 1. Fetch the workout
    const workoutDoc = await db.collection(`users/${uid}/workouts`).doc(workoutId).get();

    if (!workoutDoc.exists) {
      return {
        output: "ERROR: Workout not found. It may have been deleted.",
        suggestionChips: [
          {label: "Show schedule", command: "Show my schedule"},
          {label: "Create workout", command: "Create a workout"},
        ],
      };
    }

    const workout = workoutDoc.data() as {
      id: string;
      name: string;
      status: WorkoutStatus;
      exerciseIds: string[];
    };

    // 2. Validate status
    if (workout.status === "inProgress") {
      return {
        output: `ERROR: Cannot modify workout '${workout.name}' because it's currently in progress. End it first to make changes.`,
        suggestionChips: [
          {label: "End workout", command: `End workout ${workoutId}`},
        ],
      };
    }

    if (workout.status === "completed") {
      return {
        output: `ERROR: Cannot modify completed workout '${workout.name}'. Would you like me to create a new workout instead?`,
        suggestionChips: [
          {label: "Create similar", command: "Create a similar workout"},
        ],
      };
    }

    // 3. Resolve protocol
    let protocolConfig: ProtocolConfig | null = null;
    let finalReps = targetReps || 10;
    let finalSets = targetSets || 3;
    let finalRest = restBetweenSets || 60;
    let finalTempo = tempo || "2010";
    let finalRPE = targetRPE || 8;
    let protocolId = "custom";
    let protocolName = "Custom Protocol";

    const hasCustomValues = targetReps !== undefined || targetSets !== undefined ||
      restBetweenSets !== undefined || tempo !== undefined || targetRPE !== undefined;

    if (namedProtocol) {
      protocolConfig = resolveProtocol(namedProtocol);

      if (!protocolConfig) {
        return {
          output: `ERROR: Unknown protocol '${namedProtocol}'. Available protocols: gbc, drop sets, myo, waves, pyramid, strength, hypertrophy, endurance.`,
          suggestionChips: [
            {label: "Use GBC", command: `Change protocol to GBC for workout ${workoutId}`},
            {label: "Use Drop Sets", command: `Change protocol to drop sets for workout ${workoutId}`},
          ],
        };
      }

      // Use protocol values, with optional overrides
      protocolId = protocolConfig.id;
      protocolName = protocolConfig.name;
      finalReps = targetReps ?? protocolConfig.reps;
      finalSets = targetSets ?? protocolConfig.sets;
      finalRest = restBetweenSets ?? protocolConfig.rest;
      finalTempo = tempo ?? protocolConfig.tempo;
      finalRPE = targetRPE ?? protocolConfig.rpe;

      console.log(`[change_protocol] Resolved protocol: ${protocolName} (${protocolId})`);
    } else if (!hasCustomValues) {
      return {
        output: "ERROR: Must provide either namedProtocol (e.g., 'gbc', 'drop sets', 'waves', 'myo') or custom values (targetReps, targetSets, etc.)",
        suggestionChips: [
          {label: "Use GBC", command: `Change protocol to GBC for workout ${workoutId}`},
          {label: "Custom", command: `Change protocol for workout ${workoutId} with 8 reps, 4 sets`},
        ],
      };
    }

    // 4. Fetch and update all exercise instances
    const instancesSnap = await db
      .collection(`users/${uid}/workouts/${workoutId}/instances`)
      .get();

    if (instancesSnap.empty) {
      return {
        output: "ERROR: This workout has no exercises to modify.",
        suggestionChips: [
          {label: "Modify workout", command: `Modify workout ${workoutId}`},
        ],
      };
    }

    const batch = db.batch();
    let instancesUpdated = 0;

    for (const instanceDoc of instancesSnap.docs) {
      // Update the instance's protocolVariantId
      batch.update(instanceDoc.ref, {
        protocolVariantId: protocolId,
        updatedAt: new Date().toISOString(),
      });
      instancesUpdated++;
    }

    // 5. Update workout name if protocol was applied
    let finalWorkoutName = workout.name;
    if (protocolConfig) {
      const shortName = protocolName.split(" ")[0];
      if (!workout.name.toLowerCase().includes(shortName.toLowerCase())) {
        finalWorkoutName = `${workout.name} - ${shortName}`;
        batch.update(workoutDoc.ref, {
          name: finalWorkoutName,
          updatedAt: new Date().toISOString(),
        });
      }
    }

    await batch.commit();

    console.log(`[change_protocol] Updated ${instancesUpdated} instances to protocol ${protocolId}`);

    // 6. Format response
    const output = `SUCCESS: Protocol changed to ${protocolName}.

WORKOUT_ID: ${workoutId}
Name: ${finalWorkoutName}
Exercises: ${instancesUpdated}

NEW PROTOCOL VALUES:
- Reps: ${finalReps} per set
- Sets: ${finalSets}
- Rest: ${finalRest} seconds
- Tempo: ${finalTempo}
- RPE: ${finalRPE}

INSTRUCTIONS:
1. Confirm the protocol was changed successfully
2. Briefly explain what changed (e.g., "Now using GBC protocol with 12 reps, 30s rest for metabolic stress")
3. Tell them to tap the link below to see the updated workout`;

    const chips: SuggestionChip[] = [
      {label: "Start workout", command: `Start workout ${workoutId}`},
      {label: "Show schedule", command: "Show my schedule"},
    ];

    const workoutCard: WorkoutCardData = {
      workoutId,
      workoutName: finalWorkoutName,
    };

    return {
      output,
      suggestionChips: chips,
      workoutCard,
    };
  } catch (error) {
    console.error(`[change_protocol] Error:`, error);
    return {
      output: `ERROR: Failed to change protocol. ${error instanceof Error ? error.message : "Unknown error"}`,
      suggestionChips: [
        {label: "Try again", command: `Change protocol for workout ${workoutId}`},
        {label: "Show schedule", command: "Show my schedule"},
      ],
    };
  }
}
