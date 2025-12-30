/**
 * Update Exercise Target Handler
 *
 * Saves user's 1RM or working weight for an exercise.
 * Port of iOS UpdateExerciseTargetHandler.swift
 *
 * Parameters:
 *   exercise_id: Exercise ID (e.g., "barbell_bench_press")
 *   weight_lbs: Weight in pounds
 *   weight_type: "1rm" or "working"
 *   reps: (required if weight_type is "working") Number of reps
 *
 * Firestore structure:
 *   users/{uid}/targets/{exerciseId} → ExerciseTarget
 */

import type {HandlerContext, HandlerResult} from "./index";

interface TargetEntry {
  date: string;
  target: number;
  calibrationSource: string;
}

interface ExerciseTarget {
  id: string;
  exerciseId: string;
  memberId: string;
  currentTarget: number;
  lastCalibrated: string;
  targetHistory: TargetEntry[];
}

/**
 * Calculate 1RM using Epley formula
 * 1RM = weight × (1 + reps/30)
 */
function calculateOneRM(weight: number, reps: number): number | null {
  if (reps < 1 || reps > 20) return null;
  if (reps === 1) return weight;
  return weight * (1 + reps / 30);
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
 * Update exercise target (1RM or working weight)
 */
export async function updateExerciseTargetHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;

  // Parse required arguments
  const exerciseId = args.exercise_id as string | undefined;
  if (!exerciseId) {
    return {
      output: "ERROR: Missing exercise_id parameter",
    };
  }

  const weightLbs = typeof args.weight_lbs === "number" ?
    args.weight_lbs :
    parseFloat(args.weight_lbs as string);
  if (isNaN(weightLbs) || weightLbs <= 0) {
    return {
      output: "ERROR: Missing or invalid weight_lbs parameter",
    };
  }

  const weightType = args.weight_type as string | undefined;
  if (!weightType || !["1rm", "working"].includes(weightType)) {
    return {
      output: "ERROR: Missing weight_type parameter (must be '1rm' or 'working')",
    };
  }

  // Normalize exercise ID
  const normalizedId = exerciseId
    .toLowerCase()
    .replace(/\s+/g, "_")
    .replace(/-/g, "_");

  // Calculate effective 1RM
  let effectiveMax = weightLbs;
  let repsUsed: number | null = null;

  if (weightType === "working") {
    const reps = typeof args.reps === "number" ?
      args.reps :
      parseInt(args.reps as string);

    if (isNaN(reps) || reps < 1 || reps > 20) {
      return {
        output: "ERROR: 'reps' is required when weight_type is 'working' (1-20)",
      };
    }

    const calculated = calculateOneRM(weightLbs, reps);
    if (calculated === null) {
      return {
        output: "ERROR: Could not calculate 1RM from provided weight and reps",
      };
    }

    effectiveMax = calculated;
    repsUsed = reps;
  }

  try {
    const targetRef = db
      .collection("users")
      .doc(uid)
      .collection("targets")
      .doc(normalizedId);

    const targetDoc = await targetRef.get();
    const previousMax = targetDoc.exists ?
      (targetDoc.data()?.currentTarget as number | undefined) :
      undefined;

    // Create or update target
    const now = new Date().toISOString();
    const newEntry: TargetEntry = {
      date: now,
      target: Math.round(effectiveMax),
      calibrationSource: "chat_input",
    };

    const existingHistory: TargetEntry[] = targetDoc.exists ?
      (targetDoc.data()?.targetHistory || []) :
      [];

    const target: ExerciseTarget = {
      id: `${uid}-${normalizedId}`,
      exerciseId: normalizedId,
      memberId: uid,
      currentTarget: Math.round(effectiveMax),
      lastCalibrated: now,
      targetHistory: [...existingHistory, newEntry],
    };

    await targetRef.set(target);

    // Also add exercise to library
    const libraryRef = db
      .collection("users")
      .doc(uid)
      .collection("library")
      .doc("exercises");

    const libraryDoc = await libraryRef.get();
    const currentExercises: string[] = libraryDoc.exists ?
      (libraryDoc.data()?.exerciseIds || []) :
      [];

    if (!currentExercises.includes(normalizedId)) {
      await libraryRef.set(
        {
          exerciseIds: [...currentExercises, normalizedId],
          lastModified: new Date(),
        },
        {merge: true}
      );
    }

    // Build response
    const exerciseName = formatExerciseName(normalizedId);
    let response = `SUCCESS: Exercise target updated.\n`;
    response += `Exercise: ${exerciseName}\n`;
    response += `1RM: ${Math.round(effectiveMax)} lbs`;

    if (repsUsed !== null) {
      response += `\nCalculated from: ${Math.round(weightLbs)} lbs x ${repsUsed} reps (Epley formula)`;
    }

    if (previousMax !== undefined) {
      const change = Math.round(effectiveMax) - Math.round(previousMax);
      const changeStr = change >= 0 ? `+${change}` : `${change}`;
      response += `\nPrevious 1RM: ${Math.round(previousMax)} lbs (${changeStr} lbs)`;
    }

    return {
      output: response,
      suggestionChips: [
        {label: "Save another", command: "save my 1RM for another exercise"},
        {label: "Create workout", command: "create a workout"},
      ],
    };
  } catch (error) {
    console.error("[updateExerciseTarget] Error:", error);
    return {
      output: `ERROR: Failed to update exercise target. ${
        error instanceof Error ? error.message : "Unknown error"
      }`,
    };
  }
}
