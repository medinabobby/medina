/**
 * Modify Workout Handler
 *
 * Migrated from iOS: ModifyWorkoutHandler.swift, WorkoutModificationService.swift
 * Handles modify_workout tool calls - modifies existing workout via delete + recreate pattern
 */

import * as admin from "firebase-admin";
import {HandlerContext, HandlerResult, SuggestionChip, WorkoutCardData} from "./index";

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
  protocolCustomizations?: ProtocolCustomizationArg[];
}

/**
 * Protocol customization from tool args
 */
interface ProtocolCustomizationArg {
  exercisePosition: number;
  repsAdjustment?: number;
  restAdjustment?: number;
  setsAdjustment?: number;
  tempoOverride?: string;
  rpeOverride?: number;
  rationale?: string;
}

/**
 * Split day types (matches iOS SplitDay enum)
 */
type SplitDay = "upper" | "lower" | "push" | "pull" | "legs" | "fullBody" |
  "chest" | "back" | "shoulders" | "arms" | "notApplicable";

/**
 * Effort level types
 */
type EffortLevel = "recovery" | "standard" | "push";

/**
 * Session type
 */
type SessionType = "strength" | "cardio";

/**
 * Workout status types
 */
type WorkoutStatus = "scheduled" | "inProgress" | "completed" | "skipped";

/**
 * Workout document from Firestore
 */
interface WorkoutDocument {
  id: string;
  name: string;
  scheduledDate: string;
  type: SessionType;
  splitDay: SplitDay;
  status: WorkoutStatus;
  exerciseIds: string[];
  protocolVariantIds: Record<string, string>;
  planId?: string;
  programId?: string;
  createdAt: string;
  updatedAt: string;
}

/**
 * Plan document from Firestore
 */
interface PlanDocument {
  id: string;
  name: string;
  status: string;
  targetSessionDuration?: number;
  trainingLocation?: string;
  availableEquipment?: string[];
  isSingleWorkout?: boolean;
}

// ============================================================================
// Constants
// ============================================================================

/**
 * Effort level to intensity mapping
 */
const EFFORT_INTENSITY: Record<EffortLevel, number> = {
  recovery: 0.60,
  standard: 0.75,
  push: 0.85,
};

/**
 * Exercise count based on duration
 */
function getExerciseCount(duration: number): number {
  if (duration <= 30) return 3;
  if (duration <= 45) return 4;
  if (duration <= 60) return 5;
  if (duration <= 75) return 6;
  return 7;
}

/**
 * Default protocols for exercise types and intensities
 */
function getDefaultProtocol(exerciseType: string, intensity: number): string {
  if (exerciseType === "cardio") {
    return "cardio_30min_steady";
  }

  if (exerciseType === "compound") {
    if (intensity < 0.65) return "strength_3x5_moderate";
    if (intensity < 0.80) return "strength_3x5_heavy";
    return "strength_3x3_heavy";
  }

  // Isolation
  if (intensity < 0.65) return "accessory_3x12_light";
  if (intensity < 0.80) return "accessory_3x10_rpe8";
  return "accessory_3x8_rpe8";
}

/**
 * Generate workout name based on split day
 */
function generateWorkoutName(splitDay: SplitDay): string {
  const names: Record<SplitDay, string> = {
    upper: "Upper Body Strength",
    lower: "Lower Body Strength",
    push: "Push Day",
    pull: "Pull Day",
    legs: "Leg Day - Strength Focus",
    fullBody: "Full Body Strength",
    chest: "Chest Focus",
    back: "Back Focus",
    shoulders: "Shoulders Focus",
    arms: "Arms Focus",
    notApplicable: "Workout",
  };
  return names[splitDay] || "Workout";
}

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Parse scheduled date string
 */
function parseScheduledDate(dateStr: string | undefined): Date {
  if (!dateStr) return new Date();
  const parsed = new Date(dateStr);
  return isNaN(parsed.getTime()) ? new Date() : parsed;
}

/**
 * Format date for display
 */
function formatDate(date: Date): string {
  return date.toLocaleDateString("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
  });
}

/**
 * Delete workout and all its exercise instances
 */
async function deleteWorkout(
  db: admin.firestore.Firestore,
  uid: string,
  workoutId: string
): Promise<void> {
  const batch = db.batch();

  // Delete exercise instances
  const instancesSnap = await db
    .collection(`users/${uid}/workouts/${workoutId}/instances`)
    .get();

  for (const doc of instancesSnap.docs) {
    batch.delete(doc.ref);
  }

  // Delete workout document
  const workoutRef = db.collection(`users/${uid}/workouts`).doc(workoutId);
  batch.delete(workoutRef);

  await batch.commit();
  console.log(`[modify_workout] Deleted workout ${workoutId} with ${instancesSnap.size} instances`);
}

/**
 * Get exercises from global collection
 */
async function getExercisesForWorkout(
  db: admin.firestore.Firestore,
  exerciseIds: string[]
): Promise<Array<{id: string; name: string; exerciseType: string}>> {
  const exercises: Array<{id: string; name: string; exerciseType: string}> = [];

  for (const exerciseId of exerciseIds) {
    const doc = await db.collection("exercises").doc(exerciseId).get();
    if (doc.exists) {
      const data = doc.data();
      exercises.push({
        id: doc.id,
        name: data?.name || exerciseId,
        exerciseType: data?.exerciseType || "compound",
      });
    }
  }

  return exercises;
}

/**
 * Create exercise instances for the workout
 */
async function createExerciseInstances(
  db: admin.firestore.Firestore,
  uid: string,
  workoutId: string,
  exerciseIds: string[],
  intensity: number,
  exercises: Array<{id: string; name: string; exerciseType: string}>,
  overrideProtocolId?: string
): Promise<Record<string, string>> {
  const batch = db.batch();
  const protocolVariantIds: Record<string, string> = {};

  for (let i = 0; i < exerciseIds.length; i++) {
    const exerciseId = exerciseIds[i];
    const exercise = exercises.find((e) => e.id === exerciseId);
    const instanceId = `instance_${workoutId}_${i}`;

    // Determine protocol
    const protocolId = overrideProtocolId ||
      getDefaultProtocol(exercise?.exerciseType || "compound", intensity);

    protocolVariantIds[i.toString()] = protocolId;

    const instanceDoc = {
      id: instanceId,
      workoutId,
      exerciseId,
      protocolVariantId: protocolId,
      position: i,
      createdAt: new Date().toISOString(),
    };

    const instanceRef = db
      .collection(`users/${uid}/workouts/${workoutId}/instances`)
      .doc(instanceId);

    batch.set(instanceRef, instanceDoc);
  }

  await batch.commit();
  return protocolVariantIds;
}

// ============================================================================
// Main Handler
// ============================================================================

/**
 * Handle modify_workout tool call
 *
 * Flow:
 * 1. Validate workout exists and can be modified
 * 2. Capture original values as defaults
 * 3. Delete old workout and instances
 * 4. Create new workout with merged parameters
 * 5. Return new workout details
 */
export async function modifyWorkoutHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;
  const {
    workoutId,
    newDuration,
    newSplitDay: newSplitDayStr,
    newEffortLevel: newEffortLevelStr,
    newName,
    newScheduledDate: newScheduledDateStr,
    newSessionType: newSessionTypeStr,
    newTrainingLocation: _newTrainingLocation,
    protocolCustomizations: _protocolCustomizations,
  } = args as ModifyWorkoutArgs;

  // Validate workout ID
  if (!workoutId) {
    return {
      output: "ERROR: Missing required parameter 'workoutId'. Please specify which workout to modify.",
    };
  }

  console.log(`[modify_workout] Modifying workout ${workoutId} for user ${uid}`);

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

    const workout = workoutDoc.data() as WorkoutDocument;

    // 2. Validate status
    if (workout.status === "inProgress") {
      return {
        output: `ERROR: Cannot modify workout '${workout.name}' because it's currently in progress. End or abandon it first.`,
        suggestionChips: [
          {label: "End workout", command: `End workout ${workoutId}`},
          {label: "Abandon workout", command: `Abandon workout ${workoutId}`},
        ],
      };
    }

    if (workout.status === "completed") {
      return {
        output: `ERROR: Cannot modify completed workout '${workout.name}'. This is a historical record. Would you like me to create a new one instead?`,
        suggestionChips: [
          {label: "Create similar", command: `Create a ${workout.splitDay} workout`},
          {label: "Show schedule", command: "Show my schedule"},
        ],
      };
    }

    // 3. Get plan for duration default (if workout has a plan)
    let originalDuration = 45; // Default
    if (workout.planId) {
      const planDoc = await db.collection(`users/${uid}/plans`).doc(workout.planId).get();
      if (planDoc.exists) {
        const plan = planDoc.data() as PlanDocument;
        originalDuration = plan.targetSessionDuration || 45;
      }
    }

    // 4. Capture original values
    const originalName = workout.name;
    const originalDate = new Date(workout.scheduledDate);
    const originalSplitDay = workout.splitDay || "fullBody";
    const originalSessionType = workout.type || "strength";
    const originalExerciseIds = workout.exerciseIds || [];

    // 5. Determine new values (new overrides original)
    const finalSplitDay = (newSplitDayStr as SplitDay) || originalSplitDay;
    const finalEffortLevel = (newEffortLevelStr as EffortLevel) || "standard";
    const finalSessionType = (newSessionTypeStr as SessionType) || originalSessionType;
    const finalDate = newScheduledDateStr ? parseScheduledDate(newScheduledDateStr) : originalDate;
    const finalDuration = newDuration || originalDuration;

    // Auto-generate name if split changed but no explicit name
    const splitChanged = newSplitDayStr && newSplitDayStr !== originalSplitDay;
    const finalName = newName || (splitChanged ? generateWorkoutName(finalSplitDay) : originalName);

    // Determine if structural change (affects exercise selection)
    const structuralChange =
      (newSplitDayStr && newSplitDayStr !== originalSplitDay) ||
      (newDuration && newDuration !== originalDuration) ||
      (newSessionTypeStr && newSessionTypeStr !== originalSessionType);

    // Preserve exercises if no structural change
    const preserveExercises = !structuralChange;

    const intensity = EFFORT_INTENSITY[finalEffortLevel] || 0.75;

    console.log(`[modify_workout] Original: ${originalName}, Split: ${originalSplitDay}, Duration: ${originalDuration}`);
    console.log(`[modify_workout] New: ${finalName}, Split: ${finalSplitDay}, Duration: ${finalDuration}, Preserve: ${preserveExercises}`);

    // 6. Delete the old workout
    await deleteWorkout(db, uid, workoutId);

    // 7. Determine exercise IDs for new workout
    let exerciseIds: string[];

    if (preserveExercises && originalExerciseIds.length > 0) {
      // Keep original exercises
      exerciseIds = originalExerciseIds;
      console.log(`[modify_workout] Preserving ${exerciseIds.length} exercises`);
    } else {
      // Need to select new exercises based on split day
      // For simplicity, query exercises that match the split day
      const targetMuscles = getMusclesForSplit(finalSplitDay);
      const exerciseCount = getExerciseCount(finalDuration);

      const exercisesSnap = await db.collection("exercises")
        .where("muscleGroups", "array-contains-any", targetMuscles.slice(0, 10)) // Firestore limit
        .limit(exerciseCount)
        .get();

      exerciseIds = exercisesSnap.docs.map((doc) => doc.id);
      console.log(`[modify_workout] Selected ${exerciseIds.length} new exercises for ${finalSplitDay}`);
    }

    // 8. Fetch exercise details
    const exercises = await getExercisesForWorkout(db, exerciseIds);

    // 9. Generate new workout ID
    const newWorkoutId = `${uid}_workout_${Date.now()}`;

    // 10. Create exercise instances
    const protocolVariantIds = await createExerciseInstances(
      db,
      uid,
      newWorkoutId,
      exerciseIds,
      intensity,
      exercises
    );

    // 11. Create new workout document
    const newWorkoutDoc: WorkoutDocument = {
      id: newWorkoutId,
      name: finalName,
      scheduledDate: finalDate.toISOString(),
      type: finalSessionType,
      splitDay: finalSplitDay,
      status: "scheduled",
      exerciseIds,
      protocolVariantIds,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };

    // Preserve plan/program association if original had one
    if (workout.planId) {
      newWorkoutDoc.planId = workout.planId;
    }
    if (workout.programId) {
      newWorkoutDoc.programId = workout.programId;
    }

    await db.collection(`users/${uid}/workouts`).doc(newWorkoutId).set(newWorkoutDoc);

    console.log(`[modify_workout] Created new workout ${newWorkoutId} with ${exerciseIds.length} exercises`);

    // 12. Format response
    const exerciseNames = exercises.slice(0, 5).map((e) => e.name);
    const exerciseList = exerciseNames.join(", ") + (exercises.length > 5 ? "..." : "");

    const output = `SUCCESS: Workout modified.

NEW_WORKOUT_ID: ${newWorkoutId}
Name: ${finalName}
Date: ${formatDate(finalDate)}
Exercise count: ${exerciseIds.length}
Exercises: ${exerciseList}

INSTRUCTIONS:
1. Confirm the modification was successful
2. Briefly describe what changed
3. Tell the user the updated workout link is below`;

    const chips: SuggestionChip[] = [
      {label: "Start workout", command: `Start workout ${newWorkoutId}`},
      {label: "Show schedule", command: "Show my schedule"},
    ];

    const workoutCard: WorkoutCardData = {
      workoutId: newWorkoutId,
      workoutName: finalName,
    };

    return {
      output,
      suggestionChips: chips,
      workoutCard,
    };
  } catch (error) {
    console.error(`[modify_workout] Error:`, error);
    return {
      output: `ERROR: Failed to modify workout. ${error instanceof Error ? error.message : "Unknown error"}`,
      suggestionChips: [
        {label: "Try again", command: `Modify workout ${workoutId}`},
        {label: "Show schedule", command: "Show my schedule"},
      ],
    };
  }
}

/**
 * Get target muscle groups for a split day
 */
function getMusclesForSplit(splitDay: SplitDay): string[] {
  const muscles: Record<SplitDay, string[]> = {
    upper: ["chest", "back", "shoulders", "biceps", "triceps"],
    lower: ["quadriceps", "hamstrings", "glutes", "calves"],
    push: ["chest", "shoulders", "triceps"],
    pull: ["back", "biceps", "traps", "lats"],
    legs: ["quadriceps", "hamstrings", "glutes", "calves"],
    fullBody: ["chest", "back", "quadriceps", "hamstrings", "shoulders"],
    chest: ["chest", "triceps"],
    back: ["back", "biceps", "traps"],
    shoulders: ["shoulders", "traps"],
    arms: ["biceps", "triceps", "forearms"],
    notApplicable: [],
  };
  return muscles[splitDay] || [];
}
