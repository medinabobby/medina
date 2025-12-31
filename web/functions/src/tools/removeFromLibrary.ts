/**
 * Remove from Library Handler
 *
 * Removes an exercise from the user's favorites library.
 * Port of iOS RemoveFromLibraryHandler.swift
 *
 * v242: Unified Firestore structure with iOS:
 *   users/{uid}/preferences/exercise → { favorites: string[] }
 */

import type {HandlerContext, HandlerResult} from "./index";

/**
 * Remove an exercise from user's library
 */
export async function removeFromLibraryHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;

  // Validate required parameter
  const exerciseId = args.exerciseId as string | undefined;
  if (!exerciseId) {
    return {
      output: "ERROR: Missing required parameter 'exerciseId'",
    };
  }

  // Normalize exercise ID (lowercase, underscores)
  const normalizedId = exerciseId
    .toLowerCase()
    .replace(/\s+/g, "_")
    .replace(/-/g, "_");

  try {
    // v242: Use iOS Firestore path for cross-platform compatibility
    const prefsRef = db
      .collection("users")
      .doc(uid)
      .collection("preferences")
      .doc("exercise");

    const prefsDoc = await prefsRef.get();
    const currentExercises: string[] = prefsDoc.exists ?
      (prefsDoc.data()?.favorites || []) :
      [];

    // Check if exercise is in library
    if (!currentExercises.includes(normalizedId)) {
      return {
        output: `The exercise "${formatExerciseName(normalizedId)}" is not in your library.`,
        suggestionChips: [
          {label: "Show library", command: "show my exercise library"},
          {label: "Add exercise", command: "add exercise to library"},
        ],
      };
    }

    // Remove the exercise
    const updatedExercises = currentExercises.filter((id) => id !== normalizedId);

    await prefsRef.set(
      {
        favorites: updatedExercises,
        lastModified: new Date(),
      },
      {merge: true}
    );

    return {
      output: `Removed "${formatExerciseName(normalizedId)}" from your library.`,
      suggestionChips: [
        {label: "Show library", command: "show my exercise library"},
        {label: "Add exercise", command: "add exercise to library"},
      ],
    };
  } catch (error) {
    console.error("[removeFromLibrary] Error:", error);
    return {
      output: `ERROR: Failed to remove exercise from library. ${
        error instanceof Error ? error.message : "Unknown error"
      }`,
    };
  }
}

/**
 * Format exercise ID for display
 * e.g., "barbell_bench_press" → "Barbell Bench Press"
 */
function formatExerciseName(exerciseId: string): string {
  return exerciseId
    .split("_")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}
