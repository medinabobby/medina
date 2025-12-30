/**
 * Get Summary Handler
 *
 * Returns summary of workout, program, or plan progress.
 * Port of iOS GetSummaryHandler.swift
 *
 * Parameters:
 *   scope: "workout", "program", or "plan"
 *   id: ID of the entity to summarize
 */

import type {HandlerContext, HandlerResult} from "./index";

interface WorkoutExercise {
  exerciseId: string;
  sets: number;
  reps?: number;
  status?: string;
}

interface Workout {
  id: string;
  name?: string;
  status: string;
  scheduledDate?: string;
  completedDate?: string;
  exercises?: WorkoutExercise[];
  estimatedDuration?: number;
  actualDuration?: number;
}

interface Plan {
  id: string;
  name: string;
  status: string;
  startDate?: string;
  programIds?: string[];
}

/**
 * Format exercise ID for display
 */
function formatExerciseName(exerciseId: string): string {
  return exerciseId
    .split("_")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

/**
 * Get summary of workout, program, or plan
 */
export async function getSummaryHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;

  const scope = args.scope as string | undefined;
  const id = args.id as string | undefined;

  if (!scope || !id) {
    return {
      output: "ERROR: Missing required parameters. Please specify 'scope' and 'id'.",
    };
  }

  try {
    switch (scope) {
    case "workout":
      return await getWorkoutSummary(uid, id, db);

    case "plan":
      return await getPlanSummary(uid, id, db);

    case "program":
      return {
        output: `Program summary for "${id}" - Program summaries are available within plan context.`,
        suggestionChips: [
          {label: "Show plan", command: "show my training plan"},
        ],
      };

    default:
      return {
        output: `ERROR: Invalid scope '${scope}'. Use 'workout', 'program', or 'plan'.`,
      };
    }
  } catch (error) {
    console.error("[getSummary] Error:", error);
    return {
      output: `ERROR: Failed to get summary. ${
        error instanceof Error ? error.message : "Unknown error"
      }`,
    };
  }
}

/**
 * Get workout summary
 */
async function getWorkoutSummary(
  uid: string,
  workoutId: string,
  db: FirebaseFirestore.Firestore
): Promise<HandlerResult> {
  const workoutRef = db
    .collection("users")
    .doc(uid)
    .collection("workouts")
    .doc(workoutId);

  const workoutDoc = await workoutRef.get();

  if (!workoutDoc.exists) {
    return {
      output: `ERROR: Workout not found with ID: ${workoutId}`,
    };
  }

  const workout = workoutDoc.data() as Workout;
  const exercises = workout.exercises || [];
  const completedExercises = exercises.filter((e) => e.status === "completed").length;
  const totalSets = exercises.reduce((sum, e) => sum + (e.sets || 0), 0);
  const completedSets = exercises
    .filter((e) => e.status === "completed")
    .reduce((sum, e) => sum + (e.sets || 0), 0);

  const durationText = workout.actualDuration ?
    `${Math.round(workout.actualDuration / 60)} minutes` :
    workout.estimatedDuration ?
      `~${Math.round(workout.estimatedDuration / 60)} minutes (estimated)` :
      "Duration not tracked";

  let output = `WORKOUT SUMMARY: "${workout.name || "Workout"}"\n`;
  output += `Status: ${workout.status}\n`;
  output += `Duration: ${durationText}\n`;
  output += `Exercises: ${completedExercises} of ${exercises.length} completed\n`;
  output += `Sets: ${completedSets} of ${totalSets} completed\n\n`;

  if (exercises.length > 0) {
    output += "EXERCISE BREAKDOWN:\n";
    exercises.forEach((ex) => {
      const name = formatExerciseName(ex.exerciseId);
      const status = ex.status === "completed" ? "Completed" :
        ex.status === "skipped" ? "Skipped" : "Pending";
      output += `- ${name}: ${status}\n`;
    });
  }

  return {
    output,
    suggestionChips: [
      {label: "Next workout", command: "what's my next workout"},
      {label: "Show schedule", command: "show my schedule"},
    ],
  };
}

/**
 * Get plan summary
 */
async function getPlanSummary(
  uid: string,
  planId: string,
  db: FirebaseFirestore.Firestore
): Promise<HandlerResult> {
  const planRef = db
    .collection("users")
    .doc(uid)
    .collection("plans")
    .doc(planId);

  const planDoc = await planRef.get();

  if (!planDoc.exists) {
    return {
      output: `ERROR: Plan not found with ID: ${planId}`,
    };
  }

  const plan = planDoc.data() as Plan;

  // Get workouts for this plan
  const workoutsSnap = await db
    .collection("users")
    .doc(uid)
    .collection("workouts")
    .where("planId", "==", planId)
    .get();

  const workouts = workoutsSnap.docs.map((doc) => doc.data() as Workout);
  const completedWorkouts = workouts.filter((w) => w.status === "completed").length;

  // Collect unique exercises
  const exerciseIds = new Set<string>();
  workouts.forEach((w) => {
    (w.exercises || []).forEach((e) => exerciseIds.add(e.exerciseId));
  });

  let output = `PLAN SUMMARY: "${plan.name}"\n`;
  output += `Status: ${plan.status}\n`;
  output += `Workouts: ${completedWorkouts} of ${workouts.length} completed\n`;
  output += `Unique exercises: ${exerciseIds.size}\n\n`;

  if (exerciseIds.size > 0) {
    output += "EXERCISES IN THIS PLAN:\n";
    Array.from(exerciseIds)
      .slice(0, 10)
      .forEach((id) => {
        output += `- ${formatExerciseName(id)}\n`;
      });
    if (exerciseIds.size > 10) {
      output += `... and ${exerciseIds.size - 10} more\n`;
    }
  }

  return {
    output,
    suggestionChips: [
      {label: "Today's workout", command: "what's my workout today"},
      {label: "Show schedule", command: "show my schedule"},
    ],
  };
}
