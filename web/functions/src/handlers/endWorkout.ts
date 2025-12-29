/**
 * End Workout Handler
 *
 * Migrated from iOS: EndWorkoutHandler.swift
 * Ends an in-progress workout, marks remaining sets as skipped,
 * calculates completion stats, and returns summary with next workout info.
 */

import {HandlerContext, HandlerResult, SuggestionChip} from "./index";

/**
 * Arguments for end_workout tool
 */
interface EndWorkoutArgs {
  workoutId?: string;
}

/**
 * Workout status enum (matches iOS/Firestore)
 */
type WorkoutStatus = "scheduled" | "inProgress" | "completed" | "skipped";

/**
 * Workout document from Firestore
 */
interface WorkoutDoc {
  id?: string;
  name?: string;
  status?: WorkoutStatus;
  scheduledDate?: string;
  startedAt?: string;
  completedAt?: string;
}

/**
 * Set document
 */
interface SetDoc {
  id?: string;
  completion?: string;
  actualWeight?: number;
  actualReps?: number;
}

/**
 * Format a date as "Monday, December 15"
 */
function formatDate(date: Date): string {
  return date.toLocaleDateString("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
  });
}

/**
 * Build friendly date context for next workout
 */
function buildDateContext(scheduledDate: Date): string {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const workoutDay = new Date(scheduledDate);
  workoutDay.setHours(0, 0, 0, 0);

  const diffTime = workoutDay.getTime() - today.getTime();
  const daysUntil = Math.ceil(diffTime / (1000 * 60 * 60 * 24));

  if (daysUntil === 0) {
    return "You have another workout today!";
  } else if (daysUntil === 1) {
    return "See you tomorrow!";
  } else if (daysUntil === 2) {
    return "See you in a couple days!";
  } else if (daysUntil >= 3 && daysUntil <= 6) {
    const dayName = scheduledDate.toLocaleDateString("en-US", {weekday: "long"});
    return `See you on ${dayName}!`;
  } else {
    const dateStr = formatDate(scheduledDate);
    return `Your next workout is on ${dateStr}.`;
  }
}

/**
 * Calculate duration in minutes between two dates
 */
function calculateDurationMinutes(startedAt: string, endedAt: Date): number {
  const start = new Date(startedAt);
  const diffMs = endedAt.getTime() - start.getTime();
  return Math.round(diffMs / (1000 * 60));
}

/**
 * Handle end_workout tool call
 *
 * Flow:
 * 1. Resolve workoutId (supports "current" alias for in-progress workout)
 * 2. Validate workout exists and is in progress
 * 3. Count completed vs total sets
 * 4. Mark remaining sets as skipped
 * 5. Update workout status to completed
 * 6. Return summary with next workout info
 */
export async function endWorkoutHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;
  const {workoutId: rawWorkoutId} = args as EndWorkoutArgs;

  let workoutId = rawWorkoutId;

  // Handle "current" alias - find user's in-progress workout
  if (!workoutId || workoutId === "current") {
    const inProgressSnapshot = await db
      .collection("users")
      .doc(uid)
      .collection("workouts")
      .where("status", "==", "inProgress")
      .limit(1)
      .get();

    if (inProgressSnapshot.empty) {
      return {
        output: "You don't have a workout in progress. Nothing to end.",
        suggestionChips: [
          {label: "Start a workout", command: "Start my next workout"},
          {label: "Show schedule", command: "Show my schedule"},
        ],
      };
    }

    workoutId = inProgressSnapshot.docs[0].id;
  }

  // Get the workout
  const workoutRef = db.collection("users").doc(uid).collection("workouts").doc(workoutId);
  const workoutDoc = await workoutRef.get();

  if (!workoutDoc.exists) {
    return {
      output: `ERROR: Workout not found with ID '${workoutId}'.`,
    };
  }

  const workout = {id: workoutDoc.id, ...workoutDoc.data()} as WorkoutDoc;
  const workoutName = workout.name || "Workout";

  // Check status - only in-progress workouts can be ended
  switch (workout.status) {
  case "completed":
    return {
      output: "This workout has already been completed.",
    };

  case "skipped":
    return {
      output: "This workout was skipped. Nothing to end.",
    };

  case "scheduled": {
    const chips: SuggestionChip[] = [
      {label: "Skip workout", command: `Skip workout ${workout.id}`},
      {label: "Start workout", command: `Start workout ${workout.id}`},
    ];
    return {
      output: `'${workoutName}' hasn't been started yet.\n\nWould you like to skip it instead?`,
      suggestionChips: chips,
    };
  }

  case "inProgress":
    // Valid case - proceed with ending
    break;

  default:
    // Unknown status, try to proceed
    break;
  }

  // Calculate completion stats by iterating through exercise instances and sets
  let completedSetsCount = 0;
  let totalSetsCount = 0;
  let completedExercisesCount = 0;
  let totalExercisesCount = 0;

  const now = new Date();
  const batch = db.batch();

  // Get all exercise instances for this workout
  const instancesSnapshot = await workoutRef.collection("instances").get();
  totalExercisesCount = instancesSnapshot.size;

  for (const instanceDoc of instancesSnapshot.docs) {
    // Note: instance data not needed for completion calculation, only iterating sets
    let exerciseHasCompletedSet = false;

    // Get all sets for this instance
    const setsSnapshot = await instanceDoc.ref.collection("sets").get();

    for (const setDoc of setsSnapshot.docs) {
      totalSetsCount += 1;
      const set = setDoc.data() as SetDoc;

      // Check if set is completed (either marked completed or has actual data)
      const isCompleted = set.completion === "completed" ||
        (set.actualWeight !== undefined && set.actualReps !== undefined);

      if (isCompleted) {
        completedSetsCount += 1;
        exerciseHasCompletedSet = true;
      } else {
        // Mark unlogged sets as skipped
        batch.update(setDoc.ref, {
          completion: "skipped",
          updatedAt: now.toISOString(),
        });
      }
    }

    if (exerciseHasCompletedSet) {
      completedExercisesCount += 1;
    }

    // Update instance status
    const instanceStatus = exerciseHasCompletedSet ? "completed" : "skipped";
    batch.update(instanceDoc.ref, {
      status: instanceStatus,
      updatedAt: now.toISOString(),
    });
  }

  // Determine final workout status: completed if any sets done, skipped if none
  const finalStatus: WorkoutStatus = completedSetsCount > 0 ? "completed" : "skipped";

  // Update the workout
  const workoutUpdate: Record<string, unknown> = {
    status: finalStatus,
    updatedAt: now.toISOString(),
  };

  if (finalStatus === "completed") {
    workoutUpdate.completedAt = now.toISOString();
  }

  batch.update(workoutRef, workoutUpdate);

  // Commit all updates
  try {
    await batch.commit();
  } catch (error) {
    console.error(`[end_workout] Error updating workout:`, error);
    return {
      output: `ERROR: Failed to end workout. Please try again.`,
    };
  }

  // Calculate duration if we have a start time
  let durationText = "";
  if (workout.startedAt) {
    const durationMinutes = calculateDurationMinutes(workout.startedAt, now);
    if (durationMinutes > 0) {
      if (durationMinutes < 60) {
        durationText = ` Duration: ${durationMinutes} minutes.`;
      } else {
        const hours = Math.floor(durationMinutes / 60);
        const mins = durationMinutes % 60;
        durationText = ` Duration: ${hours}h ${mins}m.`;
      }
    }
  }

  console.log(`[end_workout] Ended workout '${workoutName}': ${completedSetsCount}/${totalSetsCount} sets, ` +
    `${completedExercisesCount}/${totalExercisesCount} exercises, status=${finalStatus} for user ${uid}`);

  // Build progress summary
  const skippedSetsCount = totalSetsCount - completedSetsCount;
  let progressSummary: string;

  if (completedSetsCount === 0) {
    progressSummary = `No sets were completed.${durationText}`;
  } else if (skippedSetsCount === 0) {
    progressSummary = `All ${completedSetsCount} sets completed!${durationText}`;
  } else {
    progressSummary = `Completed ${completedSetsCount} of ${totalSetsCount} sets ` +
      `(${completedExercisesCount} of ${totalExercisesCount} exercises). ` +
      `Marked ${skippedSetsCount} remaining sets as skipped.${durationText}`;
  }

  // Find next scheduled workout
  const nextSnapshot = await db
    .collection("users")
    .doc(uid)
    .collection("workouts")
    .where("status", "==", "scheduled")
    .orderBy("scheduledDate", "asc")
    .limit(1)
    .get();

  const statusWord = finalStatus === "completed" ? "completed" : "ended";

  if (!nextSnapshot.empty) {
    const nextDoc = nextSnapshot.docs[0];
    const nextWorkout = nextDoc.data() as WorkoutDoc;
    const nextName = nextWorkout.name || "Workout";
    const nextDate = nextWorkout.scheduledDate ? new Date(nextWorkout.scheduledDate) : null;
    const dateContext = nextDate ? buildDateContext(nextDate) : "";

    return {
      output: `Workout ${statusWord}! ${progressSummary}\n\nYour next workout is '${nextName}'. ${dateContext}`,
      suggestionChips: [
        {label: "Start next workout", command: `Start workout ${nextDoc.id}`},
        {label: "Show schedule", command: "Show my schedule"},
      ],
    };
  } else {
    return {
      output: `Workout ${statusWord}! ${progressSummary}\n\nYou don't have any more scheduled workouts coming up. Would you like me to create a new workout?`,
      suggestionChips: [
        {label: "Create workout", command: "Create a workout for today"},
        {label: "Show schedule", command: "Show my schedule"},
      ],
    };
  }
}
