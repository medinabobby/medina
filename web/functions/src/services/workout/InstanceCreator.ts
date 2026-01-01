/**
 * Instance Creator Service
 *
 * Creates exercise instances and sets for a workout in Firestore.
 * Handles target weight calculation from user's 1RM data.
 *
 * Key features:
 * - Batch writes for efficiency
 * - Target weight from 1RM data
 * - Set creation based on protocol
 */

import type * as admin from 'firebase-admin';
import {
  ExerciseDoc,
  ExerciseInstanceDocument,
  ExerciseSetDocument,
  ExerciseTargetDoc,
} from './types';
import { calculateTargetWeight } from './ProtocolAssigner';

// ============================================================================
// Types
// ============================================================================

/**
 * Request to create instances for a workout
 */
export interface CreateInstancesRequest {
  userId: string;
  workoutId: string;
  exercises: ExerciseDoc[];
  protocolIds: Record<number, string>;
  intensity: number;
}

/**
 * Result of instance creation
 */
export interface CreateInstancesResult {
  instances: ExerciseInstanceDocument[];
  sets: ExerciseSetDocument[];
  protocolVariantIds: Record<string, string>;
}

// ============================================================================
// Protocol Set Configurations
// ============================================================================

/**
 * Number of sets for each protocol
 */
const PROTOCOL_SETS: Record<string, number> = {
  // Strength protocols
  'strength_3x5_moderate': 3,
  'strength_3x5_heavy': 3,
  'strength_3x3_heavy': 3,

  // Accessory protocols
  'accessory_3x12_light': 3,
  'accessory_3x10_rpe8': 3,
  'accessory_3x8_rpe8': 3,

  // Cardio - typically single "set"
  'cardio_30min_steady': 1,
  'cardio_30min_intervals': 1,
  'cardio_20min_hiit': 1,
};

/**
 * Target reps for each protocol
 */
const PROTOCOL_REPS: Record<string, number> = {
  'strength_3x5_moderate': 5,
  'strength_3x5_heavy': 5,
  'strength_3x3_heavy': 3,
  'accessory_3x12_light': 12,
  'accessory_3x10_rpe8': 10,
  'accessory_3x8_rpe8': 8,
  'cardio_30min_steady': 1,
  'cardio_30min_intervals': 1,
  'cardio_20min_hiit': 1,
};

// ============================================================================
// Main Function
// ============================================================================

/**
 * Create exercise instances and sets for a workout
 *
 * @param db - Firestore database instance
 * @param request - Creation request
 * @returns Created instances and sets (also written to Firestore)
 */
export async function createInstances(
  db: admin.firestore.Firestore,
  request: CreateInstancesRequest
): Promise<CreateInstancesResult> {
  const { userId, workoutId, exercises, protocolIds, intensity } = request;

  // Get user's exercise targets (1RM data)
  const exerciseIds = exercises.map((e) => e.id);
  const exerciseTargets = await getExerciseTargets(db, userId, exerciseIds);

  // Prepare documents
  const instances: ExerciseInstanceDocument[] = [];
  const sets: ExerciseSetDocument[] = [];
  const protocolVariantIds: Record<string, string> = {};

  for (let i = 0; i < exercises.length; i++) {
    const exercise = exercises[i];
    const protocolId = protocolIds[i] || 'strength_3x5_moderate';
    const instanceId = `instance_${workoutId}_${i}`;

    // Get target weight from 1RM data
    const target = exerciseTargets.get(exercise.id);
    const targetWeight = calculateTargetWeight(target?.oneRepMax, intensity);

    // Create instance document
    const instance: ExerciseInstanceDocument = {
      id: instanceId,
      workoutId,
      exerciseId: exercise.id,
      protocolVariantId: protocolId,
      position: i,
      createdAt: new Date().toISOString(),
      ...(targetWeight !== undefined && { targetWeight }),
    };
    instances.push(instance);
    protocolVariantIds[i.toString()] = protocolId;

    // Create set documents
    const numSets = PROTOCOL_SETS[protocolId] || 3;
    const targetReps = PROTOCOL_REPS[protocolId] || 10;

    for (let s = 0; s < numSets; s++) {
      const setId = `set_${instanceId}_${s}`;
      const setDoc: ExerciseSetDocument = {
        id: setId,
        instanceId,
        setNumber: s + 1,
        targetReps,
        createdAt: new Date().toISOString(),
        ...(targetWeight !== undefined && { targetWeight }),
      };
      sets.push(setDoc);
    }
  }

  // Batch write to Firestore
  await writeToFirestore(db, userId, workoutId, instances, sets);

  console.log(
    `[InstanceCreator] Created ${instances.length} instances with ${sets.length} sets`
  );

  return {
    instances,
    sets,
    protocolVariantIds,
  };
}

// ============================================================================
// Data Fetching
// ============================================================================

/**
 * Get user's exercise targets (1RM data)
 */
async function getExerciseTargets(
  db: admin.firestore.Firestore,
  userId: string,
  exerciseIds: string[]
): Promise<Map<string, ExerciseTargetDoc>> {
  const targets = new Map<string, ExerciseTargetDoc>();

  // Batch fetch for efficiency
  const promises = exerciseIds.map(async (exerciseId) => {
    const targetDoc = await db
      .collection(`users/${userId}/exerciseTargets`)
      .doc(exerciseId)
      .get();

    if (targetDoc.exists) {
      const data = targetDoc.data();
      return {
        exerciseId,
        oneRepMax: data?.oneRepMax,
        lastUpdated: data?.lastUpdated,
      } as ExerciseTargetDoc;
    }
    return null;
  });

  const results = await Promise.all(promises);
  for (const target of results) {
    if (target) {
      targets.set(target.exerciseId, target);
    }
  }

  return targets;
}

// ============================================================================
// Firestore Operations
// ============================================================================

/**
 * Write instances and sets to Firestore
 */
async function writeToFirestore(
  db: admin.firestore.Firestore,
  userId: string,
  workoutId: string,
  instances: ExerciseInstanceDocument[],
  sets: ExerciseSetDocument[]
): Promise<void> {
  const batch = db.batch();

  // Write instances
  for (const instance of instances) {
    const instanceRef = db
      .collection(`users/${userId}/workouts/${workoutId}/exerciseInstances`)
      .doc(instance.id);
    batch.set(instanceRef, instance);
  }

  // Write sets (grouped by instance)
  for (const setDoc of sets) {
    const setRef = db
      .collection(`users/${userId}/workouts/${workoutId}/exerciseInstances/${setDoc.instanceId}/sets`)
      .doc(setDoc.id);
    batch.set(setRef, setDoc);
  }

  await batch.commit();
}
