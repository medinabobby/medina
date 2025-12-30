/**
 * Add to Library Handler
 *
 * Adds an exercise to the user's favorites library.
 * Port of iOS AddToLibraryHandler.swift
 *
 * Firestore structure:
 *   users/{uid}/library/exercises → { exerciseIds: string[] }
 */

import type {HandlerContext, HandlerResult} from "./index";

/**
 * Add an exercise to user's library
 */
export async function addToLibraryHandler(
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
    // Get the user's library document
    const libraryRef = db
      .collection("users")
      .doc(uid)
      .collection("library")
      .doc("exercises");

    const libraryDoc = await libraryRef.get();
    const currentExercises: string[] = libraryDoc.exists ?
      (libraryDoc.data()?.exerciseIds || []) :
      [];

    // Check for duplicates
    if (currentExercises.includes(normalizedId)) {
      return {
        output: `The exercise "${formatExerciseName(normalizedId)}" is already in your library.`,
        suggestionChips: [
          {label: "Show library", command: "show my exercise library"},
          {label: "Add another", command: "add exercise to library"},
        ],
      };
    }

    // Add the exercise
    const updatedExercises = [...currentExercises, normalizedId];

    await libraryRef.set(
      {
        exerciseIds: updatedExercises,
        lastModified: new Date(),
      },
      {merge: true}
    );

    return {
      output: `Added "${formatExerciseName(normalizedId)}" to your library.`,
      suggestionChips: [
        {label: "Create workout", command: `create workout with ${normalizedId}`},
        {label: "Add another", command: "add exercise to library"},
      ],
    };
  } catch (error) {
    console.error("[addToLibrary] Error:", error);
    return {
      output: `ERROR: Failed to add exercise to library. ${
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
