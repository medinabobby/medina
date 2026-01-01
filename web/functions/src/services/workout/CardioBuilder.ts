/**
 * Cardio Builder Service
 *
 * v236: Separate service for cardio workouts
 *
 * Key design decisions:
 * - Independent from StrengthBuilder for easier iteration
 * - Different exercise selection (endurance vs strength)
 * - Different protocol structure (duration-based vs sets/reps)
 * - Supports steady-state, intervals, and HIIT
 *
 * Cardio workout structure:
 * - Warmup phase (optional)
 * - Main cardio block(s)
 * - Cooldown phase (optional)
 */

import type * as admin from 'firebase-admin';
import {
  WorkoutDocument,
  ExerciseInstanceDocument,
  EffortLevel,
  SessionType,
  TrainingLocation,
  Equipment,
  EFFORT_INTENSITY,
} from './types';

// ============================================================================
// Types
// ============================================================================

/**
 * Cardio workout style
 */
export type CardioStyle = 'steady' | 'intervals' | 'hiit' | 'mixed';

/**
 * Request to build a cardio workout
 */
export interface CardioBuildRequest {
  userId: string;
  name: string;
  targetDuration: number; // minutes
  effortLevel: EffortLevel;
  scheduledDate: Date;
  cardioStyle?: CardioStyle;
  trainingLocation?: TrainingLocation;
  availableEquipment?: Equipment[];
  planId?: string;
  programId?: string;
  existingWorkoutId?: string;
}

/**
 * Result of cardio workout building
 */
export interface CardioBuildResult {
  workout: WorkoutDocument;
  instances: ExerciseInstanceDocument[];
  actualDuration: number;
  exerciseCount: number;
}

/**
 * Cardio exercise from catalog
 */
interface CardioExercise {
  id: string;
  name: string;
  cardioType: 'running' | 'cycling' | 'rowing' | 'elliptical' | 'swimming' | 'jumping' | 'walking';
  equipment?: string;
  intensity: 'low' | 'medium' | 'high';
}

// ============================================================================
// Constants
// ============================================================================

/**
 * Protocol IDs for cardio workouts
 */
const CARDIO_PROTOCOLS: Record<CardioStyle, Record<EffortLevel, string>> = {
  steady: {
    recovery: 'cardio_20min_easy',
    standard: 'cardio_30min_steady',
    push: 'cardio_45min_steady',
  },
  intervals: {
    recovery: 'cardio_20min_intervals_easy',
    standard: 'cardio_30min_intervals',
    push: 'cardio_30min_intervals_hard',
  },
  hiit: {
    recovery: 'cardio_15min_hiit_easy',
    standard: 'cardio_20min_hiit',
    push: 'cardio_25min_hiit',
  },
  mixed: {
    recovery: 'cardio_25min_mixed_easy',
    standard: 'cardio_35min_mixed',
    push: 'cardio_45min_mixed',
  },
};

/**
 * Duration for warmup/cooldown by effort level
 */
const WARMUP_COOLDOWN_DURATION: Record<EffortLevel, { warmup: number; cooldown: number }> = {
  recovery: { warmup: 3, cooldown: 3 },
  standard: { warmup: 5, cooldown: 5 },
  push: { warmup: 5, cooldown: 5 },
};

/**
 * Exercise count by duration and style
 */
function getCardioExerciseCount(duration: number, style: CardioStyle): number {
  // Steady state: typically 1 main exercise
  if (style === 'steady') {
    return duration >= 30 ? 2 : 1; // Add variety for longer sessions
  }

  // Intervals/HIIT: more variety
  if (style === 'hiit') {
    return Math.min(4, Math.max(2, Math.floor(duration / 10)));
  }

  // Mixed: moderate variety
  return Math.min(3, Math.max(1, Math.floor(duration / 15)));
}

// ============================================================================
// Main Function
// ============================================================================

/**
 * Build a complete cardio workout
 */
export async function buildCardioWorkout(
  db: admin.firestore.Firestore,
  request: CardioBuildRequest
): Promise<CardioBuildResult> {
  const {
    userId,
    name,
    targetDuration,
    effortLevel,
    scheduledDate,
    cardioStyle = 'steady',
    trainingLocation,
    availableEquipment,
    planId,
    programId,
    existingWorkoutId,
  } = request;

  console.log(
    `[CardioBuilder] Building workout: ${name}, ` +
    `${targetDuration}min, ${cardioStyle}, ${effortLevel}`
  );

  // 1. Calculate phase durations
  const phases = WARMUP_COOLDOWN_DURATION[effortLevel];
  const mainDuration = targetDuration - phases.warmup - phases.cooldown;

  // 2. Determine exercise count for main phase
  const mainExerciseCount = getCardioExerciseCount(mainDuration, cardioStyle);

  // 3. Select cardio exercises
  const exercises = await selectCardioExercises(db, {
    count: mainExerciseCount,
    style: cardioStyle,
    effortLevel,
    trainingLocation,
    availableEquipment,
  });

  if (exercises.length === 0) {
    throw new Error(
      `No cardio exercises available for ${cardioStyle} workout. ` +
      `Please check exercise catalog or try a different configuration.`
    );
  }

  // 4. Generate workout ID
  const workoutId = existingWorkoutId || `${userId}_workout_${Date.now()}`;

  // 5. Get protocol for this workout
  const protocolId = CARDIO_PROTOCOLS[cardioStyle][effortLevel];
  const intensity = EFFORT_INTENSITY[effortLevel];

  // 6. Create instances
  const instances = await createCardioInstances(db, {
    userId,
    workoutId,
    exercises,
    protocolId,
    intensity,
    mainDuration,
  });

  // 7. Build protocol variant IDs map
  const protocolVariantIds: Record<string, string> = {};
  exercises.forEach((_, index) => {
    protocolVariantIds[index.toString()] = protocolId;
  });

  // 8. Create workout document
  const workout: WorkoutDocument = {
    id: workoutId,
    name,
    scheduledDate: scheduledDate.toISOString(),
    type: 'cardio',
    splitDay: 'notApplicable',
    status: 'scheduled',
    exerciseIds: exercises.map((e) => e.id),
    protocolVariantIds,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    effortLevel,
    targetDuration,
    ...(planId && { planId }),
    ...(programId && { programId }),
  };

  // 9. Write workout to Firestore
  await db.collection(`users/${userId}/workouts`).doc(workoutId).set(workout);

  console.log(
    `[CardioBuilder] Created cardio workout ${workoutId} with ` +
    `${exercises.length} exercises, ~${targetDuration}min`
  );

  return {
    workout,
    instances,
    actualDuration: targetDuration,
    exerciseCount: exercises.length,
  };
}

// ============================================================================
// Exercise Selection
// ============================================================================

interface CardioSelectionRequest {
  count: number;
  style: CardioStyle;
  effortLevel: EffortLevel;
  trainingLocation?: TrainingLocation;
  availableEquipment?: Equipment[];
}

/**
 * Select cardio exercises from catalog
 */
async function selectCardioExercises(
  db: admin.firestore.Firestore,
  request: CardioSelectionRequest
): Promise<CardioExercise[]> {
  const { count, effortLevel, trainingLocation, availableEquipment } = request;

  // Query cardio exercises
  let query = db.collection('exercises')
    .where('exerciseType', '==', 'cardio')
    .limit(count * 2); // Fetch extra for filtering

  const snapshot = await query.get();

  if (snapshot.empty) {
    console.log('[CardioBuilder] No cardio exercises found in catalog');
    return [];
  }

  // Map to CardioExercise and filter
  let exercises: CardioExercise[] = snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      name: data.name,
      cardioType: data.cardioType || 'running',
      equipment: data.equipment,
      intensity: mapIntensity(data.intensity || 'medium'),
    };
  });

  // Filter by equipment if specified
  if (availableEquipment && availableEquipment.length > 0) {
    exercises = exercises.filter((e) =>
      !e.equipment ||
      e.equipment === 'bodyweight' ||
      availableEquipment.includes(e.equipment as Equipment)
    );
  }

  // Filter by location
  if (trainingLocation === 'home') {
    exercises = exercises.filter((e) =>
      !e.equipment || e.equipment === 'bodyweight' || e.equipment === 'none'
    );
  }

  // Sort by intensity match
  const targetIntensity = effortLevel === 'push' ? 'high' :
                          effortLevel === 'recovery' ? 'low' : 'medium';

  exercises.sort((a, b) => {
    const aMatch = a.intensity === targetIntensity ? 0 : 1;
    const bMatch = b.intensity === targetIntensity ? 0 : 1;
    return aMatch - bMatch;
  });

  // Return requested count
  return exercises.slice(0, count);
}

/**
 * Map intensity string to enum
 */
function mapIntensity(intensity: string): 'low' | 'medium' | 'high' {
  if (intensity === 'low' || intensity === 'easy') return 'low';
  if (intensity === 'high' || intensity === 'hard') return 'high';
  return 'medium';
}

// ============================================================================
// Instance Creation
// ============================================================================

interface CardioInstanceRequest {
  userId: string;
  workoutId: string;
  exercises: CardioExercise[];
  protocolId: string;
  intensity: number;
  mainDuration: number;
}

/**
 * Create exercise instances for cardio workout
 */
async function createCardioInstances(
  db: admin.firestore.Firestore,
  request: CardioInstanceRequest
): Promise<ExerciseInstanceDocument[]> {
  const { userId, workoutId, exercises, protocolId, mainDuration } = request;

  const instances: ExerciseInstanceDocument[] = [];
  const batch = db.batch();

  // Divide main duration among exercises
  const durationPerExercise = Math.floor(mainDuration / exercises.length);

  for (let i = 0; i < exercises.length; i++) {
    const exercise = exercises[i];
    const instanceId = `instance_${workoutId}_${i}`;

    const instance: ExerciseInstanceDocument = {
      id: instanceId,
      workoutId,
      exerciseId: exercise.id,
      protocolVariantId: protocolId,
      position: i,
      createdAt: new Date().toISOString(),
      // Cardio-specific: target duration instead of weight
      // targetWeight used as duration in minutes for cardio
      targetWeight: durationPerExercise,
    };

    instances.push(instance);

    const instanceRef = db
      .collection(`users/${userId}/workouts/${workoutId}/exerciseInstances`)
      .doc(instanceId);

    batch.set(instanceRef, instance);
  }

  await batch.commit();

  console.log(`[CardioBuilder] Created ${instances.length} cardio instances`);

  return instances;
}

// ============================================================================
// Utility Functions
// ============================================================================

/**
 * Determine cardio style from duration and effort
 */
export function suggestCardioStyle(
  duration: number,
  effortLevel: EffortLevel
): CardioStyle {
  // Short + high effort = HIIT
  if (duration <= 25 && effortLevel === 'push') {
    return 'hiit';
  }

  // Medium duration + standard = intervals
  if (duration <= 35 && effortLevel === 'standard') {
    return 'intervals';
  }

  // Long duration or recovery = steady
  if (duration >= 40 || effortLevel === 'recovery') {
    return 'steady';
  }

  // Default to mixed
  return 'mixed';
}

/**
 * Check if workout request is for cardio
 */
export function isCardioWorkout(sessionType: SessionType): boolean {
  return sessionType === 'cardio';
}
