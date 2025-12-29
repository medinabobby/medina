/**
 * Skip Workout Handler
 *
 * Marks a workout as skipped and returns info about the next scheduled workout.
 * Validates that the workout exists and hasn't already been completed/skipped.
 */

import {HandlerContext, HandlerResult} from "./index";

interface WorkoutDoc {
  id?: string;
  name?: string;
  scheduledDate?: string;
  status?: string;
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
 * Handle skip_workout tool call
 *
 * @param args - { workoutId: string }
 * @param context - Handler context with uid and db
 * @returns Status message and next workout info
 */
export async function skipWorkoutHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const workoutId = args.workoutId as string;
  const {uid, db} = context;

  // Validate workoutId provided
  if (!workoutId) {
    return {
      output: "ERROR: No workout ID provided. Please specify which workout to skip.",
    };
  }

  // Fetch the workout
  const workoutRef = db.doc(`users/${uid}/workouts/${workoutId}`);
  const workoutDoc = await workoutRef.get();

  if (!workoutDoc.exists) {
    return {
      output: `ERROR: Workout not found. The workout ID "${workoutId}" does not exist.`,
    };
  }

  const workout = workoutDoc.data() as WorkoutDoc;
  const workoutName = workout.name || "Workout";

  // Check if already skipped or completed
  if (workout.status === "skipped") {
    return {
      output: `"${workoutName}" has already been skipped.`,
    };
  }

  if (workout.status === "completed") {
    return {
      output: `Cannot skip "${workoutName}" - it has already been completed.`,
    };
  }

  // Update status to skipped
  await workoutRef.update({
    status: "skipped",
    updatedAt: new Date().toISOString(),
  });

  // Find next scheduled workout
  const now = new Date().toISOString();
  const nextSnapshot = await db
    .collection(`users/${uid}/workouts`)
    .where("status", "==", "scheduled")
    .where("scheduledDate", ">", now)
    .orderBy("scheduledDate", "asc")
    .limit(1)
    .get();

  // Build response based on whether there's a next workout
  if (nextSnapshot.empty) {
    return {
      output: `"${workoutName}" has been skipped. You have no more scheduled workouts.`,
      suggestionChips: [
        {label: "Create workout", command: "Create a workout for today"},
        {label: "Show schedule", command: "Show my schedule"},
      ],
    };
  }

  const nextDoc = nextSnapshot.docs[0];
  const nextWorkout = nextDoc.data() as WorkoutDoc;
  const nextName = nextWorkout.name || "Workout";
  const nextDate = nextWorkout.scheduledDate ?
    formatDate(new Date(nextWorkout.scheduledDate)) :
    "soon";

  return {
    output: `"${workoutName}" has been skipped.

Your next workout is "${nextName}" on ${nextDate}.

[VOICE_READY]
Confirm the skip and mention when the next workout is scheduled.`,
    suggestionChips: [
      {label: `Start ${nextName}`, command: `Start workout ${nextDoc.id}`},
      {label: "Show schedule", command: "Show my schedule"},
    ],
  };
}
