/**
 * Reset Workout Handler
 *
 * Migrated from iOS: ResetWorkoutHandler.swift
 * Handles reset_workout tool calls - clears logged set data so user can start fresh
 * Requires confirmation for destructive action
 */

import {HandlerContext, HandlerResult, SuggestionChip} from "./index";

/**
 * Arguments for reset_workout tool
 */
interface ResetWorkoutArgs {
  workoutId?: string;
  confirmReset?: boolean;
}

/**
 * Workout status enum (matches iOS/Firestore)
 */
type WorkoutStatus = "scheduled" | "inProgress" | "completed" | "skipped";

/**
 * Workout document from Firestore
 */
interface WorkoutDoc {
  id: string;
  name?: string;
  displayName?: string;
  status: WorkoutStatus;
  scheduledDate?: string;
  completedDate?: string;
  memberId: string;
}

/**
 * Exercise set document from Firestore
 */
interface SetDoc {
  id: string;
  actualWeight?: number | null;
  actualReps?: number | null;
  completion?: string | null;
  startTime?: string | null;
  endTime?: string | null;
}

// Note: Instance documents are accessed via subcollection queries
// Their structure includes id, workoutId, and status fields

/**
 * Get start of today in ISO format
 */
function getTodayStart(): string {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return today.toISOString();
}

/**
 * Get end of today in ISO format
 */
function getTodayEnd(): string {
  const today = new Date();
  today.setHours(23, 59, 59, 999);
  return today.toISOString();
}

/**
 * Handle reset_workout tool call
 *
 * Flow:
 * 1. Resolve workoutId (supports "today" and "current" aliases)
 * 2. Validate workout exists and belongs to user
 * 3. Check if workout has data to reset
 * 4. If not confirmed, return warning with logged set count
 * 5. If confirmed, clear all set data and reset status to scheduled
 */
export async function resetWorkoutHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;
  const {workoutId: rawWorkoutId, confirmReset = false} = args as ResetWorkoutArgs;

  let workoutId = rawWorkoutId;

  // Handle "today" or "current" alias - find user's workout for today
  if (workoutId === "today" || workoutId === "current") {
    const todayStart = getTodayStart();
    const todayEnd = getTodayEnd();

    const todaySnapshot = await db
      .collection("users")
      .doc(uid)
      .collection("workouts")
      .where("scheduledDate", ">=", todayStart)
      .where("scheduledDate", "<=", todayEnd)
      .limit(1)
      .get();

    if (todaySnapshot.empty) {
      return {
        output: "ERROR: You don't have a workout scheduled for today.",
        suggestionChips: [
          {label: "Show schedule", command: "Show my schedule"},
          {label: "Create workout", command: "Create a workout for today"},
        ],
      };
    }

    workoutId = todaySnapshot.docs[0].id;
  }

  // Validate workoutId provided
  if (!workoutId) {
    return {
      output: "ERROR: Missing required parameter 'workoutId'. Please specify which workout to reset.",
    };
  }

  // Get the workout
  const workoutRef = db.collection("users").doc(uid).collection("workouts").doc(workoutId);
  const workoutDoc = await workoutRef.get();

  if (!workoutDoc.exists) {
    return {
      output: `ERROR: Workout not found with ID '${workoutId}'. Please check the workout ID.`,
    };
  }

  const workout = {id: workoutDoc.id, ...workoutDoc.data()} as WorkoutDoc;
  const workoutName = workout.displayName || workout.name || "Workout";

  // Get exercise instances for this workout
  const instancesSnapshot = await workoutRef.collection("instances").get();

  // Count logged sets
  let loggedSetsCount = 0;
  let totalSetsCount = 0;

  for (const instanceDoc of instancesSnapshot.docs) {
    const setsSnapshot = await instanceDoc.ref.collection("sets").get();

    for (const setDoc of setsSnapshot.docs) {
      totalSetsCount++;
      const setData = setDoc.data() as SetDoc;

      if (setData.actualWeight !== null && setData.actualWeight !== undefined ||
          setData.actualReps !== null && setData.actualReps !== undefined ||
          setData.completion === "completed") {
        loggedSetsCount++;
      }
    }
  }

  // Check if workout is already in initial state (nothing to reset)
  if (workout.status === "scheduled" && loggedSetsCount === 0) {
    return {
      output: `'${workoutName}' is already in its initial state. Nothing to reset.`,
      suggestionChips: [
        {label: "Start workout", command: `Start workout ${workout.id}`},
        {label: "Show schedule", command: "Show my schedule"},
      ],
    };
  }

  // If not confirmed and there's data to reset, ask for confirmation
  if (!confirmReset && loggedSetsCount > 0) {
    const chips: SuggestionChip[] = [
      {label: "Yes, reset it", command: `Reset workout ${workoutId} confirmed`},
      {label: "No, keep data", command: "Cancel"},
    ];

    return {
      output: `This will clear all logged data for '${workoutName}':\n` +
        `- ${loggedSetsCount} logged set${loggedSetsCount === 1 ? "" : "s"} will be erased\n` +
        `- Workout will return to 'Scheduled' status\n\n` +
        `This cannot be undone. Are you sure?`,
      suggestionChips: chips,
    };
  }

  // Perform the reset
  try {
    const batch = db.batch();

    // Reset all sets to unlogged state
    for (const instanceDoc of instancesSnapshot.docs) {
      const setsSnapshot = await instanceDoc.ref.collection("sets").get();

      for (const setDoc of setsSnapshot.docs) {
        batch.update(setDoc.ref, {
          actualWeight: null,
          actualReps: null,
          completion: null,
          startTime: null,
          endTime: null,
        });
      }

      // Reset instance status
      batch.update(instanceDoc.ref, {
        status: "scheduled",
      });
    }

    // Reset workout status
    batch.update(workoutRef, {
      status: "scheduled",
      completedDate: null,
      updatedAt: new Date().toISOString(),
    });

    // Commit all updates
    await batch.commit();

    console.log(`[reset_workout] Reset workout '${workoutName}' (${workoutId}): cleared ${loggedSetsCount} logged sets for user ${uid}`);

    // Build success message
    let message = `'${workoutName}' has been reset.`;
    if (loggedSetsCount > 0) {
      message += ` Cleared ${loggedSetsCount} logged set${loggedSetsCount === 1 ? "" : "s"}.`;
    }
    message += " Ready to start fresh!";

    return {
      output: message,
      suggestionChips: [
        {label: "Start workout", command: `Start workout ${workout.id}`},
        {label: "Show schedule", command: "Show my schedule"},
      ],
    };
  } catch (error) {
    console.error(`[reset_workout] Error resetting workout:`, error);
    return {
      output: `ERROR: Failed to reset workout. Please try again.`,
    };
  }
}
