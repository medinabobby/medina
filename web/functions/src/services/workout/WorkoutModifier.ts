/**
 * Workout Modifier Service
 *
 * v236: In-place workout modifications with history tracking
 *
 * Key improvements over delete+recreate:
 * - Preserves workout ID (stable references, links, etc.)
 * - Tracks modification history in subcollection
 * - Metadata changes are instant (no rebuild)
 * - Structural changes rebuild instances but keep workout ID
 */

import * as admin from "firebase-admin";
import {buildStrengthWorkout} from "./StrengthBuilder";
import {
  WorkoutDocument,
  EffortLevel,
  SplitDay,
  SessionType,
  TrainingLocation,
  Equipment,
  ExerciseInstanceDocument,
  EFFORT_INTENSITY,
} from "./types";

// ============================================================================
// Types
// ============================================================================

/**
 * Modification request
 */
export interface ModifyWorkoutRequest {
  userId: string;
  workoutId: string;

  // Metadata changes (in-place)
  newName?: string;
  newScheduledDate?: Date;
  newEffortLevel?: EffortLevel;

  // Structural changes (requires rebuild)
  newSplitDay?: SplitDay;
  newDuration?: number;
  newSessionType?: SessionType;
  newTrainingLocation?: TrainingLocation;
  newAvailableEquipment?: Equipment[];

  // Exercise-level changes
  exerciseSubstitutions?: ExerciseSubstitution[];
}

/**
 * Exercise substitution request
 */
export interface ExerciseSubstitution {
  position: number;
  newExerciseId: string;
  reason?: string;
}

/**
 * Result of modification
 */
export interface ModifyWorkoutResult {
  workout: WorkoutDocument;
  changeType: ChangeType;
  modificationId: string;
  exerciseCount: number;
}

/**
 * Types of changes
 */
export type ChangeType = "metadata" | "structural" | "substitution";

/**
 * History entry saved to Firestore
 */
export interface WorkoutHistoryEntry {
  id: string;
  version: number;
  snapshot: WorkoutDocument;
  instanceSnapshots: ExerciseInstanceDocument[];
  changeType: ChangeType;
  changeDescription: string;
  modifiedAt: string;
}

// ============================================================================
// Change Classification
// ============================================================================

/**
 * Classify the type of modification
 */
export function classifyChange(
  original: WorkoutDocument,
  request: ModifyWorkoutRequest
): ChangeType {
  // Structural changes require rebuilding instances
  if (request.newSplitDay && request.newSplitDay !== original.splitDay) {
    return "structural";
  }

  if (request.newSessionType && request.newSessionType !== original.type) {
    return "structural";
  }

  // Duration change >15 min is structural (different exercise count)
  if (request.newDuration) {
    const originalDuration = original.targetDuration || 45;
    if (Math.abs(request.newDuration - originalDuration) > 15) {
      return "structural";
    }
  }

  // Location/equipment change is structural (different exercise selection)
  if (request.newTrainingLocation || request.newAvailableEquipment) {
    return "structural";
  }

  // Exercise substitutions
  if (request.exerciseSubstitutions && request.exerciseSubstitutions.length > 0) {
    return "substitution";
  }

  // Everything else is metadata
  return "metadata";
}

/**
 * Generate description of changes for history
 */
export function describeChanges(
  original: WorkoutDocument,
  request: ModifyWorkoutRequest,
  changeType: ChangeType
): string {
  const changes: string[] = [];

  if (request.newName && request.newName !== original.name) {
    changes.push(`name: "${original.name}" → "${request.newName}"`);
  }

  if (request.newScheduledDate) {
    const origDate = new Date(original.scheduledDate).toISOString().split("T")[0];
    const newDate = request.newScheduledDate.toISOString().split("T")[0];
    if (origDate !== newDate) {
      changes.push(`date: ${origDate} → ${newDate}`);
    }
  }

  if (request.newEffortLevel && request.newEffortLevel !== original.effortLevel) {
    changes.push(`effort: ${original.effortLevel || "standard"} → ${request.newEffortLevel}`);
  }

  if (request.newSplitDay && request.newSplitDay !== original.splitDay) {
    changes.push(`split: ${original.splitDay} → ${request.newSplitDay}`);
  }

  if (request.newDuration) {
    const origDur = original.targetDuration || 45;
    if (request.newDuration !== origDur) {
      changes.push(`duration: ${origDur}min → ${request.newDuration}min`);
    }
  }

  if (request.newSessionType && request.newSessionType !== original.type) {
    changes.push(`type: ${original.type} → ${request.newSessionType}`);
  }

  if (request.exerciseSubstitutions && request.exerciseSubstitutions.length > 0) {
    changes.push(`${request.exerciseSubstitutions.length} exercise substitution(s)`);
  }

  return changes.length > 0 ? changes.join(", ") : "no changes";
}

// ============================================================================
// History Tracking
// ============================================================================

/**
 * Save workout state to history before modification
 */
export async function saveHistory(
  db: admin.firestore.Firestore,
  userId: string,
  workout: WorkoutDocument,
  instances: ExerciseInstanceDocument[],
  changeType: ChangeType,
  changeDescription: string
): Promise<string> {
  const historyRef = db
    .collection(`users/${userId}/workouts/${workout.id}/history`)
    .doc();

  const version = (workout.version || 0) + 1;

  const historyEntry: WorkoutHistoryEntry = {
    id: historyRef.id,
    version,
    snapshot: workout,
    instanceSnapshots: instances,
    changeType,
    changeDescription,
    modifiedAt: new Date().toISOString(),
  };

  await historyRef.set(historyEntry);

  console.log(`[WorkoutModifier] Saved history v${version} for workout ${workout.id}`);
  return historyRef.id;
}

/**
 * Load current instances for a workout
 */
async function loadInstances(
  db: admin.firestore.Firestore,
  userId: string,
  workoutId: string
): Promise<ExerciseInstanceDocument[]> {
  const snap = await db
    .collection(`users/${userId}/workouts/${workoutId}/exerciseInstances`)
    .orderBy("position")
    .get();

  return snap.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  })) as ExerciseInstanceDocument[];
}

// ============================================================================
// Modification Handlers
// ============================================================================

/**
 * Apply metadata changes in-place (no rebuild)
 */
async function applyMetadataChanges(
  db: admin.firestore.Firestore,
  userId: string,
  workout: WorkoutDocument,
  request: ModifyWorkoutRequest
): Promise<WorkoutDocument> {
  const updates: Partial<WorkoutDocument> = {
    updatedAt: new Date().toISOString(),
    version: (workout.version || 0) + 1,
  };

  if (request.newName) {
    updates.name = request.newName;
  }

  if (request.newScheduledDate) {
    updates.scheduledDate = request.newScheduledDate.toISOString();
  }

  if (request.newEffortLevel) {
    updates.effortLevel = request.newEffortLevel;

    // Also update target weights on instances if effort changed
    const intensity = EFFORT_INTENSITY[request.newEffortLevel];
    await updateInstanceTargetWeights(db, userId, workout.id, intensity);
  }

  await db
    .collection(`users/${userId}/workouts`)
    .doc(workout.id)
    .update(updates);

  console.log(`[WorkoutModifier] Applied metadata changes to ${workout.id}`);

  return {
    ...workout,
    ...updates,
  };
}

/**
 * Update target weights on instances when effort level changes
 */
async function updateInstanceTargetWeights(
  db: admin.firestore.Firestore,
  userId: string,
  workoutId: string,
  newIntensity: number
): Promise<void> {
  const instancesSnap = await db
    .collection(`users/${userId}/workouts/${workoutId}/exerciseInstances`)
    .get();

  if (instancesSnap.empty) return;

  // Load user's 1RM data
  const oneRepMaxSnap = await db
    .collection(`users/${userId}/oneRepMaxes`)
    .get();

  const oneRepMaxMap = new Map<string, number>();
  oneRepMaxSnap.docs.forEach((doc) => {
    oneRepMaxMap.set(doc.id, doc.data().weight);
  });

  const batch = db.batch();

  for (const doc of instancesSnap.docs) {
    const instance = doc.data();
    const exerciseId = instance.exerciseId;

    const oneRM = oneRepMaxMap.get(exerciseId);
    if (oneRM) {
      const newTargetWeight = Math.round((oneRM * newIntensity) / 5) * 5;
      batch.update(doc.ref, {targetWeight: newTargetWeight});
    }
  }

  await batch.commit();
  console.log(`[WorkoutModifier] Updated target weights for ${instancesSnap.size} instances`);
}

/**
 * Apply exercise substitutions
 */
async function applySubstitutions(
  db: admin.firestore.Firestore,
  userId: string,
  workout: WorkoutDocument,
  substitutions: ExerciseSubstitution[]
): Promise<WorkoutDocument> {
  const batch = db.batch();

  // Update exerciseIds array
  const newExerciseIds = [...workout.exerciseIds];

  for (const sub of substitutions) {
    if (sub.position >= 0 && sub.position < newExerciseIds.length) {
      const oldExerciseId = newExerciseIds[sub.position];
      newExerciseIds[sub.position] = sub.newExerciseId;

      // Update the instance
      const instanceId = `instance_${workout.id}_${sub.position}`;
      const instanceRef = db
        .collection(`users/${userId}/workouts/${workout.id}/exerciseInstances`)
        .doc(instanceId);

      batch.update(instanceRef, {
        exerciseId: sub.newExerciseId,
        substitutedFrom: oldExerciseId,
        substitutionReason: sub.reason || null,
      });

      console.log(`[WorkoutModifier] Substituted pos ${sub.position}: ${oldExerciseId} → ${sub.newExerciseId}`);
    }
  }

  // Update workout document
  const workoutRef = db.collection(`users/${userId}/workouts`).doc(workout.id);
  const updates: Partial<WorkoutDocument> = {
    exerciseIds: newExerciseIds,
    updatedAt: new Date().toISOString(),
    version: (workout.version || 0) + 1,
  };

  batch.update(workoutRef, updates);
  await batch.commit();

  return {
    ...workout,
    ...updates,
    exerciseIds: newExerciseIds,
  };
}

/**
 * Rebuild workout for structural changes
 * Deletes instances and recreates, but keeps workout ID
 */
async function rebuildWorkout(
  db: admin.firestore.Firestore,
  userId: string,
  workout: WorkoutDocument,
  request: ModifyWorkoutRequest
): Promise<WorkoutDocument> {
  // Delete existing instances
  const instancesSnap = await db
    .collection(`users/${userId}/workouts/${workout.id}/exerciseInstances`)
    .get();

  const deleteBatch = db.batch();
  for (const doc of instancesSnap.docs) {
    deleteBatch.delete(doc.ref);
  }
  await deleteBatch.commit();

  console.log(`[WorkoutModifier] Deleted ${instancesSnap.size} instances for rebuild`);

  // Build new workout using StrengthBuilder
  const result = await buildStrengthWorkout(db, {
    userId,
    name: request.newName || workout.name,
    targetDuration: request.newDuration || workout.targetDuration || 45,
    splitDay: request.newSplitDay || workout.splitDay,
    effortLevel: request.newEffortLevel || workout.effortLevel || "standard",
    sessionType: request.newSessionType || workout.type,
    scheduledDate: request.newScheduledDate || new Date(workout.scheduledDate),
    availableEquipment: request.newAvailableEquipment,
    trainingLocation: request.newTrainingLocation,
    planId: workout.planId,
    programId: workout.programId,
    // Force the workout ID to preserve it
    existingWorkoutId: workout.id,
  });

  console.log(`[WorkoutModifier] Rebuilt workout ${workout.id} with ${result.exerciseCount} exercises`);

  return result.workout;
}

// ============================================================================
// Main Entry Point
// ============================================================================

/**
 * Modify an existing workout
 *
 * Flow:
 * 1. Load workout and instances
 * 2. Classify change type
 * 3. Save history snapshot
 * 4. Apply changes based on type
 * 5. Return updated workout
 */
export async function modifyWorkout(
  db: admin.firestore.Firestore,
  request: ModifyWorkoutRequest
): Promise<ModifyWorkoutResult> {
  const {userId, workoutId} = request;

  // 1. Load workout
  const workoutDoc = await db
    .collection(`users/${userId}/workouts`)
    .doc(workoutId)
    .get();

  if (!workoutDoc.exists) {
    throw new Error(`Workout ${workoutId} not found`);
  }

  const workout = {id: workoutDoc.id, ...workoutDoc.data()} as WorkoutDocument;

  // Validate status
  if (workout.status === "inProgress") {
    throw new Error(`Cannot modify workout while in progress`);
  }

  if (workout.status === "completed") {
    throw new Error(`Cannot modify completed workout`);
  }

  // 2. Load current instances
  const instances = await loadInstances(db, userId, workoutId);

  // 3. Classify change
  const changeType = classifyChange(workout, request);
  const changeDescription = describeChanges(workout, request, changeType);

  console.log(`[WorkoutModifier] ${changeType} change: ${changeDescription}`);

  // 4. Save history before modification
  const modificationId = await saveHistory(
    db,
    userId,
    workout,
    instances,
    changeType,
    changeDescription
  );

  // 5. Apply changes based on type
  let updatedWorkout: WorkoutDocument;

  switch (changeType) {
    case "metadata":
      updatedWorkout = await applyMetadataChanges(db, userId, workout, request);
      break;

    case "substitution":
      updatedWorkout = await applySubstitutions(
        db,
        userId,
        workout,
        request.exerciseSubstitutions!
      );
      break;

    case "structural":
      updatedWorkout = await rebuildWorkout(db, userId, workout, request);
      break;

    default:
      throw new Error(`Unknown change type: ${changeType}`);
  }

  return {
    workout: updatedWorkout,
    changeType,
    modificationId,
    exerciseCount: updatedWorkout.exerciseIds.length,
  };
}
