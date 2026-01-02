/**
 * Strength Builder Service
 *
 * Main orchestrator for building strength workouts.
 * Coordinates ExerciseSelector, ProtocolAssigner, and InstanceCreator.
 *
 * Key features:
 * - Formula-based exercise count (no iteration)
 * - Coordinates all sub-services
 * - Creates complete workout with instances and sets
 * - Writes everything to Firestore in a batch
 */

import type * as admin from 'firebase-admin';
import {
  WorkoutBuildRequest,
  WorkoutBuildResult,
  WorkoutDocument,
} from './types';
import {
  selectExercises,
  calculateExerciseCount,
  determinePrimaryEquipment,
} from './ExerciseSelector';
import { assignProtocols, getIntensity } from './ProtocolAssigner';
import { createInstances } from './InstanceCreator';

// ============================================================================
// Main Function
// ============================================================================

/**
 * Build a complete strength workout
 *
 * @param db - Firestore database instance
 * @param request - Build request with all parameters
 * @returns Complete workout with instances and sets
 */
export async function buildStrengthWorkout(
  db: admin.firestore.Firestore,
  request: WorkoutBuildRequest
): Promise<WorkoutBuildResult> {
  const {
    userId,
    targetDuration,
    splitDay,
    effortLevel,
    sessionType,
    name,
    scheduledDate,
    exerciseIds: requestedExerciseIds,
    availableEquipment,
    trainingLocation,
    protocolOverride,
    planId,
    programId,
    existingWorkoutId,
  } = request;

  console.log(
    `[StrengthBuilder] Building workout: ${name}, ` +
    `${targetDuration}min, ${splitDay}, ${effortLevel}`
  );

  // 1. Calculate exercise count from duration (formula-based, no iteration)
  const primaryEquipment = determinePrimaryEquipment(trainingLocation, availableEquipment);
  const targetExerciseCount = calculateExerciseCount(targetDuration, primaryEquipment);

  console.log(
    `[StrengthBuilder] Target: ${targetExerciseCount} exercises ` +
    `(${targetDuration}min / ${primaryEquipment})`
  );

  // 2. Select exercises
  const selectionResult = await selectExercises(db, {
    splitDay,
    sessionType,
    targetCount: targetExerciseCount,
    requestedExerciseIds,
    availableEquipment,
    trainingLocation,
  });

  if (selectionResult.exercises.length === 0) {
    throw new Error(
      `No exercises available for ${splitDay} ${sessionType} workout. ` +
      `Please check exercise catalog or try a different configuration.`
    );
  }

  // 3. Assign protocols
  const protocolResult = assignProtocols({
    exercises: selectionResult.exercises,
    effortLevel,
    protocolOverride,
  });

  // 4. Use existing ID (for modifications) or generate new one
  const workoutId = existingWorkoutId || `${userId}_workout_${Date.now()}`;

  // 5. Create instances and sets
  const intensity = getIntensity(effortLevel);
  const instanceResult = await createInstances(db, {
    userId,
    workoutId,
    exercises: selectionResult.exercises,
    protocolIds: protocolResult.protocolIds,
    intensity,
  });

  // 6. Create workout document
  const workout: WorkoutDocument = {
    id: workoutId,
    name,
    scheduledDate: scheduledDate.toISOString(),
    type: sessionType,
    splitDay,
    status: 'scheduled',
    exerciseIds: selectionResult.exercises.map((e) => e.id),
    protocolVariantIds: instanceResult.protocolVariantIds,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    // v236: Track effort and duration for modifications
    effortLevel,
    targetDuration,
    ...(planId && { planId }),
    ...(programId && { programId }),
  };

  // 7. Write workout to Firestore
  await db.collection(`users/${userId}/workouts`).doc(workoutId).set(workout);

  console.log(
    `[StrengthBuilder] Created workout ${workoutId} with ` +
    `${selectionResult.exercises.length} exercises, ~${protocolResult.estimatedDuration}min`
  );

  return {
    workout,
    instances: instanceResult.instances,
    sets: instanceResult.sets,
    actualDuration: protocolResult.estimatedDuration,
    exerciseCount: selectionResult.exercises.length,
    // v258: Pass through name matches for substitution reporting
    nameMatches: selectionResult.nameMatches,
  };
}

// ============================================================================
// Plan Context
// ============================================================================

/**
 * Get active plan for user (if any)
 * Used to automatically insert workouts into active plans
 */
export async function getActivePlan(
  db: admin.firestore.Firestore,
  userId: string
): Promise<{ planId: string; programId: string; planName: string } | null> {
  const plansSnapshot = await db
    .collection(`users/${userId}/plans`)
    .where('status', '==', 'active')
    .where('isSingleWorkout', '==', false)
    .limit(1)
    .get();

  if (plansSnapshot.empty) {
    return null;
  }

  const planDoc = plansSnapshot.docs[0];
  const planData = planDoc.data();

  // Get the program for this plan
  const programsSnapshot = await planDoc.ref.collection('programs').limit(1).get();
  const programId = programsSnapshot.empty
    ? `program_${planDoc.id}`
    : programsSnapshot.docs[0].id;

  return {
    planId: planDoc.id,
    programId,
    planName: planData.name || 'Training Plan',
  };
}

// ============================================================================
// Validation
// ============================================================================

/**
 * Validate workout build request
 * Returns error message or null if valid
 */
export function validateBuildRequest(request: Partial<WorkoutBuildRequest>): string | null {
  if (!request.name) {
    return 'Missing required parameter: name';
  }

  if (!request.splitDay) {
    return 'Missing required parameter: splitDay';
  }

  if (!request.scheduledDate) {
    return 'Missing required parameter: scheduledDate';
  }

  if (!request.effortLevel) {
    return 'Missing required parameter: effortLevel';
  }

  if (!request.exerciseIds || request.exerciseIds.length === 0) {
    return 'Missing required parameter: exerciseIds. Please select exercises from your EXERCISE OPTIONS context.';
  }

  return null;
}

/**
 * Parse scheduled date string to Date object
 */
export function parseScheduledDate(dateStr: string | undefined): Date {
  if (!dateStr) {
    return new Date();
  }

  const parsed = new Date(dateStr);
  if (isNaN(parsed.getTime())) {
    return new Date();
  }

  return parsed;
}

/**
 * Format date for display
 */
export function formatDate(date: Date): string {
  return date.toLocaleDateString('en-US', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  });
}
