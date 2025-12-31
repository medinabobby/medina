/**
 * Exercise Selector Service
 *
 * Selects exercises for workouts based on split day, equipment, and user constraints.
 * Validates AI-provided exercises and supplements from library if needed.
 *
 * Key features:
 * - Validates AI exercise IDs against global catalog
 * - Filters by split day muscle groups
 * - Filters by available equipment
 * - Prioritizes compound exercises
 * - Prevents duplicate base exercises (e.g., barbell + dumbbell bench press)
 */

import type * as admin from 'firebase-admin';
import {
  ExerciseDoc,
  ExerciseSelectionRequest,
  ExerciseSelectionResult,
  SplitDay,
  SessionType,
  Equipment,
  SPLIT_DAY_MUSCLES,
} from './types';

// ============================================================================
// Main Function
// ============================================================================

/**
 * Select exercises for a workout
 *
 * @param db - Firestore database instance
 * @param request - Selection request with constraints
 * @returns Selected exercises with metadata about supplementation
 */
export async function selectExercises(
  db: admin.firestore.Firestore,
  request: ExerciseSelectionRequest
): Promise<ExerciseSelectionResult> {
  const {
    splitDay,
    sessionType,
    targetCount,
    requestedExerciseIds,
    availableEquipment,
    trainingLocation,
  } = request;

  // Track base exercises to prevent duplicates (e.g., barbell + dumbbell bench press)
  const usedBaseExercises = new Set<string>();
  const selectedExercises: ExerciseDoc[] = [];

  // Determine if home workout with bodyweight only
  const isBodyweightOnly = trainingLocation === 'home' && (
    !availableEquipment ||
    availableEquipment.length === 0 ||
    (availableEquipment.length === 1 && availableEquipment[0] === 'bodyweight')
  );

  // 1. Validate AI-provided exercises first (highest priority)
  if (requestedExerciseIds && requestedExerciseIds.length > 0) {
    const validatedExercises = await validateExerciseIds(
      db,
      requestedExerciseIds,
      splitDay,
      sessionType,
      availableEquipment,
      isBodyweightOnly,
      usedBaseExercises
    );
    selectedExercises.push(...validatedExercises);
  }

  const aiExerciseCount = selectedExercises.length;

  // 2. Supplement from global catalog if needed
  if (selectedExercises.length < targetCount) {
    const supplementCount = targetCount - selectedExercises.length;
    const supplemented = await selectFromCatalog(
      db,
      splitDay,
      sessionType,
      supplementCount,
      availableEquipment,
      isBodyweightOnly,
      usedBaseExercises
    );
    selectedExercises.push(...supplemented);
  }

  const supplementedCount = selectedExercises.length - aiExerciseCount;

  console.log(
    `[ExerciseSelector] Selected ${selectedExercises.length} exercises ` +
    `(${aiExerciseCount} from AI, ${supplementedCount} supplemented)`
  );

  return {
    exercises: selectedExercises.slice(0, targetCount),
    wasSupplemented: supplementedCount > 0,
    aiExerciseCount,
    supplementedCount,
  };
}

// ============================================================================
// Validation
// ============================================================================

/**
 * Validate AI-provided exercise IDs
 * Returns only exercises that exist and pass all filters
 */
async function validateExerciseIds(
  db: admin.firestore.Firestore,
  exerciseIds: string[],
  splitDay: SplitDay,
  sessionType: SessionType,
  availableEquipment: Equipment[] | undefined,
  isBodyweightOnly: boolean,
  usedBaseExercises: Set<string>
): Promise<ExerciseDoc[]> {
  const validExercises: ExerciseDoc[] = [];
  const targetMuscles = new Set(SPLIT_DAY_MUSCLES[splitDay]);

  for (const exerciseId of exerciseIds) {
    const exerciseDoc = await db.collection('exercises').doc(exerciseId).get();

    if (!exerciseDoc.exists) {
      console.log(`[ExerciseSelector] Rejecting ${exerciseId} - not found`);
      continue;
    }

    const data = exerciseDoc.data();
    if (!data) continue;

    const exercise: ExerciseDoc = {
      id: exerciseDoc.id,
      name: data.name || exerciseId,
      muscleGroups: data.muscleGroups || [],
      exerciseType: data.exerciseType || 'compound',
      equipment: data.equipment || 'barbell',
      baseExercise: data.baseExercise || data.name || exerciseId,
    };

    // Check equipment filter
    if (!passesEquipmentFilter(exercise, availableEquipment, isBodyweightOnly)) {
      console.log(`[ExerciseSelector] Rejecting ${exerciseId} - equipment mismatch`);
      continue;
    }

    // Check muscle group filter (skip for cardio)
    if (sessionType !== 'cardio') {
      if (!passesMuscleFilter(exercise, targetMuscles)) {
        console.log(`[ExerciseSelector] Rejecting ${exerciseId} - muscle mismatch for ${splitDay}`);
        continue;
      }
    }

    // Check for duplicate base exercise
    const baseExercise = exercise.baseExercise || exercise.id;
    if (usedBaseExercises.has(baseExercise)) {
      console.log(`[ExerciseSelector] Rejecting ${exerciseId} - duplicate base exercise ${baseExercise}`);
      continue;
    }

    usedBaseExercises.add(baseExercise);
    validExercises.push(exercise);
  }

  return validExercises;
}

// ============================================================================
// Catalog Selection
// ============================================================================

/**
 * Select exercises from global catalog
 * Used to supplement AI-provided exercises
 */
async function selectFromCatalog(
  db: admin.firestore.Firestore,
  splitDay: SplitDay,
  sessionType: SessionType,
  targetCount: number,
  availableEquipment: Equipment[] | undefined,
  isBodyweightOnly: boolean,
  usedBaseExercises: Set<string>
): Promise<ExerciseDoc[]> {
  const targetMuscles = new Set(SPLIT_DAY_MUSCLES[splitDay]);
  const exercisesRef = db.collection('exercises');

  // Query based on session type
  let query: admin.firestore.Query = exercisesRef;
  if (sessionType === 'cardio') {
    query = query.where('exerciseType', '==', 'cardio');
  }

  const snapshot = await query.limit(100).get();
  const candidates: ExerciseDoc[] = [];

  for (const doc of snapshot.docs) {
    const data = doc.data();

    const exercise: ExerciseDoc = {
      id: doc.id,
      name: data.name || doc.id,
      muscleGroups: data.muscleGroups || [],
      exerciseType: data.exerciseType || 'compound',
      equipment: data.equipment || 'barbell',
      baseExercise: data.baseExercise || data.name || doc.id,
    };

    // Skip cardio for strength workouts
    if (sessionType !== 'cardio' && exercise.exerciseType === 'cardio') {
      continue;
    }

    // Check equipment filter
    if (!passesEquipmentFilter(exercise, availableEquipment, isBodyweightOnly)) {
      continue;
    }

    // Check muscle group filter (skip for cardio)
    if (sessionType !== 'cardio') {
      if (!passesMuscleFilter(exercise, targetMuscles)) {
        continue;
      }
    }

    // Check for duplicate base exercise
    const baseExercise = exercise.baseExercise || exercise.id;
    if (usedBaseExercises.has(baseExercise)) {
      continue;
    }

    candidates.push(exercise);
  }

  // Sort: compounds first, then by name for consistency
  candidates.sort((a, b) => {
    if (a.exerciseType === 'compound' && b.exerciseType !== 'compound') return -1;
    if (a.exerciseType !== 'compound' && b.exerciseType === 'compound') return 1;
    return a.name.localeCompare(b.name);
  });

  // Select and mark as used
  const selected: ExerciseDoc[] = [];
  for (const exercise of candidates) {
    if (selected.length >= targetCount) break;
    const base = exercise.baseExercise || exercise.id;
    usedBaseExercises.add(base);
    selected.push(exercise);
  }

  return selected;
}

// ============================================================================
// Filters
// ============================================================================

/**
 * Check if exercise passes equipment filter
 */
function passesEquipmentFilter(
  exercise: ExerciseDoc,
  availableEquipment: Equipment[] | undefined,
  isBodyweightOnly: boolean
): boolean {
  // Bodyweight-only mode (home with no equipment)
  if (isBodyweightOnly) {
    return exercise.equipment === 'bodyweight' || exercise.equipment === 'none';
  }

  // No filter specified - allow all
  if (!availableEquipment || availableEquipment.length === 0) {
    return true;
  }

  // Bodyweight always allowed
  if (exercise.equipment === 'bodyweight' || exercise.equipment === 'none') {
    return true;
  }

  // Check if equipment is in available list
  return availableEquipment.includes(exercise.equipment);
}

/**
 * Check if exercise targets any of the split day muscles
 */
function passesMuscleFilter(
  exercise: ExerciseDoc,
  targetMuscles: Set<string>
): boolean {
  // If no target muscles defined (notApplicable), allow all
  if (targetMuscles.size === 0) {
    return true;
  }

  // Check for any muscle overlap
  return exercise.muscleGroups.some((muscle) => targetMuscles.has(muscle));
}

// ============================================================================
// Utility
// ============================================================================

/**
 * Calculate exercise count from target duration
 * Uses formula-based approach (no iteration)
 */
export function calculateExerciseCount(
  targetDuration: number,
  primaryEquipment: Equipment = 'barbell'
): number {
  // Average time per exercise based on equipment
  const avgTimes: Record<Equipment, number> = {
    bodyweight: 8.0,
    resistanceBand: 8.0,
    cable: 8.5,
    machine: 8.0,
    dumbbells: 9.0,
    barbell: 9.5,
    kettlebell: 8.5,
    none: 8.0,
  };

  const avgTime = avgTimes[primaryEquipment] || 9.0;
  const rawCount = Math.floor(targetDuration / avgTime);

  // Clamp to reasonable range (3-8 exercises)
  return Math.max(3, Math.min(8, rawCount));
}

/**
 * Determine primary equipment from training location and available equipment
 */
export function determinePrimaryEquipment(
  trainingLocation?: TrainingLocation,
  availableEquipment?: Equipment[]
): Equipment {
  // If only bodyweight available
  if (availableEquipment) {
    const nonBodyweight = availableEquipment.filter((e) => e !== 'bodyweight' && e !== 'none');
    if (nonBodyweight.length === 0) {
      return 'bodyweight';
    }
    // Return first available non-bodyweight equipment
    if (nonBodyweight.length > 0) {
      return nonBodyweight[0];
    }
  }

  // Infer from location
  if (trainingLocation === 'home') {
    return 'bodyweight';
  }

  // Default to barbell (gym assumption)
  return 'barbell';
}

type TrainingLocation = 'home' | 'gym' | 'outdoor' | 'hybrid';
