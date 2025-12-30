/**
 * Get Substitution Options Handler
 *
 * Finds alternative exercises for a given exercise.
 * Port of iOS GetSubstitutionHandler.swift
 *
 * Note: This simplified version provides basic substitution suggestions
 * based on exercise category patterns. Full implementation would require
 * the exercise database to be available in Firestore.
 *
 * Parameters:
 *   exerciseId: Exercise ID to find substitutes for
 *   workoutId: (optional) Context for equipment restrictions
 */

import type {HandlerContext, HandlerResult} from "./index";

/**
 * Basic exercise category mapping for substitution suggestions
 */
const EXERCISE_CATEGORIES: Record<string, string[]> = {
  // Chest movements
  "bench_press": ["dumbbell_bench_press", "push_up", "cable_fly", "machine_chest_press"],
  "incline_bench_press": ["incline_dumbbell_press", "incline_push_up", "low_cable_fly"],
  "dumbbell_bench_press": ["bench_press", "push_up", "cable_fly"],
  "push_up": ["bench_press", "dumbbell_bench_press", "cable_fly"],

  // Back movements
  "pull_up": ["lat_pulldown", "assisted_pull_up", "chin_up", "cable_row"],
  "lat_pulldown": ["pull_up", "cable_row", "dumbbell_row"],
  "barbell_row": ["dumbbell_row", "cable_row", "t_bar_row", "machine_row"],
  "dumbbell_row": ["barbell_row", "cable_row", "machine_row"],

  // Shoulder movements
  "overhead_press": ["dumbbell_shoulder_press", "arnold_press", "machine_shoulder_press"],
  "lateral_raise": ["cable_lateral_raise", "machine_lateral_raise", "dumbbell_lateral_raise"],

  // Leg movements
  "squat": ["leg_press", "goblet_squat", "hack_squat", "front_squat"],
  "leg_press": ["squat", "hack_squat", "lunge"],
  "deadlift": ["romanian_deadlift", "trap_bar_deadlift", "hip_thrust"],
  "lunge": ["split_squat", "bulgarian_split_squat", "step_up"],

  // Arm movements
  "bicep_curl": ["hammer_curl", "cable_curl", "preacher_curl", "concentration_curl"],
  "tricep_pushdown": ["skull_crusher", "tricep_dip", "close_grip_bench_press"],
};

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
 * Find the best matching category for an exercise
 */
function findExerciseCategory(exerciseId: string): string | null {
  const normalizedId = exerciseId.toLowerCase().replace(/\s+/g, "_");

  // Direct match
  if (EXERCISE_CATEGORIES[normalizedId]) {
    return normalizedId;
  }

  // Partial match - check if any category key is contained in the exercise ID
  for (const category of Object.keys(EXERCISE_CATEGORIES)) {
    if (normalizedId.includes(category) || category.includes(normalizedId)) {
      return category;
    }
  }

  return null;
}

/**
 * Get substitution options for an exercise
 */
export async function getSubstitutionOptionsHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const exerciseId = args.exerciseId as string | undefined;
  if (!exerciseId) {
    return {
      output: "ERROR: Missing exerciseId parameter.",
    };
  }

  // Normalize exercise ID
  const normalizedId = exerciseId
    .toLowerCase()
    .replace(/\s+/g, "_")
    .replace(/-/g, "_");

  const exerciseName = formatExerciseName(normalizedId);

  // Find matching category
  const category = findExerciseCategory(normalizedId);

  if (!category || !EXERCISE_CATEGORIES[category]) {
    // No known substitutes - provide general guidance
    return {
      output: `No pre-defined alternatives found for "${exerciseName}".\n` +
        "Suggestions:\n" +
        "1. Look for exercises targeting the same muscle group\n" +
        "2. Consider equipment availability\n" +
        "3. Match the movement pattern (push, pull, hinge, squat, etc.)\n\n" +
        "Ask me about a specific exercise type for more targeted suggestions.",
      suggestionChips: [
        {label: "Chest exercises", command: "show me chest exercise alternatives"},
        {label: "Back exercises", command: "show me back exercise alternatives"},
        {label: "Leg exercises", command: "show me leg exercise alternatives"},
      ],
    };
  }

  const alternatives = EXERCISE_CATEGORIES[category];
  const displayAlternatives = alternatives
    .filter((alt) => alt !== normalizedId)
    .slice(0, 5);

  if (displayAlternatives.length === 0) {
    return {
      output: `No alternatives found for "${exerciseName}".`,
    };
  }

  let output = `Found ${displayAlternatives.length} alternatives for ${exerciseName}:\n\n`;

  displayAlternatives.forEach((alt, index) => {
    output += `${index + 1}. ${formatExerciseName(alt)}\n`;
  });

  output += "\nThese exercises target similar muscle groups and movement patterns.";

  return {
    output,
    suggestionChips: [
      {label: "Substitute first", command: `use ${formatExerciseName(displayAlternatives[0])} instead`},
      {label: "More options", command: "show me more exercise options"},
    ],
  };
}
