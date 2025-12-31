/**
 * Modify Workout Handler
 *
 * v236: Refactored to use WorkoutModifier service layer
 *
 * Handles modify_workout tool calls - modifies existing workout with:
 * - In-place updates for metadata changes (name, date, effort)
 * - Exercise substitutions (preserves workout structure)
 * - Full rebuild for structural changes (split, duration >15min, location)
 *
 * Key improvement: Preserves workout ID and tracks modification history.
 */

import {HandlerContext, HandlerResult, SuggestionChip, WorkoutCardData} from "./index";
import {
  modifyWorkout,
  ModifyWorkoutRequest,
  formatDate,
  SplitDay,
  EffortLevel,
  SessionType,
  TrainingLocation,
  Equipment,
  ExerciseSubstitution,
} from "../services/workout";

// ============================================================================
// Types
// ============================================================================

/**
 * Arguments for modify_workout tool
 */
interface ModifyWorkoutArgs {
  workoutId?: string;
  newDuration?: number;
  newSplitDay?: string;
  newEffortLevel?: string;
  newName?: string;
  newScheduledDate?: string;
  newSessionType?: string;
  newTrainingLocation?: string;
  newAvailableEquipment?: string[];
  exerciseSubstitutions?: ExerciseSubstitutionArg[];
}

/**
 * Exercise substitution from tool args
 */
interface ExerciseSubstitutionArg {
  position: number;
  newExerciseId: string;
  reason?: string;
}

// ============================================================================
// Validation
// ============================================================================

/**
 * Validate required parameters
 */
function validateArgs(args: ModifyWorkoutArgs): string | null {
  if (!args.workoutId) {
    return "ERROR: Missing required parameter 'workoutId'. Please specify which workout to modify.";
  }

  // At least one modification must be provided
  const hasChange =
    args.newName ||
    args.newScheduledDate ||
    args.newEffortLevel ||
    args.newSplitDay ||
    args.newDuration ||
    args.newSessionType ||
    args.newTrainingLocation ||
    args.newAvailableEquipment ||
    (args.exerciseSubstitutions && args.exerciseSubstitutions.length > 0);

  if (!hasChange) {
    return "ERROR: No modifications specified. Please provide at least one change (newName, newDate, newEffortLevel, etc.).";
  }

  return null;
}

/**
 * Parse date string to Date object
 */
function parseDate(dateStr: string | undefined): Date | undefined {
  if (!dateStr) return undefined;
  const parsed = new Date(dateStr);
  return isNaN(parsed.getTime()) ? undefined : parsed;
}

// ============================================================================
// Main Handler
// ============================================================================

/**
 * Handle modify_workout tool call
 *
 * Flow:
 * 1. Validate required parameters
 * 2. Build modification request
 * 3. Delegate to WorkoutModifier service
 * 4. Format and return response
 */
export async function modifyWorkoutHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;
  const typedArgs = args as ModifyWorkoutArgs;

  // Validate required parameters
  const validationError = validateArgs(typedArgs);
  if (validationError) {
    return {output: validationError};
  }

  const {
    workoutId,
    newName,
    newScheduledDate: rawScheduledDate,
    newEffortLevel,
    newSplitDay,
    newDuration,
    newSessionType,
    newTrainingLocation,
    newAvailableEquipment,
    exerciseSubstitutions: rawSubstitutions,
  } = typedArgs;

  console.log(`[modify_workout] Modifying workout ${workoutId} for user ${uid}`);

  try {
    // Build modification request
    const request: ModifyWorkoutRequest = {
      userId: uid,
      workoutId: workoutId!,
    };

    // Metadata changes
    if (newName) {
      request.newName = newName;
    }

    if (rawScheduledDate) {
      request.newScheduledDate = parseDate(rawScheduledDate);
    }

    if (newEffortLevel) {
      request.newEffortLevel = newEffortLevel as EffortLevel;
    }

    // Structural changes
    if (newSplitDay) {
      request.newSplitDay = newSplitDay as SplitDay;
    }

    if (newDuration) {
      request.newDuration = newDuration;
    }

    if (newSessionType) {
      request.newSessionType = newSessionType as SessionType;
    }

    if (newTrainingLocation) {
      request.newTrainingLocation = newTrainingLocation as TrainingLocation;
    }

    if (newAvailableEquipment) {
      request.newAvailableEquipment = newAvailableEquipment as Equipment[];
    }

    // Exercise substitutions
    if (rawSubstitutions && rawSubstitutions.length > 0) {
      request.exerciseSubstitutions = rawSubstitutions.map((sub): ExerciseSubstitution => ({
        position: sub.position,
        newExerciseId: sub.newExerciseId,
        reason: sub.reason,
      }));
    }

    // Execute modification
    const result = await modifyWorkout(db, request);

    const {workout, changeType, exerciseCount} = result;

    console.log(`[modify_workout] ${changeType} modification complete for ${workoutId}`);

    // Get exercise names for display
    const exerciseNames: string[] = [];
    for (const exerciseId of workout.exerciseIds.slice(0, 5)) {
      const exerciseDoc = await db.collection("exercises").doc(exerciseId).get();
      if (exerciseDoc.exists) {
        exerciseNames.push(exerciseDoc.data()?.name || exerciseId);
      } else {
        exerciseNames.push(exerciseId);
      }
    }
    const exerciseList = exerciseNames.join(", ") + (exerciseCount > 5 ? "..." : "");

    // Format success response
    const dateString = formatDate(new Date(workout.scheduledDate));

    let output = `SUCCESS: Workout modified.

WORKOUT_ID: ${workout.id}
Name: ${workout.name}
Date: ${dateString}
Exercise count: ${exerciseCount}
Change type: ${changeType}

EXERCISES:
${exerciseList}`;

    // Add change-type specific guidance
    switch (changeType) {
      case "metadata":
        output += `

MODIFICATION TYPE: Instant update
The workout's metadata was updated in place. No exercises were changed.`;
        break;

      case "substitution":
        output += `

MODIFICATION TYPE: Exercise substitution
The specified exercises were swapped while preserving the workout structure.`;
        break;

      case "structural":
        output += `

MODIFICATION TYPE: Structural rebuild
The workout was rebuilt with new exercises to match the updated configuration.`;
        break;
    }

    output += `

RESPONSE_GUIDANCE:
1. Confirm the modification was successful
2. Describe what changed (${changeType} change)
3. Tell the user they can tap the workout card below to review`;

    // Build suggestion chips
    const chips: SuggestionChip[] = [
      {label: "Start workout", command: `Start workout ${workout.id}`},
      {label: "Show schedule", command: "Show my schedule"},
    ];

    // Include workout card for inline display
    const workoutCard: WorkoutCardData = {
      workoutId: workout.id,
      workoutName: workout.name,
    };

    return {
      output,
      suggestionChips: chips,
      workoutCard,
    };
  } catch (error) {
    console.error(`[modify_workout] Error:`, error);

    // Handle specific error cases
    const errorMessage = error instanceof Error ? error.message : "Unknown error";

    if (errorMessage.includes("not found")) {
      return {
        output: "ERROR: Workout not found. It may have been deleted.",
        suggestionChips: [
          {label: "Show schedule", command: "Show my schedule"},
          {label: "Create workout", command: "Create a workout"},
        ],
      };
    }

    if (errorMessage.includes("in progress")) {
      return {
        output: `ERROR: Cannot modify workout while it's in progress. End or abandon it first.`,
        suggestionChips: [
          {label: "End workout", command: `End workout ${workoutId}`},
          {label: "Abandon workout", command: `Abandon workout ${workoutId}`},
        ],
      };
    }

    if (errorMessage.includes("completed")) {
      return {
        output: "ERROR: Cannot modify completed workout. This is a historical record. Would you like me to create a new one instead?",
        suggestionChips: [
          {label: "Create similar", command: "Create a workout like this"},
          {label: "Show schedule", command: "Show my schedule"},
        ],
      };
    }

    return {
      output: `ERROR: Failed to modify workout. ${errorMessage}`,
      suggestionChips: [
        {label: "Try again", command: `Modify workout ${workoutId}`},
        {label: "Show schedule", command: "Show my schedule"},
      ],
    };
  }
}
